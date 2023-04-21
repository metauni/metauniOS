local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

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
	local Waypoint: Value<Vector3> = Value(orbPart.Position)

	local speakerValue = NewTracked "ObjectValue" {
		Name = "Speaker",
		Parent = orbPart,
	}
	local observeSpeaker: Observable<Player?> = 
		Rx.of(speakerValue):Pipe {
			Rxi.property("Value"),
		}

	local PlayerToOrb: Folder = ReplicatedStorage.OrbController:FindFirstChild("PlayerToOrb")

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
			end
		end)
	)


	destructor:Add(
		Players.PlayerRemoving:Connect(function(player: Player)
			if speakerValue.Value == player then
				speakerValue.Value = nil
			end
		end)
	)

	destructor:Add(
		Remotes.DetachPlayer.OnServerEvent:Connect(function(player: Player, triggeredOrb: Part)
			if triggeredOrb == orbPart then
				if speakerValue.Value == player then
					speakerValue.Value = nil
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

	Rx.of(Players):Pipe {
		Rxi.children(),
		Rx.switchMap(function(players: {Players})
			local AttachedOrNilObservers = {}
			for _, player in players do
				AttachedOrNilObservers[player] = Rx.of(player.PlayerGui):Pipe {
					Rxi.findFirstChildWithClass("ObjectValue", "AttachedOrb"),
					Rxi.property("Value"),
					Rx.map(function(attachedOrb: Part)
						return attachedOrb == orbPart or nil
					end)
				}
			end

			-- This emits the latest set of players attached to this orb
			return Rx.combineLatest(AttachedOrNilObservers)
		end),
	}:Pipe {
		
	}

	local viewModeValue = NewTracked "StringValue" {
		Name = "ViewMode",
		Value = "double",
		Parent = orbPart,
	}
	local observeViewMode: Observable<Player?> = 
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
					return Waypoint:get() or Vector3.zero
				end),
				Attachment0 = orbAttachment,
				MaxForce = 10000,
				MaxVelocity = 8,
			},
		}
	}

	-- Emit the speaker position every second, but only when it has changed
	local function observeSpeakerMovementThrottled(interval: number)
		return observeSpeaker:Pipe {
			Rxi.property("Character"),
			Rxi.property("PrimaryPart"),
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
			SpeakerPosition = observeSpeakerMovementThrottled(0.5),
			-- Move Direction
			MoveDirection = observeSpeaker:Pipe {
				Rxi.property("Character"),
				Rxi.findFirstChildOfClass("Humanoid"),
				Rxi.property("MoveDirection"),
				Rxi.notNil(),
			},
			ViewMode = observeViewMode,
			-- Whenever Speaker Attachment gets parented to the speaker
			_attachment = Rx.fromSignal(speakerAttachment.AncestryChanged),
		})
		:Subscribe(function(data)
			local speakerPosition: Vector3? = data.SpeakerPosition
			local moveDirection: Vector3? = data.MoveDirection
			local viewMode: "single" | "double" | "freecam" | nil = data.ViewMode

			if viewMode == nil or viewMode == "freecam" then
				return
			end

			-- If the orb is already looking at a board
			-- don't move it until speaker is out of shot.
			if viewMode == "single" and poi1Value.Value and not poi2Value.Value then

				local focalPosition = poi1Value.Value.Position
				if poi2Value.Value then
					focalPosition += poi2Value.Value.Position
					focalPosition /= 2
				end

				local waypoint = Waypoint:get(false)
				local orbLook = (focalPosition - waypoint).Unit
				local horizontalFOVRad = 2 * math.atan(Config.AssumedAspectRatio * math.tan(math.rad(Config.OrbcamFOV)/2))
				local cosAngleToSpeaker = ((speakerPosition - waypoint).Unit):Dot(orbLook)

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

			-- Speaker stopped in shot of camera
			if true or moveDirection.Magnitude == 0 then
				poi1Value.Value = firstPart
				poi2Value.Value = secondPart

				-- Put orb in camera position, but lower it down to the ground
				local waypoint = camCFrame.Position
				local raycastResult = workspace:Raycast(camCFrame.Position, -Vector3.yAxis * 50, raycastParams)
				if raycastResult then
					waypoint = Vector3.new(waypoint.X, raycastResult.Position.Y, waypoint.Z)
				end
				Waypoint:set(waypoint)
			end
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

	destructor:Add(
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

	destructor:Add(
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