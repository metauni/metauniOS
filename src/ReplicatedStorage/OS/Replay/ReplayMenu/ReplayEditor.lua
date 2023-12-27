local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(ReplicatedStorage.OS.UIBlend)
local Sift = require(ReplicatedStorage.Packages.Sift)
local t = require(ReplicatedStorage.Packages.t)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)
local Promise = require(ReplicatedStorage.Util.Promise)
local Rx = require(ReplicatedStorage.Util.Rx)

type AudioClip = {
	AssetId: string,
	StartTimestamp: number,
	StartOffset: number,
	EndOffset: number,
}

local checkAudioClip = t.strictInterface {
	AssetId = t.string,
	StartTimestamp = t.number,
	StartOffset = t.number,
	EndOffset = t.number,
}

local function clipEntry(i: number, props: {
		ClipData: {
			AssetId: string,
			StartTimestamp: number,
			StartOffset: number,
			EndOffset: number,
		},
		OnDelete: () -> (),
		OnEditClip: (AudioClip) -> ()
	}, maid)

	local ClipState = maid:Add(Blend.State(table.clone(props.ClipData)))

	maid:GiveTask(ClipState:Observe():Pipe {
		Rx.throttleTime(1, { leading = true, trailing = true })
	}:Subscribe(function(state)
		if not Sift.Dictionary.equalsDeep(state, props.ClipData) then
			props.OnEditClip(state)
		end
	end))

	return UI.Div {

		LayoutOrder = i,

		Size = UDim2.new(1,0,0,30),

		UI.Padding { Left = 5, Right = 5, Top = 0, Bottom = 0 },
		Blend.New "UIStroke" { Thickness = 1 },
		Blend.New "UIListLayout" {
			Padding = UDim.new(0, 0),
			FillDirection = Enum.FillDirection.Horizontal,
		},

		Blend.New "TextBox" {
			LayoutOrder = 0,
			BackgroundTransparency = 1,
			
			Size = UDim2.fromOffset(140, 30),
			Text = props.ClipData.AssetId,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			PlaceholderText = "Asset ID",

			[Blend.OnChange "Text"] = function(text)
				ClipState.Value = Sift.Dictionary.set(ClipState.Value, "AssetId", text)
			end,
		},

		Blend.New "TextLabel" {
			LayoutOrder = 1,
			BackgroundTransparency = 1,

			Size = UDim2.fromOffset(40, 30),
			Text = "Start:",
			TextXAlignment = Enum.TextXAlignment.Left,
		},

		Blend.New "Frame" {
			LayoutOrder = 2,
			Size = UDim2.fromOffset(60, 30),
			BackgroundTransparency = 1,
			
			UI.Padding { Offset = 5, },
			
			Blend.New "TextBox" {
				BorderSizePixel = 1,
				Size = UDim2.fromScale(1,1),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = props.ClipData.StartTimestamp, -- Set initial value
				TextWrapped = true,

				[Blend.OnChange "Text"] = function(text)
					ClipState.Value = Sift.Dictionary.set(ClipState.Value, "StartTimestamp", tonumber(text))
				end,
			},
		},

		Blend.New "TextLabel" {
			LayoutOrder = 3,
			BackgroundTransparency = 1,

			Size = UDim2.fromOffset(60, 30),
			Text = "StartOffset:",
			TextXAlignment = Enum.TextXAlignment.Left,
		},

		Blend.New "Frame" {
			LayoutOrder = 4,
			Size = UDim2.fromOffset(60, 30),
			BackgroundTransparency = 1,

			UI.Padding { Offset = 5, },

			Blend.New "TextBox" {
				BorderSizePixel = 1,
				Size = UDim2.fromScale(1,1),

				TextXAlignment = Enum.TextXAlignment.Left,

				Text = props.ClipData.StartOffset, -- Set initial value
				TextWrapped = true,
				[Blend.OnChange "Text"] = function(text)
					ClipState.Value = Sift.Dictionary.set(ClipState.Value, "StartOffset", tonumber(text))
				end,
			},
		},

		Blend.New "TextLabel" {
			LayoutOrder = 5,
			BackgroundTransparency = 1,

			Size = UDim2.fromOffset(60, 30),
			Text = "EndOffset:",
			TextXAlignment = Enum.TextXAlignment.Left,
		},

		Blend.New "Frame" {
			LayoutOrder = 6,
			Size = UDim2.fromOffset(60, 30),
			BackgroundTransparency = 1,

			UI.Padding { Offset = 5, },

			Blend.New "TextBox" {
				BorderSizePixel = 1,
				Size = UDim2.fromScale(1,1),

				TextXAlignment = Enum.TextXAlignment.Left,

				Text = props.ClipData.EndOffset, -- Set initial value
				TextWrapped = true,
				[Blend.OnChange "Text"] = function(text)
					ClipState.Value = Sift.Dictionary.set(ClipState.Value, "EndOffset", tonumber(text))
				end,
			},
		},

		UI.Div {
			LayoutOrder = 7,
			Size = UDim2.fromOffset(50, 30),
			
			Blend.New "TextButton" {
				AnchorPoint = Vector2.new(0.5,0.5),
				Position = UDim2.fromScale(0.5,0.5),
				Size = UDim2.fromOffset(40, 25),
				Text = "Delete",
				TextColor3 = Color3.new(1,1,1),
				BackgroundColor3 = BrickColor.new("Tr. Red").Color,

				[Blend.OnEvent "Activated"] = function()
					props.OnDelete()
				end
			},
		},

	}
end

type CharacterVoices = {
	-- Key is CharacterId
	[string]: {
		CharacterName: string,
		Clips: {
			{
				AssetId: string,
				StartTimestamp: number,
				StartOffset: number,
				EndOffset: number,
			}
		}
	}
}

local checkCharacterVoices = t.map(t.string, t.strictInterface {
	CharacterName = t.string,
	Clips = t.array (checkAudioClip)
})

return function(props: {
	Replay: {
		ReplayId: string,
		ReplayName: string,
	},
	OnClose: () -> (),
	FetchCharacterVoices: () -> CharacterVoices,
	SaveCharacterVoicesPromise: (CharacterVoices) -> typeof(Promise)
})

	local maid = Maid.new()
	local CharacterVoices = maid:Add(Blend.State({}))
	local SyncState = maid:Add(Blend.State("Synced"))

	maid:GiveTask(task.spawn(function()
		CharacterVoices.Value = Sift.Dictionary.copyDeep(props.FetchCharacterVoices() or {})
		maid:GiveTask(CharacterVoices.Changed:Connect(function()
			SyncState.Value = "OutOfSync"
		end))
	end))

	return UI.RoundedBackplate {
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromOffset(550, 300),

		BackgroundColor3 = Color3.new(1,1,1),

		Blend.New "UIStroke" { Thickness = 2 },

		UI.TextLabel {
			Text = "Replay Editor",
			FontFace = Font.fromName("Merriweather"),
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			AnchorPoint = Vector2.new(0,0),
			Position = UDim2.fromOffset(10,0),
			Size = UDim2.new(1,0,0, 50),
		},
		
		UI.TextLabel {
			RichText = true,
			Text = `<u>{props.Replay.ReplayName}</u>`,
			FontFace = Font.fromName("Merriweather", Enum.FontWeight.ExtraBold),
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5,0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.new(1,0,0, 50),
		},

		Blend.New "TextButton" {
			Visible = Blend.Computed(SyncState, function(state)
				return state == "OutOfSync"
			end),
			AnchorPoint = Vector2.new(1,0.5),
			Position = UDim2.new(1,-100,0,25),
			Size = UDim2.new(0,50,0,40),
			BackgroundColor3 = BrickColor.Blue().Color,

			Text = "Discard Changes",
			TextWrapped = true,

			[Blend.OnEvent "Activated"] = function()
				CharacterVoices.Value = Sift.Dictionary.copyDeep(props.FetchCharacterVoices() or {})
				SyncState.Value = "Synced"
			end,
		},

		Blend.New "TextButton" {
			Visible = Blend.Computed(SyncState, function(state)
				return state == "OutOfSync"
			end),
			AnchorPoint = Vector2.new(1,0.5),
			Position = UDim2.new(1,-50,0,25),
			Size = UDim2.new(0,40,0,40),
			BackgroundColor3 = BrickColor.Green().Color,

			Text = "Save",

			[Blend.OnEvent "Activated"] = function()
				local characterVoices = CharacterVoices.Value
				local pass, msg = checkCharacterVoices(characterVoices)
				if not pass then
					warn(msg)
					warn(characterVoices)
					SyncState.Value = "Fail"
					return
				end

				SyncState.Value = "Saving"
				local promise = props.SaveCharacterVoicesPromise(CharacterVoices.Value)
				promise:Then(function()
					CharacterVoices.Value = Sift.Dictionary.copyDeep(props.FetchCharacterVoices() or {})
					SyncState.Value = "Synced"
				end, function(...)
					warn(...)
					SyncState.Value = "Fail"
					task.delay(1, function()
						SyncState.Value = "OutOfSync"
					end)
				end)
			end,
		},

		Blend.New "TextLabel" {
			Visible = Blend.Computed(SyncState, function(state)
				return state == "Saving" or state == "Fail"
			end),
			AnchorPoint = Vector2.new(1,0.5),
			Position = UDim2.new(1,-50,0,25),
			Size = UDim2.new(0,40,0,40),
			BackgroundColor3 = Blend.Computed(SyncState, function(state)
				if state == "Fail" then
					return BrickColor.Red().Color
				else
					return BrickColor.Gray().Color
				end
			end),

			Text = SyncState,
		},

		UI.HLine {
			ZIndex = 10,
			Position = UDim2.new(0.5, 0, 0, 50-2),
			Size = UDim2.new(1, 0, 0, 4),
			BackgroundColor3 = Color3.new(),
		},

		UI.Div {
			AnchorPoint = Vector2.new(1,0),
			Position = UDim2.fromScale(1,0),
			Size = UDim2.fromOffset(50,50),
			
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
		
		Blend.New "ScrollingFrame" {
			Position = UDim2.fromOffset(0,50),
			Size = UDim2.new(1,0, 1, -50),
			BackgroundTransparency = 1,
			CanvasSize = Blend.Computed(CharacterVoices, function(voices)
				if not next(voices) then
					return UDim2.fromScale(1,1)
				end
				local height = 0
				for _, voice in voices do
					height += 40 + (#voice.Clips) * 31
				end
				return UDim2.new(1, 0, 0, height)
			end),
			ScrollingDirection = Enum.ScrollingDirection.Y,

			Blend.New "UIListLayout" {
				Padding = UDim.new(0, 1),
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.Name,
			},

			Blend.ComputedPairs(CharacterVoices, function(characterId: string, characterVoice, characterMaid)
				
				local height = 40 + (#characterVoice.Clips) * 31

				return UI.Div {
					Name = characterId,
					BorderSizePixel = 1,
					Size = UDim2.new(1, 0, 0, height),

					Blend.New "UIListLayout" {
						Padding = UDim.new(0, 1),
						FillDirection = Enum.FillDirection.Vertical,
					},

					UI.Div {
						Size = UDim2.new(1, -10, 0, 40),

						UI.Padding { Left = 5, Right = 5, },
						Blend.New "UIListLayout" {
							Padding = UDim.new(0, 5),
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
						},
						
						Blend.New "TextLabel" {
							Size = UDim2.fromOffset(100, 30),
							LayoutOrder = 0,
							Text = characterVoice.CharacterName,
							BackgroundTransparency = 1,
							TextXAlignment = Enum.TextXAlignment.Left,
							FontFace = Font.fromName("Merriweather", Enum.FontWeight.Bold),
							TextSize = 16,
						},

						Blend.New "TextButton" {
							Text = "AddClip",
							BorderSizePixel = 1,
							BackgroundColor3 = BrickColor.new("Bright green").Color:Lerp(Color3.new(1,1,1), 0.3),
							Size = UDim2.fromOffset(40, 25),

							[Blend.OnEvent "Activated"] = function()
								CharacterVoices.Value = Sift.Dictionary.set(CharacterVoices.Value, characterId,
									Sift.Dictionary.set(characterVoice, "Clips",
										Sift.Array.append(characterVoice.Clips, {
											AssetId = "ASSETID",
											StartTimestamp = 0,
											StartOffset = 0,
											EndOffset = 0,
										})
									)
								)
							end,
						}
					},

					Blend.ComputedPairs(characterVoice.Clips, function(j, clip, clipMaid)
						return clipEntry(j, {
							ClipData = {
								AssetId = clip.AssetId,
								StartTimestamp = clip.StartTimestamp,
								StartOffset = clip.StartOffset,
								EndOffset = clip.EndOffset,
							},
							OnDelete = function()
								CharacterVoices.Value = Sift.Dictionary.set(CharacterVoices.Value, characterId,
									Sift.Dictionary.set(characterVoice, "Clips",
										Sift.Array.removeIndex(characterVoice.Clips, j)
									)
								)
							end,
							OnEditClip = function(editedClip: AudioClip)
								SyncState.Value = "OutOfSync"
								CharacterVoices.Value[characterId] =
									Sift.Dictionary.set(characterVoice, "Clips",
										Sift.Array.set(characterVoice.Clips, j, editedClip)
									)
							end,
						}, clipMaid)
					end)
				}
			end)
		},
	}
end
