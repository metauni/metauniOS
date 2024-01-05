local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RecordUtils = require(script.Parent.RecordUtils)
local OrbService = require(ServerScriptService.OS.OrbService)
local OrbServer = require(ServerScriptService.OS.OrbService.OrbServer)
local Sift = require(ReplicatedStorage.Packages.Sift)
local t = require(ReplicatedStorage.Packages.t)
local Maid = require(ReplicatedStorage.Util.Maid)
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
	self._stageMaid = Maid.new()
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
	
	Remotes.StartRecording.OnServerInvoke = function(player: Player, orbPart: Part, recordingName: string)
		do
			local ok, level = PermissionsService:promisePermissionLevel(player.UserId):catch(warn):await()
			if not ok then
				return false
			end
	
			if level < 254 then -- ADMIN_PERM level (should be accessible from PermissionsService)
				warn("Non-admin tried to make Studio recording")
				return false
			end
		end

		local orbServer = OrbService.Orbs[orbPart]
		if not orbServer then
			warn("No orb found")
			return false, "No orb found"
		end
		local orbId = orbServer.GetOrbId()
		assert(orbId, "Bad orbId")

		if self.OrbToStudio.Value[orbPart] then
			warn("Studio already exists")
			return false
		end
		
		local studio: Studio.Studio
		local recordingId do
			local ok, msg = pcall(function()
				local counter, _keyInfo = self.ReplayDataStore:IncrementAsync(`OrbReplays/{orbId}/Counter`, 1)
				recordingId = orbId .. "-".. counter
			end)
			if not ok then
				warn(msg)
				return false, msg
			end
		end
		
		do
			local ok, msg = pcall(function()
				studio = self:NewOrbStudio(orbServer, recordingName, recordingId)
			end)
			if not ok then
				warn(msg)
				return false, msg
			end
		end

		self.OrbToStudio.Value = Sift.Dictionary.set(self.OrbToStudio.Value, orbPart, studio)

		studio.InitRecording()
		studio.StartRecording()

		return true, recordingId
	end

	-- In theory this can be called multiple times to reattempt save...
	-- Don't spam it though
	Remotes.StopRecording.OnServerInvoke = function(player: Player, orbPart: Part)
		local studio = self.OrbToStudio.Value[orbPart]

		if not studio then
			return false, `No active studio recording for orbPart {orbPart:GetFullName()}`
		end

		if studio.PhaseIsBefore("Recorded") then
			studio.StopRecording()
		end

		local orbServer = OrbService.Orbs[orbPart]
		if not orbServer then
			warn("No orb found")
			return false, "No orb found"
		end
		local orbId = orbServer.GetOrbId()
		assert(orbId, "Bad orbId")

		studio.Store()

		do
			local ok, msg = pcall(function()
				self.ReplayDataStore:UpdateAsync(`OrbReplays/{orbId}`, function(data, _keyInfo: DataStoreKeyInfo)
					if data == nil then
						data = {}
					end
					table.insert(data, {
						ReplayId = studio.props.RecordingId,
						ReplayName = studio.props.RecordingName,
						UTCDate = os.date("!*t"),
					})
					print(`[ReplayService] Stored replay id {studio.props.RecordingId} in OrbReplay/{orbId} catalog`)
					return data
				end)
			end)

			if not ok then
				return false, msg
			end
		end

		studio.Destroy()
		self.OrbToStudio.Value = Sift.Dictionary.set(self.OrbToStudio.Value, orbPart, nil)

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

	Remotes.GetReplays.OnServerInvoke = function(_player: Player, orbPart: Part)

		local orbServer = OrbService.Orbs[orbPart]
		if not orbServer then
			return nil, "Orb not found"
		end

		local orbId = orbServer.GetOrbId()
		if not orbId then
			return nil, "Bad OrbId"
		end

		local replays do
			local ok, msg = pcall(function()
				replays = self.ReplayDataStore:GetAsync(`OrbReplays/{orbId}`) or {}
			end)
			if not ok then
				warn(msg)
				return nil, msg
			end
		end

		return replays
	end

	Remotes.InitReplay.OnServerEvent:Connect(function(_player: Player, orbPart, replayId: string, replayName: string)
		-- TODO: just trusting the client with the replayName here. yikes
		self:InitReplay(orbPart, replayId, replayName)
	end)

	Remotes.Play.OnServerEvent:Connect(function(_player: Player, orbPart)
		self:Play(orbPart)
	end)

	Remotes.Pause.OnServerEvent:Connect(function(_player: Player, orbPart)
		self:Pause(orbPart)
	end)

	Remotes.SkipAhead.OnServerEvent:Connect(function(_player: Player, orbPart, seconds: number)
		self:SkipAhead(orbPart, seconds)
	end)

	Remotes.SkipBack.OnServerEvent:Connect(function(_player: Player, orbPart, seconds: number)
		self:SkipBack(orbPart, seconds)
	end)

	Remotes.Restart.OnServerEvent:Connect(function(_player: Player, orbPart)
		self:Restart(orbPart)
	end)

	Remotes.Stop.OnServerEvent:Connect(function(_player: Player, orbPart)
		self:Stop(orbPart)
	end)

	Remotes.GetCharacterVoices.OnServerInvoke = function(_player: Player, replayId: string)
		self._replaySegmentCache = self._replayCache or {}
		local replaySegment = self._replaySegmentCache[replayId]
		if replaySegment then
			return RecordUtils.ToCharacterVoices(replaySegment)
		end

		replaySegment = self.ReplayDataStore:GetAsync(`Replay/{replayId}/{1}`)
		self._replaySegmentCache[replayId] = replaySegment
		return RecordUtils.ToCharacterVoices(replaySegment)
	end

	local checkCharacterVoices = t.map(t.string, t.strictInterface {
		CharacterName = t.string,
		Clips = t.array (t.strictInterface {
			AssetId = t.string,
			StartTimestamp = t.number,
			StartOffset = t.number,
			EndOffset = t.number,
		})
	})

	Remotes.SaveCharacterVoices.OnServerInvoke = function(player: Player, replayId: string, characterVoices: any)
		local ok, msg = pcall(function()
			assert(t.string(replayId))
			assert(checkCharacterVoices(characterVoices))
			local levelOk, level = PermissionsService:promisePermissionLevel(player.UserId):catch(warn):await()
			if not levelOk or level < 254 then
				error("Replays only editable by admin")
			end

			self.ReplayDataStore:UpdateAsync(`Replay/{replayId}/{1}`, function(data, _keyInfo: DataStoreKeyInfo)
				if not data then
					error("No replay record to update")
				end
	
				assert(t.interface { Records = t.table, } (data))
	
				RecordUtils.EditSoundRecordsInPlace(data, characterVoices)
				return data
			end)
		end)

		if not ok then
			warn(msg)
			return false, msg
		end

		return true
	end
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

function ReplayService:NewOrbStudio(orbServer: OrbServer.OrbServer, recordingName: string, recordingId: string)
	local origin = orbServer.GetReplayOrigin()
	assert(typeof(origin) == "CFrame", "Bad origin for ReplayStudio")

	local studio = Studio({
		RecordingName = recordingName,
		RecordingId = recordingId,
		Origin = origin,
		DataStore = self.ReplayDataStore,
	})

	studio.TrackOrb(orbServer)

	for _, board in orbServer.GetBoardsInBoardGroup() do
		local persistId = board:GetPersistId()
		if persistId then
			studio.TrackBoard(tostring(persistId), board)
		end
	end

	for player, attachedOrb in self:_getPlayerToOrb() do
		if attachedOrb == orbServer.GetPart() then
			studio.TrackPlayerCharacter(tostring(player.UserId), player.DisplayName, player)
		end
	end

	return studio
end

function ReplayService:InitReplay(orbPart, replayId: string, replayName: string)
	local stage = self.OrbToStage.Value[orbPart]
	local orbServer: OrbServer.OrbServer = OrbService.Orbs[orbPart]
	if not orbServer then
		warn("No orb found")
		return
	end

	if stage then
		stage.Destroy()
	end

	stage = Stage {
		DataStore = self.ReplayDataStore,
		Origin = orbServer.GetReplayOrigin(),
		ReplayId = replayId,
		BoardGroup = orbServer.GetBoardGroup(),
		OrbServer = orbServer,
	}

	self.OrbToStage.Value = Sift.Dictionary.set(self.OrbToStage.Value, orbPart, stage)

	local cleanup = {}
	self._stageMaid[orbPart] = cleanup

	table.insert(cleanup, stage)
	table.insert(cleanup, function()
		orbPart:SetAttribute("ReplayActive", false)
		orbPart:SetAttribute("ReplayId", "")
		orbPart:SetAttribute("ReplayName", "")
		orbPart:SetAttribute("ReplayDuration", 0)
		orbPart:SetAttribute("ReplayPlayState", "")
		self.OrbToStage.Value = Sift.Dictionary.removeKey(self.OrbToStage.Value, orbPart)
	end)

	orbPart:SetAttribute("ReplayActive", true)
	orbPart:SetAttribute("ReplayId", replayId)
	orbPart:SetAttribute("ReplayName", replayName)
	orbPart:SetAttribute("ReplayDuration", stage.GetDuration())
	table.insert(cleanup, stage.ObservePlayState():Subscribe(function(playState)
		orbPart:SetAttribute("ReplayPlayState", playState or "")
	end))
	table.insert(cleanup, stage.ObserveTimestampSeconds():Subscribe(function(timestamp)
		orbPart:SetAttribute("ReplayTimestamp", timestamp)
	end))

	stage.GetFinishedSignal():Once(function()
		self._stageMaid[orbPart] = nil
	end)

	stage.Init()
	-- Immediately play?
	stage.Play()

    return stage.GetFinishedSignal()
end

function ReplayService:Play(orbPart)
	local stage: Stage.Stage = self.OrbToStage.Value[orbPart]
	if not stage then
		warn("No active stage found")
		return
	end

	stage.Play()
end

function ReplayService:Pause(orbPart)
	local stage: Stage.Stage = self.OrbToStage.Value[orbPart]
	if not stage then
		warn("No active stage found")
		return
	end
	
	stage.Pause()
end

function ReplayService:SkipAhead(orbPart, seconds: number)
	local stage: Stage.Stage = self.OrbToStage.Value[orbPart]
	if not stage then
		warn("No active stage found")
		return
	end
	
	stage.SkipAhead(seconds)
end

function ReplayService:SkipBack(orbPart, seconds: number)
	local stage: Stage.Stage = self.OrbToStage.Value[orbPart]
	if not stage then
		warn("No active stage found")
		return
	end
	
	stage.SkipBack(seconds)
end

function ReplayService:Restart(orbPart)
	local stage: Stage.Stage = self.OrbToStage.Value[orbPart]
	if not stage then
		warn("No active stage found")
		return
	end
	
	stage.Restart()
end

function ReplayService:Stop(orbPart)
	local stage: Stage.Stage = self.OrbToStage.Value[orbPart]
	if not stage then
		warn("No active stage found")
		return
	end
	
	self._stageMaid[orbPart] = nil
end


return ReplayService