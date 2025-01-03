--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Stream = require(ReplicatedStorage.Util.Stream)
local Spring = require(ReplicatedStorage.Util.Spring)
local AccelTween = require(ReplicatedStorage.Util.AccelTween)
local Value = require(ReplicatedStorage.Util.Value)
local U = require(ReplicatedStorage.Util.U)

export type Value<T> = Value.Value<T>
export type Stream<T...> = Stream.Stream<T...>

local UI = {}

local palletes = {
	light = {
		Stroke = Color3.fromHex("#2f2f2f"),
		Background = Color3.fromHex("#cdcdcd"),
	},
	dark = {
		Stroke = Color3.fromHex("#cdcdcd"),
		-- Background = Color3.fromHex("#252c35"),
		Background = Color3.fromHex("#2f2f2f"),
	},
}

UI.Theme = Value("dark" :: any) :: Value<"light" | "dark">

local function themeColor(name): Stream.Stream<Color3>
	return function(listener)
		return UI.Theme:Stream()(function(theme)
			listener(palletes[theme][name])
		end)
	end
end

UI.Color = {
	Stroke = themeColor("Stroke"),
	Background = themeColor("Background"),
}

function UI.toggleTheme()
	UI.Theme.Value = if UI.Theme.Value == "light" then "dark" else "light"
end

function UI.addUDim(a: UDim, b: UDim)
	return UDim.new(a.Scale + b.Scale, a.Offset + b.Offset)
end

function UI.addUDim2(a: UDim2, b: UDim2)
	return UDim2.new(UI.addUDim(a.X, b.X), UI.addUDim(a.Y, b.Y))
end

--[[
	Create a stream that smoothly interpolate towards the latest target value
	according to spring physics. Each emitted value becomes the new target of the spring.

	Internally creates a RenderStepped connection when listened to, but only emits values
	when the spring is actually animating.
]]
function UI.Spring<T>(target: Has<T>, config: { speed: Has<number>?, damper: Has<number>? }): Stream<T>
	assert(config == nil or typeof(config) == "table", "Bad spring config")

	if U.isStaticHas(target) then
		return Stream.of(target :: any)
	end

	local Target: Stream<T> = U.toStream(target)
	local Speed: Stream<number> = U.toStream(config and config.speed or 30)
	local Damper: Stream<number> = U.toStream(config and config.damper or 1)

	return function(listener)
		local spring = nil
		local connection = RunService.RenderStepped:Connect(function()
			if spring then
				local animating, position = spring:Animating()
				if animating then
					listener(Spring.fromLinearIfNeeded(position))
				end
			end
		end)

		local cleanupStream = Stream.listen3(Target, Speed, Damper, function(value, speed, damper)
			if spring == nil then
				listener(value)
				spring = Spring.new(Spring.toLinearIfNeeded(value))
			end
			spring.Speed = speed
			spring.Damper = damper
			spring.Target = Spring.toLinearIfNeeded(value)
		end)

		return function()
			Stream.clean(connection)
			connection = nil
			Stream.clean(cleanupStream)
			cleanupStream = nil
		end
	end
end

--[[
	Create a stream that smoothly interpolate between emitted target values
	using constant acceleration to reach each target in minimum time. Each emitted value
	becomes the new target position.

	Internally creates a RenderStepped connection when listened to, but only emits values
	while the acceltween is running (.rtime > 0), and once when it stops.
]]
function UI.AccelTween<T>(target: Has<T>, config: { acceleration: Has<number>? }): Stream<T>
	assert(config == nil or typeof(config) == "table", "Bad acceltween config")

	if U.isStaticHas(target) then
		return Stream.of(target :: any)
	end

	local Target: Stream<T> = U.toStream(target)
	local Acceleration: Stream<number> = U.toStream(config and config.acceleration or 10)

	return function(listener)
		local accelTween = nil
		local active = false
		local connection = RunService.RenderStepped:Connect(function()
			if active then
				listener(Spring.fromLinearIfNeeded(accelTween.p))
				-- The active flags helps us update the listener one last time after .rtime becomes <= 0
				active = accelTween.rtime > 0
			end
		end)

		local cleanupStream = Stream.listen2(Target, Acceleration, function(value, acceleration)
			if accelTween == nil then
				listener(value)
				accelTween = AccelTween.new(acceleration)
				accelTween.p = Spring.toLinearIfNeeded(value)
				accelTween.v = 0
			end
			accelTween.a = acceleration
			accelTween.t = Spring.toLinearIfNeeded(value)
			active = accelTween.rtime > 0
		end)

		return function()
			Stream.clean(connection)
			connection = nil
			Stream.clean(cleanupStream)
			cleanupStream = nil
		end
	end
end

function UI.listedChildren(layoutPropsAndChildren: { [string | number]: any })
	local orderedChildren = {} :: { any }
	local layoutProps = {}
	for key, value in layoutPropsAndChildren do
		if typeof(key) == "number" then
			if typeof(value) == "Instance" then
				(value :: any).LayoutOrder = key
				table.insert(orderedChildren, value)
			elseif typeof(value) == "function" then
				table.insert(
					orderedChildren,
					Stream.tap(function(child)
						assert(typeof(child) == "Instance", "Bad child");
						(child :: any).LayoutOrder = key
					end)(value :: Stream.Stream<Instance>)
				)
			else
				error(`[UI.listedChildren] Child {value} ({typeof(value)}) is not an Instance or Stream<Instance>`)
			end
		else
			layoutProps[key] = value
		end
	end

	return {
		U.new "UIListLayout"(layoutProps),
		orderedChildren :: any,
	}
end

function UI.horizontalChildren(mixedProps)
	mixedProps.FillDirection = Enum.FillDirection.Horizontal
	return UI.listedChildren(mixedProps)
end

function UI.verticalChildren(mixedProps: { [string | number]: any })
	mixedProps.FillDirection = Enum.FillDirection.Vertical
	return UI.listedChildren(mixedProps)
end

UI.Attach = "instance"

export type Has<T> = U.Has<T>

function UI.Backplate(props: {
	Size: Has<UDim2>?,
	AnchorPoint: Has<Vector2>?,
	Position: Has<UDim2>?,

	Children: { any }?,
})
	local thickness = 2

	return U.new "Frame" {
		Name = "Backplate",

		Size = props.Size,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		BackgroundColor3 = UI.Color.Background,
		U.new "UIGradient" {
			Rotation = 90,
			Color = U.compute2(UI.Color.Stroke, UI.Color.Background, function(stroke, background)
				return ColorSequence.new(stroke, background)
			end),
			Transparency = NumberSequence.new(0.08, 0),
		},

		U.new "UIStroke" {
			Thickness = 4,
			Color = UI.Color.Stroke,
			LineJoinMode = "Miter",
		},

		U.new "Frame" {

			Size = UDim2.new(1, -thickness * 2, 1, -thickness * 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = UI.Color.Background,

			U.new "UIStroke" {
				Thickness = thickness,
				Color = UI.Color.Stroke,
				LineJoinMode = Enum.LineJoinMode.Miter,
			},

			props.Children,
		},
	}
end

function UI.CloseButton(props: {
	AnchorPoint: Has<Vector2>?,
	Position: Has<UDim2>?,
	Size: Has<UDim2>?,

	OnClose: () -> (),
})
	local Hovered = U.Value(false)
	local Pressed = U.Value(false)

	return U.new "TextButton" {
		cleanup = { Hovered, Pressed },

		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		Text = "",
		BackgroundTransparency = UI.Spring(
			U.compute2(Hovered, Pressed, function(hover, pressed)
				return (hover and 0.75 or 1) * (pressed and 0.75 or 1)
			end),
			{ speed = 20 }
		),
		BackgroundColor3 = Color3.new(1, 1, 1),

		-- Two frame rectangles forming an X
		U.new "Frame" {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0.5, 0, 0, 2),
			Rotation = 45,
			BackgroundColor3 = UI.Color.Stroke,
		},

		U.new "Frame" {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 2, 0.5, 0),
			Rotation = 45,
			BackgroundColor3 = UI.Color.Stroke,
		},

		Activated = props.OnClose,
		MouseButton1Down = function()
			Pressed.Value = true
		end,
		MouseButton1Up = function()
			Pressed.Value = false
		end,
		MouseEnter = function()
			Hovered.Value = true
		end,
		MouseLeave = function()
			Hovered.Value = false
			Pressed.Value = false
		end,
	}
end

function UI.TitledWindow(props: {
	Size: Has<UDim2>?,
	AnchorPoint: Has<Vector2>?,
	Position: Has<UDim2>?,

	Height: number?,
	Title: Has<string>,
	OnClose: (() -> ())?,

	Children: { any }?,
})
	local titleHeight = props.Height or 30

	local maybeCloseButton = if props.OnClose
		then U.new "Frame" {
			Size = UDim2.new(0, titleHeight, 0, titleHeight),
			Position = UDim2.new(1, 0, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			-- BorderSizePixel = 2,
			BorderColor3 = UI.Color.Stroke,
			UI.CloseButton { OnClose = props.OnClose },
			-- U.new "UIStroke" { Thickness = 4, LineJoinMode = "Miter", Color = UI.Color.Stroke },
		}
		else nil

	local titleLabel = U.new "TextLabel" {
		Size = UDim2.new(1, 0, 0, titleHeight),
		Text = U.format("<b>%s</b>", props.Title),
		Font = Enum.Font.Merriweather,
		RichText = true,
		TextScaled = true,
		BackgroundTransparency = 1,
		TextColor3 = UI.Color.Stroke,
		TextXAlignment = Enum.TextXAlignment.Left,

		U.new "UIPadding" {
			PaddingLeft = UDim.new(0, 5),
		},

		maybeCloseButton,
	}

	return UI.Backplate {
		Size = props.Size,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,

		Children = UI.verticalChildren {
			titleLabel,

			U.new "Frame" {
				BackgroundColor3 = UI.Color.Stroke,
				Size = UDim2.new(1, 0, 0, 4),
			},
			U.new "Frame" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, -(props.Height or 30)),

				props.Children,
			},
		},
	}
end

return UI
