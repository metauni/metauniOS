local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)

local UI = {}

local function addRoundedCorner(props)
	if props.CornerRadius == 0 then
		return props
	end
	return Sift.Dictionary.merge(props, {
		[Blend.Children] = Sift.Array.concat(props[Blend.Children], {
			Blend.New "UICorner" {
				CornerRadius = props.CornerRadius or UDim.new(0,5)
			}
		}),
		CornerRadius = Sift.None,
	})
end

local function addChildren(props, children)
	return Sift.Dictionary.merge(props, {
		[Blend.Children] = Sift.Array.concat(props[Blend.Children], children),
	})
end

function UI.Div(props)
	local defaultProps = {
		Name = "Div",
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromScale(1,1),

		BackgroundTransparency = 1,
	}

	return Blend.New "Frame" (Sift.Dictionary.merge(defaultProps, props))
end

-- Makes it visible for positioning & sizing
function UI._Div(props)
	local maid = Maid.new()
	local BorderColor = Blend.State(Color3.new(0,0,0))
	maid:GiveTask(BorderColor)
	
	props = Sift.Dictionary.merge({
		BackgroundColor3 = Color3.new(1,0,0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 1,
		BorderColor3 = BorderColor,

		[Blend.Attached(function()
			maid:GiveTask(game:GetService("RunService").RenderStepped:Connect(function()
				local t = 0.5 * (math.sin(10 * os.clock()) + 1)
				BorderColor.Value = Color3.new(t,t,t)
			end))
			return maid
		end)] = true
	}, props)

	return UI.Div(props)
end

-- Alias for quickly locating current frame borders
UI._ = UI._Div {}

--[[
	Usage:
	```lua
	Padding { Offset = 5}
	Padding { Top = 5, Bottom = 10 }
	Padding { Top = 5, Bottom = 10, Left = 5, Right = 10}
	```
]]
function UI.Padding(props)
	return Blend.New "UIPadding" {
		PaddingBottom = UDim.new(0, props.Bottom or props.Offset or 0),
		PaddingTop = UDim.new(0, props.Top or props.Offset or 0),
		PaddingLeft = UDim.new(0, props.Left or props.Offset or 0),
		PaddingRight = UDim.new(0, props.Right or props.Offset or 0),
	}
end

function UI.VLine(props)

	local defaultProps = {
		Name = "VLine",
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.new(0,1 or props.Thickness,1,0),
	}

	local removeProps = {
		Thickness = Sift.None,
	}

	return Blend.New "Frame" (Sift.Dictionary.merge(defaultProps, props, removeProps))
end

function UI.HLine(props)

	local defaultProps = {
		Name = "HLine",
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.new(1,0,0,1 or props.Thickness),
	}

	local removeProps = {
		Thickness = Sift.None,
	}

	return Blend.New "Frame" (Sift.Dictionary.merge(defaultProps, props, removeProps))
end

function UI.RoundedFrame(props)
	
	local defaultProps = {
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromScale(1,1),
	}

	return Blend.New "Frame" (addRoundedCorner(Sift.Dictionary.merge(defaultProps, props)))
end

function UI.RoundedButton(props)
	
	local defaultProps = {
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromScale(1,1),
		Text = "",
	}

	return Blend.New "TextButton" (addRoundedCorner(Sift.Dictionary.merge(defaultProps, props)))
end

function UI.TextLabel(props)
	
	local defaultProps = {
		Name = props.Text,
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromScale(1,1),

		BackgroundTransparency = 1,
	}

	return Blend.New "TextLabel" (addRoundedCorner(Sift.Dictionary.merge(defaultProps, props)))
end

function UI.ImageLabel(props)
	
	local defaultProps = {
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromScale(1,1),

		BackgroundTransparency = 1,
	}

	return Blend.New "ImageLabel" (Sift.Dictionary.merge(defaultProps, props))
end

function UI.X(props)
	assert(props.Color, "X component missing .Color")
	props = addChildren(props,{
		UI.Div {
			Size = UDim2.new(1,0, 0, 2),
			BackgroundTransparency = 0,
			BackgroundColor3 = props.Color,
			Rotation = 45,
		},
		UI.Div {
			Size = UDim2.new(1,0, 0, 2),
			BackgroundTransparency = 0,
			BackgroundColor3 = props.Color,
			Rotation = -45,
		},
	})

	props = Sift.Dictionary.set(props, "Color", nil)

	return UI.Div(props)
end

return UI