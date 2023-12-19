local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StudioMenu = require(script.Parent.StudioMenu)
local Maid = require(ReplicatedStorage.Util.Maid)
local Blend = require(ReplicatedStorage.Util.Blend)

return function(target)
	local maid = Maid.new()

	
	local menu: StudioMenu.StudioMenu
	menu = StudioMenu {
		OnRecord = function()
			local start = os.clock()
			menu.SetPhaseRecording()
			
			maid._timer = RunService.RenderStepped:Connect(function()
				menu.SetTimer(os.clock() - start)
			end)
		end,
		OnStop = function()
			maid:Destroy()
		end,
	}

	menu.SetPhaseReady()

	maid:GiveTask(Blend.mount(target, {
		menu.render()
	}))

	return function()
		maid:DoCleaning()
	end
end