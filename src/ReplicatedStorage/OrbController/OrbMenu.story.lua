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

	local menu
	menu = New "Frame" {
		Parent = target,

		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 30, 1, -30),
		Size = UDim2.fromOffset(300, 150),

		BackgroundTransparency = 1,

		[Children] = OrbMenu {
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
				menu:Destroy()
			end
		}
	}

	return function ()
		menu:Destroy()
	end
end