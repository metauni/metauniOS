local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReplayEditor = require(script.Parent.ReplayEditor)
local Maid = require(ReplicatedStorage.Util.Maid)
local Blend = require(ReplicatedStorage.Util.Blend)
local Promise = require(ReplicatedStorage.Util.Promise)

return function(target)
	local maid = Maid.new()

	local characterVoices = {
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
	
	maid:GiveTask(Blend.mount(target, {
		ReplayEditor({
			Replay = {
				ReplayId = "123",
				ReplayName = "TestReplay",
			},
			OnClose = maid:Wrap(),
			SaveCharacterVoicesPromise = function()
				return Promise.spawn(function(resolve, reject)
					task.wait(0.2)
					if math.random() < 0.3 then
						reject("Random Fail")
					else
						resolve()
					end
				end)
			end,
			FetchCharacterVoices = function()
				return characterVoices
			end
		})
	}))

	return function()
		maid:DoCleaning()
	end
end