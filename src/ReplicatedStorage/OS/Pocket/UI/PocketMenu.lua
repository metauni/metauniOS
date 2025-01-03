local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Pocket = ReplicatedStorage.OS.Pocket
local PocketConfig = require(Pocket.Config)
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local UI = require(ReplicatedStorage.OS.UI)
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local Maid = require(ReplicatedStorage.Packages.metaboard.Util.Maid)
local Blend = require(ReplicatedStorage.Util.Blend)
local Rx = require(ReplicatedStorage.Util.Rx)
local Rxi = require(ReplicatedStorage.Util.Rxi)

local PocketCard = require(script.Parent.PocketCard)
local Remotes = ReplicatedStorage.OS.Pocket.Remotes

local localPlayer = Players.LocalPlayer

local metauniDarkBlue = Color3.fromHex("10223b")
local metauniLightBlue = Color3.fromHex("1a539f")

local PocketMenu = {}
PocketMenu.__index = PocketMenu

function PocketMenu.new()
	local self = setmetatable({}, PocketMenu)

	self._pockets = Fusion.Value({})
	self._schedule = Fusion.Value({})
	self._modalGuiActive = false
	self._maid = Maid.new()
	return self
end

export type PocketData = {
	Name: string,
	Image: string,
}

function PocketMenu:_startBoardSelectMode(onBoardSelected, displayType)
	local promise, maid = metaboard.Client:PromiseBoardSelection()
	-- cleans up the last maid if there was one
	self._maid._selectBoard = maid

	maid:Add(Blend.mount(Players.LocalPlayer.PlayerGui, {
		Blend.New "ScreenGui" {
			Name = "BoardSelectGui",

			Blend.New "TextButton" {
				Name = "CancelButton",
				BackgroundColor3 = Color3.fromRGB(148,148,148),
				Size = UDim2.new(0,200,0,50),
				Position = UDim2.new(0.5,-100,0.9,-70),
				TextColor3 = Color3.new(1,1,1),
				TextScaled = true,
				Text = "Cancel",
				[Blend.OnEvent "Activated"] = function()
					self._maid._selectBoard = nil
				end,

				Blend.New "UICorner" {},
			},

			Blend.New "TextLabel" {
				Name = "TextLabel",
				BackgroundColor3 = Color3.new(0,0,0),
				BackgroundTransparency = 0.9,
				Size = UDim2.new(0,300,0,50),
				Position = UDim2.new(0.5,-150,0,80),
				TextColor3 = Color3.new(1,1,1),
				TextScaled = true,
				Text = "Select a board",
			}
		}
	}))

	promise:Then(function(board)
		if not board then
			return
		end
		if onBoardSelected == "startDisplay" then
			self:_startDisplay(displayType, board)
		elseif onBoardSelected == "startDecalEntryDisplay" then
			self:_startDecalEntryDisplay(board)
		elseif onBoardSelected == "showToAI" then
			self:_showBoardToAI(board)
		end
	end)
end

function PocketMenu:_startDisplay(displayType, board: metaboard.BoardClient)
    if self._modalGuiActive then return end
    self._modalGuiActive = true

    if not board:GetPart():FindFirstChild("PersistId") then return end
    local boardPersistId = board:GetPart():FindFirstChild("PersistId").Value
	
    local isPocket = Pocket:GetAttribute("IsPocket")
    local pocketId = nil
    if isPocket then
        if Pocket:GetAttribute("PocketId") == nil then
            Pocket:GetAttributeChangedSignal("PocketId"):Wait()
        end

        pocketId = Pocket:GetAttribute("PocketId")
    end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BoardDisplay"

	local button = Instance.new("TextButton")
	button.Name = "OKButton"
	button.Size = UDim2.new(0,200,0,50)
	button.Position = UDim2.new(0.5,-100,0.5,150)
	button.Parent = screenGui
	button.BackgroundColor3 = Color3.fromRGB(0,162,0)
	button.TextColor3 = Color3.new(1,1,1)
	button.TextSize = 25
	button.Text = "OK"
	button.Activated:Connect(function()
        self._modalGuiActive = false
		screenGui:Destroy()
	end)
	Instance.new("UICorner").Parent = button
	
	local dataString
	local displayWidth

    if displayType == "key" then
        displayWidth = 600
        if isPocket then
            dataString = pocketId .. "-" .. boardPersistId
        else
            dataString = boardPersistId
        end
    elseif displayType == "URL" then
        displayWidth = 800
        if isPocket then
            local pocketName = HttpService:UrlEncode(Pocket:GetAttribute("PocketName"))
            dataString = "https://www.roblox.com/games/start?placeId=" .. PocketConfig.RootPlaceId
            dataString = dataString .. "&launchData=pocket%3A" .. pocketName
            dataString = dataString .. "-targetBoardPersistId%3A" .. boardPersistId
        else
            dataString = "https://www.roblox.com/games/start?placeId=" .. PocketConfig.RootPlaceId
            dataString = dataString .. "&launchData=targetBoardPersistId%3A" .. boardPersistId
        end
    end

	local textBox = Instance.new("TextBox")
	textBox.Name = "TextBox"
	textBox.BackgroundColor3 = Color3.new(0,0,0)
	textBox.BackgroundTransparency = 0.3
	textBox.Size = UDim2.new(0,displayWidth,0,200)
	textBox.Position = UDim2.new(0.5,-0.5 * displayWidth,0.5,-100)
	textBox.TextColor3 = Color3.new(1,1,1)
	textBox.TextSize = 20
	textBox.Text = dataString
	textBox.TextWrapped = true
	textBox.TextEditable = false
	textBox.ClearTextOnFocus = false

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0,10)
	padding.PaddingTop = UDim.new(0,10)
	padding.PaddingRight = UDim.new(0,10)
	padding.PaddingLeft = UDim.new(0,10)
	padding.Parent = textBox

	textBox.Parent = screenGui

	screenGui.Parent = localPlayer.PlayerGui
end

function PocketMenu:_showBoardToAI(board: metaboard.BoardClient)
	local remoteEvent = ReplicatedStorage.OS.Remotes.ShowToAI
	remoteEvent:FireServer(board:GetPart())
end

function PocketMenu:_startDecalEntryDisplay(board)
    local remoteEvent = ReplicatedStorage.OS.Remotes.AddDecalToBoard

    local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BoardDecalDisplay"
	
	local displayWidth = 500

	local textBox = Instance.new("TextBox")
	textBox.Name = "TextBox"
	textBox.BackgroundColor3 = Color3.new(0,0,0)
	textBox.BackgroundTransparency = 0.3
	textBox.Size = UDim2.new(0,displayWidth,0,100)
	textBox.Position = UDim2.new(0.5,-0.5 * displayWidth,0.5,-100)
	textBox.TextColor3 = Color3.new(1,1,1)
	textBox.TextSize = 20
    textBox.Text = ""
    textBox.PlaceholderText = "Enter an asset ID"
	textBox.TextWrapped = true
	textBox.ClearTextOnFocus = false

	local decal = board:GetPart():FindFirstChild("BoardDecal")
	if decal ~= nil then 
		textBox.Text = decal.Texture
	end

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0,10)
	padding.PaddingTop = UDim.new(0,10)
	padding.PaddingRight = UDim.new(0,10)
	padding.PaddingLeft = UDim.new(0,10)
	padding.Parent = textBox

	textBox.Parent = screenGui

    -- Buttons
    local button = Instance.new("TextButton")
	button.Name = "OKButton"
	button.Size = UDim2.new(0,200,0,50)
	button.Position = UDim2.new(0.5,50,0.5,100)
	button.Parent = screenGui
	button.BackgroundColor3 = Color3.fromRGB(0,162,0)
	button.TextColor3 = Color3.new(1,1,1)
	button.TextSize = 25
	button.Text = "OK"
	button.Activated:Connect(function()
        self._modalGuiActive = false
		screenGui:Destroy()
        remoteEvent:FireServer(board:GetPart(), textBox.Text)
	end)
	Instance.new("UICorner").Parent = button

    button = Instance.new("TextButton")
	button.Name = "CancelButton"
	button.Size = UDim2.new(0,200,0,50)
	button.Position = UDim2.new(0.5,-250,0.5,100)
	button.Parent = screenGui
	button.BackgroundColor3 = Color3.fromRGB(148,148,148)
	button.TextColor3 = Color3.new(1,1,1)
	button.TextSize = 25
	button.Text = "Cancel"
	button.Activated:Connect(function()
        self._modalGuiActive = false
		screenGui:Destroy()
	end)
	Instance.new("UICorner").Parent = button

	screenGui.Parent = localPlayer.PlayerGui
    textBox:CaptureFocus()
end

function PocketMenu:SetPockets(pockets: {PocketData})
	self._pockets:set(pockets)
end

function PocketMenu:SetSchedule(schedule)
	self._schedule:set(schedule)
end

function PocketMenu:_renderSchedule()
	local ROW_HEIGHT = 40

	local row = function(rowProps)
		return UI.Div {
			Name = rowProps.PocketName,
			Size = UDim2.new(1,0,0, ROW_HEIGHT),
			LayoutOrder = rowProps.LayoutOrder,

			[Fusion.Children] = {
				UI.HLine {
					Position = UDim2.fromScale(0.5, 1),
					Size = UDim2.new(1,0,0,1),
					BackgroundColor3 = Color3.fromHex("F3F3F6"),
				},

				UI.TextLabel {
					Text = rowProps.Name,
					TextColor3 = Color3.fromHex("F3F3F6"),

					AnchorPoint = Vector2.new(0,0),
					Position = UDim2.fromScale(0,0),
					Size = UDim2.fromScale(.3, 1),

				},

				UI.VLine {
					Position = UDim2.fromScale(0.3, 0.5),
					Size = UDim2.new(0, 2, 0, 25),
	
					BackgroundColor3 = Color3.fromHex("A3A3A6"),
				},

				UI.TextLabel {
					Text = rowProps.PocketName,
					TextColor3 = Color3.fromHex("F3F3F6"),

					AnchorPoint = Vector2.new(0,0),
					Position = UDim2.fromScale(0.3,0),
					Size = UDim2.fromScale(.3, 1),

				},

				UI.VLine {
					Position = UDim2.fromScale(0.6, 0.5),
					Size = UDim2.new(0, 2, 0, 25),
	
					BackgroundColor3 = Color3.fromHex("A3A3A6"),
				},

				UI.TextButton {
					Name = "JoinButton",
					Text = "Join",
					TextColor3 = Color3.fromHex("F0F0F0"),
					TextSize = 14,
					FontFace = Font.fromId(11702779517, Enum.FontWeight.Bold),
					BackgroundColor3 = BrickColor.Green().Color,
					AnchorPoint = Vector2.new(0.5,0.5),
					Position = UDim2.fromScale(0.8,0.5),
					Size = UDim2.fromOffset(100, 25),

					BackgroundTransparency = rowProps.PocketName == "The Rising Sea" and 0.8 or 0,
					TextTransparency = rowProps.PocketName == "The Rising Sea" and 0.8 or 0,
					
					[Fusion.OnEvent "Activated"] = rowProps.PocketName ~= "The Rising Sea" and function()
						Remotes.Goto:FireServer(rowProps.PocketName)
					end or nil,
				},
			}
		}
	end

	return UI.Div {

		AnchorPoint = Vector2.new(0,0),
		Position = UDim2.new(0,100,0,0),
		Size = UDim2.new(1,-100,1,0),

		[Fusion.Children] = {
			Fusion.New "UIListLayout" {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0,0),
				FillDirection = Enum.FillDirection.Vertical,
			},

			Fusion.ForPairs(self._schedule, function(i, seminar)
				return i, row {
					Name = seminar.Name,
					PocketName = seminar.PocketName,
					LayoutOrder = i,
				}
			end, Fusion.cleanup)
		}
	}
end

function PocketMenu:render()

    local screenGui
    local wholeMenu
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
				elseif SubMenu:get() == "Seminars" then
					return self:_renderSchedule()
                elseif SubMenu:get() == "Boards" then
                    -- toad
                    return Fusion.New "ScrollingFrame" {
                        ScrollingEnabled = false,
                        AnchorPoint = Vector2.new(0,0),
                        Position = UDim2.new(0,100,0,0),
                        Size = UDim2.new(1,-100,1,0),
                        BackgroundTransparency = 1,

                        [Fusion.Children] = {
                            Fusion.New "UIListLayout" {
                                SortOrder = Enum.SortOrder.LayoutOrder,
                                VerticalAlignment = Enum.VerticalAlignment.Top,
                                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                                Padding = UDim.new(0,2),
                            },
        
                            UI.HighlightTextButton {
                                Size = UDim2.fromOffset(300,60),
                                Text = "Key for Board...",
                                TextSize = 20,
                                TextColors = {Color3.fromHex("F2F2F3"), Color3.fromHex("F2F2F3")},
                                BackgroundColors = {metauniLightBlue, Color3.fromHex("303036")},
                                Transparencies = {0,1},
                                Selected = Fusion.Computed(function()
                                    return false
                                end),
                                [Fusion.OnEvent "MouseButton1Down"] = function()
                                    self:_startBoardSelectMode("startDisplay","key")
                                    screenGui:Destroy()
                                end,
                            },
                            UI.HighlightTextButton {
                                Size = UDim2.fromOffset(300,60),
                                Text = "URL for Board...",
                                TextSize = 20,
                                TextColors = {Color3.fromHex("F2F2F3"), Color3.fromHex("F2F2F3")},
                                BackgroundColors = {metauniLightBlue, Color3.fromHex("303036")},
                                Transparencies = {0,1},
                                Selected = Fusion.Computed(function()
                                    return false
                                end),
                                [Fusion.OnEvent "MouseButton1Down"] = function()
                                    self:_startBoardSelectMode("startDisplay", "URL")
                                    screenGui:Destroy()
                                end,
                            },
                            UI.HighlightTextButton {
                                Size = UDim2.fromOffset(300,60),
                                Text = "Decal for Board...",
                                TextSize = 20,
                                TextColors = {Color3.fromHex("F2F2F3"), Color3.fromHex("F2F2F3")},
                                BackgroundColors = {metauniLightBlue, Color3.fromHex("303036")},
                                Transparencies = {0,1},
                                Selected = Fusion.Computed(function()
                                    return false
                                end),
                                [Fusion.OnEvent "MouseButton1Down"] = function()
                                    self:_startBoardSelectMode("startDecalEntryDisplay")
                                    screenGui:Destroy()
                                end,
                            },
                            UI.HighlightTextButton {
                                Size = UDim2.fromOffset(300,60),
                                Text = "Show to AI...",
                                TextSize = 20,
                                TextColors = {Color3.fromHex("F2F2F3"), Color3.fromHex("F2F2F3")},
                                BackgroundColors = {metauniLightBlue, Color3.fromHex("303036")},
                                Transparencies = {0,1},
                                Selected = Fusion.Computed(function()
                                    return false
                                end),
                                [Fusion.OnEvent "MouseButton1Down"] = function()
                                    self:_startBoardSelectMode("showToAI")
                                    screenGui:Destroy()
                                end,
                            },
                        }
                    }
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
							screenGui:Destroy()
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

	local observeScale = Rx.of(workspace):Pipe {
		Rxi.property("CurrentCamera"),
		Rxi.property("ViewportSize"),
		Rx.map(function(viewportSize: Vector2?)
			if not viewportSize or viewportSize.X == 1 or viewportSize.Y == 1 then
				return 1
			else
				return math.min(1, viewportSize.Y / 850)
			end
		end)
	}

	local Scale = Fusion.Value(0)

    screenGui = Fusion.New "ScreenGui" {
		Name = "PocketMenu",
		IgnoreGuiInset = true,
		[Fusion.Children] = {
			wholeMenu,
			Fusion.New "UIScale" {
				Scale = Scale,
				[Fusion.Cleanup] = observeScale:Subscribe(function(scale: number)
					Scale:set(scale)
				end)
			}
		},
	}

    return screenGui
end

return PocketMenu