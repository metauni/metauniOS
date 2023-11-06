-- Service
local TweenService = game:GetService("TweenService")

local tweenInfo = TweenInfo.new(1/30, Enum.EasingStyle.Linear)

local function tweenToCFrame(part: BasePart, cframe: CFrame, instantly: boolean?)

	if instantly then
		
		part.CFrame = cframe
	else

		TweenService:Create(part, tweenInfo, {
			CFrame = cframe
		}):Play()
	end
end

--[[
	This is derived from Character:UpdateFromInputs() in NexusVRCharacterModel.
	It tweens or sets the cframes directly, instead of using motors
--]]
return function(nexusCharacter, HeadControllerCFrame: CFrame, LeftHandControllerCFrame: CFrame, RightHandControllerCFrame: CFrame, instantly: boolean?)

	local self = nexusCharacter

	-- From Character:UpdateFromInputs in Nexus VR Character Model

	--Get the CFrames.
	local HeadCFrame = self.Head:GetHeadCFrame(HeadControllerCFrame)
	local NeckCFrame = self.Head:GetNeckCFrame(HeadControllerCFrame)
	local LowerTorsoCFrame,UpperTorsoCFrame = self.Torso:GetTorsoCFrames(NeckCFrame)
	local JointCFrames = self.Torso:GetAppendageJointCFrames(LowerTorsoCFrame,UpperTorsoCFrame)
	local LeftUpperArmCFrame,LeftLowerArmCFrame,LeftHandCFrame = self.LeftArm:GetAppendageCFrames(JointCFrames["LeftShoulder"],LeftHandControllerCFrame)
	local RightUpperArmCFrame,RightLowerArmCFrame,RightHandCFrame = self.RightArm:GetAppendageCFrames(JointCFrames["RightShoulder"],RightHandControllerCFrame)

	--Set the character CFrames.
	--HumanoidRootParts must always face up. This makes the math more complicated.
	--Setting the CFrame directly to something not facing directly up will result in the physics
	--attempting to correct that within the next frame, causing the character to appear to move.
	local LeftFoot,RightFoot = self.FootPlanter:GetFeetCFrames()
	local LeftUpperLegCFrame,LeftLowerLegCFrame,LeftFootCFrame = self.LeftLeg:GetAppendageCFrames(JointCFrames["LeftHip"],LeftFoot * CFrame.Angles(0,math.pi,0))
	local RightUpperLegCFrame,RightLowerLegCFrame,RightFootCFrame = self.RightLeg:GetAppendageCFrames(JointCFrames["RightHip"],RightFoot * CFrame.Angles(0,math.pi,0))
	local TargetHumanoidRootPartCFrame = LowerTorsoCFrame * self.Attachments.LowerTorso.RootRigAttachment.CFrame * self.Attachments.HumanoidRootPart.RootRigAttachment.CFrame:Inverse()
	local ActualHumanoidRootPartCFrame = self.Parts.HumanoidRootPart.CFrame
	local HumanoidRootPartHeightDifference = ActualHumanoidRootPartCFrame.Y - TargetHumanoidRootPartCFrame.Y
	local NewTargetHumanoidRootPartCFrame = CFrame.new(TargetHumanoidRootPartCFrame.Position)

	-- End Character:UpdateFromInputs excerpt

	tweenToCFrame(self.Parts.Head, HeadCFrame, instantly)

	tweenToCFrame(self.Parts.LowerTorso, LowerTorsoCFrame, instantly)
	tweenToCFrame(self.Parts.UpperTorso, UpperTorsoCFrame, instantly)

	tweenToCFrame(self.Parts.LeftUpperArm, LeftUpperArmCFrame, instantly)
	tweenToCFrame(self.Parts.LeftLowerArm, LeftLowerArmCFrame, instantly)
	tweenToCFrame(self.Parts.LeftHand, LeftHandCFrame, instantly)

	tweenToCFrame(self.Parts.RightUpperArm, RightUpperArmCFrame, instantly)
	tweenToCFrame(self.Parts.RightLowerArm, RightLowerArmCFrame, instantly)
	tweenToCFrame(self.Parts.RightHand, RightHandCFrame, instantly)

	tweenToCFrame(self.Parts.LeftUpperLeg, LeftUpperLegCFrame, instantly)
	tweenToCFrame(self.Parts.LeftLowerLeg, LeftLowerLegCFrame, instantly)
	tweenToCFrame(self.Parts.LeftFoot, LeftFootCFrame, instantly)

	tweenToCFrame(self.Parts.RightUpperLeg, RightUpperLegCFrame, instantly)
	tweenToCFrame(self.Parts.RightLowerLeg, RightLowerLegCFrame, instantly)
	tweenToCFrame(self.Parts.RightFoot, RightFootCFrame, instantly)

	tweenToCFrame(self.Parts.HumanoidRootPart, TargetHumanoidRootPartCFrame, instantly)
end