local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Serialiser = require(script.Parent.Serialiser)
local t = require(ReplicatedStorage.Packages.t)
local Maid = require(ReplicatedStorage.Util.Maid)
local Rx = require(ReplicatedStorage.Util.Rx)
local Rxi = require(ReplicatedStorage.Util.Rxi)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)

export type VRCharacterRecord = {
	RecordType: "VRCharacterRecord",

	PlayerUserId: number,
	CharacterId: string,
	CharacterName: string,
	HumanoidDescription: HumanoidDescription, 
	HumanoidRigType: Enum.HumanoidRigType, 

	Timeline: {any},
	VisibleTimeline: {any},
	ChalkTimeline: {any},
}

local function getUpdateInputsRemoteEvent(): RemoteEvent
	local NexusVRCharacterModelScript = ReplicatedStorage:FindFirstChild("NexusVRCharacterModel")
	assert(t.instanceOf("ModuleScript")(NexusVRCharacterModelScript), "[VRCharacterRecorder] Expected NexusVRCharacterModel in ReplicatedStorage")
	local remoteEvent = NexusVRCharacterModelScript:FindFirstChild("UpdateInputs")
	assert(t.instanceOf("RemoteEvent")(remoteEvent), "[VRCharacterRecorder] Expected UpdateInputs RemoteEvent in NexusVRCharacterModel.")
	return remoteEvent
end

local function observeRootPart(userId: number)
	return Rxi.playerOfUserId(userId):Pipe {
		Rxi.property("Character"),
		Rxi.findFirstChild("HumanoidRootPart"),
	}
end

local function observeChalk(userId: number)
	return Rxi.playerOfUserId(userId):Pipe {
		Rxi.property("Character"),
		Rxi.findFirstChildWithClassOf("Tool", "Chalk")
	}
end

local function promiseHumanoidDataFromCharacter(userId: number)
	return Rx.toPromise(Rxi.playerOfUserId(userId):Pipe {
		Rxi.property("Character"),
		Rxi.findFirstChild("Humanoid"),
		Rxi.findFirstChild("HumanoidDescription"),
		Rxi.notNil(),
		Rx.map(function(humanoidDescription: HumanoidDescription)
			local humanoid: Humanoid = humanoidDescription.Parent :: any
			return humanoidDescription:Clone(), humanoid.RigType
		end),
	})
end

local function getHumanoidDataFromPlayerUserIdAsync(userId: number)
	local humanoidDescription = Players:GetHumanoidDescriptionFromUserId(userId)
	local humanoidRigType = Enum.HumanoidRigType.R15
	return humanoidDescription, humanoidRigType
end

export type VRCharacterRecorderProps = {
	Origin: CFrame,
	CharacterName: string,
	CharacterId: string,
	PlayerUserId: number,
}
local checkProps = t.strictInterface {
	Origin = t.CFrame,
	CharacterName = t.string,
	CharacterId = t.string,
	PlayerUserId = t.integer,
}

local function VRCharacterRecorder(props: VRCharacterRecorderProps): VRCharacterRecorder
	assert(checkProps(props))
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap(), props = props, RecorderType = "VRCharacterRecorder" }

	-- Errors if can't find it
	local UpdateInputsRemoteEvent = getUpdateInputsRemoteEvent()
	
	local Timeline = ValueObject.new({})
	local VisibleTimeline = ValueObject.new({})
	local ChalkTimeline = ValueObject.new({})

	local HumanoidDescription = nil
	local HumanoidRigType = nil
	-- Set the humanoid data as soon as it is available
	-- Very likely happens immediately
	local promise = maid:Add(promiseHumanoidDataFromCharacter(props.PlayerUserId))
	promise:Then(function(humanoidDescription, humanoidRigType)
		HumanoidDescription = humanoidDescription
		HumanoidRigType = humanoidRigType
	end)
	
	function self.FlushToRecord(): VRCharacterRecord

		local humanoidDescription = HumanoidDescription
		local humanoidRigType = HumanoidRigType
		if not humanoidDescription or not humanoidRigType then
			humanoidDescription, humanoidRigType = getHumanoidDataFromPlayerUserIdAsync(props.PlayerUserId)
		end

		local record = {
			RecordType = "VRCharacterRecord",

			PlayerUserId = props.PlayerUserId,
			CharacterId = props.CharacterId,
			CharacterName = props.CharacterName,
			HumanoidDescription = humanoidDescription, 
			HumanoidRigType = humanoidRigType, 

			Timeline = Timeline.Value,
			VisibleTimeline = VisibleTimeline.Value,
			ChalkTimeline = ChalkTimeline.Value
		}

		Timeline.Value = {}
		VisibleTimeline.Value = {}
		ChalkTimeline.Value = {}
		return record
	end

	function self.Init()
		Timeline.Value = {}
		VisibleTimeline.Value = {}
		ChalkTimeline.Value = {}
	end

	function self.Start(startTime)
		
		local originInverse = props.Origin:Inverse()

		local cleanup = {}
		maid._recording = cleanup

		table.insert(cleanup, UpdateInputsRemoteEvent.OnServerEvent:Connect(function(player: Player, HeadCFrame: CFrame, LeftHandCFrame: CFrame, RightHandCFrame: CFrame)
			if player.UserId ~= props.PlayerUserId then
				return
			end

			local now = os.clock() - startTime
			local headRel = originInverse * HeadCFrame
			local leftHandRel = originInverse * LeftHandCFrame
			local rightHandRel = originInverse * RightHandCFrame
			table.insert(Timeline.Value, {now, headRel, leftHandRel, rightHandRel})
		end))

		table.insert(cleanup, observeRootPart(props.PlayerUserId)
			:Subscribe(function(rootPart: BasePart?)
				local now = os.clock() - startTime
				local visible = rootPart ~= nil
				table.insert(VisibleTimeline.Value, {now, visible})
			end)
		)

		table.insert(cleanup, observeChalk(props.PlayerUserId)
			:Subscribe(function(chalk: Tool?)
				local now = os.clock() - startTime
				local equipped = chalk ~= nil
				table.insert(ChalkTimeline.Value, {now, equipped})
			end)
		)
	end

	function self.Stop()
		maid._recording = nil
	end

	function self.EstimateBytes(): number
		return Serialiser.estimateVRCharacterRecordBytes(Timeline.Value, VisibleTimeline.Value, ChalkTimeline.Value)
	end

	return self
end

export type VRCharacterRecorder = typeof(VRCharacterRecorder(nil :: any))

return VRCharacterRecorder