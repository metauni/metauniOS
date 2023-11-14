local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local t = require(ReplicatedStorage.Packages.t)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)

local checkRecord = t.interface {
	HumanoidDescription = t.instanceOf("HumanoidDescription"),
	HumanoidRigType = t.enum(Enum.HumanoidRigType),
	Timeline = t.table,
	VisibleTimeline = t.table,
}

local function CharacterReplay(record, origin: CFrame, characterFromPreviousReplay: Model?)
	assert(checkRecord(record))
	assert(t.CFrame(origin))

	local maid = Maid.new()
	local self = { Destroy = maid:Wrap() }

	local character = characterFromPreviousReplay or Players:CreateHumanoidModelFromDescription(record.HumanoidDescription, record.HumanoidRigType)

	local Active = Blend.State(false, "boolean")
	local RootCFrame = Blend.State()
	local CharacterParent = Blend.State(nil)
	self.Finished = false
	local timelineIndex = 1
	local visibleTimelineIndex = 1

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
		self.Finished = false
	end

	maid:GiveTask(Active:Observe():Subscribe(function(active: boolean)
		if not active then
			maid._playing = nil
			return
		end

		local cleanup = {}
		maid._playing = cleanup

		local animator: Animator = character.Humanoid.Animator
		local runAnim = character.Animate.run.RunAnim
		task.delay(2, function()
			
		end)

		table.insert(cleanup, function()
			character.Parent = nil
		end)

		table.insert(cleanup, Blend.mount(character, {

			[Blend.OnChange "Parent"] = function()
				-- TODO this makes multiple running tracks I think?
				if character.Parent == workspace then
					local runTrack = animator:LoadAnimation(runAnim)
					runTrack:Play()
					table.insert(cleanup, function()
						runTrack:Stop()
					end)
				end
			end,

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
			self.Finished = true
		end
	end
		

	return self
end

return CharacterReplay