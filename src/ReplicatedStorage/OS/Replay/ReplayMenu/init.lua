local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)

local Remotes = script.Parent.Remotes

return function(props)
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap() }

	local ReplayList = maid:Add(Blend.State({}))
	local NewRecordingName = maid:Add(Blend.State(""))

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

		return Blend.New "Frame" {
			AnchorPoint = Vector2.new(0.5,0.5),
			Position = UDim2.fromScale(0.5,0.5),
			Size = UDim2.fromOffset(400,400),

			Blend.New "Frame" {
				Size = UDim2.new(1, 0, 0, 50),
				Position = UDim2.fromOffset(0, 0),
				BorderSizePixel = 2,
				ZIndex = 2,
				
				Blend.New "TextButton" {
					Size = UDim2.fromOffset(50, 50),
					Position = UDim2.fromOffset(0, 0),
					BackgroundColor3 = Blend.Spring(Blend.Computed(RecordingNameValid, function(active)
						return if active then BrickColor.Red().Color else BrickColor.DarkGray().Color
					end), 30),
	
					[Blend.OnEvent "Activated"] = onClickRecord,
	
					Active = RecordingNameValid,
	
					Blend.New "ImageLabel" {
						LayoutOrder = 0,
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
	
				Blend.New "TextLabel" {
					Text = "Recording Name:",
					AnchorPoint = Vector2.new(0,0),
					Position = UDim2.fromOffset(50,0),
					Size = UDim2.new(0,100,0,50),
					BorderSizePixel = 1,
				},
	
				Blend.New "TextBox" {
					AnchorPoint = Vector2.new(0,0),
					Position = UDim2.fromOffset(160,0),
					Size = UDim2.new(1,-160,0,50),
					BorderSizePixel = 1,
	
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundTransparency = 1,
	
					Text = NewRecordingName.Value, -- Set initial value
					[Blend.OnChange "Text"] = function(text: string)
						NewRecordingName.Value = text
					end
				},
			},

			Blend.New "ScrollingFrame" {
				Position = UDim2.fromOffset(0,50),
				Size = UDim2.new(1,0, 1, -50),

				Blend.New "UIListLayout" {
					Padding = UDim.new(0, 1),
					FillDirection = Enum.FillDirection.Vertical,
				},
				
				Blend.ComputedPairs(ReplayList, function(i, replay)
					
					return Blend.New "TextButton" {
						Name = replay.RecordingName,
						Text = `{replay.RecordingName} (ID: {replay.RecordingId})`,
						LayoutOrder = i,
	
						Size = UDim2.new(1,0,0,50),
						BorderSizePixel = 1,

						Blend.New "ImageButton" {
							BackgroundColor3 = BrickColor.Green().Color,
							Image = "rbxassetid://8215093320",
							Size = UDim2.fromOffset(50, 50),

							[Blend.OnEvent "Activated"] = function()
								props.OnPlay(replay)
							end
						},
					}
				end)
			}, 

		}
	end

	return self
end
