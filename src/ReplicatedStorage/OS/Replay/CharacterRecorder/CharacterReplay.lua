local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local t = require(ReplicatedStorage.Packages.t)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)

local function getCharacter(record)
	local character = Players:CreateHumanoidModelFromDescription(record.HumanoidDescription, record.HumanoidRigType)
	character.Humanoid.DisplayName = "▶️-"..record.CharacterName

	return character
end

local checkRecord = t.interface {
	HumanoidDescription = t.instanceOf("HumanoidDescription"),
	HumanoidRigType = t.enum(Enum.HumanoidRigType),
	Timeline = t.table,
	VisibleTimeline = t.table,
	CharacterId = t.string,
	CharacterName = t.string,
}

local function CharacterReplay(record, origin: CFrame)
	assert(checkRecord(record))
	assert(t.CFrame(origin))

	local maid = Maid.new()
	local self = { Destroy = maid:Wrap() }

	local character = getCharacter(record)
	maid:GiveTask(character)

	local Active = maid:Add(Blend.State(false, "boolean"))
	local RootCFrame = maid:Add(Blend.State(nil))
	local CharacterParent = maid:Add(Blend.State(nil))
	
	local timelineIndex = 1
	local visibleTimelineIndex = 1
	local finished = false

	if #record.Timeline > 0 then
		local relativeCFrame = record.Timeline[1][2]
		RootCFrame.Value = origin * relativeCFrame
		character:PivotTo(origin * relativeCFrame)
	end

	function self.SetActive(value)
		Active.Value = value
	end

	function self.Init()
		timelineIndex = 1
		visibleTimelineIndex = 1
		finished = false
	end

	function self.IsFinished()
		return finished
	end

	maid:GiveTask(Active:Observe():Subscribe(function(active: boolean)
		if not active then
			maid._playing = nil
			return
		end

		local cleanup = {}
		maid._playing = cleanup

		--[[
			This animation part will be replaced when the humanoid state is stored
			in a timeline. Then it will be easier to play the right animation track.
		]]
		local animator: Animator = character.Humanoid.Animator
		local runAnim = character.Animate.run.RunAnim
		local RunTrack = Blend.State(nil)

		local lastMoved = nil
		table.insert(cleanup, Blend.Computed(RunTrack, RootCFrame, function(runTrack: AnimationTrack, _rootCFrame)
			lastMoved = os.clock()
			if runTrack and not runTrack.IsPlaying then
				runTrack:Play()
			end
		end):Subscribe())

		table.insert(cleanup, Blend.Computed(CharacterParent, function(parent)
			if parent == workspace then
				if RunTrack.Value then
					RunTrack.Value:Stop()
				end
				RunTrack.Value = animator:LoadAnimation(runAnim)
			end
		end):Subscribe())

		table.insert(cleanup, RunService.Heartbeat:Connect(function()
			if lastMoved and os.clock() - lastMoved >= 2 * 1/30 then
				lastMoved = nil
				local runTrack = RunTrack.Value
				if runTrack then
					runTrack:Stop()
				end
			end
		end))

		table.insert(cleanup, function()
			character.Parent = nil
		end)

		table.insert(cleanup, Blend.mount(character, {

			Parent = CharacterParent,

			Blend.New "AlignPosition" {
				Position = Blend.Computed(RootCFrame, function(cframe)
					return (cframe or CFrame.new()).Position
				end),
				Mode = Enum.PositionAlignmentMode.OneAttachment,
				Attachment0 = character.HumanoidRootPart.RootAttachment,
				MaxForce = math.huge,
				MaxVelocity = 100,
				Parent = character,
				Responsiveness = 100,
			},
			
			Blend.New "AlignOrientation" {
				CFrame = RootCFrame,
				Mode = Enum.OrientationAlignmentMode.OneAttachment,
				Attachment0 = character.HumanoidRootPart.RootAttachment,
			}
		}))
	end))

	function self.UpdatePlayhead(playhead: number)
		while timelineIndex <= #record.Timeline do

			local event = record.Timeline[timelineIndex]
			if event[1] <= playhead then
				local relativeCFrame = event[2]
				RootCFrame.Value = origin * relativeCFrame
				timelineIndex += 1
				continue
			end
	
			break
		end
	
		while visibleTimelineIndex <= #record.VisibleTimeline do
	
			local event = record.VisibleTimeline[visibleTimelineIndex]
			if event[1] <= playhead then
				local visible = event[2]
				CharacterParent.Value = visible and workspace or nil
				visibleTimelineIndex += 1
				continue
			end
	
			break
		end
	
		-- Check finished
		if timelineIndex > #record.Timeline and visibleTimelineIndex > #record.VisibleTimeline then
			finished = true
		end
	end
		

	return self
end

return CharacterReplay