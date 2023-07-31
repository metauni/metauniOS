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

	local SubMenu = Fusion.Value("Recent")

	local scrollingFrame = Fusion.New "ScrollingFrame" {

		AnchorPoint = Vector2.new(0,0.5),
		Position = UDim2.new(0,115,0.5,0),
		Size = UDim2.new(1,-130,1,-30),
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

	return UI.RoundedFrame {
		Size = UDim2.fromOffset(760, 650),
	
		BackgroundColor3 = Color3.fromHex("B9B9B9"),
	
		[Fusion.Children] = {
			scrollingFrame,

			UI.Div {
				AnchorPoint = Vector2.new(0,0.5),
				Position = UDim2.fromScale(0,0.5),
				Size = UDim2.new(0,100,1,0),


				[Fusion.Children] = {
					Fusion.New "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Top,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0,1),
					},

					UI.HighlightTextButton {
						Size = UDim2.fromOffset(100,50),
						Text = "Recent",
						TextSize = 20,
						Selected = Fusion.Computed(function()
							return SubMenu:get() == "Recent"
						end),
						[Fusion.OnEvent "MouseButton1Down"] = function()
							SubMenu:set("Recent")
						end,
					},

					UI.HighlightTextButton {
						Size = UDim2.fromOffset(100,50),
						Text = "Seminars",
						TextSize = 20,
						Selected = Fusion.Computed(function()
							return SubMenu:get() == "Seminars"
						end),
						[Fusion.OnEvent "MouseButton1Down"] = function()
							SubMenu:set("Seminars")
						end,
					},

					UI.HighlightTextButton {
						Size = UDim2.fromOffset(100,50),
						Text = "Boards",
						TextSize = 20,
						Selected = Fusion.Computed(function()
							return SubMenu:get() == "Boards"
						end),
						[Fusion.OnEvent "MouseButton1Down"] = function()
							SubMenu:set("Boards")
						end,
					},


				}
			}
		}

	}

end

return PocketMenu