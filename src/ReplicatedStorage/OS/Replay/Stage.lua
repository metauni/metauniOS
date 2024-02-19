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
local CharacterRecorder = require(script.Parent.CharacterRecorder)
local CharacterReplay = require(script.Parent.CharacterRecorder.CharacterReplay)
local RecordUtils = require(script.Parent.RecordUtils)
local VRCharacterReplay = require(script.Parent.VRCharacterRecorder.VRCharacterReplay)

local ENDTIMESTAMP_BUFFER = 0.5

export type StageProps = {
	ReplayId: string,
	ReplayName: string,
	NumSegments: number,
	Origin: CFrame, -- We ignore the stored origin, and play the replay relative to this one
	DataStore: DataStore,
	BoardGroup: Instance,
	OrbServer: OrbServer.OrbServer?
}

local function Stage(props: StageProps)
	assert(typeof(props.NumSegments) == "number" and props.NumSegments >= 1, "Bad NumSegments")

	local maid = Maid.new()
	local self = { Destroy = maid:Wrap(), props = props }

	local Playing = maid:Add(ValueObject.new(false))
	local Pausehead = maid:Add(ValueObject.new(0))
	local initialised = false
	local finishedSignal = maid:Add(GoodSignal.new())
	local TimestampSeconds = maid:Add(ValueObject.new(0))
	local segmentofRecordsList = {}

	local Replays: ValueObject.ValueObject<{RecordUtils.AnyReplay}> = maid:Add(ValueObject.new(nil))
	local endTimestamp: number = nil
	maid:GiveTask(function()
		local replays = Replays.Value
		if replays then
			for _, replay in replays do
				replay.Destroy()
			end
		end
	end)

	local function getCharacters(): {[string]: Model?}
		local characterReplays = Sift.Array.filter(Replays.Value, function(replay: RecordUtils.AnyReplay)
			return replay.ReplayType == "CharacterReplay" or replay.ReplayType == "VRCharacterReplay"
		end)

		return Sift.Dictionary.map(characterReplays, function(replay: CharacterReplay.CharacterReplay | VRCharacterReplay.VRCharacterReplay)
			return replay.GetCharacter(), replay.props.Record.CharacterId
		end)
	end

	local function fetchMissingRecords(): boolean
		local ok, msg = pcall(function()
			for i=1, props.NumSegments do
				if segmentofRecordsList[i] then
					continue
				end
	
				local data = props.DataStore:GetAsync(`Replay/{props.ReplayId}/{i}`)
				local segmentOfRecords = Serialiser.deserialiseSegmentOfRecords(data)
				segmentofRecordsList[i] = segmentOfRecords
	
				if not endTimestamp or segmentOfRecords.EndTimestamp > endTimestamp then
					endTimestamp = segmentOfRecords.EndTimestamp
				end
			end
		end)

		return ok, msg
	end

	local function initReplays()

		for i=1, props.NumSegments do
			if not segmentofRecordsList[i] then
				error(`SegmentOfRecords {i} not downloaded`)
			end
		end
		
		local replays = {}

		local ok, msg = pcall(function()
			local allRecords = Sift.Array.concat(Sift.Array.map(segmentofRecordsList, function(segmentOfRecords)
				return segmentOfRecords.Records
			end))
	
			local badRecords = Sift.Array.filter(allRecords, function(record)
				if table.find({
					"CharacterRecord",
					"VRCharacterRecord",
					"BoardRecord",
					"SoundRecord",
				}, record.RecordType) then
					return false
				end
	
				if record.RecordType == "StateRecord" then
					return false
				end
	
				return true
			end)
	
			if #badRecords > 0 then
				for _, record in badRecords do
					warn(`Unrecognised record, RecordType={record.RecordType}`)
				end
				error("[ReplayStage] Initialisation failed. Unrecognised records found.")
			end
	
			for _, record in RecordUtils.FilterRecords(allRecords, "CharacterRecord") do
				local replay = RecordUtils.GetCharacterReplay(replays, record.CharacterId)
				if replay then
					replay.ExtendRecord(record)
				else
					table.insert(replays, CharacterReplay({
						Record = record,
						Origin = props.Origin,
					}))
				end
			end
	
			for _, record in RecordUtils.FilterRecords(allRecords, "VRCharacterRecord") do
				local existing = RecordUtils.GetCharacterReplay(replays, record.CharacterId)
				if existing then
					existing.ExtendRecord(record)
				else
					table.insert(replays, VRCharacterReplay({
						Record = record,
						Origin = props.Origin,
					}))
				end
			end
	
			for _, record in RecordUtils.FilterRecords(allRecords, "BoardRecord") do
				local existing = RecordUtils.GetBoardReplay(replays, record.BoardId)
				if existing then
					existing.ExtendRecord(record)
				else
					table.insert(replays, BoardReplay({
						Origin = props.Origin,
						Record = record,
						BoardParent = props.BoardGroup,
					}))
				end
			end
	
			for _, record in allRecords do
				if record.RecordType == "StateRecord" and record.StateType == "Orb" then
					if not props.OrbServer then
						error("No orb given")
					end
	
					local existing = Sift.Array.filter(replays, function(replay)
						return replay.ReplayType == "StateReplay" and replay.props.Record.StateType == "Orb"
					end)[1]
	
					if existing then
						existing.ExtendRecord(record)
					else
						table.insert(replays, StateReplay({
							Record = record,
							Handler = function(state)
								local characters = getCharacters()
								local character = characters[state.SpeakerId]
								if false then
									-- TODO: enable this functionality without allowing speakerAttachment to be destroyed on cleanup
									props.OrbServer.SetSpeakerCharacter(character)
								end
								props.OrbServer.SetViewMode(state.ViewMode)
								props.OrbServer.SetWaypointOnly(state.WaypointOnly)
								props.OrbServer.SetShowAudience(state.ShowAudience)
							end,
						}))
					end
				end
			end
	
			for _, record in RecordUtils.FilterRecords(allRecords, "SoundRecord") do
				local existing = RecordUtils.GetCharacterReplay(replays, record.CharacterId)
				if existing then
					existing.ExtendVoice(record)
				end
			end
	
			for _, replay in Replays.Value do
				replay.Init()
			end
		end)

		if not ok then
			for _, replay in Replays do
				replay.Destroy()
			end
			return false, msg
		end

		Replays.Value = replays
		
		for _, segmentOfRecords in segmentofRecordsList do
			if endTimestamp then
				endTimestamp = math.max(endTimestamp, segmentOfRecords.EndTimestamp)
			else
				endTimestamp = segmentOfRecords.EndTimestamp
			end
		end

		return true
	end

	function self.Init()
		-- Can do this after placing Replay boards, but need to add tag
		-- like "ReplayBoard" to replay boards so this code doesn't hide them too
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

		do
			local ok, msg = fetchMissingRecords()
			if not ok then
				warn(msg)
				return
			end
		end

		do
			local ok, msg = initReplays()
			if not ok then
				warn(msg)
				return
			end
		end

		initialised = true
	end

	function self.GetFinishedSignal()
		return finishedSignal
	end

	-- Remember could be nil
	local timeAtResume: number?

	local function updateTimestamp()
		if timeAtResume then
			local timestamp = Pausehead.Value + (os.clock() - timeAtResume)
			TimestampSeconds.Value = math.round(timestamp)
		end
	end

	function self.Play()
		if not initialised then
			do
				local ok, msg = fetchMissingRecords()
				if not ok then
					warn(msg)
					return
				end
			end
	
			do
				local ok, msg = initReplays()
				if not ok then
					warn(msg)
					return
				end
			end
	
			initialised = true
		end
		
		if Playing.Value then
			return
		end

		for _, replay in Replays.Value do
			if typeof(replay.SetActive) == "function" then
				replay.SetActive(true)
			end
		end

		timeAtResume = os.clock()

		maid._playing = RunService.Heartbeat:Connect(function()
			updateTimestamp()
			local timestamp = Pausehead.Value + (os.clock() - (timeAtResume :: number))
			for _, replay in Replays.Value do
				replay.UpdatePlayhead(timestamp)
			end
			if timestamp >= endTimestamp + ENDTIMESTAMP_BUFFER then
				print(`[ReplayStage] Replay {props.ReplayName} (ID: {props.ReplayId}) ended.`)
				maid._playing = nil
				Playing.Value = false
				for _, replay in Replays.Value do
					if typeof(replay.SetActive) == "function" then
						replay.SetActive(false)
					end
				end
				
				finishedSignal:Fire()
			end
		end)

		Playing.Value = true
	end

	function self.Pause()
		maid._playing = nil

		for _, replay in Replays.Value do
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

		updateTimestamp()
	end

	function self.SkipBack(seconds: number)
		assert(t.numberPositive(seconds), "Bad seconds")
		
		local wasPlaying = Playing.Value
		self.Pause()
		local newPausehead = math.max(0, Pausehead.Value - seconds)
		for _, replay in Replays.Value do
			if typeof(replay.RewindTo) == "function" then
				replay.RewindTo(newPausehead)
			end
		end
		Pausehead.Value = newPausehead
		if wasPlaying then
			self.Play()
		else
			updateTimestamp()
		end
	end

	function self.Restart()
		
		local wasPlaying = Playing.Value
		self.Pause()
		for _, replay in Replays.Value do
			if typeof(replay.RewindTo) == "function" then
				replay.RewindTo(0)
			end
		end
		Pausehead.Value = 0
		if wasPlaying then
			self.Play()
		else
			updateTimestamp()
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

	function self.GetDuration(): number?
		return endTimestamp
	end

	return self
end

export type Stage = typeof(Stage(nil :: any))

return Stage