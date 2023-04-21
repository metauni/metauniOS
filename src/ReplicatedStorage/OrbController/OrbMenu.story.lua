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
	local Audience = Value("audience")
	local OrbcamActive = Value(true)

	local gui
	gui = OrbMenu {
		Parent = target,
		OrbcamActive = OrbcamActive,
		SetOrbcamActive = function(active)
			OrbcamActive:set(active)
		end,
		ViewMode = ViewMode,
		SetViewMode = function(viewMode)
			ViewMode:set(viewMode)
		end,
		Audience = Audience,
		SetAudience = function(audience)
			Audience:set(audience)
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