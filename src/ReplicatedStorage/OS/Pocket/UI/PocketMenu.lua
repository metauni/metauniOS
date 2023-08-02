local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local UI = require(ReplicatedStorage.OS.UI)

local PocketCard = require(script.Parent.PocketCard)
local Remotes = ReplicatedStorage.OS.Pocket.Remotes

local PocketMenu = {}
PocketMenu.__index = PocketMenu

function PocketMenu.new()
	local self = setmetatable({}, PocketMenu)

	self._pockets = Fusion.Value({})
	return self
end

export type PocketData = {
	Name: string,
	Image: string,
}

function PocketMenu:SetPockets(pockets: {PocketData})
	self._pockets:set(pockets)
end

function PocketMenu:render()

	local metauniDarkBlue = Color3.fromHex("10223b")
	local metauniLightBlue = Color3.fromHex("1a539f")

	local SubMenu = Fusion.Value("Pockets")

	local function ScrollingFrame()
	
		return Fusion.New "ScrollingFrame" {
			ScrollingEnabled = false,
			AnchorPoint = Vector2.new(0,0),
			Position = UDim2.new(0,100,0,0),
			Size = UDim2.new(1,-100,1,0),
			BackgroundTransparency = 1,

			
			[Fusion.Children] = {

				Fusion.New "UIGridLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
					CellSize = UDim2.fromOffset(150,130),
					CellPadding = UDim2.fromOffset(15, 15),
					FillDirection = Enum.FillDirection.Horizontal,
					FillDirectionMaxCells = 4,
				},

				UI.Padding {Offset = 15},

				Fusion.ForPairs(self._pockets, function(i, pocketData: PocketData)
					return i, PocketCard {
						PocketName = pocketData.Name,
						PocketImage = pocketData.Image,
						OnClickJoin = function()
							Remotes.Goto:FireServer(pocketData.Name)
						end,
						ActiveUsers = "?",
					}
				end, Fusion.cleanup)
			}
		}
	end

	local main = UI.Div {
		AnchorPoint = Vector2.new(0,0),
		Position = UDim2.new(0,0, 0,65),
		Size = UDim2.new(1,0,1,-65),

		[Fusion.Children] = {

			Fusion.Computed(function()
				if SubMenu:get() == "Pockets" then
					return ScrollingFrame()
				end

				return UI.TextLabel {
					Text = "Coming Soon",
					TextSize = 30,
					TextColor3 = Color3.fromHex("F2F2F3"),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,

					AnchorPoint = Vector2.new(0,0),
					Position = UDim2.new(0,110,0,10),
					Size = UDim2.new(1,-100,1,0),
				}
			end, Fusion.cleanup),

			UI.Div {
				AnchorPoint = Vector2.new(0,0.5),
				Position = UDim2.fromScale(0,0.5),
				Size = UDim2.new(0,100,1,0),


				[Fusion.Children] = {
					Fusion.New "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Top,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0,2),
					},

					UI.HighlightTextButton {
						Size = UDim2.fromOffset(100,50),
						Text = "Pockets",
						TextSize = 20,
						TextColors = {Color3.fromHex("F2F2F3"), Color3.fromHex("F2F2F3")},
						BackgroundColors = {metauniLightBlue, Color3.fromHex("303036")},
						Transparencies = {0,1},
						Selected = Fusion.Computed(function()
							return SubMenu:get() == "Pockets"
						end),
						[Fusion.OnEvent "MouseButton1Down"] = function()
							SubMenu:set("Pockets")
						end,
					},

					UI.HighlightTextButton {
						Size = UDim2.fromOffset(100,50),
						Text = "Seminars",
						TextSize = 20,
						TextColors = {Color3.fromHex("F2F2F3"), Color3.fromHex("F2F2F3")},
						BackgroundColors = {metauniLightBlue, Color3.fromHex("303036")},
						Transparencies = {0,1},
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
						TextColors = {Color3.fromHex("F2F2F3"), Color3.fromHex("F2F2F3")},
						BackgroundColors = {metauniLightBlue, Color3.fromHex("303036")},
						Transparencies = {0,1},
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


	local wholeMenu
	wholeMenu = UI.RoundedFrame {

		Size = UDim2.fromOffset(780, 700),

		CornerRadius = UDim.new(0,20),
	
		BackgroundColor3 = Color3.fromHex("303036"),
		BackgroundTransparency = 0.1,

		[Fusion.Children] = {
			main,

			UI.Div {
				AnchorPoint = Vector2.new(1,0),
				Position = UDim2.new(1,0, 0, 0),
				Size = UDim2.fromOffset(65,65),
				
				[Fusion.Children] = {
					Fusion.New "TextButton" {
					
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(.5,.5),
						Position = UDim2.fromScale(.5, .5),
						Size = UDim2.fromOffset(30,30),
	
		
						[Fusion.OnEvent "MouseButton1Down"] = function()
							wholeMenu:Destroy()
						end,
		
						[Fusion.Children] = {
							UI.X {
								Color = Color3.fromHex("F3F3F6"),
							}
						},
					},
				}
			},

			UI.TextLabel {
				Text = "metauni",

				TextColor3 = Color3.fromHex("F3F3F6"),
				TextSize = 48,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = Font.fromName("Merriweather", Enum.FontWeight.Bold),
				
				AnchorPoint = Vector2.new(0,0),
				Position = UDim2.new(0, 0, 0, 0),
				Size = UDim2.new(1,0,0,65),
				ZIndex = 1,

				[Fusion.Children] = {UI.Padding {Offset = 10}},
			},

			Fusion.New "Frame" {
				AnchorPoint = Vector2.new(0,0),
				Position = UDim2.new(0,0,0,65),
				Size = UDim2.new(1,0,0,1),

				BackgroundColor3 = Color3.fromHex("F3F3F6"),
			},

			Fusion.New "Frame" {
				AnchorPoint = Vector2.new(0,0),
				Position = UDim2.new(0,100,0,65),
				Size = UDim2.new(0,1,1,-65),

				BackgroundColor3 = Color3.fromHex("F3F3F6"),
			},
		},
	}

	return Fusion.New "ScreenGui" {
		Name = "PocketMenu",
		IgnoreGuiInset = true,
		[Fusion.Children] = wholeMenu,
	}
end

return PocketMenu