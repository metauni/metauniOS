--[[
	For managing the simultaneous playback of a collection of replays
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local VRCharacterReplay = require(ReplicatedStorage.OS.Replay.VRCharacterRecorder.VRCharacterReplay)
local Sift = require(ReplicatedStorage.Packages.Sift)
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local Maid = require(ReplicatedStorage.Util.Maid)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)
local Serialiser = require(script.Parent.Serialiser)
local BoardReplay = require(script.Parent.BoardRecorder.BoardReplay)
local CharacterReplay = require(script.Parent.CharacterRecorder.CharacterReplay)

local ENDTIMESTAMP_BUFFER = 0.5

export type SegmentOfReplays = {
	Replays: {CharacterReplay.CharacterReplay | VRCharacterReplay.VRCharacterReplay | BoardReplay.BoardReplay},
	EndTimestamp: number,
}

export type StageProps = {
	ReplayId: string,
	Origin: CFrame, -- We ignore the stored origin, and play the replay relative to this one
	DataStore: DataStore,
	BoardGroup: Instance,
}

local function Stage(props: StageProps)
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap(), props = props }

	local Playing = ValueObject.new(false)
	local SegmentIndex = ValueObject.new(1, "number")
	local Pausehead = ValueObject.new(0)
	local initialised = false

	local segments = {}
	maid:GiveTask(function()
		for _, segment in segments do
			for _, replay in segment.Replays do
				replay.Destroy()
			end
		end
	end)

	local function fetchSegment(): SegmentOfReplays

		local data = props.DataStore:GetAsync(`Replay/{props.ReplayId}/{1}`)
		local segmentOfRecords = Serialiser.deserialiseSegmentOfRecords(data)
		
		local segment = {
			Replays = {},
			EndTimestamp = segmentOfRecords.EndTimestamp,
		}

		local soundRecords = Sift.Array.filter(segmentOfRecords.Records, function(record)
			return record.RecordType == "SoundRecord"
		end)

		local function getVoiceRecord(characterId: string): any?
			assert(characterId, "Bad characterId")
			for _, soundRecord in soundRecords do
				if soundRecord.CharacterId == characterId then
					return soundRecord
				end
			end
			return nil
		end

		for _, record in segmentOfRecords.Records do
			local replay
			if record.RecordType == "CharacterRecord" then
				replay = CharacterReplay({
					Record = record,
					Origin = props.Origin,
					VoiceRecord = getVoiceRecord(record.CharacterId),
				})
			elseif record.RecordType == "VRCharacterRecord" then
				replay = VRCharacterReplay({
					Record = record,
					Origin = props.Origin,
					VoiceRecord = getVoiceRecord(record.CharacterId),
				})
			elseif record.RecordType == "BoardRecord" then
				replay = BoardReplay({
					Origin = props.Origin,
					Record = record,
					BoardParent = props.BoardGroup,
				})
			elseif record.RecordType == "SoundRecord" then
				-- Handled by character replays
				continue
			else
				error(`Record type {record.RecordType} not handled`)
			end
			table.insert(segment.Replays, replay)
		end

		segments[1] = segment

		return segment
	end

	local function getSegment(): SegmentOfReplays
		local segment = segments[SegmentIndex.Value]
		if not segment then
			segment = fetchSegment()
		end
		return segment
	end

	function self.Init()
		for board in metaboard.Server.BoardServerBinder:GetAllSet() do
			local boardContainer = board:GetContainer()
			local originalParent = boardContainer.Parent
			if boardContainer:IsDescendantOf(props.BoardGroup) then
				boardContainer.Parent = ReplicatedStorage
				maid:GiveTask(function()
					boardContainer.Parent = originalParent
				end)
			end
		end

		local segment = getSegment()
		for _, replay in segment.Replays do
			replay.Init()
		end

		initialised = true
	end

	function self.Play()
		if not initialised then
			error("Not initialised. Call stage.Init()")
		end
		if Playing.Value then
			return
		end
		local segment = getSegment()

		local cleanup = {}
		maid._playing = cleanup

		for _, replay in segment.Replays do
			if typeof(replay.SetActive) == "function" then
				replay.SetActive(true)
			end
		end

		local timeAtResume = os.clock()

		table.insert(cleanup, RunService.Heartbeat:Connect(function()
			local timestamp = Pausehead.Value + (os.clock() - timeAtResume)
			for _, replay in segment.Replays do
				replay.UpdatePlayhead(timestamp)
			end
			if timestamp >= segment.EndTimestamp + ENDTIMESTAMP_BUFFER then
				print("Finished playing!")
				maid._playing = nil
				Playing.Value = false
				for _, replay in segment.Replays do
					if typeof(replay.SetActive) == "function" then
						replay.SetActive(false)
					end
				end
				self.Destroy()
			end
		end))

		Playing.Value = true
	end

	return self
end

export type Stage = typeof(Stage(nil :: any))

return Stage