local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local UI = require(ReplicatedStorage.OS.UI)

return function(props)
	return UI.RoundedFrame {
		Size = UDim2.fromOffset(200, 300),

		BackgroundColor3 = Color3.fromHex("3A3A3A"),

		[Fusion.Children] = {
			
			UI.TextLabel {
				Name = "PocketName",
				Text = props.PocketName,
				TextColor3 = Color3.fromHex("F0F0F0"),
				TextSize = 30,
				FontFace = Font.fromName("Merriweather", Enum.FontWeight.Bold),
				Size = UDim2.new(0.9, 0, 0, 50),
				AnchorPoint = Vector2.new(0.5,0),
				Position = UDim2.fromScale(0.5, 0),
			},
			
			UI.ImageLabel {
				Name = "PocketImage",
				Image = props.PocketImage,
				BackgroundTransparency = 0,
				AnchorPoint = Vector2.new(0.5,0),
				Position = UDim2.new(0.5, 0, 0, 50),
				Size = UDim2.fromOffset(200, 150),
			},
			
			UI.TextLabel {
				Name = "ActiveUsers",
				Text = props.NumActive.." joined",
				TextColor3 = Color3.fromHex("F0F0F0"),
				TextSize = 20,
				FontFace = Font.fromId(11702779517, Enum.FontWeight.Bold),
				AnchorPoint = Vector2.new(0.5,0),
				Position = UDim2.new(0.5,0,0,200),
				Size = UDim2.new(0.9,0,0,50),
			},
			
			UI.TextButton {
				Name = "PlayButton",
				Text = "Join",
				TextColor3 = Color3.fromHex("F0F0F0"),
				TextSize = 20,
				FontFace = Font.fromId(11702779517, Enum.FontWeight.Bold),
				BackgroundColor3 = BrickColor.Green().Color,
				AnchorPoint = Vector2.new(0.5,0),
				Position = UDim2.new(0.5,0,0,250),
				Size = UDim2.new(0.9,0,0,40),

				[Fusion.OnEvent "Activated"] = props.OnClickJoin,
			},
		}
	}
end