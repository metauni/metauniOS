local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Sift = require(ReplicatedStorage.Packages.Sift)
local Blend = require(ReplicatedStorage.Util.Blend)
local GoodSignal = require(ReplicatedStorage.Util.GoodSignal)
local Maid = require(ReplicatedStorage.Util.Maid)
local SpringObject = require(ReplicatedStorage.Util.SpringObject)
local UI = require(script.Parent.UIBlend)

local Remotes = script.Remotes

local DEBUG = false
local Panel = nil

local export = {}

local function prettyPrint(value)
	if typeof(value) == "table" then
		return "{" .. table.concat(value, ",") .. "}"
	end
	return tostring(value)
end

local function makePanel()
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap() }

	local Dict = maid:Add(Blend.State({}))
	local Minimised = maid:Add(Blend.State(false))

	function self.Log(key: string, value: any)
		local dict = Dict.Value
		local prettyValue = prettyPrint(value)
		if not dict[key] then
			local Value = Blend.State(prettyValue)
			local Updated = GoodSignal.new()
			maid[key] = { Value, Updated }
			Dict.Value = Sift.Dictionary.set(dict, key, { Value, Updated })
		else
			dict[key][1].Value = prettyValue
			dict[key][2]:Fire()
		end
	end

	function self.render()
		local scrollingFrame = Blend.New "ScrollingFrame" {
			LayoutOrder = 2,

			Size = Blend.Computed(Dict, function(dict)
				local rows = Sift.Dictionary.count(dict)
				local height = rows * 30
				return UDim2.fromOffset(300 + 12, math.min(300, height))
			end),
			BackgroundTransparency = 0.5,
			Visible = Blend.Computed(Minimised, function(minimised)
				return not minimised
			end),

			ScrollingDirection = Enum.ScrollingDirection.Y,
			CanvasSize = Blend.Computed(Dict, function(dict)
				local rows = Sift.Dictionary.count(dict)
				local height = rows * 30
				return UDim2.fromOffset(300 + 12, height)
			end),

			Blend.New "UIListLayout" {
				SortOrder = Enum.SortOrder.Name,
				FillDirection = Enum.FillDirection.Vertical,
			},

			Blend.ComputedPairs(Dict, function(key: string, pair, innerMaid: Maid.Maid)
				local Value, Updated = table.unpack(pair)

				local UpdatedSpring = innerMaid:Add(SpringObject.new(1, 20))
				innerMaid:GiveTask(Updated:Connect(function()
					UpdatedSpring:SetTarget(1, true)
					UpdatedSpring:SetTarget(0, false)
				end))
				UpdatedSpring:SetTarget(0)

				return UI.Div {
					Name = key,
					Size = UDim2.fromOffset(300, 30),

					Blend.New "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirection = Enum.FillDirection.Horizontal,
					},

					Blend.New "UIStroke" { Thickness = 1 },

					Blend.New "TextLabel" {
						LayoutOrder = 1,
						Size = UDim2.new(0, 75, 1, 0),
						Text = tostring(key),
						TextWrapped = true,
						BackgroundTransparency = 1,
					},

					UI.VLine {
						LayoutOrder = 3,
						BackgroundColor3 = Color3.new(),
					},

					Blend.New "TextLabel" {
						LayoutOrder = 3,
						Size = UDim2.new(0, 300 - 75, 1, 0),
						Text = Value,
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Left,

						BackgroundColor3 = Blend.Computed(UpdatedSpring:Observe(), function(strength)
							return Color3.new(1, 1, 1):Lerp(Color3.new(1, 0, 0), strength)
						end),
						BackgroundTransparency = Blend.Computed(UpdatedSpring:Observe(), function(strength)
							return 1 - 0.8 * strength
						end),
						BorderSizePixel = 1,
					},
				}
			end),
		}

		return Blend.New "Frame" {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = Blend.Computed(Minimised, function(minimised)
				if minimised then
					return UDim2.fromOffset(130, 330)
				else
					return UDim2.fromOffset(300 + 12, 330)
				end
			end),
			BackgroundTransparency = 1,

			Blend.New "UIListLayout" {
				SortOrder = Enum.SortOrder.LayoutOrder,
				FillDirection = Enum.FillDirection.Vertical,
			},

			UI.Div {
				Size = UDim2.new(1, 0, 0, 30),
				LayoutOrder = 1,
				BackgroundTransparency = 0.5,

				Blend.New "TextLabel" {
					Size = UDim2.new(0, 100, 0, 30),
					Text = "DebugPanel",
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = Font.fromName("Merriweather"),
					TextSize = 20,
					BackgroundTransparency = 1,
				},

				Blend.New "TextButton" {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.fromScale(1, 0.5),
					Size = UDim2.fromOffset(30, 30),
					Text = "-",
					FontFace = Font.fromName("Merriweather", Enum.FontWeight.Bold),
					TextScaled = true,

					BackgroundColor3 = BrickColor.Black().Color,
					BackgroundTransparency = 0.5,

					[Blend.OnEvent "Activated"] = function()
						Minimised.Value = not Minimised.Value
					end,
				},
			},

			scrollingFrame,
		}
	end

	return self
end

function export.Log(key, value)
	if not DEBUG then
		warn("DebugPanel receiving log events but DEBUG=false")
		return
	end

	if RunService:IsServer() then
		Remotes.Log:FireAllClients(key, value)
		return
	end

	-- IsClient
	if not Panel then
		Panel = makePanel()
		Blend.mount(Players.LocalPlayer.PlayerGui, {
			Blend.New "ScreenGui" {
				Name = "DebugPanel",
				Panel.render(),
			},
		})
	end

	Panel.Log(key, value)
end

return export
