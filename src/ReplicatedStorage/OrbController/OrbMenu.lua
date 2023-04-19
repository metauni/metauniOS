local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local New = Fusion.New
local Value = Fusion.Value
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Children = Fusion.Children
local Observer = Fusion.Observer
local Spring = Fusion.Spring

local function button(props)

	local color = Computed(function()
		if props.Selected:get() then
			return BrickColor.new("CGA brown").Color
		else
			return BrickColor.new("Black").Color
		end
	end)

	return New "TextButton" {
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromOffset(55,55),
		
		LayoutOrder = props.LayoutOrder,
		Text = props.Text,
		TextColor3 = BrickColor.new("Phosph. White").Color,

		FontFace = Font.new("Arial", Enum.FontWeight.Bold),


		BackgroundColor3 = color,
		BackgroundTransparency = 0.5,


		[OnEvent "Activated"] = props.OnClick,

		[Children] = {
			New "UICorner" { CornerRadius = UDim.new(0, 10)}
		}
	}
end

return function(props)

	--[[
		<Close Button>
		Boards: (Single|Double)
		<Minimise Button>
	--]]

	local CamLook = Value(workspace.CurrentCamera.CFrame.LookVector * Vector3.new(1,0,1))
	local conn = RunService.RenderStepped:Connect(function()
		CamLook:set(workspace.CurrentCamera.CFrame.LookVector * Vector3.new(1,0,1))
	end)

	local LookSpring = Spring(CamLook, 0.4, 1)

	local Cam = Value()
	
	return New "ScreenGui" {

		Parent = props.Parent,

		[Fusion.Cleanup] = conn,

		[Children] = New "Frame" {

			AnchorPoint = Vector2.new(0,1),
			Position = UDim2.new(0, 36, 1, -36),
			Size = UDim2.fromOffset(200, 70),

			BackgroundTransparency = 1,

			[Children] = {
				New "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 10),
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
				},
				New "ViewportFrame" {
					CurrentCamera = Cam,
					LayoutOrder = 1,
					Size = UDim2.fromOffset(75,75),
					AnchorPoint = Vector2.new(0.5,0.5),
					BackgroundTransparency = 1,
					Ambient = Color3.new(0,0,0),
					LightDirection = Vector3.new(-1,0,0),

					[Children] = {

						New "Camera" {
							CFrame = Computed(function()
								return CFrame.lookAt(-LookSpring:get().Unit * 2.8, Vector3.new(0,0,0))
							end),
							[Fusion.Ref] = Cam,
						},

						New "Part" {
							Material = Enum.Material.CrackedLava,
							BrickColor = BrickColor.new("CGA brown"),
							Shape = Enum.PartType.Ball,
							Size = Vector3.new(3,3,3),
							Position = Vector3.new(0,0,0),
						}
					}
				},
				button {
					LayoutOrder = 2,
					Text = "Detach",
					Selected = Value(false),
					OnClick = function()
						props.Detach()
					end,
				},
				Computed(function()
					if props.IsSpeaker:get() then
						return button {
							LayoutOrder = 3,
							Text = "Single\nBoard",
							Selected = Computed(function()
								return props.ViewMode:get() == "single"
							end),
							OnClick = function()
								props.SetViewMode("single")
							end,
						}
					end
				end, Fusion.cleanup),
				Computed(function()
					if props.IsSpeaker:get() then
						return button {
							LayoutOrder = 3,
							Text = "Double\nBoard",
							Selected = Computed(function()
								return props.ViewMode:get() == "double"
							end),
							OnClick = function()
								props.SetViewMode("double")
							end,
						}
					end
				end, Fusion.cleanup),
			}
		},
	}
end