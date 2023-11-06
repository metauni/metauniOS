-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replay = script.Parent

-- Imports
local t = require(Replay.Parent.t)
local NexusVRCharacterModel = require(ReplicatedStorage:WaitForChild("NexusVRCharacterModel"))
local UpdateInputs = NexusVRCharacterModel:GetResource("UpdateInputs")

local VRCharacterRecorder = {}
VRCharacterRecorder.__index = VRCharacterRecorder

local check = t.strictInterface({

	Origin = t.CFrame,
	Player = t.instanceOf("Player"),
})

function VRCharacterRecorder.new(args)
	
	assert(check(args))

	return setmetatable(args, VRCharacterRecorder)
end

function VRCharacterRecorder:Start(startTime)
	
	-- Start time is passed as argument for consistency between recorders
	self.StartTime = startTime
	self.Timeline = {}
	
	self.CharacterConnection = UpdateInputs.OnServerEvent:Connect(function(player, HeadCFrame, LeftHandCFrame, RightHandCFrame)
		
		local now = os.clock() - self.StartTime
		
		if player ~= self.Player then
			return
		end

		local headRel = self.Origin:Inverse() * HeadCFrame
		local headRx, headRy, headRz = headRel:ToEulerAnglesXYZ()
		local leftHandRel = self.Origin:Inverse() * LeftHandCFrame
		local leftRx, leftRy, leftRz = leftHandRel:ToEulerAnglesXYZ()
		local rightHandRel = self.Origin:Inverse() * RightHandCFrame
		local rightRx, rightRy, rightRz = rightHandRel:ToEulerAnglesXYZ()
		
		table.insert(self.Timeline, {now,
			
			headRel.Position.X,      headRel.Position.Y,      headRel.Position.Z,      headRx, headRy, headRz,
			leftHandRel.Position.X,  leftHandRel.Position.Y,  leftHandRel.Position.Z,  leftRx, leftRy, leftRz,
			rightHandRel.Position.X, rightHandRel.Position.Y, rightHandRel.Position.Z, rightRx, rightRy, rightRz,
		})
	end)
end

function VRCharacterRecorder:Stop()
	
	if self.CharacterConnection then
		self.CharacterConnection:Disconnect()
		self.CharacterConnection = nil
	end
end

function VRCharacterRecorder:FlushTimelineToRecord()

	local record = {

		Timeline = self.Timeline,
	}

	self.Timeline = {}

	return record
end

local NUM_LENGTH_EST = 20 -- Average is about 19.26
local SCAFFOLD = #[[{"Timeline":{}}]]

function VRCharacterRecorder:GetRecordSizeEstimate()
	-- events * (maxsize * numNums + commas + eventbraces + eventComma)
	return #self.Timeline * (NUM_LENGTH_EST * 19 + 18 + 2 + 1) + SCAFFOLD
end

return VRCharacterRecorder