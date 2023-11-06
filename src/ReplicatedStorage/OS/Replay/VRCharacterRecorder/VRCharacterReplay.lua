-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replay = script.Parent.Parent

-- Imports
local t = require(Replay.Parent.t)
local NexusVRCharacterModel = require(ReplicatedStorage:WaitForChild("NexusVRCharacterModel"))
local Character = NexusVRCharacterModel:GetResource("Character")

-- Helper functions
local updateAnchoredFromInputs = require(script.Parent.updateAnchoredFromInputs)

local VRCharacterReplay = {}
VRCharacterReplay.__index = VRCharacterReplay

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

local checkReplayArgs = t.strictInterface({

	Origin = t.CFrame,
	Character = checkCharacter,
})

local checkRecord = t.strictInterface({ Timeline = t.array(t.table) })

function VRCharacterReplay.new(record, replayArgs)

	assert(checkRecord(record))
	assert(checkReplayArgs(replayArgs))

	return setmetatable({

		Record = record,
		Origin = replayArgs.Origin,
		Character = replayArgs.Character,
		NexusCharacter = Character.new(replayArgs.Character)
	}, VRCharacterReplay)
end

function VRCharacterReplay:Init()

	for _, child in ipairs(self.Character:GetChildren()) do
			
		if child:IsA("BasePart") then
			
			child.Anchored = true
		end
	end

	-- Initial values

	self.TimelineIndex = 1
	self.Finished = false
end

function VRCharacterReplay:PlayUpTo(playhead: number)

	while self.TimelineIndex <= #self.Record.Timeline do

		local event = self.Record.Timeline[self.TimelineIndex]

		if event[1] <= playhead then
		
			updateAnchoredFromInputs(
				self.NexusCharacter,
				self.Origin * CFrame.new(unpack(event, 2, 4))   * CFrame.fromEulerAnglesXYZ(unpack(event, 5, 7)),
				self.Origin * CFrame.new(unpack(event, 8, 10))  * CFrame.fromEulerAnglesXYZ(unpack(event, 11, 13)),
				self.Origin * CFrame.new(unpack(event, 14, 16)) * CFrame.fromEulerAnglesXYZ(unpack(event, 17, 19)),
				false
			)

			self.TimelineIndex += 1
			continue
		end

		break
	end

	-- Check finished

	if self.TimelineIndex > #self.Record.Timeline then

		self.Finished = true
	end
end

return VRCharacterReplay