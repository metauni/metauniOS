local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RecordUtils = require(script.Parent.RecordUtils)
local OrbService = require(ServerScriptService.OS.OrbService)
local OrbServer = require(ServerScriptService.OS.OrbService.OrbServer)
local Sift = require(ReplicatedStorage.Packages.Sift)
local t = require(ReplicatedStorage.Packages.t)
local Map = require(ReplicatedStorage.Util.Map)
local Promise = require(ReplicatedStorage.Util.Promise)
local Stage = require(script.Parent.Stage)
local Rx = require(ReplicatedStorage.Util.Rx)
local Rxi = require(ReplicatedStorage.Util.Rxi)
local Stream = require(ReplicatedStorage.Util.Stream)
local U = require(ReplicatedStorage.Util.U)
local Studio = require(script.Parent.Studio)
local PermissionsService = require(ServerScriptService.OS.PermissionsService)
local PocketService = require(ServerScriptService.OS.PocketService)

local Remotes = script.Parent.Remotes
local PlayerToOrb = ReplicatedStorage.OS.OrbController.PlayerToOrb

local TESTING = game.PlaceId == 10325447437

--[[
	Manages replay recording and selection for playback
]]
local ReplayService = {

	OrbToStage = Map({} :: {[Part]: Stage.Stage}),
	OrbToStudio = Map({} :: {[Part]: Studio.Studio}),
	OrbCatalog = {} :: {[number]: {
		{
			ReplayId: string,
			ReplayName: string,
			NumSegments: number?,
			UTCDate: typeof(os.date("!*t")),
		}
	}},
	ReplayDataStore = nil :: DataStore?
}

function ReplayService:Start()
	self = ReplayService

	if TESTING then
		warn("Using ReplayTest datastore")
		self.ReplayDataStore = DataStoreService:GetDataStore(`ReplayTest`)
	elseif PocketService.IsPocket() then
		local pocketId = PocketService.GetPocketIdAsync()
		self.ReplayDataStore = DataStoreService:GetDataStore(`Replay-{pocketId}`)
	else
		self.ReplayDataStore = DataStoreService:GetDataStore("Replay-TRS")
	end

	Remotes.StartRecording.OnServerInvoke = function(player: Player, orbPart: Part, recordingName: string)
	do
		local result = PermissionsService:getPermissionLevelById(player.UserId)
		if not result.success then
			warn(result.reason)
			return false
		end

		if result.data.perm < 254 then -- ADMIN_PERM level (should be accessible from PermissionsService)
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

		if self.OrbToStudio:Get(orbPart) then
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

		self.OrbToStudio:Set(orbPart, studio)

		studio.InitRecording()
		studio.StartRecording()

		return true, recordingId
	end

	local function stopAndSave(orbPart)
		local studio = self.OrbToStudio:Get(orbPart)

		if not studio then
			return false, `No active studio recording for orbPart {orbPart:GetFullName()}`
		end

		if studio.PhaseIsBefore("Recorded") then
			studio.StopRecording()
		end

		local ok, msg = self:PromiseSaveRecording(orbPart, studio):Then(function()
			-- Make sure it's still there, since we're async
			if studio == self.OrbToStudio:Get(orbPart) then
				self.OrbToStudio:Set(orbPart, nil)
				studio.Destroy()
			end
		end):Yield()

		return ok, msg
	end

	Remotes.StopRecording.OnServerInvoke = function(_player: Player, orbPart: Part)
		return stopAndSave(orbPart)
	end

	Remotes.AttemptSave.OnServerInvoke = function(_player: Player, orbPart: Part)
		return stopAndSave(orbPart)
	end

	Stream.listenTidyEach(Stream.eachChildOf(PlayerToOrb), function(orbValue: Instance)
		if typeof(orbValue) ~= "Instance" or not orbValue:IsA("ObjectValue") then
			return
		end
		local player = Players:GetPlayerByUserId(orbValue.Name)
		if not player then
			return
		end

		return Stream.fromValueBase(orbValue :: ObjectValue)(function(orbPart: Instance?)
			if not orbPart then
				return
			end
			local studio = self.OrbToStudio:Get(orbPart)
			if studio and studio.PhaseIsBefore("Recorded") then
				studio.TrackPlayerCharacter(tostring(player.UserId), player.DisplayName, player)
			end
		end)
	end)

	self.OrbToStudio:StreamPairs()(function()
		for orbPart, studio in self.OrbToStudio.Map do
			if studio.PhaseIsBefore("Recorded") then
				for _, orbValue in PlayerToOrb:GetChildren() do
					local player = Players:GetPlayerByUserId(orbValue.Name)
					if player and orbValue.Value == orbPart then
						studio.TrackPlayerCharacter(tostring(player.UserId), player.DisplayName, player)
					end
				end
			end
		end
	end)

	-- TODO: Currently no way to stop tracking players

	Remotes.GetReplays.OnServerInvoke = function(_player: Player, orbPart: Part)
		local orbServer = OrbService.Orbs[orbPart]
		if not orbServer then
			return nil, "Orb not found"
		end

		local orbId = orbServer.GetOrbId()
		if not orbId then
			return nil, "Bad OrbId"
		end

		local ok, result = self:PromiseReplayCatalog(orbId):Yield()
		return ok, result
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

	self.OrbToStage:ListenTidyPairs(function(orbPart: Part, stage: Stage.Stage?)
		if stage then
			return U.mountAttributes(orbPart, {
				ReplayActive = true,
				ReplayId = stage.ReplayId,
				ReplayName = stage.ReplayName,
				ReplayDuration = stage.GetDuration(),
				ReplayPlayState = stage.ObservePlayState():Pipe{Rx.map(function(playState)
					return playState or ""
				end)},
				ReplayTimestamp = stage.ObserveTimestampSeconds(),
			})
		else
			return U.mountAttributes(orbPart, {
				ReplayActive = false,
				ReplayId = "",
				ReplayName = "",
				ReplayDuration = 0,
				ReplayPlayState = "",
			})
		end
	end)
end

function ReplayService:PromiseSaveRecording(orbPart: Part, studio: Studio.Studio)

	return studio.PromiseAllSaved():Finally(function(_results)

		local orbServer = OrbService.Orbs[orbPart]
		if not orbServer then
			return Promise.rejected("No OrbServer found")
		end
		local orbId = orbServer.GetOrbId()
		if not orbId then
			return Promise.rejected("Bad OrbId")
		end

		local numSegments = studio.GetNumSegments()

		local ok, msg = pcall(function()
			self.ReplayDataStore:UpdateAsync(`OrbReplays/{orbId}`, function(data, _keyInfo: DataStoreKeyInfo)
				if data == nil then
					data = {}
				end
				table.insert(data, {
					ReplayId = studio.props.RecordingId,
					ReplayName = studio.props.RecordingName,
					NumSegments = numSegments,
					UTCDate = os.date("!*t"),
				})
				print(`[ReplayService] Stored replay id {studio.props.RecordingId} in OrbReplay/{orbId} catalog`)
				return data
			end)
		end)

		if ok then
			return Promise.resolved()
		else
			return Promise.rejected(msg)
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

function ReplayService:PromiseReplayCatalog(orbId: number)
	self = ReplayService
	if self.OrbCatalog[orbId] then
		return Promise.resolved(self.OrbCatalog[orbId])
	end

	return Promise.spawn(function(resolve, reject)
		local replays
		local ok, msg = pcall(function()
			replays = self.ReplayDataStore:GetAsync(`OrbReplays/{orbId}`) or {}
		end)
		if ok then
			self.OrbCatalog[orbId] = replays
			resolve(replays)
		else
			reject(msg)
		end
	end)
end

function ReplayService:InitReplay(orbPart, replayId: string, replayName: string)
	local stage = self.OrbToStage:Get(orbPart)
	local orbServer = OrbService.Orbs[orbPart]
	assert(orbServer, "No OrbServer found")
	local orbId = orbServer.GetOrbId()
	assert(orbId, "Bad OrbId")

	if stage then
		stage.Destroy()
	end

	local catalog = ReplayService:PromiseReplayCatalog(orbId):Wait()

	local replayEntry = Sift.Array.filter(catalog, function(entry)
		return entry.ReplayId == replayId
	end)[1]

	assert(replayEntry, `No replayEntry found in catalog for ID {replayId}`)

	local numSegments = catalog.NumSegments or 1

	stage = Stage {
		DataStore = self.ReplayDataStore,
		Origin = orbServer.GetReplayOrigin(),
		ReplayId = replayId,
		NumSegments = numSegments,
		ReplayName = replayName,
		BoardGroup = orbServer.GetBoardGroup(),
		OrbServer = orbServer,
	}

	self.OrbToStage:Set(orbPart, stage)

	stage.Init()
	-- Immediately play?
	stage.Play()

	stage.GetFinishedSignal():Once(function()
		self.OrbToStage:Set(orbPart, nil)
		stage.Destroy()
	end)

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
