local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StageUI = require(script.Parent.StageUI)
local Maid = require(ReplicatedStorage.Util.Maid)
local Blend = require(ReplicatedStorage.Util.Blend)

return function(target)
	local maid = Maid.new()

	local PlayState = maid:Add(Blend.State("Paused"))
	local Timestamp = maid:Add(Blend.State(0))

	local ui = StageUI {
		PlayState = PlayState,
		OnTogglePlaying = function()

			if PlayState.Value == "Paused" then
				PlayState.Value = "Playing"
				maid._timer = RunService.RenderStepped:Connect(function(delta)
					Timestamp.Value += delta
				end)
			else
				PlayState.Value = "Paused"
				maid._timer = nil
			end
		end,
		Timestamp = Timestamp,
		OnStop = function()
			maid:Destroy()
		end,
		Duration = 40,
		ReplayName = "Euclid",
		OnSkipAhead = print,
		OnSkipBack = print,
	}

	maid:GiveTask(Blend.mount(target, {
		ui
	}))

	return function()
		maid:DoCleaning()
	end
end