local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ListEntry = require(script.Components.ListEntry)
local ReplayEditor = require(script.ReplayEditor)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)
local UI = require(ReplicatedStorage.OS.UIBlend)

return function(props: {
	FetchReplayCharacterVoices: (string) -> any,
	SaveReplayCharacterVoicesPromise: (string, any) -> any,
	OnRecord: (string) -> (),
	OnClose: () -> (),
	OnPlay: (string, string) -> (),
})
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap() }

	local ReplayList = maid:Add(Blend.State({}))
	local NewRecordingName = maid:Add(Blend.State(""))
	local CurrentEditingReplay = maid:Add(Blend.State(nil))

	local RecordingNameValid = Blend.Computed(NewRecordingName, function(recordingName)
		return string.match(recordingName, "%S") ~= nil
	end)

	local function onClickRecord()
		local recordingName = NewRecordingName.Value
		if recordingName ~= "" then
			props.OnRecord(recordingName)
		end
	end

	function self.SetReplayList(newList)
		ReplayList.Value = newList
	end

	function self.render()

		local replayMenu = UI.RoundedBackplate {
			Name = "Backplate",
			Visible = Blend.Computed(CurrentEditingReplay, function(replay)
				return replay == nil
			end),
			AnchorPoint = Vector2.new(0.5,0.5),
			Position = UDim2.fromScale(0.5,0.5),
			Size = UDim2.fromOffset(400,400),

			BackgroundColor3 = Color3.new(0.9, 0.9, 0.9),

			UI.HLine {
				BackgroundColor3 = Color3.new(0,0,0),
				Position = UDim2.new(0.5, 0, 0, 50),
				AnchorPoint = Vector2.new(0.5,0),
				Size = UDim2.new(1, 0, 0, 4),
			},

			UI.Div {
				AnchorPoint = Vector2.new(0,0),
				Size = UDim2.new(1, 0, 0, 50),
				Position = UDim2.fromOffset(0, 0),
				BorderSizePixel = 2,
				ZIndex = 2,

				Blend.New "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
					VerticalAlignment = Enum.VerticalAlignment.Center,
				},
				
				Blend.New "TextButton" {
					LayoutOrder = 1,
					AnchorPoint = Vector2.new(0.5,0.5),
					Size = UDim2.fromOffset(50, 50),
					Position = UDim2.fromOffset(0, 0),
					BackgroundColor3 = Blend.Spring(Blend.Computed(RecordingNameValid, function(active)
						return if active then BrickColor.Red().Color else BrickColor.DarkGray().Color
					end), 30),
	
					[Blend.OnEvent "Activated"] = onClickRecord,
	
					Active = RecordingNameValid,

					Blend.New "UICorner" {
						CornerRadius = UDim.new(0.5, 0),
					},

					Blend.New "ImageLabel" {
						Image = "rbxassetid://6644618143",
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(0.5,0.5),
						Position = UDim2.fromScale(0.5,0.5),
						Size = UDim2.fromOffset(30, 30),
	
						ImageTransparency = Blend.Spring(Blend.Computed(RecordingNameValid, function(active)
							return if active then 0 else 0.5
						end), 30),
					},
				},
	
				UI.TextLabel {
					LayoutOrder = 2,
					Text = "Recording Name:",
					Size = UDim2.new(0,100,0,50),
				},

				Blend.New "Frame" {
					LayoutOrder = 3,
					Size = UDim2.new(1,-200,0,30),
					BorderSizePixel = 1,

					UI.Padding { Offset = 5, },

					Blend.New "TextBox" {
						Size = UDim2.fromScale(1,1),
		
						TextXAlignment = Enum.TextXAlignment.Left,
		
						Text = NewRecordingName.Value, -- Set initial value
						[Blend.OnChange "Text"] = function(text: string)
							NewRecordingName.Value = text
						end
					},
				},

				UI.Div {
					LayoutOrder = 4,
					Size = UDim2.fromOffset(50, 50),
					
					UI.RoundedButton {
						BackgroundColor3 = BrickColor.Red().Color,
						Size = UDim2.fromOffset(25, 25),
						
						[Blend.OnEvent "Activated"] = props.OnClose,
		
						UI.X {
							Color = Color3.new(1, 1, 1),
							ZIndex = 100,
						},
					},
				},
			},

			Blend.New "ScrollingFrame" {
				Position = UDim2.fromOffset(0,54),
				Size = UDim2.new(1,0, 1, -50),
				BackgroundTransparency = 1,

				ScrollingDirection = Enum.ScrollingDirection.Y,
				CanvasSize = Blend.Computed(ReplayList, function(replayList)
					if #replayList == 0 then
						return UDim2.fromScale(1,1)
					end
					local height = 4
					for _, replay in replayList do
						height += 51
					end
					return UDim2.new(1, 0, 0, height)
				end),

				Blend.New "UIListLayout" {
					Padding = UDim.new(0, 1),
					FillDirection = Enum.FillDirection.Vertical,
				},

				Blend.ComputedPairs(ReplayList, function(i, replay)
					
					return ListEntry(i, replay, {
						OnPlay = function()
							props.OnPlay(replay.ReplayId, replay.ReplayName)
						end,
						OnEdit = function()
							CurrentEditingReplay.Value = replay
						end,
					})
				end)
			},

		}

		return UI.Div {
			replayMenu,
			Blend.Single(Blend.Computed(CurrentEditingReplay, function(replay)
				if not replay then
					return nil
				end
				return ReplayEditor {
					Replay = replay,
					FetchCharacterVoices = function()
						return props.FetchReplayCharacterVoices(replay.ReplayId)
					end,
					SaveCharacterVoicesPromise = function(characterVoices)
						return props.SaveReplayCharacterVoicesPromise(replay.ReplayId, characterVoices)
					end,
					OnClose = function()
						CurrentEditingReplay.Value = nil
					end
				}
			end))
		}
	end

	return self
end
