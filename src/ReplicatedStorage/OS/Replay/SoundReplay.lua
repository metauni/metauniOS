local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local t = require(ReplicatedStorage.Packages.t)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)

--[[
	finishTimestamp = math.max(unpack({timestamp + sound.TimeLength - startOffset, finishTimestamp}))
	if not sound.IsLoaded then
		-- TODO: This is a hack to make it actually preload.
		sound.Parent = workspace
		sound.Loaded:Wait()
		sound.Parent = nil
	end
]]

local checkRecord = t.interface {
	RecordType = t.literal("SoundRecord"),
	Clips = t.array(t.interface {
		AssetId = t.string,
		StartTimestamp = t.number,
		StartOffset = t.number,
		EndOffset = t.number,
	}),
}
local checkProps = t.strictInterface {
	Record = checkRecord,
	SoundParent = t.Instance,
	SoundInstanceProps = t.table,
}

export type SoundRecord = {
	RecordType: "SoundRecord",
	Clips: {{
		AssetId: string,
		StartTimestamp: number,
		StartOffset: number,
		EndOffset: number,
	}},
}

export type Props = {
	Record: SoundRecord,
	SoundParent: Instance,
	SoundInstanceProps: {},
}

local TIMING_TOLERANCE_SECONDS = 1

local function SoundReplay(props: Props): SoundReplay
	assert(checkProps(props))
	local record = props.Record

	local maid = Maid.new()
	local self = { Destroy = maid:Wrap() }

	local Active = maid:Add(Blend.State(false))

	function self.SetActive(value)
		Active.Value = value
	end

	local sounds: {Sound} = {}

	local function mountClips()
		for i, clip in record.Clips do
			if sounds[i] then
				continue
			end

			local sound = maid:Add(Instance.new("Sound"))
			sound.SoundId = clip.AssetId
			sound.Name = `ReplaySound-{i}`
	
			sound.Parent = props.SoundParent
			maid:GiveTask(Blend.mount(sound, props.SoundInstanceProps))
	
			sounds[i] = sound
		end
	end

	mountClips()

	maid:GiveTask(Active:Observe():Subscribe(function(active)
		if not active then
			for _, sound in sounds do
				sound:Pause()
			end
		end
	end))

	function self.Preload()
		local toLoad = {}
		for _, sound in sounds do
			if not sound.IsLoaded then
				table.insert(toLoad, sound)
			end
		end
		if #toLoad > 0 then
			ContentProvider:PreloadAsync(toLoad)
		end
	end
	
	function self.UpdatePlayhead(playhead: number): ()
		if not Active.Value then
			return
		end

		for i=1, #sounds do
			local clip = record.Clips[i]
			local sound = sounds[i]

			local endTimestamp = clip.StartTimestamp + sound.TimeLength - clip.StartOffset - clip.EndOffset
			
			local deltaStart = playhead - clip.StartTimestamp
			local deltaEnd = playhead - endTimestamp
			
			if deltaStart >= 0 and deltaEnd < 0 then
				-- Start playing if not playing, or fix timing if too far off
				if not sound.IsPlaying or math.abs(sound.TimePosition - clip.StartOffset - deltaStart) > TIMING_TOLERANCE_SECONDS then
					sound.TimePosition = clip.StartOffset + deltaStart
					sound:Resume()
				end
			elseif sound.IsPlaying then
				sound:Pause()
			end
		end
	end

	function self.RewindTo(playhead: number): ()
		self.UpdatePlayhead(playhead)
	end
	
	function self.Pause()
		self.SetActive(false)
	end

	function self.ExtendRecord(nextRecord: SoundRecord)
		table.move(nextRecord.Clips, 1, #nextRecord.Clips, #props.Record.Clips + 1, props.Record.Clips)
		mountClips()
	end

	return self
end

export type SoundReplay = typeof(SoundReplay(nil :: any))

return SoundReplay