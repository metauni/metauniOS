local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local UI = require(ReplicatedStorage.OS.UI)

local Pocket = require(script.Parent.Pocket)

local PocketMenu = {}
PocketMenu.__index = PocketMenu

function PocketMenu.new()
	local self = setmetatable({}, PocketMenu)

	self._recentPockets = Fusion.Value({})
	return self
end

export type PocketData = {
	Name: string,
	PocketNumber: number,
}

function PocketMenu:SetRecentPockets(pockets: {PocketData})
	self._recentPockets:set(pockets)
end

local trsImages = {
	"rbxassetid://10571155928",
	"rbxassetid://10571156395",
	"rbxassetid://10571156964",
	"rbxassetid://10571157328"
}

function PocketMenu:render()

	return UI.RoundedFrame {
		Size = UDim2.fromOffset(670, 650),
	
		BackgroundColor3 = Color3.fromHex("B9B9B9"),
	
		[Fusion.Children] = {
			Fusion.New "ScrollingFrame" {

				AnchorPoint = Vector2.new(0.5,0.5),
				Position = UDim2.fromScale(0.5,0.5),
				Size = UDim2.new(1,-30,1,-30),
				BackgroundTransparency = 1,


				[Fusion.Children] = {
					Fusion.New "UIGridLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						CellSize = UDim2.fromOffset(200,300),
						CellPadding = UDim2.fromOffset(15, 15),
						FillDirection = Enum.FillDirection.Horizontal,
						FillDirectionMaxCells = 3,
					},
		
					Fusion.ForPairs(self._recentPockets, function(i, pocketData: PocketData)
						return i, Pocket {
							PocketName = pocketData.Name,
							PocketImage = trsImages[math.fmod(i-1, 4) + 1],
							OnClickJoin = function()
								print(`Joining {pocketData.Name} {pocketData.PocketNumber}`)
							end,
							NumActive = i,
						}
					end, Fusion.cleanup)
				}
			}
		}

	}

end

return PocketMenu