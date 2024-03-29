--[[
	For managing the recording, and editing of a replay recording.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local OrbServer = require(ServerScriptService.OS.OrbService.OrbServer)
local VRServerService = require(ReplicatedStorage.OS.VR.VRServerService)
local BoardRecorder = require(script.Parent.BoardRecorder)
local Sift = require(ReplicatedStorage.Packages.Sift)
local Rx = require(ReplicatedStorage.Util.Rx)
local Maid = require(ReplicatedStorage.Util.Maid)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)

local CharacterRecorder = require(script.Parent.CharacterRecorder)
local Serialiser = require(script.Parent.Serialiser)
local StateRecorder = require(script.Parent.StateRecorder)
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

	function self.StartRecording()
		assert(self.PhaseIsBefore("Recording"), `[Replay Studio] Tried to start recording during phase {RecordingPhase.Value}`)
		
		for _, recorder in recorders do
			recorder.Start(startTime)
		end
		RecordingPhase.Value = "Recording"
	end

	function self.StopRecording()
		assert(self.PhaseIsBefore("Recorded"), `[Replay Studio] Tried to stop recording during phase {RecordingPhase.Value}`)

		local segmentOfRecords = {
			Origin = props.Origin,
			Records = {},
			EndTimestamp = nil -- set after stopping
		}
		
		for _, recorder in recorders do
			recorder.Stop()
			table.insert(segmentOfRecords.Records, recorder.FlushToRecord())
		end
		segmentOfRecords.EndTimestamp = os.clock() - startTime

		RecordingPhase.Value = "Recorded"

		self.SegmentOfRecords = segmentOfRecords
	end
	
	-- TODO: worry about this being called multiple times
	function self.Store()
		assert(self.SegmentOfRecords, "No segment ready to store")
		local data = Serialiser.serialiseSegmentOfRecords(self.SegmentOfRecords, 1)

		task.spawn(function()
			while true do
				local ok, msg = pcall(function()
					props.DataStore:SetAsync(`Replay/{props.RecordingId}/{1}`, data)
				end)
				if not ok then
					warn(msg)
					task.wait(10)
					continue
				end
				break
			end

			RecordingPhase.Value = "Saved"
	
			print(`[Replay Studio] SegmentOfRecords 1 stored (Id: {props.RecordingId})`)
		end)
	end

	return self
end

export type Studio = typeof(Studio(nil :: any))

return Studio