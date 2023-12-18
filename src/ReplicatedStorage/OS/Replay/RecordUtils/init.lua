local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

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

return export