local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children

local Sift = require(ReplicatedStorage.Packages.Sift)
local Destructor = require(ReplicatedStorage.OS.Destructor)
local Rx = require(ReplicatedStorage.OS.Rx)
local Rxi = require(ReplicatedStorage.OS.Rxi)
local BoardService = require(ServerScriptService.OS.BoardService)
local CameraUtils = require(ReplicatedStorage.OS.OrbController.CameraUtils)
local Ring = require(script.Parent.Ring)

local Remotes = ReplicatedStorage.OS.OrbController.Remotes
local Config = require(ReplicatedStorage.OS.OrbController.Config)

local OrbServer = {}

function OrbServer.new(orbPart: Part)

	local destructor = Destructor.new()

	-- Transform an observable into a Fusion StateObject that
	-- holds the latest observed value
	local function observedValue(observable: Rx.Observable<T>): Value<T>
		local value = Value()
		destructor:Add(observable:Subscribe(function(newValue)
			value:set(newValue)
		end))
		return value 
	end

	-- Wrap Fusion.New in a destructor
	local NewTracked = function(className: string)
		return function (props)
			return destructor:Add(New(className)(props))
		end
	end

	-- The orb will be aligned with physics to this position
	-- If nil, and there is a speaker, the orb will chase the speaker
	local waypointValue: CFrameValue = NewTracked "CFrameValue" {
		Name = "Waypoint",
		Value = orbPart.CFrame,
		Parent = orbPart,
	}
	local observeWaypoint =
		Rx.of(waypointValue):Pipe {
			Rxi.property("Value"),
		}

	export type OrbMode = "follow" | "waypoint"
	local orbModeValue: StringValue = NewTracked "StringValue" {
		Name = "OrbMode",
		Value = "waypoint",
		Parent = orbPart,
	}
	local observeOrbMode =
		Rx.of(orbModeValue):Pipe {
			Rxi.property("Value"),
		}
		
	local waypointOnlyValue: BoolValue = NewTracked "BoolValue" {
		Name = "WaypointOnly",
		Value = false,
		Parent = orbPart,
	}
	local observeWaypointOnly =
		Rx.of(waypointOnlyValue):Pipe {
			Rxi.property("Value"),
		}

	local speakerValue = NewTracked "ObjectValue" {
		Name = "Speaker",
		Parent = orbPart,
	}
	local observeSpeaker: Observable<Player?> = 
		Rx.of(speakerValue):Pipe {
			Rxi.property("Value"),
		}

	local PlayerToOrb: Folder = ReplicatedStorage.OS.OrbController.PlayerToOrb

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
		Volume = 0.05,
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
		Volume = 0.05,
	}

	destructor:Add(
		Remotes.SetSpeaker.OnServerEvent:Connect(function(player: Player, triggeredOrb: Part)
			if triggeredOrb ~= orbPart then
				if speakerValue.Value == player then
					speakerValue.Value = nil
					detachSound:Play()
				end
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
		Remotes.SetListener.OnServerEvent:Connect(function(player: Player, triggeredOrb: Part)
			if triggeredOrb ~= orbPart then
				if speakerValue.Value == player then
					speakerValue.Value = nil
					detachSound:Play()
				end
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
		Value = "single",
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
	-- local observeShowAudience: Observable<boolean> = 
	-- 	Rx.of(showAudienceValue):Pipe {
	-- 		Rxi.property("Value"),
	-- 	}

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

	destructor:Add(
		Remotes.SetWaypointOnly.OnServerEvent:Connect(function(player: Player, triggeredOrb: Part, waypointOnly: boolean)
			if triggeredOrb ~= orbPart then
				return
			end
			if speakerValue.Value == player then
				waypointOnlyValue.Value = waypointOnly
			end
		end)
	)

	local SpeakerGroundOffset: Value<Vector3> = Value(Vector3.zero)

	local orbAttachment = NewTracked "Attachment" {
		Parent = orbPart
	}
	local speakerAttachment = NewTracked "Attachment" {
		-- Parent: set via observable
		Name = "SpeakerAttachment",
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
				
				Enabled = observedValue(observeOrbMode:Pipe {
					Rx.map(function(orbMode: OrbMode)
						return orbMode == "follow"
					end)
				}),
				Mode = Enum.PositionAlignmentMode.TwoAttachment,
				Attachment0 = orbAttachment,
				Attachment1 = speakerAttachment,
				MaxForce = math.huge,
				MaxVelocity = 16,
				ApplyAtCenterOfMass = true,
			},
			New "AlignPosition" {
	
				Name = "AlignPositionToWaypoint",

				Enabled = observedValue(observeOrbMode:Pipe {
					Rx.map(function(orbMode: OrbMode)
						return orbMode ~= "follow"
					end)
				}),
				Mode = Enum.PositionAlignmentMode.OneAttachment,
				Position = observedValue(observeWaypoint:Pipe {
					Rx.map(function(waypoint: CFrame)
						return waypoint.Position
					end),
				}),
				Attachment0 = orbAttachment,
				MaxForce = math.huge,
				MaxVelocity = 8,
			},
			New "AlignOrientation" {
				Mode = Enum.OrientationAlignmentMode.OneAttachment,
				Attachment0 = orbAttachment,
				CFrame = observedValue(observeWaypoint),
			},
		}
	}

	-- Emit the observed part's position (or nil) every second, but only when it has changed
	local function throttledMovement(interval: number)
		return function(source: Observable)
			return source:Pipe {
				Rx.switchMap(function(part: Part)
					return Rx.timer(0, interval):Pipe({
						Rx.map(function()
							return part and part.Position or nil
						end)
					})
				end),
				Rx.distinct(),
			}
		end
	end
	
	local poi1Value: ObjectValue = NewTracked "ObjectValue" {
		Name = "poi1",
		Parent = orbPart,
	}
	
	local poi2Value: ObjectValue = NewTracked "ObjectValue" {
		Name = "poi2",
		Parent = orbPart,
	}

	local nearestBoardValue: ObjectValue = NewTracked "ObjectValue" {
		Name = "NearestBoard",
		Parent = orbPart,
	}

	-- Watch speaker movement to update Waypoint and OrbMode
	destructor:Add(
		Rx.combineLatest({
			-- Speaker Movement
			SpeakerPosition = observeSpeaker:Pipe {
				Rxi.property("Character"),
				Rxi.findFirstChild("Head"),
				throttledMovement(0.5),
			},
			ViewMode = observeViewMode,
			WaypointOnly = observeWaypointOnly,
			-- Whenever Speaker Attachment gets parented to the speaker
			_attachment = Rx.fromSignal(speakerAttachment.AncestryChanged),
		})
		:Subscribe(function(data)
			local speakerPosition: Vector3? = data.SpeakerPosition
			local viewMode: "single" | "double" | "freecam" | nil = data.ViewMode
			local waypointOnly: boolean = data.WaypointOnly

			if viewMode == nil or viewMode == "freecam" or speakerPosition == nil then
				return
			end

			--[[
				Functions for determining whether speaker is within certain bounds.
				All calculations are XZ-plane relative.
			--]]

			local BUFFER = 10
			local function speakerInFrontOfFocal(camPos: Vector3, focalPos: Vector3)
				local camToSpeaker = (speakerPosition - camPos) * Vector3.new(1,0,1)
				local camToFocal = (focalPos - camPos) * Vector3.new(1,0,1)
				
				return camToSpeaker:Dot(camToFocal.Unit) <= camToFocal.Magnitude + BUFFER
			end

			local function speakerCloseToWaypoint(camPos: Vector3, focalPos: Vector3)
				local camToFocal = (focalPos - camPos) * Vector3.new(1,0,1)
				local focalToSpeaker = (speakerPosition - focalPos) * Vector3.new(1,0,1)
				
				return focalToSpeaker.Magnitude <= camToFocal.Magnitude + BUFFER
			end
			
			local function speakerInCamView(camPos: Vector3, focalPos: Vector3)
				local camToFocal = (focalPos - camPos) * Vector3.new(1,0,1)
				local horizontalFOVRad = 2 * math.atan(Config.AssumedViewportSize.X / Config.AssumedViewportSize.Y * math.tan(math.rad(Config.OrbcamFOV)/2))
				local cosAngleToSpeaker = ((speakerPosition - camPos).Unit):Dot(camToFocal.Unit)

				local ANGLE_BUFFER = math.rad(10)
				return cosAngleToSpeaker >= math.cos(horizontalFOVRad/2 + ANGLE_BUFFER)
			end

			-- Try not to move to next board in single mode until speaker is outside left/right bounds
			if viewMode == "single" and poi1Value.Value and not poi2Value.Value and waypointValue.Value then
				local boardPart = poi1Value.Value :: Part
				if speakerInCamView(waypointValue.Value.Position, boardPart.Position) then
					if speakerInFrontOfFocal(waypointValue.Value.Position, boardPart.Position) then
						return
					end
				end
			end

			local poiBoards = Sift.Dictionary.filter(BoardService.Boards, function(board)
				return not board._instance:HasTag("metaboard_personal_board")
			end)

			local firstBoard, firstPart do
				local minSoFar = math.huge
				for _, board in poiBoards do
					local distance = (board.SurfaceCFrame.Position - speakerPosition).Magnitude
					if distance < minSoFar then
						firstBoard = board
						firstPart = board._instance
						minSoFar = distance
					end
				end
			end

			if not firstBoard then
				nearestBoardValue.Value = nil
				poi1Value.Value = nil
				poi2Value.Value = nil
				if speakerAttachment.Parent then
					orbModeValue.Value = "follow"
				end
				return
			end
			
			nearestBoardValue.Value = firstPart

			-- Find next closest board with angle difference <90 degrees
			local secondBoard, secondPart
			if viewMode == "double" then
				local minSoFar = math.huge
				for _, board in poiBoards do
					local distance = (board.SurfaceCFrame.Position - speakerPosition).Magnitude
					local goodAngle = firstBoard.SurfaceCFrame.LookVector:Dot(board.SurfaceCFrame.LookVector) > 0
					
					local betweenBoards = (board.SurfaceCFrame.Position - firstBoard.SurfaceCFrame.Position).Magnitude
					local maxAxisSizeFirstBoard = math.max(firstPart.Size.X, firstPart.Size.Y, firstPart.Size.Z)
					local goodDistanceBetweenBoards = betweenBoards <= maxAxisSizeFirstBoard * 1.5
					if distance < minSoFar and goodAngle and goodDistanceBetweenBoards and board ~= firstBoard then
						secondBoard = board
						secondPart = board._instance
						minSoFar = distance
					end
				end
			end

			local camCFrame, focalPosition =
				CameraUtils.ViewBoardsAtFOV(
					{firstBoard, secondBoard},
					Config.OrbcamFOV,
					Config.AssumedViewportSize,
					Config.OrbcamBuffer
				)
			local closeEnough = speakerCloseToWaypoint(camCFrame.Position, focalPosition)
			local inFront = speakerInFrontOfFocal(camCFrame.Position, focalPosition)
			

			if not waypointOnly and not (closeEnough and inFront) then
				if speakerAttachment.Parent then
					poi1Value.Value = nil
					poi2Value.Value = nil
					orbModeValue.Value = "follow"
				end
				return
			end

			-- Speaker meets conditions to set waypoint in front of pois

			poi1Value.Value = firstPart
			poi2Value.Value = secondPart

			-- Put orb in camera position, but lower it down to the ground (if possible)
			local newWaypoint: CFrame = camCFrame
			
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			local exclude = {orbPart}
			for _, player in Players:GetPlayers() do
				if player.Character then
					table.insert(exclude, player.Character)
				end
			end
			raycastParams.FilterDescendantsInstances = exclude
			local raycastResult = workspace:Raycast(camCFrame.Position, -Vector3.yAxis * 50, raycastParams)
			
			if raycastResult then
				newWaypoint = newWaypoint - newWaypoint.Position + Vector3.new(newWaypoint.X, raycastResult.Position.Y, newWaypoint.Z)
			end
			waypointValue.Value = newWaypoint
			orbModeValue.Value = "waypoint"
		end)
	)

	local EyeRingAttachment = Value()
	local EyeRingOrientationCFrame = Value(orbPart.CFrame * CFrame.Angles(0, math.pi/2, 0))

	destructor:Add(
		Ring {
			Name = "EyeRing",
			Parent = orbPart,
			Material = Enum.Material.Neon,
			Color = Color3.new(0,0,0),
			CastShadow = false,
			CanCollide = false,
			CFrame = EyeRingOrientationCFrame:get(false),

			InnerDiameter = orbPart.Size.Y + 0.5,
			OuterDiameter = orbPart.Size.Y + 1,

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
			Material = Enum.Material.Neon,
			Color = Color3.new(1,1,1),
			Transparency = 0.8,
			CastShadow = false,
			CanCollide = false,
			CFrame = EarOrientationCFrame:get(false) * CFrame.Angles(0, math.pi/2, 0),
			
			InnerDiameter = orbPart.Size.Y + 0.1,
			OuterDiameter = orbPart.Size.Y + 0.5,

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