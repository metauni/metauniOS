local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pocket = ReplicatedStorage.OS.Pocket
local PocketMenu = require(Pocket.UI.PocketMenu)
local PocketImages = require(Pocket.Config).PocketTeleportBackgrounds

return function(target)
	local menu = PocketMenu.new()
	
	local pockets = {
		{Name = "The Rising Sea", Image = "rbxassetid://10571156964"},
		{Name = "Symbolic Wilds 37", Image = PocketImages["Symbolic Wilds"]},
		{Name = "Moonlight Forest 8", Image = PocketImages["Moonlight Forest"]},
		{Name = "Delta Plains 41", Image = PocketImages["Delta Plains"]},
		{Name = "Storyboard 1", Image = PocketImages["Storyboard"]},
		{Name = "Big Sir 2", Image = PocketImages["Big Sir"]},
		{Name = "Overland 1", Image = PocketImages["Overland"]},
	} :: {PocketMenu.PocketData}

	menu:SetPockets(pockets)

	local instance = menu:render()
	instance.Parent = target

	return function()
		target:Destroy()
	end
end