local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local New = Fusion.New
local Value = Fusion.Value
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Children = Fusion.Children
local Tween = Fusion.Tween

local UI = require(ReplicatedStorage.OS.UI)
local EmojiList = require(script.Parent.EmojiList)
local Macro = require(ReplicatedStorage.Util.Macro)

return function(props)

	local ActiveMenu = Value(nil)

	local controlsMenu = UI.RoundedFrame {

		Visible = Computed(function()
			return ActiveMenu:get() == "Controls"
		end),

		AnchorPoint = Vector2.new(0,1),
		Position = UDim2.new(0,150,1,0),
		Size = UDim2.fromOffset(200,180),

		BackgroundColor3 = BrickColor.new("Gray").Color,
		BackgroundTransparency = 0.6,

		[Children] = {

			UI.ImageButton {
				Image = "rbxassetid://13193094571",
				Position = UDim2.new(1, -15, 0, 15),
				Size = UDim2.fromOffset(25,25),
				[OnEvent "Activated"] = function()
					ActiveMenu:set(nil)
				end,
			},

			New "Frame" {
				BackgroundTransparency = 1,

				AnchorPoint = Vector2.new(0,0),
				Position = UDim2.fromOffset(10,0),
				Size = UDim2.new(0,100,1,0),

				[Children] = {

					New "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0, 5),
					},
		
					UI.Div {
						Size = UDim2.fromOffset(100, 35),
						LayoutOrder = 1,
						[Children] = {
							UI.TextButton {
								Size = UDim2.fromScale(1,1),
								Text = "Single Board",
								Font = Enum.Font.SciFi,
								BackgroundColor3 = Computed(function()
									if props.ViewMode:get() == "single" then
										return BrickColor.new("Flame reddish orange").Color
									else
										return BrickColor.new("Phosph. White").Color
									end
								end),
								[OnEvent "Activated"] = function()
									props.SetViewMode("single")
								end,
							},
							UI.TextLabel {
								Size = UDim2.fromOffset(30, 25),
								Position = UDim2.new(1, 40, 0.5, 0),
								BackgroundColor3 = BrickColor.new("Really black").Color,
								BackgroundTransparency = 0,

								Text = "<b>1</b>",
								RichText = true,
								TextScaled = true,
								Font = Enum.Font.SourceSans,
								TextColor3 = BrickColor.new("Phosph. White").Color,
							},
						},
					},
					UI.Div {
						Size = UDim2.fromOffset(100, 35),
						LayoutOrder = 2,
						[Children] = {
							UI.TextButton {
								Size = UDim2.fromScale(1,1),
								Text = "Double Board",
								Font = Enum.Font.SciFi,
								BackgroundColor3 = Computed(function()
									if props.ViewMode:get() == "double" then
										return BrickColor.new("Flame reddish orange").Color
									else
										return BrickColor.new("Phosph. White").Color
									end
								end),
								[OnEvent "Activated"] = function()
									props.SetViewMode("double")
								end,
							},
							UI.TextLabel {
								Size = UDim2.fromOffset(30, 25),
								Position = UDim2.new(1, 25, 0.5, 0),
								BackgroundColor3 = BrickColor.new("Really black").Color,
								BackgroundTransparency = 0,

								Text = "<b>1</b>",
								RichText = true,
								TextScaled = true,
								Font = Enum.Font.SourceSans,
								TextColor3 = BrickColor.new("Phosph. White").Color,
							},
							UI.TextLabel {
								Size = UDim2.fromOffset(30, 25),
								Position = UDim2.new(1, 60, 0.5, 0),
								BackgroundColor3 = BrickColor.new("Really black").Color,
								BackgroundTransparency = 0,

								Text = "<b>2</b>",
								RichText = true,
								TextScaled = true,
								Font = Enum.Font.SourceSans,
								TextColor3 = BrickColor.new("Phosph. White").Color,
							},
						},
					},
					UI.Div {
						Size = UDim2.fromOffset(100, 35),
						LayoutOrder = 3,
						[Children] = {
							UI.TextButton {
								Size = UDim2.fromScale(1,1),
								Text = "Audience",
								Font = Enum.Font.SciFi,
								BackgroundColor3 = Computed(function()
									if props.Audience:get() then
										return BrickColor.new("Bright blue").Color
									else
										return BrickColor.new("Phosph. White").Color
									end
								end),
								[OnEvent "Activated"] = function()
									props.SetAudience(not props.Audience:get())
								end,
							},
							UI.RoundedFrame {
								Size = UDim2.fromOffset(30, 30),
								Position = UDim2.new(1, 40, 0.5, 0),
								BackgroundColor3 = BrickColor.new("Really black").Color,
								BackgroundTransparency = 0,
								[Children] = {
									UI.ImageLabel {
										Size = UDim2.fromOffset(25, 25),
		
										Image = "rbxassetid://13195959348",
									},
								}
							}
						},
					},
					UI.Div {
						Size = UDim2.fromOffset(100, 35),
						LayoutOrder = 4,
						[Children] = {
							UI.TextButton {
								Size = UDim2.fromScale(1,1),
								Text = "Boards Only",
								Font = Enum.Font.SciFi,
								BackgroundColor3 = Computed(function()
									if props.WaypointOnly:get() then
										return BrickColor.new("Bright blue").Color
									else
										return BrickColor.new("Phosph. White").Color
									end
								end),
								[OnEvent "Activated"] = function()
									props.SetWaypointOnly(not props.WaypointOnly:get())
								end,
							},
						},
					},
				}
			}
		}
	}

	local OrbAbsPos = Value(Vector2.new(0,0))
	local FlyingEmojis = Value({})

	local function deployLocalEmoji(name: string)
		local Position = Value(UDim2.new(0.5,math.random(-20,20),0.5,0))
		local Transparency = Value(0)

		local lifetime = 2

		local flying = FlyingEmojis:get()
		table.insert(flying, UI.TextLabel {
			Text = EmojiList[name],
			Size = UDim2.fromOffset(50,50),
			TextScaled = true,
			Position = Tween(Position, TweenInfo.new(
				lifetime, -- Time
				Enum.EasingStyle.Linear, -- EasingStyle
				Enum.EasingDirection.In, -- EasingDirection
				0, -- RepeatCount (when less than zero the tween will loop indefinitely)
				false, -- Reverses (tween will reverse once reaching it's goal)
				0 -- DelayTime
			)),
			TextTransparency = Tween(Transparency, TweenInfo.new(
				lifetime, -- Time
				Enum.EasingStyle.Exponential, -- EasingStyle
				Enum.EasingDirection.In, -- EasingDirection
				0, -- RepeatCount (when less than zero the tween will loop indefinitely)
				false, -- Reverses (tween will reverse once reaching it's goal)
				0 -- DelayTime
			))
		})

		Position:set(UDim2.new(0.5, 0, 0.5, -OrbAbsPos:get().Y - 130/2 + 150))
		Transparency:set(1)

		FlyingEmojis:set(flying)

		task.delay(lifetime, function()
			local item = flying[1]
			if item then
				item:Destroy()
				table.remove(flying, 1)
				FlyingEmojis:set(flying)
			end
		end)
	end

	local emojiMenu do
	
		local availableEmojis = {
			":thumbsup:",
			":thumbsdown:",
			":smiley:",
			":grimacing:",
			":mind_blown:",
			":pray:",
			":fire:",
			":ok_hand:",
			":100:",
			":repeat:",
			":question:",
			":sob:",
			":laughing:",
			":rage:",
			":eyes:",
			":facepalm:",
		}

		emojiMenu =
		 UI.RoundedFrame {
			Visible = Computed(function()
				return ActiveMenu:get() == "Emoji"
			end),
	
			AnchorPoint = Vector2.new(0,1),
			Position = UDim2.new(0,150,1,0),
			Size = UDim2.fromOffset(170,140),
	
			BackgroundColor3 = BrickColor.new("Gray").Color,
			BackgroundTransparency = 0.6,

			[Fusion.Cleanup] =
				if props.ReceiveEmojiSignal then
					props.ReceiveEmojiSignal:Connect(function(emojiName: string)
						deployLocalEmoji(emojiName)
					end)
				else nil,

			[Children] = {
				UI.ImageButton {
					Name = "Close",
					Image = "rbxassetid://13193094571",
					[OnEvent "Activated"] = function()
						ActiveMenu:set(nil)
					end,
					Position = UDim2.new(1, -15, 0, 15),
					Size = UDim2.fromOffset(25,25)
				},

				UI.Div {
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.new(1,-40,1,-10),
				Position = UDim2.new(0, 10, 0.5, 0),
				[Children] = {
					
					New "UIGridLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						CellSize = UDim2.fromOffset(25,25),
						CellPadding = UDim2.fromOffset(10,10),
					},

					Fusion.ForPairs(availableEmojis, function(i, name)
						return i, UI.Div {
							[Children] = UI.TextButton {
								LayoutOrder = i,
								Text = EmojiList[name],
								BackgroundTransparency = 0.6,
								TextSize = 20,
		
								[OnEvent "Activated"] = function()
									deployLocalEmoji(name)
									props.SendEmoji(name)
								end
							}
						}
					end, Fusion.cleanup),
				}
			},
			},
		 }
	end


	local function menuButton(buttonProps)
		
		return UI.Div {
			Size = UDim2.fromOffset(120,40),
			LayoutOrder = buttonProps.LayoutOrder,
			
			[Children] = {
				
				UI.TextButton {
					AnchorPoint = Vector2.new(0,0.5),
					Position = UDim2.new(0,40, 0.5, 0),
					Size = UDim2.fromOffset(80,40),
					BackgroundTransparency = 1,
					
					TextColor3 = BrickColor.new("Phosph. White").Color,
					Text = `<b>{buttonProps.Text}</b>`,
					RichText = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = Enum.Font.SciFi,

					Visible = Computed(function()
						return ActiveMenu:get() == nil
					end),

					[OnEvent "Activated"] = buttonProps.OnClick,
				},
	
				UI.Div {
					AnchorPoint = Vector2.new(0,0.5),
					Position = UDim2.fromScale(0,0.5),
					Size = UDim2.fromOffset(30,30),

					[Children] = {
	
						UI.ImageButton {
							Image = buttonProps.Image,
							BackgroundTransparency = 0.8,
							Size = UDim2.fromOffset(30, 30),
							[OnEvent "Activated"] = buttonProps.OnClick,
						}
					}
				}
	
			}
		}
	end

	local Cam = Value()
	
	local orbcamButton =  New "TextButton" {
		AnchorPoint = Vector2.new(0,1),
		Position = UDim2.new(0, 0, 1, 0),
		-- Size = UDim2.fromOffset(130, 130),
		Size = UDim2.fromOffset(90, 90),

		BackgroundTransparency = 1,

		[Fusion.Out "AbsolutePosition"] = OrbAbsPos,

		[OnEvent "Activated"] = function()
			ActiveMenu:set(nil)
			props.SetOrbcamActive(not props.OrbcamActive:get())
		end,

		[Children] = {

			UI.Div {
				[Children] = FlyingEmojis,
			},

			New "UICorner" {
				CornerRadius = UDim.new(0.5,0)
			},
			
			New "Frame" {
				Name = "BlackRing",
				AnchorPoint = Vector2.new(0.5,0.5),
				Position = UDim2.fromScale(0.5,0.5),
				Size = UDim2.fromOffset(76,76),
				
				Visible = props.OrbcamActive,
				
				BackgroundColor3 = Color3.new(0,0,0),
				BackgroundTransparency = 1,
				
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.5,0),
					},
					New "UIStroke" {
						Thickness = 7,
						Transparency = 0.2,
					}
				}
			}, 
			
			New "Frame" {
				Name = "WhiteRing",
				AnchorPoint = Vector2.new(0.5,0.5),
				Position = UDim2.fromScale(0.5,0.5),
				Size = UDim2.fromOffset(58,58),

				ZIndex = 2,

				BackgroundColor3 = Color3.new(1,1,1),
				BackgroundTransparency = 1,
				
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.5,0),
					},
					New "UIStroke" {
						Thickness = 7,
						Color = Color3.new(1,1,1),
						Transparency = 0.2,
					}
				}
			},

			New "Frame" {
				Name = "AntiAlias",
				AnchorPoint = Vector2.new(0.5,0.5),
				Position = UDim2.fromScale(0.5,0.5),
				Size = UDim2.fromScale(0.577,0.577),

				ZIndex = 2,

				BackgroundColor3 = Color3.new(0.2, 0.184313, 0.176470),
				BackgroundTransparency = 0,
				
				[Children] = New "UICorner" {
					CornerRadius = UDim.new(0.5,0)
				},
			},
			
			New "ViewportFrame" {
				Name = "Orb",
				AnchorPoint = Vector2.new(0.5,0.5),
				Position = UDim2.fromScale(0.5,0.5),
				Size = UDim2.fromScale(1,1),

				ZIndex = 3,

				CurrentCamera = Cam,
				LayoutOrder = 1,
				BackgroundTransparency = 1,
				Ambient = Color3.new(0.6,0.6,0.6),
				LightDirection = Vector3.new(-1,0,0),
	
				[Children] = {
	
					New "Camera" {
						CFrame = CFrame.lookAt(Vector3.xAxis * 4, Vector3.new(0,0,0)),
						[Fusion.Ref] = Cam,
					},
	
					New "Part" {
						Material = props.OrbMaterial,
						BrickColor = props.OrbBrickColor,
						Shape = Enum.PartType.Ball,
						Size = Vector3.new(3,3,3),
						Position = Vector3.new(0,0,0),
					},
	
					UI.ImageLabel {
						Position = UDim2.new(0.5,0,0.5,-8),
						Size = UDim2.fromOffset(25,25),
	
						Image = "rbxassetid://13185764466",
						ImageTransparency = Computed(function()
							if props.OrbcamActive:get() then
								return 0
							else
								return 0.4
							end
						end),
						ImageColor3 = Computed(function()
							if props.OrbcamActive:get() then
								return BrickColor.new("Crimson").Color
							else
								return BrickColor.White().Color
							end
						end),
					},
					UI.TextLabel {
						Name = "Orbcam",
						Position = UDim2.new(0.5,0,0.5,8),
						Size = UDim2.fromOffset(50,50),
	
						Text = "Orbcam",
						RichText = true,
						TextStrokeTransparency = 0,
						TextColor3 = Color3.fromHex("#F0F0F0"),
						FontFace = Font.fromId(11702779517, Enum.FontWeight.Bold),
						TextSize = 12,
					}
				}
			},

		}
	}

	return UI.Div {

		[Fusion.Cleanup] = {
			Macro.new(Enum.KeyCode.LeftShift, Enum.KeyCode.E):Connect(function()
				ActiveMenu:set("Emoji")
			end),
		},

		[Children] = {
			orbcamButton,

			UI.ImageButton {
				Name = "Close",
				Image = "rbxassetid://13193094571",
				[OnEvent "Activated"] = function()
					props.Detach()
					ActiveMenu:set(nil)
				end,
				Position = UDim2.fromOffset(90,35),
				Size = UDim2.fromOffset(30,30)
			},

			controlsMenu,
			emojiMenu,

			UI.Div {
				AnchorPoint = Vector2.new(0,1),
				Position = UDim2.new(0, 110,1,0),
				Size = UDim2.fromOffset(120,140),

				[Children] = {
					New "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Bottom,
						Padding = UDim.new(0, 0),
					},
					Computed(function()
						-- TODO: Get appropriate permissions for replay menu
						if Players.LocalPlayer.UserId == 2293079954 or Players.LocalPlayer.UserId == 2211421151 and props.IsSpeaker:get() then
							return 
								menuButton {
									Text = "Replay",
									Image = "rbxassetid://8215093320",
									LayoutOrder = 1,
									BackgroundTransparency = 0.8,
									OnClick = function()
										ActiveMenu:set(nil)
										props.OnClickReplayMenu()
									end,
								}
						end
					end, Fusion.cleanup),
					Computed(function()
						if props.IsSpeaker:get() then
							return 
								menuButton {
									Text = "Controls",
									Image = "rbxassetid://13195262593",
									LayoutOrder = 2,
									BackgroundTransparency = 0.8,
									OnClick = function()
										if ActiveMenu:get() == "Controls" then
											ActiveMenu:set(nil)
										else
											ActiveMenu:set("Controls")
										end
									end,
								}
						end
					end, Fusion.cleanup),
					menuButton {
						Text = "Emoji",
						Image = "rbxassetid://13193313621",
						LayoutOrder = 3,
						BackgroundTransparency = 0.8,
						OnClick = function()
							if ActiveMenu:get() == "Emoji" then
								ActiveMenu:set(nil)
							else
								ActiveMenu:set("Emoji")
							end
						end,
					},
					Computed(function()
						if not props.IsSpeaker:get() then
							return 
								menuButton {
									Text = "Teleport",
									Image = "rbxassetid://11877012097",
									LayoutOrder = 4,
									BackgroundTransparency = 0.8,
									OnClick = function()
										props.Teleport()
									end,
								}
						end
					end, Fusion.cleanup),
				}
			}
		},
	}
end