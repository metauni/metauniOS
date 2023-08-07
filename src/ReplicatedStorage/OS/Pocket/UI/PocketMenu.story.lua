local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Pocket = ReplicatedStorage.OS.Pocket
local PocketMenu = require(Pocket.UI.PocketMenu)
local PocketImages = require(Pocket.Config).PocketTeleportBackgrounds
local SeminarService = require(ServerScriptService.OS.SeminarService)

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

	local fetch = task.spawn(function()
		menu:SetPockets(pockets)
		menu:SetSchedule(SeminarService:GetCurrentSeminars())
	end)

	local instance = menu:render()
	instance.Parent = target

	return function()
		coroutine.close(fetch)
		target:Destroy()
	end
end