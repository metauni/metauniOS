--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local BoardService = require(ServerScriptService.OS.BoardService)
local CameraUtils = require(ReplicatedStorage.OS.OrbController.CameraUtils)
local Ring = require(script.Parent.Ring)
local Rx = require(ReplicatedStorage.Util.Rx)
local Sift = require(ReplicatedStorage.Packages.Sift)
local Config = require(ReplicatedStorage.OS.OrbController.Config)
local Stream = require(ReplicatedStorage.Util.Stream)
local U = require(ReplicatedStorage.Util.U)
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local t = require(ReplicatedStorage.Packages.t)

local checkViewMode = t.union(t.literal("single"), t.literal("double"), t.literal("freecam"))

export type OrbMode = "follow" | "waypoint"

local PlayerToOrb: Folder = ReplicatedStorage.OS.OrbController.PlayerToOrb
local ATTACH_SOUND_IDS = {
	7873470625,
	7873470425,
	7873469842,
	7873470126,
	7864771146,
	7864770493,
	8214755036,
	8214754703,
}

-- Emit the observed part's position (or nil) every second, but only when it has changed
local function throttledMovement(interval: number): (Stream.Stream<Instance?>) -> Stream.Stream<Vector3?>
	return function(source: Stream.Stream<Instance?>)
		local function toInnerStream(part: Instance?)
			return Stream.map(function()
				return if part then (part :: any).Position else nil
			end)(Stream.counter(interval))
		end

		return Stream.skipUnchanged(Stream.switchMap(toInnerStream)(source))
	end
end

local function setupSpeakerAttachment(self: OrbServer, scope: U.Scope, orbPart: Part, speakerAttachment: Attachment)
	-- Parent the speaker attachment to the speaker
	local SpeakerPrimaryPart =
		Stream.toProperty("PrimaryPart")(Stream.fromValueBase(self.SpeakerCharacter :: ObjectValue))
	local SpeakerRightFoot =
		Stream.toFirstChild("RightFoot")(Stream.fromValueBase(self.SpeakerCharacter :: ObjectValue))
	scope:insert(SpeakerPrimaryPart(function(rootPart)
		if rootPart then
			speakerAttachment.Parent = rootPart
			orbPart.Anchored = false
		else
			orbPart.Anchored = true
		end
	end))

	-- Position the speaker attachment offset in front of feet
	scope:insert(SpeakerRightFoot(function(rightFoot)
		if rightFoot then
			local character = rightFoot.Parent :: Model
			local yDelta = (rightFoot :: any).Position.Y - character:GetPivot().Y
			self.SpeakerGroundOffset.Value = Vector3.new(0, yDelta, 0)
		end
	end))
end

local function followSpeakerMovement(self: OrbServer, scope: U.Scope, orbPart: Part, speakerAttachment: Attachment)
	-- Watch speaker movement to update Waypoint and OrbMode
	local SpeakerHead: Stream.Stream<Instance?> =
		Stream.toFirstChild("Head")(Stream.fromValueBase(self.SpeakerCharacter :: ObjectValue))
	local SpeakerHeadPosition = throttledMovement(0.5)(SpeakerHead)

	scope:insert(
		Stream.listen4(
			SpeakerHeadPosition,
			Stream.fromValueBase(self.ViewMode :: StringValue),
			Stream.fromValueBase(self.WaypointOnly :: BoolValue),
			Stream.fromSignal(speakerAttachment.AncestryChanged),
			function(speakerPosition, viewMode, waypointOnly, _)
				if viewMode == nil or viewMode == "freecam" or speakerPosition == nil then
					return
				end

				--[[
						Functions for determining whether speaker is within certain bounds.
						All calculations are XZ-plane relative.
					--]]

				local BUFFER = 10
				local function speakerInFrontOfFocal(camPos: Vector3, focalPos: Vector3)
					local camToSpeaker = (speakerPosition - camPos) * Vector3.new(1, 0, 1)
					local camToFocal = (focalPos - camPos) * Vector3.new(1, 0, 1)

					return camToSpeaker:Dot(camToFocal.Unit) <= camToFocal.Magnitude + BUFFER
				end

				local function speakerCloseToWaypoint(camPos: Vector3, focalPos: Vector3)
					local camToFocal = (focalPos - camPos) * Vector3.new(1, 0, 1)
					local focalToSpeaker = (speakerPosition - focalPos) * Vector3.new(1, 0, 1)

					return focalToSpeaker.Magnitude <= camToFocal.Magnitude + BUFFER
				end

				local function speakerInCamView(camPos: Vector3, focalPos: Vector3)
					local camToFocal = (focalPos - camPos) * Vector3.new(1, 0, 1)
					local horizontalFOVRad = 2
						* math.atan(
							Config.AssumedViewportSize.X
								/ Config.AssumedViewportSize.Y
								* math.tan(math.rad(Config.OrbcamFOV) / 2)
						)
					local cosAngleToSpeaker = ((speakerPosition - camPos).Unit):Dot(camToFocal.Unit)

					local ANGLE_BUFFER = math.rad(10)
					return cosAngleToSpeaker >= math.cos(horizontalFOVRad / 2 + ANGLE_BUFFER)
				end

				-- Try not to move to next board in single mode until speaker is outside left/right bounds
				if viewMode == "single" and self.Poi1.Value and not self.Poi2.Value and self.Waypoint.Value then
					local boardPart = self.Poi1.Value :: Part
					if speakerInCamView(self.Waypoint.Value.Position, boardPart.Position) then
						if speakerInFrontOfFocal(self.Waypoint.Value.Position, boardPart.Position) then
							return
						end
					end
				end

				local poiBoards = Sift.Dictionary.filter(BoardService.Boards.Map, function(board)
					return not board:GetPart():HasTag("metaboard_personal_board")
						and not board:GetPart():HasTag("orbcam_ignore")
						and (board:GetPart() :: Instance):IsDescendantOf(workspace)
				end)

				local firstBoard, firstPart
				do
					local minSoFar = math.huge
					for _, board in poiBoards do
						local distance = (board:GetSurfaceCFrame().Position - speakerPosition).Magnitude
						if distance < minSoFar then
							firstBoard = board
							firstPart = board:GetPart()
							minSoFar = distance
						end
					end
				end

				if not firstBoard then
					self.NearestBoard.Value = nil :: Instance?
					self.Poi1.Value = nil :: Instance?
					self.Poi2.Value = nil :: Instance?
					if speakerAttachment.Parent then
						self.OrbMode.Value = "follow"
					end
					return
				end

				self.NearestBoard.Value = firstPart

				-- Find next closest board with angle difference <90 degrees
				local secondBoard, secondPart
				if viewMode == "double" then
					local minSoFar = math.huge
					for _, board in poiBoards do
						local distance = (board:GetSurfaceCFrame().Position - speakerPosition).Magnitude
						local goodAngle = firstBoard
							:GetSurfaceCFrame().LookVector
							:Dot(board:GetSurfaceCFrame().LookVector) > 0

						local betweenBoards = (
							board:GetSurfaceCFrame().Position - firstBoard:GetSurfaceCFrame().Position
						).Magnitude
						local maxAxisSizeFirstBoard = math.max(firstPart.Size.X, firstPart.Size.Y, firstPart.Size.Z)
						local goodDistanceBetweenBoards = betweenBoards <= maxAxisSizeFirstBoard * 1.5
						if distance < minSoFar and goodAngle and goodDistanceBetweenBoards and board ~= firstBoard then
							secondBoard = board
							secondPart = board:GetPart()
							minSoFar = distance
						end
					end
				end

				local camCFrame, focalPosition = CameraUtils.ViewBoardsAtFOV(
					{ firstBoard, secondBoard },
					Config.OrbcamFOV,
					Config.AssumedViewportSize,
					Config.OrbcamBuffer
				)
				local closeEnough = speakerCloseToWaypoint(camCFrame.Position, focalPosition)
				local inFront = speakerInFrontOfFocal(camCFrame.Position, focalPosition)

				if not waypointOnly and not (closeEnough and inFront) then
					if speakerAttachment.Parent then
						self.Poi1.Value = nil :: Instance?
						self.Poi2.Value = nil :: Instance?
						self.OrbMode.Value = "follow"
					end
					return
				end

				-- Speaker meets conditions to set waypoint in front of pois

				self.Poi1.Value = firstPart
				self.Poi2.Value = secondPart

				-- Put orb in camera position, but lower it down to the ground (if possible)
				local newWaypoint: CFrame = camCFrame

				local raycastParams = RaycastParams.new()
				raycastParams.FilterType = Enum.RaycastFilterType.Exclude
				local exclude = { orbPart }
				for _, player in Players:GetPlayers() do
					if player.Character then
						table.insert(exclude, player.Character)
					end
				end
				raycastParams.FilterDescendantsInstances = exclude :: any
				local raycastResult = workspace:Raycast(camCFrame.Position, -Vector3.yAxis * 50, raycastParams)

				if raycastResult then
					newWaypoint = newWaypoint
						- newWaypoint.Position
						+ Vector3.new(newWaypoint.X, raycastResult.Position.Y, newWaypoint.Z)
				end

				self.Waypoint.Value = newWaypoint
				self.OrbMode.Value = "waypoint"
			end
		)
	)
end

local function setupOrbAlignment(
	self: OrbServer,
	scope: U.Scope,
	orbPart: Part,
	speakerAttachment: Attachment,
	orbAttachment: Attachment
)
	-- Align the orb to the waypoint position, if not nil, otherwise to the speaker
	scope:new "Folder" {

		Name = "Alignment",
		Parent = orbPart,

		U.new "AlignPosition" {

			Name = "AlignPositionToSpeaker",

			Enabled = U.compute(self.OrbMode, function(orbMode: string)
				return orbMode == "follow"
			end),
			Mode = Enum.PositionAlignmentMode.TwoAttachment,
			Attachment0 = orbAttachment,
			Attachment1 = speakerAttachment,
			MaxForce = math.huge,
			MaxVelocity = 16,
			ApplyAtCenterOfMass = true,
		},
		U.new "AlignPosition" {

			Name = "AlignPositionToWaypoint",

			Enabled = U.compute(self.OrbMode, function(orbMode: string)
				return orbMode ~= "follow"
			end),
			Mode = Enum.PositionAlignmentMode.OneAttachment,
			Position = U.compute(self.Waypoint, function(waypoint: CFrame)
				return waypoint.Position
			end),
			Attachment0 = orbAttachment,
			MaxForce = math.huge,
			MaxVelocity = 8,
		},
		U.new "AlignOrientation" {
			Mode = Enum.OrientationAlignmentMode.OneAttachment,
			Attachment0 = orbAttachment,
			CFrame = self.Waypoint,
		},
	}
end

local function setupRings(self: OrbServer, scope: U.Scope, orbPart: Part, orbAttachment: Attachment)
	local eyeRingAttachment = U.new "Attachment" {}
	local EyeRingOrientationCFrame = scope:Value(orbPart.CFrame * CFrame.Angles(0, math.pi / 2, 0))

	scope:insert(Ring {
		Name = "EyeRing",
		Parent = orbPart,
		Material = Enum.Material.Neon,
		Color = Color3.new(0, 0, 0),
		CastShadow = false,
		CanCollide = false,
		CFrame = EyeRingOrientationCFrame.Value,

		InnerDiameter = orbPart.Size.Y + 0.5,
		OuterDiameter = orbPart.Size.Y + 1,

		eyeRingAttachment,
		U.new "AlignPosition" {
			Mode = Enum.PositionAlignmentMode.TwoAttachment,
			Attachment0 = eyeRingAttachment,
			Attachment1 = orbAttachment,
			MaxVelocity = math.huge,
			MaxForce = math.huge,
			RigidityEnabled = true,
		},
		U.new "AlignOrientation" {
			Mode = Enum.OrientationAlignmentMode.OneAttachment,
			Attachment0 = eyeRingAttachment,
			CFrame = EyeRingOrientationCFrame,
		},
	})

	local earRingAttachment = U.new "Attachment" {}
	local EarOrientationCFrame: U.Value<CFrame> = scope:Value(orbPart.CFrame)

	scope:insert(Ring {
		Name = "EarRing",
		Parent = orbPart,
		Material = Enum.Material.Neon,
		Color = Color3.new(1, 1, 1),
		Transparency = 0.8,
		CastShadow = false,
		CanCollide = false,
		CFrame = EarOrientationCFrame.Value * CFrame.Angles(0, math.pi / 2, 0),

		InnerDiameter = orbPart.Size.Y + 0.1,
		OuterDiameter = orbPart.Size.Y + 0.5,

		earRingAttachment,
		U.new "AlignPosition" {
			Mode = Enum.PositionAlignmentMode.TwoAttachment,
			Attachment0 = earRingAttachment,
			Attachment1 = orbAttachment,
			MaxVelocity = math.huge,
			MaxForce = math.huge,
			RigidityEnabled = true,
		},
		U.new "AlignOrientation" {
			Mode = Enum.OrientationAlignmentMode.OneAttachment,
			Attachment0 = earRingAttachment,
			CFrame = U.compute1(EarOrientationCFrame, function(cframe: CFrame)
				return cframe * CFrame.Angles(0, math.pi / 2, 0)
			end),
		},
	})

	local earPartAttachment = U.new "Attachment" {}

	scope:insert(U.new "Part" {
		Name = "EarPart",
		Parent = orbPart,
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CastShadow = false,
		CanQuery = false,
		CanCollide = false,
		CFrame = orbPart.CFrame,

		earPartAttachment,
		U.new "AlignPosition" {
			Mode = Enum.PositionAlignmentMode.TwoAttachment,
			Attachment0 = earPartAttachment,
			Attachment1 = orbAttachment,
			MaxVelocity = math.huge,
			MaxForce = math.huge,
			RigidityEnabled = true,
		},
		U.new "AlignOrientation" {
			Mode = Enum.OrientationAlignmentMode.OneAttachment,
			Attachment0 = earPartAttachment,
			CFrame = EarOrientationCFrame,
		},
	})

	local ringHeartbeatConnection: RBXScriptConnection?
	scope:insert(function()
		if ringHeartbeatConnection then
			ringHeartbeatConnection:Disconnect()
			ringHeartbeatConnection = nil
		end
	end)

	local Poi1Pos = Stream.toProperty("Position")(Stream.fromValueBase(self.Poi1 :: ObjectValue))
	local Poi2Pos = Stream.toProperty("Position")(Stream.fromValueBase(self.Poi2 :: ObjectValue))
	local SpeakerHead = Stream.toFirstChild("Head")(Stream.fromValueBase(self.SpeakerCharacter :: ObjectValue))
	scope:insert(Stream.listen3(SpeakerHead, Poi1Pos, Poi2Pos, function(head, pos1, pos2)
		local target = pos1 or (head and (head :: any).Position) or nil
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
				EarOrientationCFrame.Value = CFrame.lookAt(orbPart.Position, (head :: any).Position)
			end
			if target then
				EyeRingOrientationCFrame.Value = CFrame.lookAt(orbPart.Position, target)
					* CFrame.Angles(0, math.pi / 2, 0)
			end
		end)
	end))
end

local function OrbServer(orbPart: Part): OrbServer
	local scope = U.Scope()

	-- The orb will be aligned with physics to this position
	-- If nil, and there is a speaker, the orb will chase the speaker
	local Waypoint = scope:new "CFrameValue" {
		Name = "Waypoint",
		Value = orbPart.CFrame,
		Parent = orbPart,
	}

	local OrbMode = scope:new "StringValue" {
		Name = "OrbMode",
		Value = "waypoint",
		Parent = orbPart,
	}

	local WaypointOnly = scope:new "BoolValue" {
		Name = "WaypointOnly",
		Value = false,
		Parent = orbPart,
	}

	local Speaker = scope:new "ObjectValue" {
		Name = "Speaker",
		Parent = orbPart,
	}

	-- This is separate from speakerValue so that Replay characters can be speaker (they aren't players)
	local SpeakerCharacter = scope:new "ObjectValue" {
		Name = "SpeakerCharacter",
		Parent = orbPart,
	}

	local ViewMode = scope:new "StringValue" {
		Name = "ViewMode",
		Value = "single",
		Parent = orbPart,
	}

	local ShowAudience = scope:new "BoolValue" {
		Name = "ShowAudience",
		Value = false,
		Parent = orbPart,
	}

	local SpeakerGroundOffset = scope:Value(Vector3.zero)

	local Poi1 = scope:new "ObjectValue" {
		Name = "poi1",
		Parent = orbPart,
	}

	local Poi2 = scope:new "ObjectValue" {
		Name = "poi2",
		Parent = orbPart,
	}

	local NearestBoard = scope:new "ObjectValue" {
		Name = "NearestBoard",
		Parent = orbPart,
	}

	local orbAttachment = scope:new "Attachment" {
		Parent = orbPart,
	}

	local speakerAttachment = scope:new "Attachment" {
		Name = "SpeakerAttachment",
		Position = U.compute1(SpeakerGroundOffset, function(offset)
			return offset + Vector3.new(0, 0, -5)
		end),
	}

	local attachSound = scope:new "Sound" {
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

	local detachSound = scope:new "Sound" {
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

	-- Unanchor and turn off CanCollide (but reset on destroy)
	local originalAnchored = orbPart.Anchored
	local originalCanCollide = orbPart.CanCollide
	orbPart.Anchored = false
	orbPart.CanCollide = false
	scope:insert(function()
		orbPart.Anchored = originalAnchored
		orbPart.CanCollide = originalCanCollide
	end)

	local self = {
		Waypoint = Waypoint,
		OrbMode = OrbMode,
		WaypointOnly = WaypointOnly,
		Speaker = Speaker,
		SpeakerCharacter = SpeakerCharacter,
		ViewMode = ViewMode,
		ShowAudience = ShowAudience,
		SpeakerGroundOffset = SpeakerGroundOffset,
		Poi1 = Poi1,
		Poi2 = Poi2,
		NearestBoard = NearestBoard,
	}

	setupSpeakerAttachment(self, scope, orbPart, speakerAttachment)
	followSpeakerMovement(self, scope, orbPart, speakerAttachment)
	setupOrbAlignment(self, scope, orbPart, speakerAttachment, orbAttachment)
	setupRings(self, scope, orbPart, orbAttachment)

	function self.DetachPlayer(player: Player)
		if Speaker.Value == player then
			Speaker.Value = nil :: Instance?
			SpeakerCharacter.Value = nil :: Instance?
			detachSound:Play()
		end
	end

	function self.SetSpeaker(player: Player)
		local character = player.Character
		if not character then
			warn("Speaker has no character, cannot attach")
		end

		if RunService:IsStudio() or player:GetAttribute("metaadmin_isscribe") then
			local attachedOrb: ObjectValue = PlayerToOrb:FindFirstChild(tostring(player.UserId)) :: any
				or U.new "ObjectValue" {
					Name = player.UserId,
					Parent = PlayerToOrb,
				}
			attachedOrb.Value = orbPart

			Speaker.Value = player
			SpeakerCharacter.Value = character

			attachSound.SoundId = "rbxassetid://" .. ATTACH_SOUND_IDS[math.random(1, #ATTACH_SOUND_IDS)]
			attachSound:Play()
		end
	end

	function self.SetListener(player: Player)
		local attachedOrb: ObjectValue = PlayerToOrb:FindFirstChild(tostring(player.UserId)) :: any
			or U.new "ObjectValue" {
				Name = player.UserId,
				Parent = PlayerToOrb,
			}
		attachedOrb.Value = orbPart
	end

	local function getBoardGroup()
		local boardGroup
		do
			local parent: Instance? = orbPart
			while true do
				if not parent or parent:HasTag("BoardGroup") then
					break
				end
				parent = (parent :: Instance).Parent
			end
			boardGroup = parent
		end
		return boardGroup
	end

	function self.Destroy()
		U.clean(scope)
	end

	function self.GetPart()
		return orbPart
	end

	function self.GetOrbId()
		local value = orbPart:FindFirstChild("OrbId")
		if not value then
			return nil
		end
		assert(value:IsA("IntValue"), "Bad OrbId")
		return (value :: any).Value
	end

	local function observableFromStream<T>(stream: Stream.Stream<T>): Rx.Observable
		return Rx.observable(function(sub)
			return stream(function(value)
				sub:Fire(value)
			end)
		end)
	end

	function self.ObserveSpeaker()
		return observableFromStream(Stream.fromValueBase(Speaker))
	end

	function self.ObserveViewMode()
		return observableFromStream(Stream.fromValueBase(ViewMode))
	end

	function self.ObserveShowAudience()
		return observableFromStream(Stream.fromValueBase(ShowAudience))
	end

	function self.ObserveWaypointOnly()
		return observableFromStream(Stream.fromValueBase(WaypointOnly))
	end

	function self.SetSpeakerCharacter(speakerCharacter: Model?)
		Speaker.Value = nil :: Instance?
		SpeakerCharacter.Value = speakerCharacter
	end

	function self.SetViewMode(viewMode: "single" | "double" | "freecam")
		assert(checkViewMode(viewMode))
		ViewMode.Value = viewMode
	end

	function self.SetShowAudience(showAudience: boolean)
		assert(t.boolean(showAudience))
		ShowAudience.Value = showAudience
	end

	function self.SetWaypointOnly(waypointOnly: boolean)
		assert(t.boolean(waypointOnly))
		WaypointOnly.Value = waypointOnly
	end

	function self.GetReplayOrigin()
		local value = orbPart:FindFirstChild("ReplayOrigin")
		if not value then
			return nil
		end
		assert(value:IsA("CFrameValue"), "Bad ReplayOrigin")
		return (value :: any).Value
	end

	function self.GetBoardGroup()
		return getBoardGroup()
	end

	function self.GetBoardsInBoardGroup()
		local group = getBoardGroup()
		assert(group, "Bad board group")
		local boards = {}
		for _, desc in group:GetDescendants() do
			if desc:HasTag("metaboard") then
				local board = metaboard.Server:GetBoard(desc :: any)
				if board then
					table.insert(boards, board)
				end
			end
		end

		return boards
	end

	return self
end

export type OrbServer = typeof(OrbServer(nil :: any))

return OrbServer
