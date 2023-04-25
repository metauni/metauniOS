local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local New = Fusion.New
local Value = Fusion.Value
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Children = Fusion.Children
local Tween = Fusion.Tween

local UI = require(script.Parent.UI)
local EmojiList = require(script.Parent.EmojiList)

return function(props)

	-- local ActiveMenu = Value(nil)
	local ActiveMenu = Value(nil)

	local controlsMenu = UI.RoundedFrame {

		Visible = Computed(function()
			return ActiveMenu:get() == "Controls"
		end),

		AnchorPoint = Vector2.new(0,0.5),
		Position = UDim2.new(0,130,0.5,0),
		Size = UDim2.fromOffset(200,140),

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
				Size = UDim2.new(0,100,0,140),

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
										return BrickColor.new("Flame reddish orange").Color
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
				}
			}
		}
	}

	local FlyingEmojis = Value({})

	local function deployLocalEmoji(name: string)
		local Position = Value(UDim2.new(0.5,math.random(-20,20),0.5,0))
		local Transparency = Value(0)

		local tweenInfo = TweenInfo.new(
				1.4, -- Time
				Enum.EasingStyle.Linear, -- EasingStyle
				Enum.EasingDirection.Out, -- EasingDirection
				0, -- RepeatCount (when less than zero the tween will loop indefinitely)
				false, -- Reverses (tween will reverse once reaching it's goal)
				0 -- DelayTime
		)

		local flying = FlyingEmojis:get()
		table.insert(flying, UI.TextLabel {
			Text = EmojiList[name],
			Size = UDim2.fromOffset(50,50),
			TextScaled = true,
			Position = Tween(Position, tweenInfo),
			TextTransparency = Tween(Transparency, tweenInfo)
		})

		Position:set(UDim2.new(0.5, 0, 0.5, -800))
		Transparency:set(1)

		FlyingEmojis:set(flying)

		task.delay(1.4, function()
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
	
			AnchorPoint = Vector2.new(0,0.5),
			Position = UDim2.new(0,130,0.5,0),
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
				
				UI.TextLabel {
					AnchorPoint = Vector2.new(0,0.5),
					Position = UDim2.new(0,40, 0.5, 0),
					Size = UDim2.fromOffset(80,40),
					
					TextColor3 = BrickColor.new("Phosph. White").Color,
					TextStrokeTransparency = 0,
					Text = `<b>{buttonProps.Text}</b>`,
					RichText = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = Enum.Font.SciFi,
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
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.new(0, 60, 1, -60),
		Size = UDim2.fromOffset(130, 130),

		BackgroundTransparency = 1,

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
				Size = UDim2.fromScale(0.84,0.84),
				
				Visible = props.OrbcamActive,
				
				BackgroundColor3 = Color3.new(0,0,0),
				BackgroundTransparency = 1,
				
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.5,0),
					},
					New "UIStroke" {
						Thickness = 10,
						Transparency = 0.2,
					}
				}
			}, 
			
			New "Frame" {
				Name = "WhiteRing",
				AnchorPoint = Vector2.new(0.5,0.5),
				Position = UDim2.fromScale(0.5,0.5),
				Size = UDim2.fromScale(0.65,0.65),

				ZIndex = 2,

				BackgroundColor3 = Color3.new(1,1,1),
				BackgroundTransparency = 1,
				
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.5,0),
					},
					New "UIStroke" {
						Thickness = 10,
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
						Material = Enum.Material.CrackedLava,
						BrickColor = BrickColor.new("CGA brown"),
						Shape = Enum.PartType.Ball,
						Size = Vector3.new(3,3,3),
						Position = Vector3.new(0,0,0),
					},
	
					UI.ImageLabel {
						Position = UDim2.new(0.5,0,0.5,-10),
						Size = UDim2.fromOffset(35,35),
	
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
						Position = UDim2.new(0.5,0,0.5,15),
						Size = UDim2.fromOffset(50,50),
	
						Text = `<b>Orbcam</b>`,
						RichText = true,
						TextStrokeTransparency = 0,
						TextColor3 = Color3.fromHex("#F0F0F0"),
						Font = Enum.Font.SciFi,
						TextSize = 14,
					}
				}
			},

		}
	}

	local macros = {
		{
			Keys = {Enum.KeyCode.LeftShift, Enum.KeyCode.C},
			Callback = function()
				props.SetOrbcamActive(not props.OrbcamActive:get())
			end,
		},
		{
			Keys = {Enum.KeyCode.LeftShift, Enum.KeyCode.E},
			Callback = function()
				ActiveMenu:set("Emoji")
			end,
		},
	}

	return UI.Div {

		Parent = props.Parent,

		[Fusion.Cleanup] = {
			-- Detect macro key presses and fire callback
			UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
				if gameProcessedEvent or input.KeyCode == nil then
					return
				end

				for _, macro in ipairs(macros) do
					if macro.Keys[#macro.Keys] == input.KeyCode then
						local allHeld = true
						for _, key in macro.Keys do
							if not UserInputService:IsKeyDown(key) then
								allHeld = false
							end
						end
						if allHeld then
							macro.Callback()
						end
					end
				end
				
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
				Position = UDim2.fromOffset(115,30),
				Size = UDim2.fromOffset(30,30)
			},

			controlsMenu,
			emojiMenu,

			UI.Div {
				AnchorPoint = Vector2.new(0,0.5),
				Position = UDim2.new(0, 140,0.5,0),
				Size = UDim2.fromOffset(120,140),

				Visible = Computed(function()
					return ActiveMenu:get() == nil
				end),

				[Children] = {
					New "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Bottom,
						Padding = UDim.new(0, 0),
					},
					Computed(function()
						if props.IsSpeaker:get() then
							return 
								menuButton {
									Text = "Controls",
									Image = "rbxassetid://13195262593",
									LayoutOrder = 1,
									BackgroundTransparency = 0.8,
									OnClick = function()
										ActiveMenu:set("Controls")
									end,
								}
						end
					end, Fusion.cleanup),
					menuButton {
						Text = "Emoji",
						Image = "rbxassetid://13193313621",
						LayoutOrder = 2,
						BackgroundTransparency = 0.8,
						OnClick = function()
							ActiveMenu:set("Emoji")
						end,
					},
					Computed(function()
						if not props.IsSpeaker:get() then
							return 
								menuButton {
									Text = "Teleport",
									Image = "rbxassetid://11877012097",
									LayoutOrder = 3,
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