local PocketCard = require(script.Parent.PocketCard)

local trsImages = {
	"rbxassetid://10571155928",
	"rbxassetid://10571156395",
	"rbxassetid://10571156964",
	"rbxassetid://10571157328"
}

return function(target)
	local card = PocketCard {
		PocketName = "The Rising Sea",
		PocketImage = trsImages[3],
		ActiveUsers = "3",
		OnClickJoin = function()
			print("Join!")
		end,
	}

	card.Parent = target

	return function()
		card:Destroy()
	end
end