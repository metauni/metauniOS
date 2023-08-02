local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local UI = require(ReplicatedStorage.OS.UI)

return function(props)
	return UI.RoundedFrame {
		Size = UDim2.fromOffset(150,130),

		BackgroundTransparency = 1,
		-- BackgroundColor3 = Color3.fromHex("3A3A3A"),

		[Fusion.Children] = {

			Fusion.New "UIStroke" {
				Color = Color3.fromHex("F3F3F4"),
				Thickness = 2,
			},
			
			UI.ImageLabel {
				Name = "PocketImage",
				Image = props.PocketImage,
				BackgroundTransparency = 0,
				AnchorPoint = Vector2.new(0.5,0),
				Position = UDim2.new(0.5, 0, 0, 0),
				Size = UDim2.fromOffset(150, 100),
				ZIndex = 0,

				[Fusion.Children] = {
					Fusion.New "UICorner" {
						CornerRadius = UDim.new(0,5),
					},

					UI.TextLabel {
						Name = "PocketName",
						Text = props.PocketName,
						TextColor3 = Color3.fromHex("F0F0F0"),
						TextSize = 24,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = Font.fromName("Merriweather", Enum.FontWeight.Bold),
						Size = UDim2.fromScale(0.92, 0.92),
						AnchorPoint = Vector2.new(0.5,0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						ZIndex = 1,

						TextWrap = true,
		
						[Fusion.Children] = {
							Fusion.New "UIStroke" {
								Thickness = 2,
								Transparency = 0.25,
							},
						}
					},
				}
			},

			UI.Div {
				AnchorPoint = Vector2.new(0.5,0),
				Position = UDim2.new(0.5,0,0,100),
				Size = UDim2.new(1,0,0,30),

				[Fusion.Children] = {

					UI.TextLabel {
						Name = "ActiveUsers",
						Text = "👥 "..props.ActiveUsers,
						TextColor3 = Color3.fromHex("F0F0F0"),
						TextSize = 14,
						FontFace = Font.fromId(11702779517, Enum.FontWeight.Bold),
						AnchorPoint = Vector2.new(0,0.5),
						Position = UDim2.new(0,0,0.5,0),
						Size = UDim2.new(0,30,1,0),

						-- [Fusion.Children] = {UI._},
					},
					
					UI.TextButton {
						Name = "JoinButton",
						Text = "Join",
						TextColor3 = Color3.fromHex("F0F0F0"),
						TextSize = 14,
						FontFace = Font.fromId(11702779517, Enum.FontWeight.Bold),
						BackgroundColor3 = BrickColor.Green().Color,
						AnchorPoint = Vector2.new(0,0.5),
						Position = UDim2.new(0,35,0.5,0),
						Size = UDim2.new(1,-40,0,20),
						
						[Fusion.OnEvent "Activated"] = props.OnClickJoin,
					},
				}
			},
			
		}
	}
end