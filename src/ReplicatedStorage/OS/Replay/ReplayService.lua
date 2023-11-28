local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local VRServerService = require(ReplicatedStorage.OS.VR.VRServerService)
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local Stage = require(script.Parent.Stage)
local Rx = require(ReplicatedStorage.Util.Rx)
local Rxi = require(ReplicatedStorage.Util.Rxi)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)
local Studio = require(script.Parent.Studio)
local PermissionsService = require(ServerScriptService.OS.PermissionsService)
local PocketService = require(ServerScriptService.OS.PocketService)

local Remotes = script.Parent.Remotes
local PlayerToOrb = ReplicatedStorage.OS.OrbController.PlayerToOrb

local TESTING = true 

--[[
	Manages replay recording and selection for playback
]]
local ReplayService = {}

function ReplayService:Init()
	self.OrbToStudio = ValueObject.new({})
	self.OrbToStage = ValueObject.new({})
end

function ReplayService:Start()

	if TESTING then
		self.ReplayDataStore = DataStoreService:GetDataStore(`ReplayTest`)
	elseif PocketService.IsPocket() then
		local pocketId = PocketService.GetPocketIdAsync()
		self.ReplayDataStore = DataStoreService:GetDataStore(`Replay-{pocketId}`)
	else
		self.ReplayDataStore = DataStoreService:GetDataStore("Replay-TRS")
	end

	self._orbOriginCFrame = {}
	Rxi.tagged("metaorb"):Subscribe(function(orbPart: Part)
		self._orbOriginCFrame[orbPart] = orbPart.CFrame
	end)
	Rxi.untagged("metaorb"):Subscribe(function(orbPart: Part)
		self._orbOriginCFrame[orbPart] = nil
	end)
	
	Remotes.StartRecording.OnServerInvoke = function(player: Player, orbPart: Part, recordingName: string)
		local success, level = PermissionsService:promisePermissionLevel(player.UserId):catch(warn):await()
		if not success then
			return false
		end

		if level < 254 then -- ADMIN_PERM level (should be accessible from PermissionsService)
			warn("Non-admin tried to make Studio recording")
			return false
		end

		local studio = self.OrbToStudio.Value[orbPart]
		if studio then
			warn("TODO")
			return false
		end

		local recordingId = "test"
		studio = self:NewOrbStudio(orbPart, recordingName, recordingId)

		studio.InitRecording()
		studio.StartRecording()

		task.spawn(function()
			local i = 0
			while true do
				task.wait(1)
				print(i)
				i+=1
				if i >= 60 then
					studio.StopRecording()
					studio.Store()
					self.OrbToStage.Value[orbPart] = Stage(studio.props)
					break
				end
			end
		end)
		return true
	end

	self.OrbToStudio:Observe():Pipe {
		Rx.switchMap(function()
			return Rx.of(Players):Pipe {
				Rxi.children(),
				Rx.switchMap(function(players: {Players})
					local playerToOrb = {}
					for _, player in players do
						playerToOrb[player] = Rx.of(PlayerToOrb):Pipe {
							Rxi.findFirstChildWithClass("ObjectValue", tostring(player.UserId)),
							Rxi.property("Value"),
						}
					end
					return Rx.combineLatest(playerToOrb)
				end),
			}
		end)
	}:Subscribe(function(playerToOrb: {[Player]: Part})
		for player, orb in playerToOrb do
			local studio = self.OrbToStudio.Value[orb]
			if studio and studio.PhaseIsBefore("Recorded") then
				studio.TrackPlayerCharacter(tostring(player.UserId), player.DisplayName, player)
			end
		end

		-- TODO: Currently no way to stop tracking players
	end)

	Remotes.GetReplays.OnServerInvoke = function(_player: Player, orbPart)

		if orbPart then
			self.OrbToStage.Value[orbPart] = Stage({
				RecordingId = "test",
				RecordingName = "name",
				Origin = self._orbOriginCFrame[orbPart] + Vector3.new(0,0,0),
				DataStore = self.ReplayDataStore,
			})
		end

		local replays = {}
		for _, stage in self.OrbToStage.Value do
			local props = stage.props
			table.insert(replays, {
				RecordingName = props.RecordingName,
				RecordingId = props.RecordingId,
			})
		end

		return replays
	end

	Remotes.Play.OnServerEvent:Connect(function(_player: Player, replay)
		for _orb, stage in self.OrbToStage.Value do
			if stage.props.RecordingId == replay.RecordingId then
				stage.Play()
				return
			end
		end
	end)
end



function ReplayService:_observePlayerToOrb()
	return Rx.of(Players):Pipe {
		Rxi.children(),
		Rx.switchMap(function(players: {Players})
			local playerToOrb = {}
			for _, player in players do
				playerToOrb[player] = Rx.of(PlayerToOrb):Pipe {
					Rxi.findFirstChildWithClass("ObjectValue", tostring(player.UserId)),
					Rxi.property("Value"),
				}
			end
			return Rx.combineLatest(playerToOrb)
		end),
	}
end

function ReplayService:_getPlayerToOrb()
	local playerToOrb = {}
	for _, player in Players:GetPlayers() do
		local orbValue = PlayerToOrb:FindFirstChild(tostring(player.UserId))
		playerToOrb[player] = orbValue and orbValue.Value or nil
	end
	return playerToOrb
end

function ReplayService:NewOrbStudio(orbPart: Part, recordingName: string, recordingId: string)
	local origin = self._orbOriginCFrame[orbPart]
	assert(typeof(origin) == "CFrame", "Bad origin for ReplayStudio")

	local studio = Studio({
		RecordingName = recordingName,
		RecordingId = recordingId,
		Origin = origin,
		DataStore = self.ReplayDataStore,
	})

	local boardGroup do
		local parent: Instance? = orbPart
		while true do
			if not parent or parent:HasTag("BoardGroup") then
				break
			end
			parent = (parent :: Instance).Parent
		end
		boardGroup = parent
	end
	assert(boardGroup, "No board group found for ReplayStudio")

	if boardGroup then
		for _, desc in boardGroup:GetDescendants() do
			local board = metaboard.Server:GetBoard(desc)
			if not board then
				continue
			end
			local persistId = board:GetPersistId()
			if persistId then
				studio.TrackBoard(tostring(persistId), board)
			end
		end
	end

	for player, attachedOrb in self:_getPlayerToOrb() do
		if attachedOrb == orbPart then
			if VRServerService.GetVREnabled(player) then
				studio.TrackVRPlayerCharacter(tostring(player.UserId), player.DisplayName, player)
			else
				studio.TrackPlayerCharacter(tostring(player.UserId), player.DisplayName, player)
			end
		end
	end

	return studio
end


return ReplayService