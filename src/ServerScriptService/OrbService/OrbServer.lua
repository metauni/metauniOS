local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local Sift = require(ReplicatedStorage.Packages.Sift)
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local New = Fusion.New
local Hydrate = Fusion.Hydrate
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children

local Destructor = require(ReplicatedStorage.Destructor)
local Rx = require(ReplicatedStorage.Rx)
local Rxi = require(ReplicatedStorage.Rxi)
local Rxf = require(ReplicatedStorage.Rxf)
local BoardService = require(ServerScriptService.BoardService)
local CameraUtils = require(ReplicatedStorage.OrbController.CameraUtils)

local Remotes = ReplicatedStorage.OrbController.Remotes
local Config = require(ReplicatedStorage.OrbController.Config)

local OrbServer = {}

function OrbServer.new(orbPart: Part)

	local destructor = Destructor.new()

	-- Wrap Fusion.New in a destructor
	local NewTracked = function(className: string)
		return function (props)
			return destructor:Add(New(className)(props))
		end
	end

	-- The orb will be aligned with physics to this position
	-- If nil, and there is a speaker, the orb will chase the speaker
	local Waypoint: Value<CFrame> = Value(orbPart.CFrame)

	local speakerValue = NewTracked "ObjectValue" {
		Name = "Speaker",
		Parent = orbPart,
	}
	local observeSpeaker: Observable<Player?> = 
		Rx.of(speakerValue):Pipe {
			Rxi.property("Value"),
		}

	local PlayerToOrb: Folder = ReplicatedStorage.OrbController.PlayerToOrb

	local observeAttached =
		Rx.of(Players):Pipe {
			Rxi.children(),
			Rx.switchMap(function(players: {Players})
				local AttachedOrNilObservers = {}
				for _, player in players do
					AttachedOrNilObservers[player] = Rx.of(PlayerToOrb):Pipe {
						Rxi.findFirstChildWithClass("ObjectValue", tostring(player.UserId)),
						Rxi.property("Value"),
						Rx.map(function(attachedOrb: Part)
							return attachedOrb == orbPart or nil
						end)
					}
				end

				-- This emits the latest set of players attached to this orb
				return Rx.combineLatest(AttachedOrNilObservers)
			end),
		}

	local AttachedPlayers: Value<{[Player]: true?}> = Value({})
	observeAttached:Subscribe(function(attachedPlayers)
		AttachedPlayers:set(attachedPlayers)
	end)

	destructor:Add(
		Remotes.SetListener.OnServerEvent:Connect(function(player: Player, triggeredOrb: Part)
			if triggeredOrb ~= orbPart then
				return
			end

			local attachedOrb = PlayerToOrb:FindFirstChild(player.UserId) or New "ObjectValue" {
				Name = player.UserId,
				Parent = PlayerToOrb,
			}
			attachedOrb.Value = orbPart
		end)
	)

	local attachSoundIds = {
		7873470625,
		7873470425,
		7873469842,
		7873470126,
		7864771146,
		7864770493,
		8214755036,
		8214754703
	}
	
	local attachSound = NewTracked "Sound" {
		Name = "AttachSound",
		Parent = orbPart,
		
		-- SoundId set randomly on play
		RollOffMode = Enum.RollOffMode.InverseTapered,
		RollOffMaxDistance = 200,
		RollOffMinDistance = 10,
		Playing = false,
		Looped = false,
		Volume = 0.2,
	}
	
	local detachSound = NewTracked "Sound" {
		Name = "DetachSound",
		Parent = orbPart,
		
		SoundId = "rbxassetid://7864770869",
		RollOffMode = Enum.RollOffMode.InverseTapered,
		RollOffMaxDistance = 200,
		RollOffMinDistance = 10,
		Playing = false,
		Looped = false,
		Volume = 0.2,
	}

	destructor:Add(
		Remotes.SetSpeaker.OnServerEvent:Connect(function(player: Player, triggeredOrb: Part)
			if triggeredOrb ~= orbPart then
				return
			end

			local attachedOrb = PlayerToOrb:FindFirstChild(player.UserId) or New "ObjectValue" {
				Name = player.UserId,
				Parent = PlayerToOrb,
			}
			attachedOrb.Value = orbPart

			if RunService:IsStudio() or player:GetAttribute("metaadmin_isscribe") then
				speakerValue.Value = player
				
				attachSound.SoundId = "rbxassetid://"..attachSoundIds[math.random(1, #attachSoundIds)]
				attachSound:Play()
			end
		end)
	)


	destructor:Add(
		Players.PlayerRemoving:Connect(function(player: Player)
			if speakerValue.Value == player then
				speakerValue.Value = nil
				detachSound:Play()
			end
		end)
	)

	destructor:Add(
		Remotes.DetachPlayer.OnServerEvent:Connect(function(player: Player, triggeredOrb: Part)
			if triggeredOrb == orbPart then
				if speakerValue.Value == player then
					speakerValue.Value = nil
					detachSound:Play()
				end

				local attachedOrb = PlayerToOrb:FindFirstChild(player.UserId)
				if attachedOrb then
					attachedOrb.Value = nil
				end
			end
		end)
	)

	destructor:Add(
		Remotes.TeleportToOrb.OnServerEvent:Connect(function(player: Player, triggeredOrb: Part)
			if triggeredOrb == orbPart then
				if player.Character then
					player.Character:PivotTo(orbPart.CFrame + Vector3.new(0,5 * orbPart.Size.Y,0))
				end
			end
		end)
	)

	destructor:Add(
		Remotes.SendEmoji.OnServerEvent:Connect(function(player: Player, triggeredOrb: Part, emojiName: string)
			if triggeredOrb == orbPart then
				for attachedPlayer in AttachedPlayers:get(false) do
					if attachedPlayer ~= player then
						Remotes.SendEmoji:FireClient(attachedPlayer, emojiName)
					end
				end
			end
		end)
	)

	destructor:Add(
		Remotes.OrbcamStatus.OnServerEvent:Connect(function(player: Player, triggeredOrb: Part)
			if triggeredOrb == orbPart then
				if game.Workspace.StreamingEnabled then
					player:RequestStreamAroundAsync(orbPart.Position)
				end
			end
		end)
	)

	local viewModeValue = NewTracked "StringValue" {
		Name = "ViewMode",
		Value = "double",
		Parent = orbPart,
	}
	local observeViewMode: Observable<String> = 
		Rx.of(viewModeValue):Pipe {
			Rxi.property("Value"),
		}
		
	destructor:Add(
		Remotes.SetViewMode.OnServerEvent:Connect(function(player: Player, triggeredOrb: Part, viewMode: "single" | "double" | "freecam")
			if triggeredOrb ~= orbPart then
				return
			end
			if speakerValue.Value == player then
				viewModeValue.Value = viewMode
			end
		end)
	)

	local showAudienceValue = NewTracked "BoolValue" {
		Name = "ShowAudience",
		Value = false,
		Parent = orbPart,
	}
	local observeShowAudience: Observable<boolean> = 
		Rx.of(showAudienceValue):Pipe {
			Rxi.property("Value"),
		}

	destructor:Add(
		Remotes.SetShowAudience.OnServerEvent:Connect(function(player: Player, triggeredOrb: Part, showAudience: boolean)
			if triggeredOrb ~= orbPart then
				return
			end
			if speakerValue.Value == player then
				showAudienceValue.Value = showAudience
			end
		end)
	)

	local SpeakerGroundOffset: Value<Vector3> = Value(Vector3.zero)

	local orbAttachment = NewTracked "Attachment" {
		Parent = orbPart
	}
	local speakerAttachment = NewTracked "Attachment" {
		-- Parent: set via observable
		Position = Computed(function()
			return SpeakerGroundOffset:get() + Vector3.new(0,0,-5)
		end),
	}

	-- Parent the speaker attachment to the speaker
	destructor:Add(
		observeSpeaker:Pipe {
			Rxi.property("Character"),
			Rxi.property("PrimaryPart"),
		}:Subscribe(function(rootPart: Part?)
			if rootPart then
				speakerAttachment.Parent = rootPart
				orbPart.Anchored = false
			else
				orbPart.Anchored = true
			end
		end)
	)

	-- Position the speaker attachment offset in front of feet
	destructor:Add(
		observeSpeaker:Pipe {
			Rxi.property("Character"),
			Rxi.findFirstChildWithClass("MeshPart", "RightFoot"),
			Rxi.notNil(),
		}:Subscribe(function(rightFoot: BasePart)
			local character = rightFoot.Parent :: Model
			local yDelta = rightFoot.Position.Y - character:GetPivot().Y
			SpeakerGroundOffset:set(Vector3.new(0,yDelta,0))
		end)
	)

	-- Align the orb to the waypoint position, if not nil, otherwise to the speaker
	NewTracked "Folder" {
		
		Name = "Alignment",
		Parent = orbPart,

		[Children] = {
			New "AlignPosition" {
		
				Name = "AlignPositionToSpeaker",
				
				Enabled = Computed(function()
					return Waypoint:get() == nil
				end),
				Mode = Enum.PositionAlignmentMode.TwoAttachment,
				Attachment0 = orbAttachment,
				Attachment1 = speakerAttachment,
				MaxForce = 100000,
				MaxVelocity = 16,
				ApplyAtCenterOfMass = true,
			},
			New "AlignPosition" {
	
				Name = "AlignPositionToWaypoint",

				Enabled = Computed(function()
					return Waypoint:get() ~= nil
				end),
				Mode = Enum.PositionAlignmentMode.OneAttachment,
				Position = Computed(function()
					local waypoint = Waypoint:get()
					return waypoint and waypoint.Position or Vector3.zero
				end),
				Attachment0 = orbAttachment,
				MaxForce = 10000,
				MaxVelocity = 8,
			},
		}
	}

	-- Emit the observed part's position every second, but only when it has changed
	local function throttledMovement(interval: number)
		return function(source: Observable)
			return source:Pipe {
				Rx.switchMap(function(part: Part)
					if not part then
						return Rx.never
					end
					return Rx.timer(0, interval):Pipe({
						Rx.map(function()
							return part.Position
						end)
					})
				end),
				Rx.distinct(),
			}
		end
	end
	
	local poi1Value = NewTracked "ObjectValue" {
		Name = "poi1",
		Parent = orbPart,
	}
	
	local poi2Value = NewTracked "ObjectValue" {
		Name = "poi2",
		Parent = orbPart,
	}

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {orbPart}

	-- Watch speaker movement to update Waypoint
	destructor:Add(
		Rx.combineLatest({
			-- Speaker Movement
			SpeakerPosition = observeSpeaker:Pipe {
				Rxi.property("Character"),
				Rxi.property("PrimaryPart"),
				throttledMovement(0.5),
			},
			ViewMode = observeViewMode,
			-- Whenever Speaker Attachment gets parented to the speaker
			_attachment = Rx.fromSignal(speakerAttachment.AncestryChanged),
		})
		:Subscribe(function(data)
			local speakerPosition: Vector3? = data.SpeakerPosition
			local viewMode: "single" | "double" | "freecam" | nil = data.ViewMode

			if viewMode == nil or viewMode == "freecam" then
				return
			end

			-- If the orb is already looking at a board
			-- don't move it until speaker is out of shot.
			if viewMode == "single" and poi1Value.Value and not poi2Value.Value then

				local waypoint: CFrame  = Waypoint:get(false)
				local horizontalFOVRad = 2 * math.atan(Config.AssumedAspectRatio * math.tan(math.rad(Config.OrbcamFOV)/2))
				local cosAngleToSpeaker = ((speakerPosition - waypoint).Unit):Dot(waypoint.LookVector)

				local ANGLE_BUFFER = math.rad(0)
				local insideCamView = cosAngleToSpeaker >= math.cos(horizontalFOVRad/2 + ANGLE_BUFFER)

				if insideCamView then
					return
				end
			end


			local boardByProximity = {}
			local k = if viewMode == "single" then 1 else 2

			for _=1, k do
				local minSoFar = math.huge
				local nearestBoard
				for _, board in BoardService.Boards do
					if not table.find(boardByProximity, board) then
						local distance = (board.SurfaceCFrame.Position - speakerPosition).Magnitude
						if distance < minSoFar then
							nearestBoard = board
							minSoFar = distance
						end
					end
				end
				table.insert(boardByProximity, nearestBoard)
			end

			if #boardByProximity == 0 then
				if speakerAttachment.Parent then
					poi1Value.Value = nil
					poi2Value.Value = nil
					Waypoint:set(nil)
				end
				return
			end

			local firstBoard = boardByProximity[1]
			local firstPart = if firstBoard then firstBoard._instance else nil
			local secondBoard = boardByProximity[2]
			local secondPart = if secondBoard then secondBoard._instance else nil

			if secondBoard then
				local betweenBoards = (firstPart.Position - secondPart.Position).Magnitude

				local maxAxisSizeFirstBoard = math.max(firstPart.Size.X, firstPart.Size.Y, firstPart.Size.Z)
				if betweenBoards > maxAxisSizeFirstBoard * 2 then
					secondBoard = nil
					secondPart = nil
				end
			end

			local camCFrame, focalPosition =
				CameraUtils.ViewBoardsAtFOV(
					{firstBoard, secondBoard},
					Config.OrbcamFOV,
					Config.AssumedAspectRatio,
					Config.OrbcamBuffer
				)

			local horizontalFOVRad = 2 * math.atan(Config.AssumedAspectRatio * math.tan(math.rad(Config.OrbcamFOV)/2))
			local cosAngleToSpeaker = ((speakerPosition - camCFrame.Position).Unit):Dot(camCFrame.LookVector.Unit)
			local distanceToFocalPoint = (focalPosition - camCFrame.Position).Magnitude
			local distanceToCharacter = (speakerPosition - camCFrame.Position).Magnitude

			local ANGLE_BUFFER = math.rad(2.5)
			local outsideCamView = cosAngleToSpeaker < math.cos(horizontalFOVRad/2 + ANGLE_BUFFER)
			local tooFarBehindBoard = distanceToCharacter > 2 * distanceToFocalPoint

			if outsideCamView or tooFarBehindBoard then
				if speakerAttachment.Parent then
					poi1Value.Value = nil
					poi2Value.Value = nil
					Waypoint:set(nil)
				end
				return
			end

			-- Speaker meets conditions to set waypoint in front of pois

			poi1Value.Value = firstPart
			poi2Value.Value = secondPart

			-- Put orb in camera position, but lower it down to the ground (if possible)
			local waypoint: CFrame = camCFrame
			local raycastResult = workspace:Raycast(camCFrame.Position, -Vector3.yAxis * 50, raycastParams)
			if raycastResult then
				waypoint = waypoint - waypoint.Position + Vector3.new(waypoint.X, raycastResult.Position.Y, waypoint.Z)
			end
			Waypoint:set(waypoint)
		end)
	)

	local function Ring(props)
		-- Make the ring by subtracting two cylinders
		local ringOuter = New "Part" {
			Size = Vector3.new(0.10, props.Size.Y + props.OuterWidth, props.Size.Y + props.OuterWidth),
			CFrame = CFrame.new(0,0,0),
			Shape = "Cylinder",
			Color = props.Color,
		}
	
		local ringInner = New "Part" {
			Size = Vector3.new(0.15,props.Size.Y + props.InnerWidth,props.Size.Y + props.InnerWidth),
			CFrame = CFrame.new(0,0,0),
			Shape = "Cylinder",
			Color = props.Color,
		}
	
		ringOuter.Parent = workspace
		ringInner.Parent = workspace

		-- Pass through all other props to resulting ring instance
		local passThroughProps = table.clone(props)
		passThroughProps.InnerWidth = nil
		passThroughProps.OuterWidth = nil
		passThroughProps.Size = nil
		passThroughProps.Color = nil
		
		local ring = Hydrate(ringOuter:SubtractAsync({ringInner}))(passThroughProps)

		ringOuter:Destroy()
		ringInner:Destroy()

		return ring
	end

	local EyeRingAttachment = Value()
	local EyeRingOrientationCFrame = Value(orbPart.CFrame * CFrame.Angles(0, math.pi/2, 0))

	local eyeRing = destructor:Add(
		Ring {
			Name = "EyeRing",
			Parent = orbPart,
			Size = orbPart.Size,
			Material = Enum.Material.Neon,
			Color = Color3.new(0,0,0),
			CastShadow = false,
			CanCollide = false,
			CFrame = EyeRingOrientationCFrame:get(false),

			InnerWidth = 0.5,
			OuterWidth = 1,

			[Children] = {
				New "Attachment" {
					[Fusion.Ref] = EyeRingAttachment,
				},
				New "AlignPosition" {
					Mode = Enum.PositionAlignmentMode.TwoAttachment,
					Attachment0 = EyeRingAttachment,
					Attachment1 = orbAttachment,
					MaxVelocity = math.huge,
					MaxForce = math.huge,
					RigidityEnabled = true,
				},
				New "AlignOrientation" {
					Mode = Enum.OrientationAlignmentMode.OneAttachment,
					Attachment0 = EyeRingAttachment,
					CFrame = EyeRingOrientationCFrame,
				},
			},
		}
	)

	local EarRingAttachment = Value()
	local EarOrientationCFrame = Value(orbPart.CFrame)

	local earRing = destructor:Add(
		Ring {
			Name = "EarRing",
			Parent = orbPart,
			Size = orbPart.Size,
			Material = Enum.Material.Neon,
			Color = Color3.new(1,1,1),
			Transparency = 0.8,
			CastShadow = false,
			CanCollide = false,
			CFrame = EarOrientationCFrame:get(false) * CFrame.Angles(0, math.pi/2, 0),
			
			InnerWidth = 0.1,
			OuterWidth = 0.5,

			[Children] = {
				New "Attachment" {
					[Fusion.Ref] = EarRingAttachment,
				},
				New "AlignPosition" {
					Mode = Enum.PositionAlignmentMode.TwoAttachment,
					Attachment0 = EarRingAttachment,
					Attachment1 = orbAttachment,
					MaxVelocity = math.huge,
					MaxForce = math.huge,
					RigidityEnabled = true,
				},
				New "AlignOrientation" {
					Mode = Enum.OrientationAlignmentMode.OneAttachment,
					Attachment0 = EarRingAttachment,
					CFrame = Computed(function()
						return EarOrientationCFrame:get() * CFrame.Angles(0, math.pi/2, 0)
					end),
				},
			},
		}
	)

	local EarPartAttachment = Value()

	destructor:Add(
		New "Part" {
			Name = "EarPart",
			Parent = orbPart,
			Size = Vector3.new(1,1,1),
			Transparency = 1,
			CastShadow = false,
			CanQuery = false,
			CanCollide = false,
			CFrame = orbPart.CFrame,

			[Children] = {
				New "Attachment" {
					[Fusion.Ref] = EarPartAttachment,
				},
				New "AlignPosition" {
					Mode = Enum.PositionAlignmentMode.TwoAttachment,
					Attachment0 = EarPartAttachment,
					Attachment1 = orbAttachment,
					MaxVelocity = math.huge,
					MaxForce = math.huge,
					RigidityEnabled = true,
				},
				New "AlignOrientation" {
					Mode = Enum.OrientationAlignmentMode.OneAttachment,
					Attachment0 = EarPartAttachment,
					CFrame = EarOrientationCFrame,
				},
			},
		}
	)

	do
		local maids = {}

		Rxi.playerLifetime():Subscribe(function(player: Player, added: boolean)
			
			if maids[player] then
				maids[player]:Destroy()
				maids[player] = nil
			end
			
			if not added then
				return
			end

			maids[player] = Destructor.new()

			local earHalo: UnionOperation = earRing:Clone()
			local eyeHalo: UnionOperation = eyeRing:Clone()
			maids[player]:Add(earHalo)
			maids[player]:Add(eyeHalo)
			earHalo:ClearAllChildren()
			eyeHalo:ClearAllChildren()
			earRing.Archivable = false
			eyeHalo.Archivable = false
			local earWeld: WeldConstraint = New "WeldConstraint" {
				Parent = earHalo,
				Part0 = earHalo,
			}
			local eyeWeld: WeldConstraint = New "WeldConstraint" {
				Parent = eyeHalo,
				Part0 = eyeHalo,
			}

			maids[player]:Add(
				Rx.combineLatest{
					Head = Rx.of(player):Pipe{
						Rxi.property("Character"),
						Rxi.findFirstChildWithClass("MeshPart", "Head"),
					},
					OrbcamActive = Rx.fromSignal(Remotes.OrbcamStatus.OnServerEvent):Pipe{
						Rx.map(function(triggeredPlayer: Player, triggeredOrb: Part, active: boolean)
							return (triggeredPlayer == player) and triggeredOrb == orbPart and active
						end),
						Rx.defaultsTo(false)
					},
					Attached = Rx.of(PlayerToOrb):Pipe{
						Rxi.findFirstChildWithClass("ObjectValue", tostring(player.UserId)),
						Rxi.property("Value"),
						Rx.map(function(attachedOrb: Part?)
							return attachedOrb == orbPart
						end),
					},
					Speaker = observeSpeaker,
				}:Subscribe(function(data)
					local head: Part? = data.Head
					local orbcamActive: boolean = data.OrbcamActive
					local attached: boolean = data.Attached
					local speaker: Player? = data.Speaker

					local showEar = attached and head and (speaker ~= player)
					local showEye = showEar and orbcamActive

					if showEar then
						earHalo.Parent = head
						earHalo.CFrame = head.CFrame * CFrame.new(0,Config.HaloOffset,0) * CFrame.Angles(0,0,math.pi/2)
						earWeld.Part1 = head
					else
						earHalo.Parent = nil
						earWeld.Part1 = nil
					end

					if showEye then
						eyeHalo.Parent = head
						eyeHalo.CFrame = head.CFrame * CFrame.new(0,Config.HaloOffset,0) * CFrame.Angles(0,0,math.pi/2)
						eyeWeld.Part1 = head
					else
						eyeHalo.Parent = nil
						eyeWeld.Part1 = nil
					end
				end)
			)

			local ghost: Model

			maids[player]:Add(function()
				if ghost then
					ghost:Destroy()
					ghost = nil
				end
			end)

			maids[player]:Add(
				Rx.combineLatest{
					Waypoint = Rxf.fromState(Waypoint),
					Character = Rx.of(player):Pipe{
						Rxi.property("Character")
					},
					Speaker = observeSpeaker,
					Attached = Rx.of(PlayerToOrb):Pipe{
						Rxi.findFirstChildWithClass("ObjectValue", tostring(player.UserId)),
						Rxi.property("Value"),
						Rx.map(function(attachedOrb: Part?)
							return attachedOrb == orbPart
						end),
					},
					_movement = Rx.merge{
						Rx.of(player):Pipe{
							Rxi.property("Character"),
							Rxi.property("PrimaryPart"),
							throttledMovement(0.5),
						},
						observeSpeaker:Pipe{
							Rxi.property("Character"),
							Rxi.property("PrimaryPart"),
							throttledMovement(0.5),
						},
					},
				}:Subscribe(function(data)
					local waypoint: CFrame? = data.Waypoint
					local character: Model? = data.Character
					local speaker: Player? = data.Speaker
					local attached: boolean = data.Attached

					local ghostTarget: CFrame = waypoint or orbPart.CFrame

					if
						not attached
						-- or
						-- not speaker
						or
						(character and (character.PrimaryPart.Position - ghostTarget.Position).Magnitude <= Config.GhostSpawnRadius)
						or
						(not ghost and not character)
					then
						if ghost then
							
							do -- Spooky ghost fades away ooooooooOOOOOooo
								for _, desc in ipairs(ghost:GetDescendants()) do
									if desc:IsA("BasePart") then
										TweenService:Create(desc, TweenInfo.new(
											2, -- Time
											Enum.EasingStyle.Linear, -- EasingStyle
											Enum.EasingDirection.Out, -- EasingDirection
											0, -- RepeatCount (when less than zero the tween will loop indefinitely)
											false, -- Reverses (tween will reverse once reaching it's goal)
											0 -- DelayTime
										), {Transparency = 1}):Play()
									end
								end
							end

							local _ghost = ghost
							ghost = nil
							task.delay(2.5, function()
								_ghost:Destroy()
							end)
						end
						return
					end

					if not ghost then
						-- By *logic*, character exists and is within spawn radius

						character.Archivable = true
						ghost = character:Clone()
						character.Archivable = false

						ghost.Name = character.Name.."-ghost"

						pcall(function()
							if ghost.Head:FindFirstChild("EarRing") then
								ghost.Head:FindFirstChild("EarRing"):Destroy()
							end
							if ghost.Head:FindFirstChild("EyeRing") then
								ghost.Head:FindFirstChild("EyeRing"):Destroy()
							end
						end)

						for _, desc in ipairs(ghost:GetDescendants()) do
							if desc:IsA("BasePart") then
								desc.Transparency = 1 - (0.2 * (1 - desc.Transparency))
								desc.CastShadow = false
								desc.CanCollide = false
							end
						end
						
						ghost.Parent = workspace
					end

					-- ghost exists now

					-- TODO: upperTorso/lowerTorso CanCollide seems to reactive itself
					-- TODO: needs more testing

					if (ghostTarget.Position - ghost.PrimaryPart.Position).Magnitude > Config.GhostSpawnRadius then
						local humanoid: Humanoid = ghost.Humanoid

						-- Stand somewhere sensible behind the orb
						local angle = math.pi * (3/4) * math.random() - math.pi/2
						local standBackDistance = Config.GhostMinOrbRadius + (Config.GhostMaxOrbRadius - Config.GhostMinOrbRadius) * math.random()
						local position = (ghostTarget * CFrame.Angles(0,angle,0) * CFrame.new(0,0,standBackDistance)).Position

						for _, desc in ipairs(ghost:GetDescendants()) do
							if desc:IsA("BasePart") then
								desc.CastShadow = false
								desc.CanCollide = false
							end
						end

						local animation = script.Parent.WalkAnim
						local animationTrack = humanoid.Animator:LoadAnimation(animation)
						animationTrack:Play()
						
						humanoid.MoveToFinished:Once(function()
							
							animationTrack:Stop()

							if not ghost or not ghost.PrimaryPart then
								return
							end

							local ghostPos = ghost.PrimaryPart.Position
							local speakerPosXZ = Vector3.new(orbPart.Position.X,ghostPos.Y,orbPart.Position.Z)
							-- local speakerPosXZ = Vector3.new(speakerPos.X,ghostPos.Y,speakerPos.Z)


							local tweenInfo = TweenInfo.new(
								0.5, -- Time
								Enum.EasingStyle.Linear, -- EasingStyle
								Enum.EasingDirection.Out, -- EasingDirection
								0, -- RepeatCount (when less than zero the tween will loop indefinitely)
								false, -- Reverses (tween will reverse once reaching it's goal)
								0 -- DelayTime
							)
							
							local ghostTween = TweenService:Create(ghost.PrimaryPart, tweenInfo, {CFrame = CFrame.lookAt(ghostPos, speakerPosXZ)})
							ghostTween:Play()
							
							ghost.UpperTorso.CanCollide = true
							ghost.LowerTorso.CanCollide = true
						end)
						humanoid:MoveTo(position)
					end
				end)
			)
		end)
	end

	local ringHeartbeatConnection
	destructor:Add(function()
		if ringHeartbeatConnection then
			ringHeartbeatConnection:Disconnect()
			ringHeartbeatConnection = nil
		end
	end)

	destructor:Add(
		Rx.combineLatest {
			SpeakerHead = observeSpeaker:Pipe {
				Rxi.property("Character"),
				Rxi.findFirstChild("Head"),
			},
			Poi1Pos = Rx.of(poi1Value):Pipe { Rxi.property("Value"), Rxi.property("Position") },
			Poi2Pos = Rx.of(poi2Value):Pipe { Rxi.property("Value"), Rxi.property("Position") },
		}
		:Subscribe(function(data)

			local pos1: Vector3? = data.Poi1Pos
			local pos2: Vector3? = data.Poi2Pos
			local head: BasePart? = data.SpeakerHead

			local target = pos1 or (head and head.Position) or nil
			if target and pos2 then
				target += pos2
				target /= 2
			end
			
			if ringHeartbeatConnection then
				ringHeartbeatConnection:Disconnect()
				ringHeartbeatConnection = nil
			end

			ringHeartbeatConnection = RunService.Heartbeat:Connect(function()
				if head then
					EarOrientationCFrame:set(CFrame.lookAt(orbPart.Position, head.Position))
				end
				if target then
					EyeRingOrientationCFrame:set(CFrame.lookAt(orbPart.Position, target) * CFrame.Angles(0, math.pi/2, 0))
				end
			end)
		end)
	)

	-- Like hydrate but returns a function that resets props to original values
	local function moisten(instance: Instance)
		return function (props: {any})
			local originalProps = {}
			for key, value in props do
				originalProps[key] = instance[key]
				instance[key] = value
			end

			return function ()
				for key, value in originalProps do
					instance[key] = value
				end
			end
		end
	end

	destructor:Add(
		moisten(orbPart) {
			Anchored = false,
			CanCollide = false,
		}
	)

	return {
		Destroy = function()
			destructor:Destroy()
		end
	}
end

return OrbServer