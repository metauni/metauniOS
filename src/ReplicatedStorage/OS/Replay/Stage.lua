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


export type StageProps = {
	RecordingName: string,
	RecordingId: string,
	Origin: CFrame,
	DataStore: DataStore,
}

local function Stage(props: StageProps)
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap(), props = props }

	local Playing = ValueObject.new(false)
	local SegmentIndex = ValueObject.new(1, "number")
	local Pausehead = ValueObject.new(0)

	local segments = {}
	maid:GiveTask(function()
		for _, segment in segments do
			for _, replay in segment.Replays do
				replay.Destroy()
			end
		end
	end)

	local function fetchSegment()

		local data = props.DataStore:GetAsync(`Replay/{props.RecordingId}/{1}`)
		local segmentOfRecords = Serialiser.deserialiseSegmentOfRecords(data)

		local allBoards = metaboard.Server.BoardServerBinder:GetAllSet()
		local boardIdToBoard = Sift.Dictionary.map(allBoards, function(_, board)
			local boardId = tostring(board:GetPersistId())
			return board, boardId
		end)
		
		local segment = {
			Replays = {}
		}
		for _, record in segmentOfRecords.Records do
			local replay
			if record.RecordType == "CharacterRecord" then
				replay = CharacterReplay(record, props.Origin)
			elseif record.RecordType == "VRCharacterRecord" then
				replay = VRCharacterReplay(record, props.Origin)
			elseif record.RecordType == "BoardRecord" then
				replay = BoardReplay({
					Origin = props.Origin,
					Record = record,
					Board = boardIdToBoard[record.BoardId],
				})
			else
				error(`Record type {record.RecordType} not handled`)
			end
			replay.Init()
			table.insert(segment.Replays, replay)
		end

		segments[1] = segment

		return segment
	end

	local function getSegment()
		local segment = segments[SegmentIndex.Value]
		if not segment then
			segment = fetchSegment()
		end
		return segment
	end

	function self.Init()
		
	end

	function self.Play()
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
			local finished = true
			for _, replay in segment.Replays do
				replay.UpdatePlayhead(timestamp)
				finished = finished and replay.IsFinished()
			end
			if finished then
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