local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local t = require(ReplicatedStorage.Packages.t)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)

local updateAnchoredFromInputs = require(script.Parent.updateAnchoredFromInputs)

local checkRecord = t.interface {
	HumanoidDescription = t.instanceOf("HumanoidDescription"),
	HumanoidRigType = t.enum(Enum.HumanoidRigType),
	Timeline = t.table,
	VisibleTimeline = t.table,
	ChalkTimeline = t.table,
	CharacterId = t.string,
	CharacterName = t.string,
}

local function cloneChalkTemplate(): Tool
	local chalkTemplate = ReplicatedStorage:FindFirstChild("Chalk")
	local checkChalk = t.instanceOf("Tool", {
		Handle = t.instanceOf("MeshPart", {
			Attachment = t.instanceOf("Attachment")
		})
	})
	if not checkChalk(chalkTemplate) then
		error("[VRCharacterReplay] Expected Chalk in ReplicatedStorage")
	end

	return chalkTemplate:Clone()
end

local function getCharacter(record)
	local character = Players:CreateHumanoidModelFromDescription(record.HumanoidDescription, record.HumanoidRigType)

	-- Needed for updateAnchoredFromInputs
	local checkCharacter = t.instanceOf("Model", {

		["Humanoid"] = t.instanceOf("Humanoid"),
	
		["HumanoidRootPart"] = t.instanceIsA("BasePart"),
		["Head"] = t.instanceIsA("BasePart"),
		["RightLowerArm"] = t.instanceIsA("BasePart"),
		["RightUpperArm"] = t.instanceIsA("BasePart"),
		["RightUpperLeg"] = t.instanceIsA("BasePart"),
		["RightLowerLeg"] = t.instanceIsA("BasePart"),
		["RightFoot"] = t.instanceIsA("BasePart"),
		["LeftUpperLeg"] = t.instanceIsA("BasePart"),
		["LeftLowerLeg"] = t.instanceIsA("BasePart"),
		["LeftFoot"] = t.instanceIsA("BasePart"),
		["UpperTorso"] = t.instanceIsA("BasePart"),
		["LowerTorso"] = t.instanceIsA("BasePart"),
		["LeftUpperArm"] = t.instanceIsA("BasePart"),
		["LeftLowerArm"] = t.instanceIsA("BasePart"),
		["LeftHand"] = t.instanceIsA("BasePart"),
		["RightHand"] = t.instanceIsA("BasePart"),
	})

	assert(checkCharacter(character))

	-- Motors doesn't seem to work, we anchor all parts and tween them manually
	character.HumanoidRootPart.Anchored = true
	character.Head.Anchored = true
	character.RightLowerArm.Anchored = true
	character.RightUpperArm.Anchored = true
	character.RightUpperLeg.Anchored = true
	character.RightLowerLeg.Anchored = true
	character.RightFoot.Anchored = true
	character.LeftUpperLeg.Anchored = true
	character.LeftLowerLeg.Anchored = true
	character.LeftFoot.Anchored = true
	character.UpperTorso.Anchored = true
	character.LowerTorso.Anchored = true
	character.LeftUpperArm.Anchored = true
	character.LeftLowerArm.Anchored = true
	character.LeftHand.Anchored = true
	character.RightHand.Anchored = true

	character.Humanoid.DisplayName = "▶️-"..record.CharacterName

	return character
end

local function toNexusVRCharacter(character: Model)
	local checkModulePath = t.children {
		NexusVRCharacterModel = t.children { Character = t.instanceOf("ModuleScript") }
	}
	local success, msg = checkModulePath(ReplicatedStorage)
	if not success then
		error(`[VRCharacterRecorder] Expected Character ModuleScript at ReplicatedStorage.NexusVRCharacterModel.Character: {msg}`)
	end
	return require(ReplicatedStorage.NexusVRCharacterModel.Character :: ModuleScript).new(character)
end

local function VRCharacterReplay(record, origin: CFrame)
	assert(checkRecord(record))
	assert(t.CFrame(origin))

	-- Will error if can't properly create these
	local chalk = cloneChalkTemplate()
	local character = getCharacter(record)
	local nexusVRCharacter = toNexusVRCharacter(character)

	local maid = Maid.new()
	local self = { Destroy = maid:Wrap() }

	maid:GiveTask(chalk)
	maid:GiveTask(character)
	-- nexusVRCharacter doesn't need to be destroyed

	local Active = maid:Add(Blend.State(false, "boolean"))
	local CharacterParent = maid:Add(Blend.State(nil))
	local ChalkParent = maid:Add(Blend.State(false))
	
	local timelineIndex = 1
	local visibleTimelineIndex = 1
	local chalkTimelineIndex = 1
	local finished = false

	local function updateCharacter(event, instantly: true?): ()
		local headRel = event[2]
		local leftHandRel = event[3]
		local rightHandRel = event[4]
		updateAnchoredFromInputs(nexusVRCharacter, origin * headRel, origin * leftHandRel, origin * rightHandRel, instantly)
	end

	local function updateCharacterVisible(event)
		CharacterParent.Value = event[2] and workspace or nil
	end

	local function updateChalkEquipped(event)
		ChalkParent.Value = event[2] and character or nil
	end

	function self.SetActive(value)
		Active.Value = value
	end

	function self.Init()
		timelineIndex = 1
		visibleTimelineIndex = 1
		chalkTimelineIndex = 1
		finished = false

		if #record.Timeline >= 1 then
			updateCharacter(record.Timeline[1], true)
		end
		if #record.VisibleTimeline >= 1 then
			updateCharacterVisible(record.VisibleTimeline[1])
		end
		if #record.ChalkTimeline >= 1 then
			updateChalkEquipped(record.ChalkTimeline[1])
		end
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

		table.insert(cleanup, Blend.mount(character, {
			Parent = CharacterParent,
		}))
		
		table.insert(cleanup, Blend.mount(chalk, {
			Parent = ChalkParent,
		}))

		table.insert(cleanup, function()
			character.Parent = nil
		end)
	end))

	function self.UpdatePlayhead(playhead: number)
		while timelineIndex <= #record.Timeline do
			local event = record.Timeline[timelineIndex]
			if event[1] <= playhead then
				updateCharacter(event)
				timelineIndex += 1
				continue
			end
			break
		end
	
		while visibleTimelineIndex <= #record.VisibleTimeline do
			local event = record.VisibleTimeline[visibleTimelineIndex]
			if event[1] <= playhead then
				updateCharacterVisible(event)
				visibleTimelineIndex += 1
				continue
			end
			break
		end
	
		while chalkTimelineIndex <= #record.ChalkTimeline do
			local event = record.ChalkTimeline[chalkTimelineIndex]
			if event[1] <= playhead then
				updateChalkEquipped(event)
				chalkTimelineIndex += 1
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

export type VRCharacterReplay = typeof(VRCharacterReplay(nil :: any, nil :: any))

return VRCharacterReplay