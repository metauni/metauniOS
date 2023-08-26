--[[
	
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseObject = require(ReplicatedStorage.Util.BaseObject)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)
local Rx = require(ReplicatedStorage.Util.Rx)
local UVMap = require(script.Parent.UVMap)
local Template = script.Template

local GraphMenu = setmetatable({}, BaseObject)
GraphMenu.__index = GraphMenu

local HELP_TEXT = [[Enter 3 functions to map board coordinates (<b>u</b>,<b>v</b>) onto world space (<b>x</b>,<b>y</b>,<b>z</b>).

You can make use of arithmetic <b>+</b> <b>-</b> <b>*</b> <b>/</b> <b>^</b>, the functions <b>sin</b>, <b>cos</b>, <b>tan</b>, <b>exp</b>, <b>log</b>, and the constants <b>pi</b> and <b>e</b>.

  z(u,v) = 4sin(2piu) + cos(2piu^2)]]

function GraphMenu.new(props)
	local self = setmetatable(BaseObject.new(), GraphMenu)

	self._props = props
	self._xMapStr = Blend.State("")
	self._yMapStr = Blend.State("")
	self._zMapStr = Blend.State("")

	self._showHelp = Blend.State(false)

	return self
end

function GraphMenu:_observeValidMapStr(axis)
	return self["_"..axis.."MapStr"]:Observe():Pipe {
		Rx.map(function(mapStr)
			local success = pcall(UVMap.parse, mapStr)
			return success
		end)
	}
end

function GraphMenu:render()

	local validObservers = {
		X = Rx.cache()(self:_observeValidMapStr("x")),
		Y = Rx.cache()(self:_observeValidMapStr("y")),
		Z = Rx.cache()(self:_observeValidMapStr("z")),
	}
	
	local observeAllValid = (Rx.combineLatest(validObservers):Pipe {
		Rx.map(function(state)
			return state.X and state.Y and state.Z
		end)
	})
	
	local percentVisible = Blend.Spring(Blend.Computed(self._props.Visible, function(visible)
		return visible and 1 or 0
	end), 35)
	
	local transparency = Blend.Computed(percentVisible, function(percent)
		return 1 - percent
	end)
	
	local menu = Template:Clone()
	
	local maid = Maid.new()
	maid:GiveTask(Blend.mount(menu, {

		Visible = Blend.Computed(percentVisible, function(percent)
			return percent > 0.1
		end),

		Blend.New "UIScale" {
			Scale = Blend.Computed(percentVisible, function(percent)
				return 0.8 + 0.2*percent
			end);
		};

		Blend.Find "Close" {
			[Blend.OnEvent "Activated"] = function()
				self._props.OnClose()
			end,
		},

		Blend.Find "Help" {
			[Blend.OnEvent "MouseEnter"] = function()
				self._showHelp.Value = true
			end,
			[Blend.OnEvent "MouseLeave"] = function()
				self._showHelp.Value = false
			end,
		},

		Blend.Find "ShowGrid" {
			Blend.Find "CheckBox" {
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(229, 229, 229),
				Blend.Find "Check" {
					Visible = self._props.ShowGrid,
				},
				-- Why doesn't this work for "Activated"?
				[Blend.OnEvent "MouseButton1Down"] = function()
					self._props.OnToggleShowGrid()
				end,
			}
		},

		Blend.Find "Render" {

			Active = observeAllValid,
			AutoButtonColor = observeAllValid,

			Transparency = Blend.Computed(observeAllValid, function(valid)
				return if valid then 0 else 0.5
			end),

			Blend.Find "UIStroke" {
				Transparency = Blend.Computed(observeAllValid, function(valid)
					return if valid then 0 else 0.5
				end)
			},

			[Blend.OnEvent "Activated"] = function()
				local success, result = pcall(function()
					UVMap.parse(self._xMapStr.Value)
					UVMap.parse(self._yMapStr.Value)
					UVMap.parse(self._zMapStr.Value)
				end)

				if not success then
					warn(result)
					return
				end

				self._props.OnSetUVMapStrings(
					self._xMapStr.Value,
					self._yMapStr.Value,
					self._zMapStr.Value)
			end,
		},

		Blend.ComputedPairs({"X", "Y", "Z"}, function(_, Axis)
			local axis = Axis:lower()
			local mapStrValue = self["_"..axis.."MapStr"]
			
			return Blend.Find(Axis) {

				Blend.Find "UIStroke" {
					Color = validObservers[Axis]:Pipe {
						Rx.map(function(valid: boolean)
							return if valid then Color3.new(0,0,0) else Color3.fromHex("F02828")
						end)
					}
				},
				Blend.Find "Map" {
					-- This will override whatever the user types in whenever the uv map
					-- changes on the graphbox. A little offensive, but better than not
					-- seeing the latest map when updated by someone else.
					Text = Blend.Computed(self._props.UVMap, function(uvMap)
						return uvMap[Axis.."MapStr"]
					end),
					[Blend.OnChange "Text"] = mapStrValue,
					ClearTextOnFocus = false,
				}
			}
		end)
	}))

	return Blend.New "Folder" {
		Name = "GraphMenu",

		[Blend.Attached(function() return maid end)] = true,
		
		Blend.New "CanvasGroup" {
	
			GroupTransparency = transparency,
			GroupColor3 = Blend.Spring(Blend.Computed(self._showHelp, function(showHelp)
				return if showHelp then Color3.new(0.75,0.75, 0.75) else Color3.new(1,1,1)
			end), 35),
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1,1),
			Position = UDim2.fromScale(0,0),

			menu,
		},

		Blend.New "Frame" {
			Name = "Help",

			AnchorPoint = Vector2.new(0.5,0.5),
			Position = UDim2.fromScale(0.5,0.5),
			Size = UDim2.fromOffset(300, 210),
			BackgroundColor3 = Color3.fromRGB(229, 229, 229),
	
			Visible = self._showHelp,
	
			Blend.New "UICorner" {},
			Blend.New "UIStroke" { Thickness = 2, },

			Blend.New "TextLabel" {
				Text = HELP_TEXT,
				TextWrap = true,
				RichText = true,
				TextSize = 16,
				Font = Enum.Font.JosefinSans,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,

				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5,0.5),
				Position = UDim2.fromScale(0.5,0.5),
				Size = UDim2.new(1,-40, 1, -50),
			}
		}
	}
end


return GraphMenu