local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReplayMenu = require(script.Parent)
local Maid = require(ReplicatedStorage.Util.Maid)
local Blend = require(ReplicatedStorage.Util.Blend)
local Promise = require(ReplicatedStorage.Util.Promise)

return function(target)
	local maid = Maid.new()

	local replayCharacterVoices = {
		["1"] = {
			["12345678"] = {
				CharacterName = "starsonthars",
				Clips = {
					{
						AssetId = "rbx://123",
						StartTimestamp = 0.1,
						StartOffset = 0.2,
						EndOffset = 0.3,
					},
					{
						AssetId = "rbx://456",
						StartTimestamp = 0.1,
						StartOffset = 0.2,
						EndOffset = 0.3,
					},
					{
						AssetId = "rbx://789",
						StartTimestamp = 0.1,
						StartOffset = 0.2,
						EndOffset = 0.3,
					},
				}
			},
			["101010"] = {
				CharacterName = "blinkybill",
				Clips = {
					{
						AssetId = "rbx://123",
						StartTimestamp = 0.1,
						StartOffset = 0.2,
						EndOffset = 0.3,
					},
					{
						AssetId = "rbx://456",
						StartTimestamp = 0.1,
						StartOffset = 0.2,
						EndOffset = 0.3,
					},
					{
						AssetId = "rbx://789",
						StartTimestamp = 0.1,
						StartOffset = 0.2,
						EndOffset = 0.3,
					},
				}
			},
			["0000000"] = {
				CharacterName = "test",
				Clips = {
					{
						AssetId = "rbx://123",
						StartTimestamp = 0.1,
						StartOffset = 0.2,
						EndOffset = 0.3,
					},
					{
						AssetId = "rbx://456",
						StartTimestamp = 0.1,
						StartOffset = 0.2,
						EndOffset = 0.3,
					},
					{
						AssetId = "rbx://789",
						StartTimestamp = 0.1,
						StartOffset = 0.2,
						EndOffset = 0.3,
					},
				}
			},
		}
	}

	local menu = ReplayMenu({
		OnPlay = warn,
		OnClose = maid:Wrap(),
		OnRecord = function(recordingId)
			print("Record!", recordingId)
		end,
		FetchReplayCharacterVoices = function(replayId: string)
			return replayCharacterVoices[replayId] or {}
		end,
		SaveReplayCharacterVoicesPromise = function(replayId, characterVoices)
			return Promise.spawn(function(resolve, reject)
				task.wait(0.2)
				if math.random() < 0.3 then
					reject("Random Fail")
				else
					replayCharacterVoices[replayId] = characterVoices
					resolve()
				end
			end)
		end,
	})
	
	maid:GiveTask(Blend.mount(target, {
		menu:render()
	}))

	local replayList = {}
	for i=1 , 30 do
		table.insert(replayList, {
			ReplayName = "Replay "..string.char(string.byte("A") + (i-1)),
			ReplayId = tostring(i),
		})
	end

	menu.SetReplayList(replayList)

	return function()
		maid:DoCleaning()
	end
end