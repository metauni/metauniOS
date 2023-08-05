local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local OrbClient = require(script.OrbClient)
local Rx = require(ReplicatedStorage.OS.Rx)
local Rxi = require(ReplicatedStorage.OS.Rxi)
local Rxf = require(ReplicatedStorage.OS.Rxf)
local Destructor = require(ReplicatedStorage.OS.Destructor)
local IconController = require(ReplicatedStorage.Packages.Icon.IconController)
local Themes = require(ReplicatedStorage.Packages.Icon.Themes)

local Promise = require(ReplicatedStorage.Packages.Promise)
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local BoardController = require(ReplicatedStorage.OS.BoardController)
local CameraUtils = require(script.CameraUtils)
local OrbMenu = require(script.OrbMenu)
local HumanoidController = require(ReplicatedStorage.OS.HumanoidController)

local Remotes = script.Remotes
local Config = require(ReplicatedStorage.OS.OrbController.Config)

local OrbController = {
	Orbs = {} :: {[Part]: Orb}
}

function OrbController:Start()

	-- Transform an observable into a Fusion StateObject that
	-- holds the latest observed value
	-- This version doesn't do garbage collection (for static usage)
	local function observedValue(observable: Rx.Observable<T>): Value<T>
		local value = Value()
		observable:Subscribe(function(newValue)
			value:set(newValue)
		end)
		return value 
	end

	IconController.setGameTheme(Themes["BlueGradient"])

	local observeAttachedOrb = Rx.of(ReplicatedStorage.OS.OrbController):Pipe {
		Rxi.findFirstChild("PlayerToOrb"),
		Rxi.findFirstChildWithClass("ObjectValue", tostring(Players.LocalPlayer.UserId)),
		Rxi.property("Value"),
	}

	-- Use SoundService:SetListener() to listen from orb/playerhead/camera
	Rx.combineLatest{
		AttachedOrbEarPart = observeAttachedOrb:Pipe{
			Rxi.findFirstChildWithClass("Part", "EarPart"),
		},
		PlayerHead = Rx.of(Players.LocalPlayer):Pipe{
			Rxi.property("Character"),
			Rxi.findFirstChildWithClassOf("BasePart", "Head"),
		},
	}:Subscribe(function(data)
		if data.AttachedOrbEarPart then
			SoundService:SetListener(Enum.ListenerType.ObjectCFrame, data.AttachedOrbEarPart)
		elseif data.PlayerHead then
			SoundService:SetListener(Enum.ListenerType.ObjectCFrame, data.PlayerHead)
		else
			SoundService:SetListener(Enum.ListenerType.Camera)
		end
	end)

	Rxi.tagged("metaorb"):Subscribe(function(instance: BasePart)
		if CollectionService:HasTag(instance, "metaorb_transport") then
			return
		end
		if not instance:IsA("BasePart") then
			error(`[OrbService] {instance:GetFullName()} is a Model. Must tag PrimaryPart with "metaorb".`)
		end

		if self.Orbs[instance] then
			return
		end

		local observeAttachedToThisOrb = observeAttachedOrb:Pipe {
			Rx.map(function(attachedOrb: Part?)
				return attachedOrb == instance
			end)
		}

		self.Orbs[instance] = OrbClient.new(instance, observeAttachedToThisOrb)
	end)

	Rxi.untagged("metaorb"):Subscribe(function(instance: BasePart)
		if CollectionService:HasTag(instance, "metaorb_transport") then
			return
		end
		if self.Orbs[instance] then
			self.Orbs[instance]:Destroy()
			self.Orbs[instance] = nil
		end
	end)

	Rxi.tagged("spooky_part"):Subscribe(function(instance: BasePart)

		local destructor = Destructor.new()

		destructor:Add(
			Rx.of(instance):Pipe {
				Rxi.attribute("spooky_transparency"),
			}:Subscribe(function(transparency: Number?)
				if transparency then
					TweenService:Create(instance, TweenInfo.new(
						1.8, -- Time
						Enum.EasingStyle.Linear, -- EasingStyle
						Enum.EasingDirection.Out, -- EasingDirection
						0, -- RepeatCount (when less than zero the tween will loop indefinitely)
						false, -- Reverses (tween will reverse once reaching it's goal)
						0 -- DelayTime
					), {
						Transparency = transparency,
					}):Play()
				end
			end)
		)

		instance.Destroying:Once(function()
			destructor:Destroy()
			destructor = nil
		end)
	end)

	local OrbcamActive: Value<boolean> = Value(false)

	local observeSpeaker: Observable<Player?> =
		observeAttachedOrb:Pipe {
			Rxi.findFirstChildWithClass("ObjectValue", "Speaker"),
			Rxi.property("Value"),
		}
	local observeLocalSpeaker: Observable<Player?> =
		observeSpeaker:Pipe{
			Rx.whereElse(function(speaker: Player?)
				return speaker == Players.LocalPlayer
			end)
		}
	export type ViewMode = "single" | "double" | "freecam"
	local observeViewMode: Observable<ViewMode?> =
		observeAttachedOrb:Pipe {
			Rxi.findFirstChildWithClass("StringValue", "ViewMode"),
			Rxi.property("Value"),
		}
	local observeShowAudience: Observable<ViewMode?> =
		observeAttachedOrb:Pipe {
			Rxi.findFirstChildWithClass("BoolValue", "ShowAudience"),
			Rxi.property("Value"),
		}
	local observePoi1: Observable<Part?> =
		observeAttachedOrb:Pipe {
			Rxi.findFirstChildWithClass("ObjectValue", "poi1"),
			Rxi.property("Value"),
		}
	local observeNearestBoard: Observable<Part?> =
		observeAttachedOrb:Pipe {
			Rxi.findFirstChildWithClass("ObjectValue", "NearestBoard"),
			Rxi.property("Value"),
		}
	local observePoi2: Observable<Part?> =
		observeAttachedOrb:Pipe {
			Rxi.findFirstChildWithClass("ObjectValue", "poi2"),
			Rxi.property("Value"),
		}
	local observeWaypointOnly: Observable<boolean?> =
		observeAttachedOrb:Pipe {
			Rxi.findFirstChildWithClass("BoolValue", "WaypointOnly"),
			Rxi.property("Value"),
		}

	local DAMPING = 1
	local SPEED = 1/3 * 2 * math.pi -- speed = frequency * 2π
	local CamPositionGoal = Value(workspace.CurrentCamera.CFrame.Position)
	local CamLookAtGoal = Value(workspace.CurrentCamera.CFrame.Position + workspace.CurrentCamera.CFrame.LookVector)
	local CamFOVGoal = Value(workspace.CurrentCamera.FieldOfView)
	local PositionSpring = Spring(CamPositionGoal, SPEED, DAMPING)
	local LookAtSpring = Spring(CamLookAtGoal, SPEED, DAMPING)
	local FOVSpring = Spring(CamFOVGoal, 1.5*SPEED, DAMPING)

	local PlayerToOrb: Folder = ReplicatedStorage.OS.OrbController.PlayerToOrb

	local observePeers =
		observeAttachedOrb:Pipe {
			Rxi.notNil(),
			Rx.switchMap(function(attachedOrb: Part?)
				return 
					Rx.of(Players):Pipe {
						Rxi.children(),
						Rx.switchMap(function(players: {Players})
							local attached = {}
							for _, player in players do
								attached[player] = Rx.of(PlayerToOrb):Pipe {
									Rxi.findFirstChildWithClass("ObjectValue", tostring(player.UserId)),
									Rxi.property("Value"),
									Rx.map(function(playersOrb: Part?)
										return playersOrb == attachedOrb or nil
									end)
								}
							end
							-- This emits the latest set of players attached to this orb
							return Rx.combineLatest(attached)
						end),
					}
			end),
		}

	local observePeerMovement =
		observePeers:Pipe {
			Rx.switchMap(function(peers: {[Player]: true?})

				local movement = {}
				for player in peers do
					movement[player] = Rx.of(player):Pipe {
						Rxi.property("Character"),
						Rxi.property("PrimaryPart"),
						Rx.switchMap(function(part: Part)
							return Rx.timer(0, 0.5):Pipe({
								Rx.map(function()
									if not part then
										return nil
									else
										return Vector3.new(
											math.round(part.Position.X * 10),
											math.round(part.Position.Y * 10),
											math.round(part.Position.Z * 10)
										)
									end
								end),
								Rx.distinct(),
								Rx.mapTo(part),
							})
						end),
					}
				end

				return Rx.combineLatest(movement)
			end)
		}
		

	-- For restoring after exiting orbcam
	local playerCamCFrame = nil
	local playerCamFOV = nil

	-- Commandeer current camera
	Rx.combineLatest{
		AttachedOrb = observeAttachedOrb,
		OrbcamActive = Rxf.fromState(OrbcamActive),
		Camera = Rx.of(workspace):Pipe {
			Rxi.property("CurrentCamera"),
		},
	}:Subscribe(function(data: table)
		local camera: Camera? = data.Camera

		if data.OrbcamActive and data.AttachedOrb and camera then

			-- Camera is currently PlayerCam
			playerCamFOV = camera.FieldOfView
			playerCamCFrame = camera.CFrame

			-- Teleport Camera CFrames springs to goal
			PositionSpring:setPosition(CamPositionGoal:get())
			PositionSpring:setVelocity(Vector3.zero)
			LookAtSpring:setPosition(CamLookAtGoal:get())
			LookAtSpring:setVelocity(Vector3.zero)
			FOVSpring:setPosition(CamFOVGoal:get())
			FOVSpring:setVelocity(0)
			
			-- Allow code to steer orbcam
			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView = FOVSpring:get()
			camera.CFrame = CFrame.lookAt(PositionSpring:get(), LookAtSpring:get())
		elseif camera then
			if playerCamFOV and playerCamCFrame then
				camera.FieldOfView = playerCamFOV
				camera.CFrame = playerCamCFrame
				playerCamFOV = nil
				playerCamCFrame = nil
				camera.CameraType = Enum.CameraType.Custom
			end
		end
	end)

	local runConnection

	Rx.combineLatest {
		AttachedOrb = observeAttachedOrb,
		OrbcamActive = Rxf.fromState(OrbcamActive),
		Poi1 = observePoi1,
		Poi2 = observePoi2,
		NearestBoard = observeNearestBoard,
		SpeakerCharacter = observeSpeaker:Pipe{
			Rxi.property("Character")
		},
		ViewMode = observeViewMode,
		ViewportSize = Rx.of(workspace):Pipe {
			Rxi.property("CurrentCamera"),
			Rxi.property("ViewportSize"),
			Rx.throttleTime(0.5),
		},
		ShowAudience = observeShowAudience,
		AudienceMovement = observeShowAudience:Pipe {
			-- Don't watch Audience movement while unnecessary
			Rx.switchMap(function(showAudience: boolean)
				if showAudience then
					return observePeerMovement
				else
					return Rx.of({})
				end
			end),
		},
		WaypointOnly = observeWaypointOnly,
	}
	:Subscribe(function(data)
		local attachedOrb: Part? = data.AttachedOrb
		if not attachedOrb then
			return
		end
		
		local orbcamActive: boolean? = data.OrbcamActive
		local viewportSize: Vector2 = data.ViewportSize
		local poi1: Part? = data.Poi1
		local poi2: Part? = data.Poi2
		local nearestBoard: Part? = data.NearestBoard
		local speakerCharacter: Model? = data.SpeakerCharacter
		local viewMode: ViewMode? = data.ViewMode
		local showAudience: boolean? = data.ShowAudience
		local audienceMovement: {[Player]: true?} = data.AudienceMovement
		local waypointOnly: boolean? = data.WaypointOnly

		if runConnection then
			runConnection:Disconnect()
			runConnection = nil
		end

		if orbcamActive then
			runConnection = RunService.RenderStepped:Connect(function()
	
				local camera = workspace.CurrentCamera
				if viewMode == nil or viewMode == "freecam" or camera.CameraType ~= Enum.CameraType.Scriptable then
					return
				end
	
				-- Chase speaker or orb if not looking at boards
				if not poi1 and not poi2 then
					local chaseTarget = if speakerCharacter then speakerCharacter:GetPivot().Position else attachedOrb.Position
					local camPos

					if nearestBoard then
						local targetToBoard = (chaseTarget - nearestBoard.Position)
						if targetToBoard.Magnitude < 30 then

							-- Check that cam would be within 120 view of board (not too side-on)
							if targetToBoard.Unit:Dot(nearestBoard.CFrame.LookVector.Unit) > math.cos(math.rad(60)) then
								local awayFromBoard = targetToBoard * Vector3.new(1,0,1)
								camPos = chaseTarget + awayFromBoard.Unit * 20 + Vector3.new(0,5,0)
							end
						end
					end

					-- Default to looking from wherever camera currently is
					if not camPos then
						local towardsCam = (workspace.CurrentCamera.CFrame.Position - chaseTarget) * Vector3.new(1,0,1)
						camPos = chaseTarget + towardsCam.Unit * 20 + Vector3.new(0,5,0)
					end
					CamPositionGoal:set(camPos)
					CamLookAtGoal:set(chaseTarget)
					CamFOVGoal:set(Config.OrbcamFOV)
				end
	
				workspace.CurrentCamera.CFrame = CFrame.lookAt(PositionSpring:get(), LookAtSpring:get())
				workspace.CurrentCamera.FieldOfView = FOVSpring:get()
			end)
		end

		if not poi1 then
			-- Need to set goals so the orbccam doesn't start far away
			local chaseTarget = if speakerCharacter then speakerCharacter:GetPivot().Position else attachedOrb.Position
			local towardsCam = (workspace.CurrentCamera.CFrame.Position - chaseTarget) * Vector3.new(1,0,1)
			local camPos = chaseTarget + towardsCam.Unit * 20 + Vector3.new(0,5,0)
			CamPositionGoal:set(camPos)
			CamLookAtGoal:set(chaseTarget)
			CamFOVGoal:set(Config.OrbcamFOV)
			return
		end

		local boards = {BoardController.Boards[poi1]}
		if poi2 then
			table.insert(boards, BoardController.Boards[poi2])
		end
		if #boards == 0 then
			return
		end

		local cframe, lookTarget = CameraUtils.ViewBoardsAtFOV(boards, Config.OrbcamFOV, Config.AssumedViewportSize, Config.OrbcamBuffer)
		local fov = CameraUtils.GetFOVForBoards(cframe, boards, viewportSize, Config.OrbcamBuffer)
		
		if showAudience then
			
			-- The boards + the audience characters
			local targets = {poi1, poi2}
			local audienceEmpty = true
			local speakerPos = speakerCharacter:GetPivot().Position
			local audienceRadius = math.max(30, (lookTarget - speakerPos).Magnitude)

			-- Find attached characters close enough to speaker
			for player in audienceMovement do
				local character = player.Character
				if character and character.PrimaryPart then
					if (character.PrimaryPart.Position - speakerPos).Magnitude <= audienceRadius then
						table.insert(targets, character.PrimaryPart)
						-- Include the speaker in the audience iff not waypointOnly
						if waypointOnly or character ~= speakerCharacter then
							audienceEmpty = false
						end
					end
				end
			end

			-- For testing
			for _, model in CollectionService:GetTagged("fake_audience") do
				if model.PrimaryPart then
					if (model.PrimaryPart.Position - speakerPos).Magnitude <= audienceRadius then
						table.insert(targets, model.PrimaryPart)
						audienceEmpty = false
					end
				end
			end

			-- For NPCs
			for _, model in CollectionService:GetTagged("npcservice_npc") do
				if model.PrimaryPart then
					if (model.PrimaryPart.Position - speakerPos).Magnitude <= audienceRadius then
						table.insert(targets, model.PrimaryPart)
						audienceEmpty = false
					end
				end
			end

			if audienceEmpty then
				CamPositionGoal:set(cframe.Position)
				CamLookAtGoal:set(lookTarget)
				CamFOVGoal:set(fov)
				return 
			end

			local cframeWithAudience = CameraUtils.FitTargetsAlongCFrameRay(cframe, targets, Config.OrbcamFOV, viewportSize, Config.OrbcamBuffer)
			local lookTargetWithAudience = Vector3.zero
			for _, target in targets do
				lookTargetWithAudience += target.Position
			end
			lookTargetWithAudience /= #targets
			
			CamPositionGoal:set(cframeWithAudience.Position + Vector3.new(0, 5, 0))
			CamLookAtGoal:set(lookTargetWithAudience)
			CamFOVGoal:set(Config.OrbcamFOV)
		else
			CamPositionGoal:set(cframe.Position)
			CamLookAtGoal:set(lookTarget)
			CamFOVGoal:set(fov)
		end
		
	end)

	--[[
		Slow down speaker while they are in frame
	--]]
	Rx.combineLatest {
		Poi1 = observePoi1,
		Poi2 = observePoi2,
		Humanoid = HumanoidController:ObserveHumanoid(Players.LocalPlayer),
		Speaker = observeSpeaker,
	}:Subscribe(function(data)

		-- Walk slowly while orbcam looking at poi
		if data.Speaker == Players.LocalPlayer and data.Humanoid and (data.Poi1 or data.Poi2) then
			data.Humanoid:SetWalkSpeed(10)
			data.Humanoid:SetSprintSpeed(16)
		elseif data.Humanoid then
			data.Humanoid:SetWalkSpeed(16)
			data.Humanoid:SetSprintSpeed(24)
		end
	end)


	--[[
		Make speaker turn towards camera when in frame
	--]]
	local turnTween: Tween?
	local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad)
	Rx.combineLatest {
		Poi1 = observePoi1,
		MoveDirection = observeLocalSpeaker:Pipe {
			Rxi.property("Character"),
			Rxi.findFirstChildOfClass("Humanoid"),
			Rxi.property("MoveDirection")
		},
		RootPart = observeLocalSpeaker:Pipe {
			Rxi.property("Character"),
			Rxi.property("PrimaryPart"),
		},
		HumanoidState = observeLocalSpeaker:Pipe {
			Rxi.property("Character"),
			Rxi.findFirstChild("Humanoid"),
			Rx.switchMap(function(humanoid: Humanoid?)
				if not humanoid then
					return Rx.of(nil)
				else
					return Rx.fromSignal(humanoid.StateChanged):Pipe {
						Rx.map(function(_, newState: Enum.HumanoidStateType)
							return newState
						end),
						Rx.defaultsTo(humanoid:GetState())
					}
				end
			end),
		},
		CamPositionGoal = Rxf.fromState(CamPositionGoal),
		CamLookAtGoal = Rxf.fromState(CamLookAtGoal),
		CamFOVGoal = Rxf.fromState(CamFOVGoal),
	}:Subscribe(function(data)
		local poi1: Part? = data.Poi1
		local rootPart: Part? = data.RootPart
		local humanoidState: Enum.HumanoidStateType? = data.HumanoidState
		local moveDirection: Vector3? = data.MoveDirection
		local camPositionGoal: Vector3 = data.CamPositionGoal
		local camLookAtGoal: Vector3 = data.CamLookAtGoal
		local camFOVGoal: number = data.CamFOVGoal

		-- We're either about to tween elsewhere or not tween at all
		if turnTween then
			turnTween:Cancel()
		end

		-- We're moving, don't rotate
		if moveDirection and moveDirection.Magnitude ~= 0 then
			return
		end

		-- We don't want to rotate the speaker if they're jumping or something else
		-- Yes it says running but that's the state when just standing still
		if
			not humanoidState
			or humanoidState == Enum.HumanoidStateType.Jumping
			or humanoidState == Enum.HumanoidStateType.Freefall
		then
			return
		end

		-- print("not running")
		
		-- No character or poi1 not looking at anything
		if not rootPart or not poi1 then
			return
		end
		
		local lookVector = camLookAtGoal - camPositionGoal
		local horizontalFOVRad = 2 * math.atan(Config.AssumedViewportSize.X / Config.AssumedViewportSize.Y * math.tan(math.rad(Config.OrbcamFOV)/2))
		local cosAngleToSpeaker = ((rootPart.Position - camPositionGoal).Unit):Dot(lookVector.Unit)
		local distanceToFocalPoint = (camLookAtGoal - camPositionGoal).Magnitude
		local distanceToCharacter = (rootPart.Position - camPositionGoal).Magnitude
		
		local ANGLE_BUFFER = math.rad(2.5)
		local outsideCamView = cosAngleToSpeaker < math.cos(horizontalFOVRad/2 + ANGLE_BUFFER)
		local tooFarBehindBoard = distanceToCharacter > 2 * distanceToFocalPoint
		
		if not outsideCamView and not tooFarBehindBoard then
			
			local target = Vector3.new(camPositionGoal.X, rootPart.Position.Y, camPositionGoal.Z)
			turnTween = TweenService:Create(rootPart, tweenInfo, {
				CFrame = CFrame.lookAt(rootPart.Position, target)
			})
			;(turnTween :: Tween):Play()
		end
	end)

	local function PoiHighlight(observePoi)

		local observeAdornee = observePoi:Pipe{
			Rx.map(function(poi: Part?)
				if poi and poi.Parent and poi.Parent:IsA("Model") and poi.Parent.PrimaryPart == poi then
					return poi.Parent
				end
				return poi
			end),
		}

		local observeMoving = observeLocalSpeaker:Pipe {
			Rxi.property("Character"),
			Rxi.findFirstChildOfClass("Humanoid"),
			Rxi.property("MoveDirection"),
			Rx.map(function(direction: Vector3?)
				return direction and direction.Magnitude ~= 0
			end),
		}

		local holdPromise
		if holdPromise then
			holdPromise:cancel()
			holdPromise = nil
		end

		local Transparency = Value(1)
		local SpringTransparency = Spring(Transparency, 30, 1)

		-- When the player is moving, show the highlights,
		-- when they stop, hide the highlights after a short delay
		Rx.combineLatest{
			Adornee = observeAdornee,
			Moving = observeMoving,
		}:Subscribe(function(data)
			if data.Moving and data.Adornee then
				if holdPromise then
					holdPromise:cancel()
					holdPromise = nil
				end
				holdPromise = 
				Promise.delay(0.6)
					:andThen(function()
						Transparency:set(1)
					end)
				Transparency:set(0)
			end
		end)

		local highlight = New "Highlight" {
			Adornee = observedValue(observeAdornee),
			FillColor = Color3.new(1,1,1),
			-- This would be better if it made it brighter, not darker...
			-- FillTransparency = Computed(function()
			-- 	return 0.8 + 0.2 * SpringTransparency:get()
			-- end),
			FillTransparency = 1,
			OutlineColor = BrickColor.new("Baby blue").Color,
			OutlineTransparency = SpringTransparency,
		}

		New "Folder" {
			Name = "HideHighlight",
			Parent = workspace,
			[Children] = highlight,
		}
	end

	PoiHighlight(observePoi1)
	PoiHighlight(observePoi2)

	local AttachedOrb = observedValue(observeAttachedOrb)

	-- UI in bottom right when orbcam is active
	New "ScreenGui" {

		Parent = Players.LocalPlayer.PlayerGui,

		[Children] = 
			Computed(function()
				local attachedOrb = AttachedOrb:get()
				if not attachedOrb then
					return nil
				end
				return New "Frame" {
		
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 15, 1, -15),
					Size = UDim2.fromOffset(250, 125),
		
					BackgroundTransparency = 1,
		
					[Children] = OrbMenu {
						OrbBrickColor = attachedOrb.BrickColor,
						OrbMaterial = attachedOrb.Material,
						ViewMode = observedValue(observeViewMode),
						SetViewMode = function(viewMode: ViewMode)
							Remotes.SetViewMode:FireServer(attachedOrb, viewMode)
						end,
						Detach = function()
							OrbcamActive:set(false)
							Remotes.DetachPlayer:FireServer(attachedOrb)
						end,
						IsSpeaker = observedValue(observeSpeaker:Pipe{
							Rx.map(function(speaker: Player?)
								return speaker == Players.LocalPlayer
							end)
						}),
						Audience = observedValue(observeShowAudience),
						SetAudience = function(audience)
							Remotes.SetShowAudience:FireServer(attachedOrb, audience)
						end,
						OrbcamActive = OrbcamActive,
						SetOrbcamActive = function(active)
							Remotes.OrbcamStatus:FireServer(attachedOrb, active)
							OrbcamActive:set(active)
						end,
						Teleport = function()
							Remotes.Teleport:FireServer(attachedOrb)
						end,
						SendEmoji = function(emojiName: string)
							Remotes.SendEmoji:FireServer(attachedOrb, emojiName)
						end,
						ReceiveEmojiSignal = Remotes.SendEmoji.OnClientEvent,
						WaypointOnly = observedValue(observeWaypointOnly),
						SetWaypointOnly = function(waypointOnly: boolean)
							Remotes.SetWaypointOnly:FireServer(attachedOrb, waypointOnly)
						end,
					}
				}
			end, Fusion.cleanup)
	}
end

return OrbController