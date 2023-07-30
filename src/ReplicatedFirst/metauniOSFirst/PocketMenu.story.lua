local PocketMenu = require(script.Parent.PocketMenu)
local UI = require(game.ReplicatedStorage.OS.UI)
local Fusion = require(game.ReplicatedStorage.Packages.Fusion)

return function(target)
	local menu = PocketMenu.new()

	local pockets: {PocketMenu.PocketData} = {}

	for i=1, 10 do
		table.insert(pockets, {
			Name = "The Rising Sea",
			PocketNumber = i,
		})
	end
	menu:SetRecentPockets(pockets)

	local instance = menu:render()
	instance.Parent = target

	return function()
		target:Destroy()
	end
end