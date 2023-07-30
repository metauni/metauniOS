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
			}
		}),
		CornerRadius = Sift.None,
	}

	local finalProps = Sift.Dictionary.merge(defaultProps, props, overrideProps)

	return New "TextButton" (finalProps)
end

local function Div(props)
	local defaultProps = {
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromScale(1,1),

		BackgroundTransparency = 1,
	}

	local finalProps = Sift.Dictionary.merge(defaultProps, props)

	return New "Frame" (finalProps)
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

return {
	ImageButton = ImageButton,
	Button = TextButton,
	TextButton = TextButton,
	RoundedFrame = RoundedFrame,
	TextLabel = TextLabel,
	ImageLabel = ImageLabel,
	Div = Div,
}