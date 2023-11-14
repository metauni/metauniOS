local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReplayMenu = require(script.Parent)
local Maid = require(ReplicatedStorage.Util.Maid)
local Blend = require(ReplicatedStorage.Util.Blend)

return function(target)
	local maid = Maid.new()

	local menu = ReplayMenu({
		OnRecord = function(recordingName: string)
			print("Record!", recordingName)
		end
	})
	
	maid:GiveTask(Blend.mount(target, {
		menu:render()
	}))

	menu.SetReplayList({
		{
			Name = "Test Replay",
			Id = "TestId",
		},
		{
			Name = "Test Replay",
			Id = "TestId",
		},
		{
			Name = "Test Replay",
			Id = "TestId",
		},
		{
			Name = "Test Replay",
			Id = "TestId",
		},
		{
			Name = "Test Replay",
			Id = "TestId",
		},
	})

	return function()
		maid:DoCleaning()
	end
end