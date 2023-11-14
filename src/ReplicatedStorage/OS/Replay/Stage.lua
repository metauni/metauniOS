--[[
	For managing the simultaneous playback of a collection of replays
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Maid = require(ReplicatedStorage.Util.Maid)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)

local CharacterReplay = require(script.Parent.CharacterRecorder.CharacterReplay)
local Serialiser = require(script.Parent.Serialiser)

export type StageProps = {
	RecordingName: string,
	RecordingId: string,
	Origin: CFrame,
	DataStore: DataStore,
}

local function Stage(props: StageProps)
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap() }

	function self.getProps()
		return props
	end

	local Playing = ValueObject.new(false)
	local SegmentIndex = ValueObject.new(1, "number")
	local Pausehead = ValueObject.new(0)

	local segments = {}

	local function fetchSegment()

		local data = props.DataStore:GetAsync(`Replay/{props.RecordingId}/{1}`)
		local segmentOfRecords = Serialiser.deserialiseSegmentOfRecords(data)
		
		local segment = {
			Replays = {}
		}
		for _, record in segmentOfRecords.Records do
			if record.RecordType == "CharacterRecord" then
				local replay = CharacterReplay(record, props.Origin, nil)
				replay:Init()
				table.insert(segment.Replays, replay)
			end
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
			replay.SetActive(true)
		end

		local timeAtResume = os.clock()

		table.insert(cleanup, RunService.Heartbeat:Connect(function()
			local timestamp = Pausehead.Value + (os.clock() - timeAtResume)
			local finished = true
			for _, replay in segment.Replays do
				replay.UpdatePlayhead(timestamp)
				finished = finished and replay.Finished
			end
			if finished then
				print("Finished playing!")
				maid._playing = nil
				Playing.Value = false
				for _, replay in segment.Replays do
					replay.SetActive(false)
				end
			end
		end))

		Playing.Value = true
	end

	return self
end

export type Stage = typeof(Stage(nil :: any))

return Stage