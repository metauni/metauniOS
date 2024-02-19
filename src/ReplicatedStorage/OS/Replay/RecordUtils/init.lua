local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateRecorder = require(script.Parent.StateRecorder)
local StateReplay = require(script.Parent.StateRecorder.StateReplay)
local BoardRecorder = require(script.Parent.BoardRecorder)
local BoardReplay = require(script.Parent.BoardRecorder.BoardReplay)
local CharacterRecorder = require(script.Parent.CharacterRecorder)
local CharacterReplay = require(script.Parent.CharacterRecorder.CharacterReplay)
local SoundReplay = require(script.Parent.SoundReplay)
local VRCharacterRecorder = require(script.Parent.VRCharacterRecorder)
local VRCharacterReplay = require(script.Parent.VRCharacterRecorder.VRCharacterReplay)
local Sift = require(ReplicatedStorage.Packages.Sift)

export type AnyRecord = 
	CharacterRecorder.CharacterRecord |
	VRCharacterRecorder.VRCharacterRecord |
	BoardRecorder.BoardRecord |
	StateRecorder.StateRecord |
	SoundReplay.SoundRecord

export type AnyReplay = 
	CharacterReplay.CharacterReplay |
	VRCharacterReplay.VRCharacterReplay |
	BoardReplay.BoardReplay |
	StateReplay.StateReplay |
	SoundReplay.SoundReplay

export type CharacterVoices = {
	-- Key is CharacterId
	[string]: {
		CharacterName: string,
		Clips: {
			{
				AssetId: string,
				StartTimestamp: number,
				StartOffset: number,
				EndOffset: number,
			}
		}
	}
}

local export = {}

function export.ToCharacterVoices(recordSegment)
	local characterVoices = {}
	
	for _, record in recordSegment.Records do
		if record.RecordType == "CharacterRecord" or record.RecordType == "VRCharacterRecord" then
			characterVoices[record.CharacterId] = {
				CharacterName = record.CharacterName,
				Clips = {},
			}
		end
	end

	for _, record in recordSegment.Records do
		if record.RecordType == "SoundRecord" and record.CharacterId then
			characterVoices[record.CharacterId] = {
				CharacterName = record.CharacterName,
				Clips = record.Clips,
			}
		end
	end

	return characterVoices
end

function export.EditSoundRecordsInPlace(segmentOfRecords, newCharacterVoices: CharacterVoices): ()

	for characterId, characterVoice in newCharacterVoices do
		local existings = Sift.Array.filter(segmentOfRecords.Records, function(record)
			return record.RecordType == "SoundRecord" and record.CharacterId == characterId
		end)

		if #existings > 1 then
			error(`Duplicate sound records exist for {characterId}`)
		end

		local soundRecord = existings[1]
		if not soundRecord then
			soundRecord = {
				RecordType = "SoundRecord",
				CharacterId = characterId,
				CharacterName = characterVoice.CharacterName,
				-- Clips is set later
			}
			-- Add new sound record to segment of records
			table.insert(segmentOfRecords.Records, soundRecord)
		end

		-- Edit soundRecord in place
		soundRecord.Clips = characterVoice.Clips
		soundRecord.CharacterName = characterVoice.CharacterName
	end

	-- Nothing returned, this is an in-place operation
end

function export.RecordExtendsReplay(record: AnyRecord, replay: AnyReplay)
	if record.RecordType ~= replay.props.Record.RecordType then
		return false
	end

	if record.RecordType == "BoardRecord" then
		return record.BoardId == replay.props.Record.BoardId
	elseif record.RecordType == "CharacterRecord" then
		return record.CharacterId == replay.props.Record.CharacterId
	elseif record.RecordType == "VRCharacterRecord" then
		return record.CharacterId == replay.props.Record.CharacterId
	end

	return false
end

function export.FilterRecords(records: {AnyRecord}, recordType: string): {AnyRecord}
	return Sift.Array.filter(records, function(record)
		return record.RecordType == recordType
	end)
end

function export.FilterReplays(replays: {AnyReplay}, recordType: string): {AnyReplay}
	return Sift.Array.filter(replays, function(replay)
		return replay.props.Record.RecordType == recordType
	end)
end

function export.GetCharacterReplay(replays: {AnyReplay}, characterId: string): CharacterReplay.CharacterReplay | VRCharacterReplay.VRCharacterReplay | nil
	for _, replay in replays do
		if replay.ReplayType == "CharacterReplay" or replay.ReplayType == "VRCharacterReplay" then
			if characterId == replay.props.Record.CharacterId then
				return replay
			end
		end
	end

	return nil
end

function export.GetBoardReplay(replays: {AnyReplay}, boardId: string): BoardReplay.BoardReplay?
	for _, replay in replays do
		if replay.ReplayType == "BoardReplay" then
			if boardId == replay.props.Record.BoardId then
				return replay
			end
		end
	end

	return nil
end

return export