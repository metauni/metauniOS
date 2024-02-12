local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)
local Rx = require(ReplicatedStorage.Util.Rx)
local Rxi = require(ReplicatedStorage.Util.Rxi)

-- Mute button blocker constants
local BLOCKERTHICKNESS = 0.01
local BLOCKERNEARPLANEZOFFSET = 0.5

local UI = {}

local function addRoundedCorner(props)
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

function UI.HorizontalListLayout(props)
	props = Sift.Dictionary.merge({
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, props)

	return Blend.New "UIListLayout" (props)
end

function UI.VerticalListLayout(props)
	props = Sift.Dictionary.merge({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, props)

	return Blend.New "UIListLayout" (props)
end

function UI.RoundedBackplate(props: {[any]: any?} & {Visible: any?})
	assert(props.Transparency == nil or props.Transparency == 0, "Backplate cannot be transparent (for mute button blocker)")
	if props.CornerRadius then
		assert(typeof(props.CornerRadius) == "UDim", "Bad CornerRadius")
		assert(props.CornerRadius.Scale == 0, "Backplate CornerRadius must be offset only")
	end

	props = Sift.Dictionary.merge({
		BackgroundColor3 = Color3.new(0,0,0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		CornerRadius = UDim.new(0, 5),
	}, props)

	;(props :: any)[Blend.Attached(function(frame)
		if not frame then
			return
		end

		local maid = Maid.new()

		local Part = maid:Add(Blend.State(nil))

		local ScreenGui = Rx.fromSignal(frame.AncestryChanged):Pipe {
			Rx.defaultsToNil,
			Rx.map(function()
				local instance = frame.Parent
				while instance ~= nil and not instance:IsA("ScreenGui") do
					instance = instance.Parent
				end

				return instance
			end),
		}

		local InsideEnabledScreenGui = ScreenGui:Pipe {
			Rx.switchMap(function(screenGui)
				if screenGui == nil then
					return Rx.of(false)
				end

				return Rxi.propertyOf(screenGui, "Enabled")
			end),
		}

		local AbsoluteSize = Rxi.propertyOf(frame, "AbsoluteSize")
		local AbsolutePosition = Rxi.propertyOf(frame, "AbsolutePosition")
		local CamProps = Rxi.propertyOf(workspace, "CurrentCamera"):Pipe {
			Rx.switchMap(function(camera)
				return Rx.combineLatest {
					CFrame       = Rxi.propertyOf(camera, "CFrame"),
					NearPlaneZ   = Rxi.propertyOf(camera, "NearPlaneZ"),
					ViewportSize = Rxi.propertyOf(camera, "ViewportSize"),
					FieldOfView  = Rxi.propertyOf(camera, "FieldOfView"),
				}
			end)
		}

		-- Returns the stud size of a pixel projected onto a plane facing the camera at
		-- a given zDistance
		local function pixelsToStuds(viewportSize, fieldOfView, zDistance)
			return (1 / viewportSize.Y) * 2 * zDistance * math.tan(math.rad(fieldOfView) / 2)
		end


		maid:Add(Rx.combineLatest {
			Part = Part:Observe(),
			CamProps = CamProps,
			AbsolutePosition = AbsolutePosition,
			AbsoluteSize = AbsoluteSize,
		}:Subscribe(function(state)

			if not state.Part then
				return
			end
			
			state.AbsoluteSize -= 2 * Vector2.new(props.CornerRadius.Offset, props.CornerRadius.Offset)
			state.AbsolutePosition += Vector2.new(props.CornerRadius.Offset, props.CornerRadius.Offset)

			local zDistance = state.CamProps.NearPlaneZ + BLOCKERNEARPLANEZOFFSET
			local factor = pixelsToStuds(state.CamProps.ViewportSize, state.CamProps.FieldOfView, zDistance)

			state.Part.Size = Vector3.new(
				state.AbsoluteSize.X * factor * 0.99,
				state.AbsoluteSize.Y * factor * 0.99,
				BLOCKERTHICKNESS
			)

			local viewportCentre = state.CamProps.ViewportSize / 2
			local canvasCentre = state.AbsolutePosition + state.AbsoluteSize / 2 + GuiService:GetGuiInset()
			local pixelShift = canvasCentre - viewportCentre

			local x = pixelShift.X * factor
			local y = -pixelShift.Y * factor

			-- Position blocker to coincide with backplate
			state.Part.CFrame = state.CamProps.CFrame * CFrame.new(x, y, 0) + state.CamProps.CFrame.LookVector * (zDistance + BLOCKERTHICKNESS / 2)
		end))

		maid:Add(
			Blend.New "Part" {
				Name = "MuteButtonBlocker",
				Color = Color3.new(0,0,0),

				Parent = Blend.Computed(InsideEnabledScreenGui, props.Visible or true, function(enabled, visible)
					return if enabled and visible then workspace else nil
				end),
				Transparency = 0.95,  -- Must be semi-transparent (not fully) to actually block click events
				Anchored = true,
				CanCollide = false,
				CastShadow = false,
				CanQuery = true,

				function(part)
					Part.Value = part
				end,
			}:Subscribe()
		)

		return maid
	end)] = true

	return Blend.New "Frame" (addRoundedCorner(props))
end

function UI.Backplate(props)

	props = Sift.Dictionary.set(props, "CornerRadius", UDim.new(0, 0))

	return UI.RoundedBackplate(props)
end



return UI