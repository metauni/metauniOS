local Pocket = require(script.Parent.Pocket)
local UI = require(game.ReplicatedStorage.OS.UI)

local trsImages = {
	"rbxassetid://10571155928",
	"rbxassetid://10571156395",
	"rbxassetid://10571156964",
	"rbxassetid://10571157328"
}

return function(target)
	local pocket = Pocket {
		PocketName = "The Rising Sea",
		PocketImage = trsImages[3],
		NumActive = 3,
		OnClickJoin = function()
			print("Join!")
		end,
	}

	local ui = UI.Div {
		BackgroundColor3 = Color3.fromHex("F0F0F0"),
		BackgroundTransparency = 0,
	}

	pocket.Parent = ui
	ui.Parent = target

	return function()
		ui:Destroy()
	end
end