local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(ReplicatedStorage.OS.UIBlend)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)

type Phase = nil | "Ready" | "Recording"

local function StudioMenu(props: {
		OnRecord: () -> (),
		OnStop: () -> (),
	})

	local maid = Maid.new()
	local self = { Destroy = maid:Wrap(), props = props }

	local Time = maid:Add(Blend.State(0))
	-- Phase: nil -> "Ready" -> "Recording"
	local Phase = maid:Add(Blend.State(nil)) :: ValueObject.ValueObject<Phase>

	function self.SetTimer(seconds: number)
		Time.Value = math.round(seconds)
	end

	function self.SetPhaseReady()
		Time.Value = 0
		Phase.Value = "Ready"
	end
	
	function self.SetPhaseRecording()
		Phase.Value = "Recording"
	end

	local function record(order: number)
		return Blend.New "TextButton" {
			LayoutOrder = order,
			Size = UDim2.fromOffset(30,30),
			Text = "",

			BackgroundTransparency = Blend.Spring(Blend.Computed(Phase, function(phase: Phase)
				return if phase == "Recording" then 1 else 0
			end), 30),
			BackgroundColor3 = Blend.Spring(Blend.Computed(Phase, function(phase: Phase)
				return if phase == "Ready" then BrickColor.new("Crimson").Color else BrickColor.Gray().Color
			end), 30),

			Blend.New "UICorner" { CornerRadius = UDim.new(0.5, 0)},

			[Blend.OnEvent "Activated"] = function()
				if Phase.Value == "Ready" then
					props.OnRecord()
				end
			end,
		}
	end

	local function timer(order: number)
		return Blend.New "TextLabel" {
			LayoutOrder = order,
			Size = UDim2.fromOffset(50,30),

			Text = Blend.Computed(Time, function(seconds)
				if seconds < 3600 then -- <1hr
					return os.date("!%M:%S", seconds)
				else
					return os.date("!%H:%M:%S", seconds)
				end
			end),
			TextScaled = true,
			FontFace = Font.fromEnum(Enum.Font.Code),
			BackgroundTransparency = 1,
			TextTransparency = Blend.Spring(Blend.Computed(Phase, function(phase)
				return if phase == "Recording" then 0 else 0.5
			end), 30),
		}
	end

	local function stop(order: number)
		return Blend.New "TextButton" {
			LayoutOrder = order,
			Size = UDim2.fromOffset(30,30),
			Text = "",

			BackgroundColor3 = Color3.new(0,0,0),
			BackgroundTransparency = Blend.Spring(Blend.Computed(Phase, function(phase: Phase)
				return if phase == "Recording" then 0 else 0.8
			end), 30),

			Blend.New "UICorner" { CornerRadius = UDim.new(0, 5) },

			[Blend.OnEvent "Activated"] = function()
				if Phase.Value == "Recording" then
					props.OnStop()
				end
			end,
		}
	end

	function self.render()
		return UI.Div {
			AnchorPoint = Vector2.new(0.5,0),
			Position = UDim2.new(0.5,0,0,40),
			Size = UDim2.fromOffset(130, 40),
			BackgroundTransparency = 0.4,
			BackgroundColor3 = Color3.new(0.3,0.3,0.35),

			Blend.New "UICorner" { CornerRadius = UDim.new(0, 5) },

			UI.HorizontalListLayout { 
				Padding = UDim.new(0, 5),
				HorizontalAlignment = Enum.HorizontalAlignment.Center
			},

			record(1),
			timer(2),
			stop(3),
	
		}
	end

	return self
end

export type StudioMenu = typeof(StudioMenu(nil :: any))

return StudioMenu