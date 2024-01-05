local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(ReplicatedStorage.OS.UIBlend)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)

export type PlayState = "Paused" | "Playing"

local SKIP_AHEAD_SECONDS = 10
local SKIP_BACK_SECONDS = 10

local function StageUI(props: {
		PlayState: any, -- Something stateful
		OnTogglePlaying: () -> (),
		OnStop: () -> (),
		Duration: any,
		Timestamp: any,
		ReplayName: any,
		-- OnRestart: () -> (),
		OnSkipAhead: (number) -> (),
		OnSkipBack: (number) -> (),
	})

	local maid = Maid.new()

	local function title(order)
		return Blend.New "TextLabel" {
			LayoutOrder = order,
			Size = UDim2.fromOffset(200, 20),
			BackgroundTransparency = 1,
			
			Text = Blend.Computed(props.ReplayName, function(replayName: string?)
				return replayName or ""
			end),
			FontFace = Font.fromName("Merriweather"),
			TextYAlignment = Enum.TextYAlignment.Bottom,
			TextSize = 18,
		}
	end

	local function playPause(order: number)
		return Blend.New "TextButton" {
			LayoutOrder = order,
			Size = UDim2.fromOffset(30,30),
			Text = Blend.Computed(props.PlayState, function(playState)
				if playState == "Paused" then
					return "▶️"
				elseif playState == "Playing" then
					return "⏸️"
				else
					return "..."
				end
			end),
			TextScaled = true,
			BackgroundTransparency = 1,

			[Blend.OnEvent "Activated"] = props.OnTogglePlaying,
		}
	end

	local function skipBack(order: number)
		return Blend.New "TextButton" {
			LayoutOrder = order,
			Size = UDim2.fromOffset(30,30),
			Text = "⏪",
			TextScaled = true,
			BackgroundTransparency = 1,

			[Blend.OnEvent "Activated"] = function()
				props.OnSkipBack(SKIP_BACK_SECONDS)
			end,
		}
	end

	local function timer(order: number)
		return Blend.New "TextLabel" {
			LayoutOrder = order,
			Size = UDim2.fromOffset(120,30),

			Text = Blend.Computed(props.Timestamp, props.Duration, function(timestamp, duration)
				if not duration or not timestamp then
					return ""
				end
				if duration < 3600 then -- <1hr
					return `{os.date("!%M:%S", timestamp or 0)} - {os.date("!%M:%S", duration)}`
				else
					return `{os.date("!%H:%M:%S", timestamp or 0)} - {os.date("!%H:%M:%S", duration)}`
				end
			end),
			TextScaled = true,
			FontFace = Font.fromEnum(Enum.Font.Code),
			BackgroundTransparency = 1,
			TextTransparency = Blend.Spring(Blend.Computed(props.PlayState, function(playState)
				return if playState == nil then 1 else 0
			end), 30),
		}
	end

	local function skipAhead(order: number)
		return Blend.New "TextButton" {
			LayoutOrder = order,
			Size = UDim2.fromOffset(30,30),
			Text = "⏩",
			TextScaled = true,
			BackgroundTransparency = 1,

			[Blend.OnEvent "Activated"] = function()
				props.OnSkipAhead(SKIP_AHEAD_SECONDS)
			end,
		}
	end

	local function stop(order: number)
		return Blend.New "TextButton" {
			LayoutOrder = order,
			Size = UDim2.fromOffset(30,30),
			Text = "",

			BackgroundColor3 = Color3.new(0,0,0),
			BackgroundTransparency = Blend.Spring(Blend.Computed(props.PlayState, function(playState)
				return if playState == nil then 0.5 else 0
			end), 30),

			Blend.New "UICorner" { CornerRadius = UDim.new(0, 5) },

			[Blend.OnEvent "Activated"] = props.OnStop,
		}
	end

	return UI.Div {

		[Blend.Attached(function()
			return maid
		end)] = true,

		AnchorPoint = Vector2.new(0.5,0),
		Position = UDim2.fromScale(0.5,0),
		Size = UDim2.fromOffset(270, 60),
		BackgroundTransparency = 0.4,
		BackgroundColor3 = Color3.new(0.3,0.3,0.35),

		Blend.New "UICorner" { CornerRadius = UDim.new(0, 5) },

		UI.VerticalListLayout {},

		title(1),

		UI.Div {
			LayoutOrder = 2,
			Size = UDim2.fromOffset(270, 35),

			UI.HorizontalListLayout { 
				Padding = UDim.new(0, 5),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			},

			playPause(1),
			skipBack(2),
			timer(3),
			skipAhead(4),
			stop(5),
		}

	}
end

return StageUI