--[[
	For managing the recording, and editing of a replay recording.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)
local Maid = require(ReplicatedStorage.Util.Maid)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)

local CharacterRecorder = require(script.Parent.CharacterRecorder)
local Serialiser = require(script.Parent.Serialiser)

export type Phase = "Uninitialised" | "Initialised" | "Recording" | "Recorded" | "Saved"
local PHASES = {"Uninitialised", "Initialised", "Recording", "Recorded", "Saved"}

export type StudioProps = {
	RecordingName: string,
	RecordingId: string,
	Origin: CFrame,
	DataStore: DataStore,
}

local function Studio(props: StudioProps)
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap() }
	
	local boards = {}
	local recorders = {}

	-- "Uninitialised" -> "Initialised" -> "Recording" -> "Recorded" -> "Saved"
	local RecordingPhase = maid:Add(ValueObject.new("Uninitialised"))

	function self.PhaseIsBefore(phase: Phase): boolean
		return table.find(PHASES, RecordingPhase.Value) < table.find(PHASES, phase)
	end

	function self.getProps()
		return props
	end

	local function getCharacterRecorderFor(characterId: string)
		return Sift.List.findWhere(recorders, function(recorder)
			return recorder.RecorderType == "CharacterRecorder" and recorder.CharacterId == characterId
		end)
	end
	
	function self.TrackPlayerCharacter(characterId: string, player: Player)
		assert(typeof(characterId) == "string", "Bad characterId")
		assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")

		local existing = getCharacterRecorderFor(characterId)
		if existing and existing.PlayerUserId ~= player.UserId  then
			error(`[ReplayStudio] Cannot change player to track for CharacterId={characterId} to {player.UserId} ({player.Name}), already tracking {existing.PlayerUserId}`)
		end

		table.insert(recorders, CharacterRecorder.new(characterId, player.UserId, props.Origin))
	end

	function self.TrackBoard(boardId: string, board)
		error("Not implemented")
		assert(typeof(board) == "table", "Bad board")
		if boards[boardId] then
			-- TODO allow repeated requests to track same board.
			error(`[ReplayStudio] BoardId {boardId} already tracked`)
		end
	end

	function self.InitRecording()
		assert(self.PhaseIsBefore("Initialised"), `[Replay Studio] Tried to initialise during phase {RecordingPhase.Value}`)

		self.StartTime = os.clock()
		
		RecordingPhase.Value = "Initialised"
	end

	function self.StartRecording()
		assert(self.PhaseIsBefore("Recording"), `[Replay Studio] Tried to start recording during phase {RecordingPhase.Value}`)
		
		for _, recorder in recorders do
			recorder:Start(self.StartTime)
		end
		RecordingPhase.Value = "Recording"
	end

	function self.StopRecording()
		assert(self.PhaseIsBefore("Recorded"), `[Replay Studio] Tried to stop recording during phase {RecordingPhase.Value}`)

		local segmentOfRecords = {
			Records = {},
		}
		
		for _, recorder in recorders do
			recorder:Stop()
			table.insert(segmentOfRecords.Records, recorder:FlushToRecord())
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