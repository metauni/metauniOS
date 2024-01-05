--[[
	For managing the simultaneous playback of a collection of replays
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local OrbServer = require(ServerScriptService.OS.OrbService.OrbServer)
local StateReplay = require(ReplicatedStorage.OS.Replay.StateRecorder.StateReplay)
local Sift = require(ReplicatedStorage.Packages.Sift)
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local t = require(ReplicatedStorage.Packages.t)
local GoodSignal = require(ReplicatedStorage.Util.GoodSignal)
local Maid = require(ReplicatedStorage.Util.Maid)
local Rx = require(ReplicatedStorage.Util.Rx)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)
local Serialiser = require(script.Parent.Serialiser)
local BoardReplay = require(script.Parent.BoardRecorder.BoardReplay)
local CharacterReplay = require(script.Parent.CharacterRecorder.CharacterReplay)
local VRCharacterReplay = require(script.Parent.VRCharacterRecorder.VRCharacterReplay)

local ENDTIMESTAMP_BUFFER = 0.5

export type AnyReplay = CharacterReplay.CharacterReplay | VRCharacterReplay.VRCharacterReplay | BoardReplay.BoardReplay | StateReplay.StateReplay

export type SegmentOfReplays = {
	Replays: {AnyReplay},
	EndTimestamp: number,
}

export type StageProps = {
	ReplayId: string,
	Origin: CFrame, -- We ignore the stored origin, and play the replay relative to this one
	DataStore: DataStore,
	BoardGroup: Instance,
	OrbServer: OrbServer.OrbServer?
}

local function Stage(props: StageProps)
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap(), props = props }

	local Playing = maid:Add(ValueObject.new(false))
	local SegmentIndex = maid:Add(ValueObject.new(1, "number"))
	local Pausehead = maid:Add(ValueObject.new(0))
	local initialised = false
	local finishedSignal = maid:Add(GoodSignal.new())
	local TimestampSeconds = maid:Add(ValueObject.new(0))

	local segments = {}
	maid:GiveTask(function()
		for _, segment in segments do
			for _, replay in segment.Replays do
				replay.Destroy()
			end
		end
	end)

	local function getCharacters(segment: SegmentOfReplays): {[string]: Model?}
		local characterReplays = Sift.Array.filter(segment.Replays, function(replay: AnyReplay)
			return replay.ReplayType == "CharacterReplay" or replay.ReplayType == "VRCharacterReplay"
		end)

		return Sift.Dictionary.map(characterReplays, function(replay: CharacterReplay.CharacterReplay | VRCharacterReplay.VRCharacterReplay)
			return replay.GetCharacter(), replay.props.Record.CharacterId
		end)
	end

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
			elseif record.RecordType == "StateRecord" and record.StateType == "Orb" then
				if not props.OrbServer then
					error("No orb given")
				end

				replay = StateReplay({
					Record = record,
					Handler = function(state)
						local characters = getCharacters(segment)
						local character = characters[state.SpeakerId]
						props.OrbServer.SetSpeakerCharacter(character)
						props.OrbServer.SetViewMode(state.ViewMode)
						props.OrbServer.SetWaypointOnly(state.WaypointOnly)
						props.OrbServer.SetShowAudience(state.ShowAudience)
					end,
				})

				maid:GiveTask(function()
					props.OrbServer.SetSpeakerCharacter(nil)
				end)

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

	function self.GetFinishedSignal()
		return finishedSignal
	end

	-- Remember could be nil
	local timeAtResume

	function self.Play()
		if not initialised then
			error("Not initialised. Call stage.Init()")
		end
		if Playing.Value then
			return
		end
		local segment = getSegment()

		for _, replay in segment.Replays do
			if typeof(replay.SetActive) == "function" then
				replay.SetActive(true)
			end
		end

		timeAtResume = os.clock()

		maid._playing = RunService.Heartbeat:Connect(function()
			local timestamp = Pausehead.Value + (os.clock() - timeAtResume)
			TimestampSeconds.Value = math.round(timestamp)
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
				
				print("finished!")
				finishedSignal:Fire()
			end
		end)

		Playing.Value = true
	end

	function self.Pause()
		maid._playing = nil
		local segment = getSegment()
		for _, replay in segment.Replays do
			if typeof(replay.SetActive) == "function" then
				replay.SetActive(false)
			end
		end 

		if timeAtResume then
			Pausehead.Value = Pausehead.Value + (os.clock() - timeAtResume)
			timeAtResume = nil
		end
		Playing.Value = false
	end

	function self.SkipAhead(seconds: number)
		assert(t.numberPositive(seconds), "Bad seconds")
		Pausehead.Value += seconds
	end

	function self.SkipBack(seconds: number)
		assert(t.numberPositive(seconds), "Bad seconds")
		
		local wasPlaying = Playing.Value
		self.Pause()
		local newPausehead = math.max(0, Pausehead.Value - seconds)
		local segment = getSegment()
		for _, replay in segment.Replays do
			if typeof(replay.RewindTo) == "function" then
				replay.RewindTo(newPausehead)
			end
		end
		Pausehead.Value = newPausehead
		if wasPlaying then
			self.Play()
		end
	end

	function self.Restart()
		
		local wasPlaying = Playing.Value
		self.Pause()
		local segment = getSegment()
		for _, replay in segment.Replays do
			if typeof(replay.RewindTo) == "function" then
				replay.RewindTo(0)
			end
		end
		Pausehead.Value = 0
		if wasPlaying then
			self.Play()
		end
	end

	function self.ObservePlayState()
		return Playing:Observe():Pipe {
			Rx.map(function(playing)
				return playing and "Playing" or "Paused"
			end)
		}
	end

	function self.ObserveTimestampSeconds()
		return TimestampSeconds:Observe()
	end

	function self.GetDuration()
		local segment = getSegment()
		return segment.EndTimestamp
	end

	return self
end

export type Stage = typeof(Stage(nil :: any))

return Stage