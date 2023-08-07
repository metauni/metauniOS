local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local New = Fusion.New
local Value = Fusion.Value
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local Sift = require(ReplicatedStorage.Packages.Sift)

local function addOffset(udim: UDim2, x: number, y: number)
	return UDim2.new(udim.X.Scale, udim.X.Offset + x, udim.Y.Scale, udim.Y.Offset + y)
end

local function ImageButton(props)

	local isHovering = Value(false)
	local isHeldDown = Value(false)

	-- props overrides any of these default values
	local defaultProps = {

		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),

		BackgroundTransparency = 1,
	
		[OnEvent "MouseButton1Down"] = function()
			isHeldDown:set(true)
			if props[OnEvent "MouseButton1Down"] then
				props[OnEvent "MouseButton1Down"]()
			end
		end,
	
		[OnEvent "MouseButton1Up"] = function()
			isHeldDown:set(false)
			if props[OnEvent "MouseButton1Up"] then
				props[OnEvent "MouseButton1Up"]()
			end
		end,
	
		[OnEvent "MouseEnter"] = function()
			isHovering:set(true)
			if props[OnEvent "MouseEnter"] then
				props[OnEvent "MouseEnter"]()
			end
		end,
	
		[OnEvent "MouseLeave"] = function()
			isHovering:set(false)
			isHeldDown:set(false)
			if props[OnEvent "MouseLeave"] then
				props[OnEvent "MouseLeave"]()
			end
		end,
	}

	local size = props.Size or UDim2.fromScale(1,1)

	local overrideProps = {
		Size = Computed(function()
			if isHovering:get() and not isHeldDown:get() then
				return addOffset(size, 2, 2)
			else
				return size
			end
		end),
		[Children] = Sift.Dictionary.merge(props[Children], {
			["_UICorner"] = New "UICorner" {
				CornerRadius = props.CornerRadius or UDim.new(0,5)
			}
		}),
		CornerRadius = Sift.None,
	}

	local finalProps = Sift.Dictionary.merge(defaultProps, props, overrideProps)

	return New "ImageButton" (finalProps)
end

local function TextButton(props)

	local isHovering = Value(false)
	local isHeldDown = Value(false)

	-- props overrides any of these default values
	local defaultProps = {

		Name = props.Text,

		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
	
		[OnEvent "MouseButton1Down"] = function()
			isHeldDown:set(true)
			if props[OnEvent "MouseButton1Down"] then
				props[OnEvent "MouseButton1Down"]()
			end
		end,
	
		[OnEvent "MouseButton1Up"] = function()
			isHeldDown:set(false)
			if props[OnEvent "MouseButton1Up"] then
				props[OnEvent "MouseButton1Up"]()
			end
		end,
	
		[OnEvent "MouseEnter"] = function()
			isHovering:set(true)
			if props[OnEvent "MouseEnter"] then
				props[OnEvent "MouseEnter"]()
			end
		end,
	
		[OnEvent "MouseLeave"] = function()
			isHovering:set(false)
			isHeldDown:set(false)
			if props[OnEvent "MouseLeave"] then
				props[OnEvent "MouseLeave"]()
			end
		end,
	}

	local size = props.Size or UDim2.fromScale(1,1)

	local overrideProps = {
		Size = Computed(function()
			if isHovering:get() and not isHeldDown:get() then
				return addOffset(size, 2, 2)
			else
				return size
			end
		end),
		[Children] = Sift.Dictionary.merge(props[Children], {
			["_UICorner"] = New "UICorner" {
				CornerRadius = props.CornerRadius or UDim.new(0,5)
			},
		}),
		CornerRadius = Sift.None,
	}

	local finalProps = Sift.Dictionary.merge(defaultProps, props, overrideProps)

	return New "TextButton" (finalProps)
end

local function Div(props)
	local defaultProps = {
		Name = "Div",
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromScale(1,1),

		BackgroundTransparency = 1,
	}

	local finalProps = Sift.Dictionary.merge(defaultProps, props)

	return New "Frame" (finalProps)
end

-- Makes it visible for positioning & sizing
local function _Div(props)
	local BorderColor = Fusion.Value(Color3.new(0,0,0))
	
	props.BackgroundColor3 = Color3.new(1,0,0)
	props.BackgroundTransparency = 0.5
	props.BorderSizePixel = 1
	props.BorderColor3 = BorderColor

	props[Fusion.Cleanup] = {
		game:GetService("RunService").RenderStepped:Connect(function()
			local t = 0.5 * (math.sin(10 * os.clock()) + 1)
			BorderColor:set(Color3.new(t,t,t))
		end),
		props[Fusion.Cleanup],
	}
	return Div(props)
end

local function Padding(props)
	return Fusion.New "UIPadding" {
		PaddingBottom = UDim.new(0, props.Bottom or props.Offset or 0),
		PaddingTop = UDim.new(0, props.Top or props.Offset or 0),
		PaddingLeft = UDim.new(0, props.Left or props.Offset or 0),
		PaddingRight = UDim.new(0, props.Left or props.Offset or 0),
	}
end

local function VLine(props)

	local defaultProps = {
		Name = "VLine",
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.new(0,1 or props.Thickness,1,0),
	}

	local removeProps = {
		Thickness = Sift.None,
	}

	return Fusion.New "Frame" (Sift.Dictionary.merge(defaultProps, props, removeProps))
end

local function HLine(props)

	local defaultProps = {
		Name = "VLine",
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.new(1,0,0,1 or props.Thickness),
	}

	local removeProps = {
		Thickness = Sift.None,
	}

	return Fusion.New "Frame" (Sift.Dictionary.merge(defaultProps, props, removeProps))
end

local function RoundedFrame(props)
	
	local defaultProps = {
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromScale(1,1),
	}

	local finalProps = (Sift.Dictionary.merge(defaultProps, props, {
		[Children] = Sift.Dictionary.merge(props[Children], {
			UICorner = New "UICorner" {
				CornerRadius = props.CornerRadius or UDim.new(0,5)
			}
		}),
		CornerRadius = Sift.None,
	}))

	return New "Frame" (finalProps)
end

local function TextLabel(props)
	
	local defaultProps = {
		Name = props.Text,
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromScale(1,1),

		BackgroundTransparency = 1,
	}

	local finalProps = (Sift.Dictionary.merge(defaultProps, props, {
		[Children] = Sift.Dictionary.merge(props[Children], {
			UICorner = New "UICorner" {
				CornerRadius = props.CornerRadius or UDim.new(0,5)
			}
		}),
		CornerRadius = Sift.None,
	}))

	return New "TextLabel" (finalProps)
end

local function ImageLabel(props)
	
	local defaultProps = {
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromScale(1,1),

		BackgroundTransparency = 1,
	}

	local finalProps = Sift.Dictionary.merge(defaultProps, props)

	return New "ImageLabel" (finalProps)
end

local function HighlightTextButton(props)

	local Selected = props.Selected
	local TextColors = props.TextColors or {Color3.fromHex("F2F2F3"), Color3.fromHex("060607")}
	props.TextColors = nil
	local BackgroundColors = props.BackgroundColors or {Color3.fromHex("060607"), Color3.fromHex("F2F2F3")}
	props.BackgroundColors = nil
	local Transparencies = props.Transparencies or {0,0}
	props.Transparencies = nil
	local isHovering = Value(false)
	
	local isHoveringOrSelected = Computed(function()
		return isHovering:get() or Selected:get()
	end)

	-- props overrides any of these default values
	local defaultProps = {

		Name = props.Text,

		TextColor3 = Computed(function()
			if isHoveringOrSelected:get() then
				return TextColors[1]
			else
				return TextColors[2]
			end
		end),

		BackgroundColor3 = Computed(function()
			if isHoveringOrSelected:get() then
				return BackgroundColors[1]
			else
				return BackgroundColors[2]
			end
		end),

		BackgroundTransparency = Computed(function()
			if isHoveringOrSelected:get() then
				return Transparencies[1]
			else
				return Transparencies[2]
			end
		end),

		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
	
		[OnEvent "MouseEnter"] = function()
			isHovering:set(true)
			if props[OnEvent "MouseEnter"] then
				props[OnEvent "MouseEnter"]()
			end
		end,
	
		[OnEvent "MouseLeave"] = function()
			isHovering:set(false)
			if props[OnEvent "MouseLeave"] then
				props[OnEvent "MouseLeave"]()
			end
		end,
	}

	-- Temp - this is just from the toolbox. Use something else!
	local clickSound: Sound
	clickSound = Fusion.New "Sound" {
		SoundId = "rbxassetid://876939830",
		Volume = 0.2,

		[Fusion.Cleanup] = Fusion.Observer(isHoveringOrSelected):onChange(function()
			clickSound.TimePosition = 0.03
			clickSound:Play()
		end),
	} :: Sound

	local finalProps = Sift.Dictionary.merge(defaultProps, props, {
		[Children] = Sift.Dictionary.merge(props[Children], {
			_ClickSound = clickSound
		}),
	})

	return New "TextButton" (finalProps)
end

local function X(props)
	assert(props.Color, "X component missing .Color")
	props[Fusion.Children] = {
		Div {
			Size = UDim2.new(1,0, 0, 2),
			BackgroundTransparency = 0,
			BackgroundColor3 = props.Color,
			Rotation = 45,
		},
		Div {
			Size = UDim2.new(1,0, 0, 2),
			BackgroundTransparency = 0,
			BackgroundColor3 = props.Color,
			Rotation = -45,
		},
	}

	props.Color = nil

	return Div(props)
end

return {
	ImageButton = ImageButton,
	Button = TextButton,
	TextButton = TextButton,
	RoundedFrame = RoundedFrame,
	TextLabel = TextLabel,
	ImageLabel = ImageLabel,
	Div = Div,
	HighlightTextButton = HighlightTextButton,
	Padding = Padding,
	X = X,

	VLine = VLine,
	HLine = HLine,

	_Div = _Div,
	_ = _Div {},
}