--[[
	For managing the recording, and editing of a replay recording.
]]
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local OrbServer = require(ServerScriptService.OS.OrbService.OrbServer)
local VRServerService = require(ReplicatedStorage.OS.VR.VRServerService)
local BoardRecorder = require(script.Parent.BoardRecorder)
local Sift = require(ReplicatedStorage.Packages.Sift)
local Rx = require(ReplicatedStorage.Util.Rx)
local Maid = require(ReplicatedStorage.Util.Maid)
local Promise = require(ReplicatedStorage.Util.Promise)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)

local CharacterRecorder = require(script.Parent.CharacterRecorder)
local Serialiser = require(script.Parent.Serialiser)
local StateRecorder = require(script.Parent.StateRecorder)
local VRCharacterRecorder = require(script.Parent.VRCharacterRecorder)

-- Leaves a buffer of 4_194_304 - 3_900_000 = 294_304 bytes
local MAX_SEGMENT_BYTES = 3_900_000
local DEBUG = false

export type Phase = "Uninitialised" | "Initialised" | "Recording" | "Recorded" | "SaveFailed" | "Saved"
local PHASE_ORDER: {Phase} = {"Uninitialised", "Initialised", "Recording", "Recorded", "SaveFailed", "Saved"}

export type StudioProps = {
	RecordingName: string,
	RecordingId: string,
	Origin: CFrame,
	DataStore: DataStore,
}

type Recorder = 
	VRCharacterRecorder.VRCharacterRecorder |
	CharacterRecorder.CharacterRecorder |
	BoardRecorder.BoardRecorder |
	StateRecorder.StateRecorder

local function Studio(props: StudioProps): Studio
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap(), props = props }
	
	local recorders: {Recorder} = {}
	local savePromises = {}
	local segments = {}
	local orb: OrbServer.OrbServer = nil
	local startTime = nil

	-- "Uninitialised" -> "Initialised" -> "Recording" -> "Recorded" -> "Saved"
	local RecordingPhase = maid:Add(ValueObject.new("Uninitialised"))

	function self.PhaseIsBefore(phase: Phase): boolean
		return table.find(PHASE_ORDER, RecordingPhase.Value) < table.find(PHASE_ORDER, phase)
	end

	local function getCharacterRecorder(characterId: string)
		local index = Sift.Array.findWhere(recorders, function(recorder)
			return recorder.RecorderType == "CharacterRecorder" and recorder.props.CharacterId == characterId
		end)
		return recorders[index]
	end

	local function getVRCharacterRecorder(characterId: string)
		local index = Sift.Array.findWhere(recorders, function(recorder)
			return recorder.RecorderType == "VRCharacterRecorder" and recorder.props.CharacterId == characterId
		end)
		return recorders[index]
	end

	local function getBoardRecorder(boardId: string)
		local index = Sift.Array.findWhere(recorders, function(recorder)
			return recorder.RecorderType == "BoardRecorder" and recorder.props.BoardId == boardId
		end)
		return recorders[index]
	end
	
	function self.TrackPlayerCharacter(characterId: string, characterName: string, player: Player)
		assert(typeof(characterId) == "string", "Bad characterId")
		assert(typeof(characterName) == "string", "Bad characterName")
		assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player") 

		local existing = getCharacterRecorder(characterId) or getVRCharacterRecorder(characterId)
		if existing then
			if existing.props.PlayerUserId ~= player.UserId then
				error(`[ReplayStudio] Cannot change player-to-track for CharacterId={characterId} to {player.UserId} ({player.Name}), already tracking {existing.PlayerUserId}`)
			end
		else
			if VRServerService.GetVREnabled(player) then
				table.insert(recorders, VRCharacterRecorder({
					Origin = props.Origin,
					CharacterId = characterId,
					PlayerUserId = player.UserId,
					CharacterName = characterName,
				}))
			else
				table.insert(recorders, CharacterRecorder({
					Origin = props.Origin,
					CharacterId = characterId,
					PlayerUserId = player.UserId,
					CharacterName = characterName,
				}))
			end
		end
	end

	function self.TrackBoard(boardId: string, board)
		assert(typeof(board) == "table", "Bad board")
		local existing = getBoardRecorder(boardId)
		if existing then
			if existing.props.Board ~= board  then
				error(`[ReplayStudio] Cannot change board for BoardId={boardId}. A different board is already tracked at this boardId`)
			end
		else
			table.insert(recorders, BoardRecorder({
				Origin = props.Origin,
				Board = board,
				BoardId = boardId,
			}))
		end
	end

	function self.TrackOrb(orbServer: OrbServer.OrbServer)
		if orb then
			error("[ReplayStudio] already tracking orb")
		end

		orb = orbServer

		table.insert(recorders, StateRecorder {
			StateType = "Orb",
			StateInfo = {
				OrbId = orbServer:GetOrbId(),
			},
			Observable = Rx.combineLatest {
				SpeakerId = orbServer.ObserveSpeaker():Pipe {
					Rx.map(function(speaker: Player?)
						if speaker then
							return tostring(speaker.UserId)
						else
							return ""
						end
					end)
				},
				ViewMode = orbServer.ObserveViewMode(),
				ShowAudience = orbServer.ObserveShowAudience(),
				WaypointOnly = orbServer.ObserveWaypointOnly(),
			},
		})
	end

	function self.InitRecording()
		assert(self.PhaseIsBefore("Initialised"), `[Replay Studio] Tried to initialise during phase {RecordingPhase.Value}`)

		startTime = os.clock()
		
		RecordingPhase.Value = "Initialised"
	end

	local function promiseSave(segmentOfRecords, segmentIndex: number)
		return Promise.spawn(function(resolve, reject)

			local data
			do
				local ok, msg = pcall(function()
					data = Serialiser.serialiseSegmentOfRecords(segmentOfRecords, segmentIndex)
				end)
				if not ok then
					reject(tostring(msg))
					return
				end
			end

			if DEBUG then
				local dataBytes = #HttpService:JSONEncode(data)
				print(`[DEBUG] Segment {segmentIndex} is {dataBytes} bytes.`)
			end

			for i=1, 5 do
				local ok, msg = pcall(function()
					props.DataStore:SetAsync(`Replay/{props.RecordingId}/{segmentIndex}`, data)
				end)
				if ok then
					print(`[Replay Studio] SegmentOfRecords {segmentIndex} stored (Id: {props.RecordingId})`)
					resolve()
					return
				end

				if i==5 then
					reject(tostring(msg))
					return
				else
					warn(msg)
					task.wait(10)
				end
			end
		end)
	end

	local function flushAndSaveCurrentSegment()

		local segmentOfRecords = {
			Origin = props.Origin,
			Records = {},
			EndTimestamp = nil -- set after stopping
		}

		table.insert(segments, segmentOfRecords)
		local segmentIndex = #segments

		for _, recorder in recorders do
			table.insert(segmentOfRecords.Records, recorder.FlushToRecord())
		end
		segmentOfRecords.EndTimestamp = os.clock() - startTime
		
		savePromises[segmentIndex] = promiseSave(segmentOfRecords, segmentIndex)
	end

	function self.StartRecording()
		assert(self.PhaseIsBefore("Recording"), `[Replay Studio] Tried to start recording during phase {RecordingPhase.Value}`)
		
		for _, recorder in recorders do
			recorder.Start(startTime)
		end

		maid._estimator = Rx.timer(0, 10):Subscribe(function()
			local totalBytes = 0
			for _, recorder in recorders do
				totalBytes += recorder.EstimateBytes()
			end
			if DEBUG then
				print(`[DEBUG] Recording estimate at {totalBytes} bytes`)
			end
			if totalBytes >= MAX_SEGMENT_BYTES then
				flushAndSaveCurrentSegment()
			end
		end)

		RecordingPhase.Value = "Recording"
	end

	function self.StopRecording()
		assert(self.PhaseIsBefore("Recorded"), `[Replay Studio] Tried to stop recording during phase {RecordingPhase.Value}`)

		maid._estimator = nil

		for _, recorder in recorders do
			recorder.Stop()
		end
		
		-- Start save of the last segment (possibly the only segment)
		flushAndSaveCurrentSegment()

		RecordingPhase.Value = "Recorded"

		self.PromiseAllSaved():Then(function(results)
			print(`[ReplayStudio] Saved {#results}/{#results} segments for recording (ID: {props.RecordingId})`)
		end):Catch(function(results)
			local successful = Sift.Array.count(results, function(okOrMsg)
				return okOrMsg == true
			end)
			warn(`[ReplayStudio] Saved {successful}/{#results} segments for recording (ID: {props.RecordingId})`)
			for segmentIndex, okOrMsg in results do
				if okOrMsg ~= true then
					warn(`[ReplayStudio] Failed to save segment {segmentIndex}:`)
					warn(okOrMsg)
				end
			end
		end)
	end

	-- Resolves with table mapping segmentIndices to true
	-- Rejects with table mapping segmentIndices to true for success or a string for failure
	function self.PromiseAllSaved()
		assert(not self.PhaseIsBefore("Recorded"), "[ReplayStudio] Cannot initiate save before recording finished")
		
		if not Sift.Array.findWhere(savePromises, function(promise) return promise:IsPending() end) then
			savePromises = Sift.Array.map(savePromises, function(promise, segmentIndex)
				if promise:IsFulfilled() then
					return promise
				end
				return promiseSave(segments[segmentIndex], segmentIndex)
			end)
		end

		local promiseAllSaved = Promise.combine(savePromises)
		promiseAllSaved
			:Then(function()
				RecordingPhase.Value = "Saved"
			end)
			:Catch(function()
				-- Don't revert a previous success
				if self.PhaseIsBefore("Saved") then
					RecordingPhase.Value = "Saved"
				end
			end)

		return promiseAllSaved
	end

	function self.GetNumSegments(): number
		assert(not self.PhaseIsBefore("Recorded"), `[Replay Studio] Cannot report number of segments before recording ended.`)

		return #segments
	end

	return self
end

export type Studio = typeof(Studio(nil :: any))

return Studio