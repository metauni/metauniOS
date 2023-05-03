local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local New = Fusion.New
local Value = Fusion.Value
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local Destructor = require(ReplicatedStorage.Destructor)
local Rx = require(ReplicatedStorage.Rx)
local Rxi = require(ReplicatedStorage.Rxi)
local Rxf = require(ReplicatedStorage.Rxf)
local BoardController = require(ReplicatedStorage.BoardController)
local CameraUtils = require(script.Parent.CameraUtils)
local OrbMenu = require(script.Parent.OrbMenu)

local Remotes = script.Parent.Remotes
local Config = require(ReplicatedStorage.OrbController.Config)

local OrbClient = {}
OrbClient.__index = OrbClient

export type ViewMode = "single" | "double" | "freecam"

function OrbClient.new(orbPart: Part, observedAttachedOrb: Observable): OrbClient

	local destructor = Destructor.new()

	-- Wrap Fusion.New in a destructor
	local NewTracked = function(className: string)
		return function (props)
			return destructor:Add(New(className)(props))
		end
	end

	-- Transform an observable into a Fusion StateObject that
	-- holds the latest observed value
	local function observedValue(observable: Rx.Observable<T>): Value<T>
		local value = Value()
		destructor:Add(observable:Subscribe(function(newValue)
			value:set(newValue)
		end))
		return value 
	end

	local OrbcamActive: Value<boolean> = Value(false)

	local observeAttached: Observable<boolean> = observedAttachedOrb:Pipe{
		Rx.map(function(attachedOrb: Part?)
			return attachedOrb == orbPart
		end)
	}
	local observeSpeaker: Observable<Player?> =
		Rx.of(orbPart):Pipe {
			Rxi.findFirstChildWithClass("ObjectValue", "Speaker"),
			Rxi.property("Value"),
		}
	local observeLocalSpeaker: Observable<Player?> =
		observeSpeaker:Pipe{
			Rx.whereElse(function(speaker: Player?)
				return speaker == Players.LocalPlayer
			end)
		}
	local observeViewMode: Observable<ViewMode?> =
		Rx.of(orbPart):Pipe {
			Rxi.findFirstChildWithClass("StringValue", "ViewMode"),
			Rxi.property("Value"),
		}
	local observeShowAudience: Observable<ViewMode?> =
		Rx.of(orbPart):Pipe {
			Rxi.findFirstChildWithClass("BoolValue", "ShowAudience"),
			Rxi.property("Value"),
		}
	local observePoi1: Observable<Part?> =
		Rx.of(orbPart):Pipe {
			Rxi.findFirstChildWithClass("ObjectValue", "poi1"),
			Rxi.property("Value"),
		}
	local observePoi2: Observable<Part?> =
		Rx.of(orbPart):Pipe {
			Rxi.findFirstChildWithClass("ObjectValue", "poi2"),
			Rxi.property("Value"),
		}
	local observeWaypointOnly: Observable<boolean?> =
		Rx.of(orbPart):Pipe {
			Rxi.findFirstChildWithClass("BoolValue", "WaypointOnly"),
			Rxi.property("Value"),
		}

	NewTracked "ProximityPrompt" {

		Name = "AttachAsListenerPrompt",
		ActionText = "Attach as Listener",
		KeyboardKeyCode = Enum.KeyCode.E,
		GamepadKeyCode = Enum.KeyCode.ButtonX,
		Enabled = observedValue(observedAttachedOrb:Pipe{
			Rx.map(function(attachedOrb: Part?)
				return attachedOrb == nil
			end)
		}),
		[OnEvent "Triggered"] = function()
			Remotes.SetListener:FireServer(orbPart)
		end,
		
		MaxActivationDistance = 24,
		ObjectText = "Orb",
		RequiresLineOfSight = false,
		Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow,
		HoldDuration = 1,
		Parent = orbPart,
	}

	NewTracked "ProximityPrompt" {

		Name = "AttachAsSpeakerPrompt",
		
		ActionText = "Attach as Speaker",
		KeyboardKeyCode = Enum.KeyCode.F,
		GamepadKeyCode = Enum.KeyCode.ButtonY,
		UIOffset = Vector2.new(0,75),
		Enabled = observedValue(
			Rx.combineLatest({
				observeSpeaker,
				Rx.of(Players.LocalPlayer):Pipe({
					Rxi.attribute("metaadmin_isscribe")
				}),
				observedAttachedOrb,
			})
			:Pipe {
				Rx.unpacked,
				Rx.map(function(speaker: Player?, isScribe: boolean?, attachedOrb: Part?)
					return (attachedOrb == nil) and (isScribe or RunService:IsStudio()) and speaker == nil
				end)
			}
		),
		[OnEvent "Triggered"] = function()
			Remotes.SetSpeaker:FireServer(orbPart)
		end,

		MaxActivationDistance = 24,
		Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow,
		HoldDuration = 1,
		ObjectText = "Orb",
		RequiresLineOfSight = false,
		
		Parent = orbPart,
	}

	local DAMPING = 1
	local SPEED = 1/3 * 2 * math.pi -- speed = frequency * 2π
	local CamPositionGoal = Value(workspace.CurrentCamera.CFrame.Position)
	local CamLookAtGoal = Value(workspace.CurrentCamera.CFrame.Position + workspace.CurrentCamera.CFrame.LookVector)
	local PositionSpring = Spring(CamPositionGoal, SPEED, DAMPING)
	local LookAtSpring = Spring(CamLookAtGoal, SPEED, DAMPING)

	local orbcam
	orbcam = NewTracked "Camera" {
		
		Name = "OrbCam"..orbPart:GetFullName(),
		CameraType = Enum.CameraType.Scriptable,
		CFrame = Computed(function()
			return CFrame.lookAt(PositionSpring:get(), LookAtSpring:get())
		end),
		FieldOfView = 55,
		Parent = ReplicatedStorage,
	}
	
	local defaultCam: Camera = workspace.CurrentCamera

	destructor:Add(
		
		Rx.combineLatest{
			Attached = observeAttached,
			OrbcamActive = Rxf.fromState(OrbcamActive),
		}:Subscribe(function(data: table)
			if data.OrbcamActive and data.Attached then
				-- Teleport Camera CFrames springs to goal
				PositionSpring:setPosition(CamPositionGoal:get())
				PositionSpring:setVelocity(Vector3.zero)
				LookAtSpring:setPosition(CamLookAtGoal:get())
				LookAtSpring:setVelocity(Vector3.zero)
				-- Store exising camera in ReplicatedStorage - is destroyed otherwise
				defaultCam = workspace.CurrentCamera
				defaultCam.Parent = ReplicatedStorage
				orbcam.Parent = workspace
				-- selene: allow(incorrect_standard_library_use)
				workspace.CurrentCamera = orbcam
			else
				defaultCam.Parent = workspace
				orbcam.Parent = ReplicatedStorage
				-- selene: allow(incorrect_standard_library_use)
				workspace.CurrentCamera = defaultCam
			end
		end)
	)

	local runConnection
	destructor:Add(function()
		if runConnection then
			runConnection:Disconnect()
			runConnection = nil
		end
	end)

	local PlayerToOrb: Folder = ReplicatedStorage.OrbController.PlayerToOrb

	local observeAttachedCharacterMovement =
		Rx.of(Players):Pipe {
			Rxi.children(),
			Rx.switchMap(function(players: {Players})
				local movements = {}
				for _, player in players do
					movements[player] = Rx.of(PlayerToOrb):Pipe {
						Rxi.findFirstChildWithClass("ObjectValue", tostring(player.UserId)),
						Rxi.property("Value"),
						Rx.switchMap(function(attachedOrb: Part)
							if attachedOrb == orbPart then
								return Rx.of(player):Pipe {
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
											end)
										})
									end),
									Rx.distinct(),
									Rx.mapTo(true),
								}
							else
								-- won't appear in emitted table
								return Rx.of(nil)
							end
						end)
					}
				end

				-- This emits the latest set of players attached to this orb
				return Rx.combineLatest(movements)
			end),
		}

	destructor:Add(

		Rx.combineLatest {
			Poi1 = observePoi1,
			Poi2 = observePoi2,
			SpeakerCharacter = observeSpeaker:Pipe{
				Rxi.property("Character")
			},
			ViewMode = observeViewMode,
			ViewportSize = Rx.fromSignal(orbcam:GetPropertyChangedSignal("ViewportSize")):Pipe {
				Rx.defaultsTo(nil),
				Rx.throttleTime(0.5),
				Rx.map(function()
					return workspace.CurrentCamera.ViewportSize
				end),
			},
			ShowAudience = observeShowAudience,
			AudienceMovement = observeShowAudience:Pipe {
				Rx.switchMap(function(showAudience: boolean)
					if showAudience then
						return observeAttachedCharacterMovement
					else
						return Rx.of({})
					end
				end),
			},
			WaypointOnly = observeWaypointOnly
		}
		:Subscribe(function(data)
			local poi1: Part? = data.Poi1
			local poi2: Part? = data.Poi2
			local speakerCharacter: Model? = data.SpeakerCharacter
			local viewMode: ViewMode? = data.ViewMode
			local showAudience: boolean? = data.ShowAudience
			local viewportSize: Vector2 = data.ViewportSize
			local audienceMovement: {[Player]: true?} = data.AudienceMovement
			local waypointOnly: boolean? = data.WaypointOnly

			if runConnection then
				runConnection:Disconnect()
				runConnection = nil
			end
			runConnection = RunService.RenderStepped:Connect(function()

				if viewMode == nil or viewMode == "Freecam" then
					return
				end
	
				-- Chase speaker or orb if not looking at boards
				if not poi1 and not poi2 then
					local chaseTarget = if speakerCharacter then speakerCharacter:GetPivot().Position else orbPart.Position
					local towardsCam = (orbcam.CFrame.Position - chaseTarget) * Vector3.new(1,0,1)
					local camPos = chaseTarget + towardsCam.Unit * 20 + Vector3.new(0,5,0)
					CamPositionGoal:set(camPos)
					CamLookAtGoal:set(chaseTarget)
				end
			end)

			if not poi1 then
				return
			end

			local boards = {BoardController.Boards[poi1]}
			if poi2 then
				table.insert(boards, BoardController.Boards[poi2])
			end
			if #boards == 0 then
				return
			end

			local aspectRatio = viewportSize.X / viewportSize.Y
			local cframe, lookTarget = CameraUtils.ViewBoardsAtFOV(boards, orbcam.FieldOfView, aspectRatio, Config.OrbcamBuffer)
			
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
					return 
				end

				local cframeWithAudience = CameraUtils.FitTargetsAlongCFrameRay(cframe, targets, orbcam.FieldOfView, aspectRatio, Config.OrbcamBuffer)
				local lookTargetWithAudience = Vector3.zero
				for _, target in targets do
					lookTargetWithAudience += target.Position
				end
				lookTargetWithAudience /= #targets
				
				CamPositionGoal:set(cframeWithAudience.Position + Vector3.new(0, 5, 0))
				CamLookAtGoal:set(lookTargetWithAudience)
			else
				CamPositionGoal:set(cframe.Position)
				CamLookAtGoal:set(lookTarget)
			end
			
		end)
	)

	--[[
		Slow down speaker while they are in frame
	--]]
	destructor:Add(
		Rx.combineLatest {
			Poi1 = observePoi1,
			Poi2 = observePoi2,
			Humanoid = observeLocalSpeaker:Pipe {
				Rxi.property("Character"),
				Rxi.findFirstChildOfClass("Humanoid"),
			},
		}:Subscribe(function(data)
			local poi1: Part? = data.Poi1
			local poi2: Part? = data.Poi2
			local humanoid: Humanoid? = data.Humanoid

			-- Walk slowly while orbcam looking at poi
			if humanoid and (poi1 or poi2) then
				humanoid.WalkSpeed = 10
			elseif humanoid then
				humanoid.WalkSpeed = 16
			end
		end)
	)


	--[[
		Make speaker turn towards camera when in frame
	--]]
	local turnTween: Tween?
	local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad)
	destructor:Add(
		Rx.combineLatest {
			Poi1 = observePoi1,
			MoveDirection = observeLocalSpeaker:Pipe {
				Rxi.property("Character"),
				Rxi.findFirstChildOfClass("Humanoid"),
				Rxi.property("MoveDirection")
			},
			RootPart = observeLocalSpeaker:Pipe {
				Rxi.property("Character"),
				Rxi.findFirstChildWithClass("Part", "HumanoidRootPart")
			},
			CamPositionGoal = Rxf.fromState(CamPositionGoal),
			CamLookAtGoal = Rxf.fromState(CamLookAtGoal),
		}:Subscribe(function(data)
			local poi1: Part? = data.Poi1
			local rootPart: Part? = data.RootPart
			local moveDirection: Vector3? = data.MoveDirection
			local camPositionGoal: Vector3? = data.CamPositionGoal
			local camLookAtGoal: Vector3? = data.CamLookAtGoal

			-- We're either about to tween elsewhere or not tween at all
			if turnTween then
				turnTween:Cancel()
			end

			-- We're moving, don't rotate
			if moveDirection and moveDirection.Magnitude ~= 0 then
				return
			end
			
			-- No character or poi1 not looking at anything
			if not rootPart or not poi1 then
				return
			end
			
			local lookVector = camLookAtGoal - camPositionGoal
			local aspectRatio = orbcam.ViewportSize.X / orbcam.ViewportSize.Y
			local horizontalFOVRad = 2 * math.atan(aspectRatio * math.tan(math.rad(Config.OrbcamFOV)/2))
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
				turnTween:Play()
			end
		end)
	)

	local function PoiHighlight(observePoi)

		local observeAdornee = observePoi:Pipe{
			Rx.map(function(poi: Part?)
				if poi then
					if poi.Parent and poi.Parent:IsA("Model") and poi.Parent.PrimaryPart == poi then
						return poi.Parent
					end
				end
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

		local showValue: StateObject<boolean> = observedValue(
			Rx.combineLatest{
				observeAdornee,
				observeMoving,
			}:Pipe{
				Rx.unpacked,
				Rx.map(function(adornee: Part?, isMoving: boolean)
					return isMoving and adornee ~= nil
				end),
			}
		)

		local spring = Spring(Computed(function()
			return showValue:get() and 0 or 1
		end), 30, 1)

		local highlight = NewTracked "Highlight" {
			Adornee = observedValue(observeAdornee),
			FillTransparency = 1,
			OutlineColor = BrickColor.new("Flame reddish orange").Color,
			OutlineTransparency = spring,
		}

		Fusion.Hydrate(highlight) {
			[Fusion.Cleanup] = {
				-- adornee seems to have to be set after parent is set in order to use adornee over parent
				observeAttached:Subscribe(function(attached: boolean)
					highlight.Parent = attached and orbPart or nil
					highlight.Adornee = highlight.Adornee
				end),
				-- Due to delay between client and server, the highlight may have faded
				-- away by the time the new poi replicates.
				-- This gives it a final bump
				observeAdornee:Subscribe(function(adornee: Part?)
					if adornee ~= nil then
						spring:setPosition(0)
					end
				end)
			}
		}

		return highlight
	end

	PoiHighlight(observePoi1)
	PoiHighlight(observePoi2)

	local Attached = observedValue(observeAttached)

	-- UI in bottom right when orbcam is active
	destructor:Add(

		New "ScreenGui" {

			Parent = Players.LocalPlayer.PlayerGui,
			Enabled = Attached,

			[Children] = New "Frame" {

				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 30, 1, -30),
				Size = UDim2.fromOffset(300, 150),

				BackgroundTransparency = 1,

				[Children] = OrbMenu {
					Enabled = Attached,
					ViewMode = observedValue(observeViewMode),
					SetViewMode = function(viewMode: ViewMode)
						Remotes.SetViewMode:FireServer(orbPart, viewMode)
					end,
					Detach = function()
						Remotes.DetachPlayer:FireServer(orbPart)
					end,
					IsSpeaker = observedValue(observeSpeaker:Pipe{
						Rx.map(function(speaker: Player?)
							return speaker == Players.LocalPlayer
						end)
					}),
					Audience = observedValue(observeShowAudience),
					SetAudience = function(audience)
						Remotes.SetShowAudience:FireServer(orbPart, audience)
					end,
					OrbcamActive = OrbcamActive,
					SetOrbcamActive = function(active)
						Remotes.OrbcamStatus:FireServer(orbPart, active)
						OrbcamActive:set(active)
					end,
					Teleport = function()
						Remotes.Teleport:FireServer(orbPart)
					end,
					SendEmoji = function(emojiName: string)
						Remotes.SendEmoji:FireServer(orbPart, emojiName)
					end,
					ReceiveEmojiSignal = Remotes.SendEmoji.OnClientEvent,
					WaypointOnly = observedValue(observeWaypointOnly),
					SetWaypointOnly = function(waypointOnly: boolean)
						Remotes.SetWaypointOnly:FireServer(orbPart, waypointOnly)
					end,
				}
			}
		}
	)

	return {
		Destroy = function()
			destructor:Destroy()
		end
	}
end

return OrbClient