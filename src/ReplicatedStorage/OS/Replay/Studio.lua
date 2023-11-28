--[[
	For managing the recording, and editing of a replay recording.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardRecorder = require(script.Parent.BoardRecorder)
local Sift = require(ReplicatedStorage.Packages.Sift)
local Maid = require(ReplicatedStorage.Util.Maid)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)

local CharacterRecorder = require(script.Parent.CharacterRecorder)
local Serialiser = require(script.Parent.Serialiser)
local VRCharacterRecorder = require(script.Parent.VRCharacterRecorder)

export type Phase = "Uninitialised" | "Initialised" | "Recording" | "Recorded" | "Saved"
local PHASE_ORDER: {Phase} = {"Uninitialised", "Initialised", "Recording", "Recorded", "Saved"}

export type StudioProps = {
	RecordingName: string,
	RecordingId: string,
	Origin: CFrame,
	DataStore: DataStore,
}

local function Studio(props: StudioProps): Studio
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap(), props = props }
	
	local recorders = {}
	local StartTime = ValueObject.new(nil)

	-- "Uninitialised" -> "Initialised" -> "Recording" -> "Recorded" -> "Saved"
	local RecordingPhase = maid:Add(ValueObject.new("Uninitialised"))

	function self.PhaseIsBefore(phase: Phase): boolean
		return table.find(PHASE_ORDER, RecordingPhase.Value) < table.find(PHASE_ORDER, phase)
	end

	local function getCharacterRecorder(characterId: string)
		return Sift.List.findWhere(recorders, function(recorder)
			return recorder.RecorderType == "CharacterRecorder" and recorder.CharacterId == characterId
		end)
	end

	local function getVRCharacterRecorder(characterId: string)
		return Sift.List.findWhere(recorders, function(recorder)
			return recorder.RecorderType == "VRCharacterRecorder" and recorder.CharacterId == characterId
		end)
	end

	local function getBoardRecorder(boardId: string)
		return Sift.List.findWhere(recorders, function(recorder)
			return recorder.RecorderType == "BoardRecorder" and recorder.BoardId == boardId
		end)
	end
	
	function self.TrackPlayerCharacter(characterId: string, characterName: string, player: Player)
		assert(typeof(characterId) == "string", "Bad characterId")
		assert(typeof(characterName) == "string", "Bad characterName")
		assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")

		local existing = getCharacterRecorder(characterId)
		if existing and existing.PlayerUserId ~= player.UserId  then
			if existing.PlayerUserId ~= player.UserId then
				error(`[ReplayStudio] Cannot change player-to-track for CharacterId={characterId} to {player.UserId} ({player.Name}), already tracking {existing.PlayerUserId}`)
			end
		else
			table.insert(recorders, CharacterRecorder({
				Origin = props.Origin,
				CharacterId = characterId,
				PlayerUserId = player.UserId,
				CharacterName = characterName,
			}))
		end
	end

	function self.TrackVRPlayerCharacter(characterId: string, characterName: string, player: Player)
		assert(typeof(characterId) == "string", "Bad characterId")
		assert(typeof(characterName) == "string", "Bad characterName")
		assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")

		local existing = getVRCharacterRecorder(characterId)
		if existing and existing.PlayerUserId ~= player.UserId  then
			if existing.PlayerUserId ~= player.UserId then
				error(`[ReplayStudio] Cannot change vr-player-to-track for CharacterId={characterId} to {player.UserId} ({player.Name}), already tracking {existing.PlayerUserId}`)
			end
		else
			table.insert(recorders, VRCharacterRecorder({
				Origin = props.Origin,
				CharacterId = characterId,
				PlayerUserId = player.UserId,
				CharacterName = characterName,
			}))
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

	function self.InitRecording()
		assert(self.PhaseIsBefore("Initialised"), `[Replay Studio] Tried to initialise during phase {RecordingPhase.Value}`)

		StartTime.Value = os.clock()
		
		RecordingPhase.Value = "Initialised"
	end

	function self.StartRecording()
		assert(self.PhaseIsBefore("Recording"), `[Replay Studio] Tried to start recording during phase {RecordingPhase.Value}`)
		
		for _, recorder in recorders do
			recorder.Start(StartTime.Value)
		end
		RecordingPhase.Value = "Recording"
	end

	function self.StopRecording()
		assert(self.PhaseIsBefore("Recorded"), `[Replay Studio] Tried to stop recording during phase {RecordingPhase.Value}`)

		local segmentOfRecords = {
			Records = {},
		}
		
		for _, recorder in recorders do
			recorder.Stop()
			table.insert(segmentOfRecords.Records, recorder.FlushToRecord())
		end

		self.SegmentOfRecords = segmentOfRecords
	end
	
	function self.Store()
		assert(self.SegmentOfRecords, "No segment ready to store")
		local data = Serialiser.serialiseSegmentOfRecords(self.SegmentOfRecords, 1)

		props.DataStore:SetAsync(`Replay/{props.RecordingId}/{1}`, data)

		print(`[Replay Studio] SegmentOfRecords 1 stored (Id: {props.RecordingId})`)
	end

	return self
end

export type Studio = typeof(Studio(nil :: any))

return Studio