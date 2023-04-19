local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local New = Fusion.New
local Value = Fusion.Value
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Children = Fusion.Children
local Observer = Fusion.Observer

local OrbMenu = require(script.Parent.OrbMenu)

return function (target)

	local ViewMode = Value("single")

	local gui
	gui = OrbMenu {
		Parent = target,
		ViewMode = ViewMode,
		SetViewMode = function(viewMode)
			ViewMode:set(viewMode)
		end,
		IsSpeaker = Value(true),
		Detach = function()
			gui:Destroy()
		end
	}

	return function ()
		gui:Destroy()
	end
end