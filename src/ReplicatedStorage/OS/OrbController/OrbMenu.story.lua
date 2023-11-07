local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local New = Fusion.New
local Value = Fusion.Value
local Children = Fusion.Children

local OrbMenu = require(script.Parent.OrbMenu)

return function (target)

	local ViewMode = Value("single")
	local Audience = Value("audience")
	local OrbcamActive = Value(true)
	local WaypointOnly = Value(false)

	local menu
	menu = New "Frame" {
		Parent = target,

		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 15, 1, -15),
		Size = UDim2.fromOffset(250, 125),

		BackgroundTransparency = 1,

		[Children] = OrbMenu {
			OrbBrickColor = BrickColor.new("CGA brown"),
			OrbMaterial = Enum.Material.CrackedLava,
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
			end,
			Teleport = function()
				print("teleport!")
			end,
			SendEmoji = function(emojiName: string)
				print(`send emoji! - {emojiName}`)
			end,
			WaypointOnly = WaypointOnly,
			SetWaypointOnly = function(waypointOnly: boolean)
				WaypointOnly:set(waypointOnly)
			end,
			OnClickReplayMenu = function()
				print("Open Replay Menu!")
			end
		}
	}

	return function ()
		menu:Destroy()
	end
end