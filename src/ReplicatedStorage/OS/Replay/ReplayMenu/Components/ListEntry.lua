local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(ReplicatedStorage.OS.UIBlend)
local Blend = require(ReplicatedStorage.Util.Blend)

type Replay = {
	ReplayName: string,
	ReplayId: string,
}

type Props = {
	OnPlay: () -> (),
	OnEdit: () -> (),
}

return function(i: number, replay: Replay, props: Props)

	return UI.Div {

		LayoutOrder = i,

		Size = UDim2.new(1,0,0,50),

		Blend.New "UIStroke" { Thickness = 1 },
		Blend.New "UIListLayout" {
			Padding = UDim.new(0, 0),
			FillDirection = Enum.FillDirection.Horizontal,
		},

		Blend.New "ImageButton" {
			BackgroundColor3 = BrickColor.Green().Color,
			Image = "rbxassetid://8215093320",
			Size = UDim2.fromOffset(50, 50),
			LayoutOrder = 1,

			[Blend.OnEvent "Activated"] = function()
				props.OnPlay()
			end,
		},

		Blend.New "TextButton" {
			BackgroundColor3 = BrickColor.Yellow().Color,
			Text = "Edit",
			Size = UDim2.fromOffset(50, 50),
			LayoutOrder = 1,

			[Blend.OnEvent "Activated"] = function()
				props.OnEdit()
			end,
		},

		Blend.New "TextButton" {
			Name = replay.ReplayName,
			Text = `{replay.ReplayName} (ID: {replay.ReplayId})`,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			
			Size = UDim2.new(1,-50, 1),
			AnchorPoint = Vector2.new(0,0),
			Position = UDim2.fromOffset(50,0),
			LayoutOrder = 2,

			UI.Padding { Left = 5, Right = 5 },
		},
	}
end
