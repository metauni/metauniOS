local Selection = game:GetService("Selection")

local Packages = script.Parent.Parent.Packages
local PluginEssentials = require(Packages.PluginEssentials)

local Widget = PluginEssentials.Widget
local MainButton = PluginEssentials.MainButton
local ScrollFrame = PluginEssentials.ScrollFrame
local Label = PluginEssentials.Label
local TextInput = PluginEssentials.TextInput

local Fusion = require(Packages.Fusion)

local GhostBoard = require(script.Parent.GhostBoard)
local BaseObject = require(script.Parent.BaseObject)

local App = setmetatable({}, BaseObject)
App.__index = App

return function(pluginProps)

	local Radius = Fusion.Value(40)
	local Apart = Fusion.Value(10)
	local Side = Fusion.Value(nil)

	local Valid = Fusion.Computed(function()
		return Radius:get() and tonumber(Apart:get())
	end)

	local ghostBoard = GhostBoard.new(Radius:get(false), Apart:get(false))

	if pluginProps.WidgetEnabled:get(false) then
		ghostBoard:Start()
	end

	local viewer = ghostBoard:render({
		Show = Fusion.Computed(function()
			return Side:get() ~= nil and Valid:get()
		end),
		Parent = game:GetService("CoreGui")
	})
	
	local cleanup = {

		ghostBoard,
		viewer,

		Fusion.Observer(pluginProps.WidgetEnabled):onChange(function()
			if pluginProps.WidgetEnabled:get() then
				ghostBoard:Start()
			else
				ghostBoard:Stop()
			end
		end),

		Fusion.Observer(Radius):onChange(function()
			ghostBoard:SetCurvature(Radius:get(false))
		end),
		
		Fusion.Observer(Apart):onChange(function()
			ghostBoard:SetApart(Apart:get(false))
		end),
		
		Fusion.Observer(Side):onChange(function()
			ghostBoard:SetSide(Side:get(false))
		end),
	}

	return Widget {
		Id = game:GetService("HttpService"):GenerateGUID(),
		Name = "metauniTools",

		InitialDockTo = Enum.InitialDockState.Left,
		InitialEnabled = false,
		ForceInitialEnabled = false,
		FloatingSize = Vector2.new(250, 200),
		MinimumSize = Vector2.new(250, 200),

		Enabled = pluginProps.WidgetEnabled,
		[Fusion.OnChange "Enabled"] = function(isEnabled)
			pluginProps.WidgetEnabled:set(isEnabled)
		end,

		[Fusion.Cleanup] = cleanup,

		[Fusion.Children] = ScrollFrame {
			ZIndex = 1,
			Size = UDim2.fromScale(1, 1),

			CanvasScaleConstraint = Enum.ScrollingDirection.X,

			UILayout = Fusion.New "UIListLayout" {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 7),
			},

			UIPadding = Fusion.New "UIPadding" {
				PaddingLeft = UDim.new(0, 5),
				PaddingRight = UDim.new(0, 5),
				PaddingBottom = UDim.new(0, 10),
				PaddingTop = UDim.new(0, 10),
			},

			[Fusion.Children] = {
				Label {
					Text = "Place Board Copies",
					TextSize = 20,
				},
				Label {
					Text = "Radius",
				},
				TextInput {
					PlaceholderText = "",
					Text = tostring(Radius:get(false)),
					[Fusion.OnChange "Text"] = function(newText)
						Radius:set(newText == "" and "flat" or tonumber(newText))
					end,
				},
				Label {
					Text = "Apart",
				},
				TextInput {
					PlaceholderText = "",
					Text = tostring(Apart:get(false)),
					[Fusion.OnChange "Text"] = function(newText)
						Apart:set(tonumber(newText))
					end,
				},
				Fusion.New "Frame" {
					AnchorPoint = Vector2.new(0,0),
					Position = UDim2.fromScale(0,0),
					Size = UDim2.new(1,0,0, 30),
					BackgroundTransparency = 1,
					[Fusion.Children] = Fusion.Computed(function()
						if not ghostBoard:State():get() then
							return {Label {
								Text = "Select a Board",
								TextColorStyle = Enum.StudioStyleGuideColor.WarningText,
							}}
						else
							return 
								Fusion.ForValues({"left", "right"}, function(side: "left" | "right")
									local text = ({left = "Left", right = "Right"})[side]
									local pos = ({left = 0.25, right = 0.75})[side]
								
									return MainButton {
										Text = text,
										AnchorPoint = Vector2.new(0.5,0.5),
										Position = UDim2.fromScale(pos,0.5),
										Size = UDim2.fromScale(1/3,1),
								
										[Fusion.OnEvent "MouseEnter"] = function()
											Side:set(side)
										end,
										[Fusion.OnEvent "MouseLeave"] = function()
											Side:set(nil)
										end,
										[Fusion.OnEvent "Activated"] = function()
											local clone = ghostBoard:CreateCopyAtGhost()
											Selection:set({clone})
										end,
									}
								end, Fusion.cleanup)
						end
					end, Fusion.cleanup),
					
				},
			}
		}
	}
end