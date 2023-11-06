-- Services
local ContentProvider = game:GetService("ContentProvider")
-- local Replay = script.Parent

-- Imports
-- local t = require(Replay.Parent.t)

local SoundReplay = {}
SoundReplay.__index = SoundReplay

function SoundReplay.new(record, replayArgs)
	
	local self = setmetatable({

		Record = record,
		SoundProps = replayArgs.SoundProps,
	}, SoundReplay)

	self.Sounds = {}

	local finishTimestamp
	
	for _, event in ipairs(self.Record.Timeline) do
		
		local timestamp, assetId, startOffset = unpack(event)
		
		local sound = Instance.new("Sound")
		sound.SoundId = assetId

		ContentProvider:PreloadAsync({sound})

		if not sound.IsLoaded then
			
			-- TODO: This is a hack to make it actually preload.
			sound.Parent = workspace
			sound.Loaded:Wait()

			finishTimestamp = math.max(unpack({timestamp + sound.TimeLength - startOffset, finishTimestamp}))
			
			sound.Parent = nil
		end
		
		for key, value in self.SoundProps do
			
			sound[key] = value
		end


	
		table.insert(self.Sounds, sound)
	end

	self.FinishTimestamp = finishTimestamp
	
	return self
end

function SoundReplay:Destroy()
	
	for _, sound in ipairs(self.Sounds) do
		
		sound:Destroy()
	end
end

function SoundReplay:Init()

	self.TimelineIndex = 1
	self.Finished = false
end

function SoundReplay:PlayUpTo(playhead: number)

	for i=self.TimelineIndex, #self.Record.Timeline do

		local timestamp, _assetId, startOffset = unpack(self.Record.Timeline[i])
		local sound = self.Sounds[i]
		
		local delta = playhead - timestamp
		
		if delta >= 0 then
			
			if delta + startOffset < sound.TimeLength and not sound.IsPlaying then
	
				sound.TimePosition = startOffset + delta
				sound:Resume()
				self.TimelineIndex = i + 1
			end
		end
	end

	-- Check finished

	if playhead >= self.FinishTimestamp then
		
		self.Finished = true
	end
end

function SoundReplay:Resume()
	
	self.TimelineIndex = 1
end

function SoundReplay:Pause()
	
	for _, sound in ipairs(self.Sounds) do
			
		sound:Pause()
	end
end

function SoundReplay:Stop()

	for _, sound in ipairs(self.Sounds) do
			
		sound:Pause()
	end
end

return SoundReplay