local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local t = require(ReplicatedStorage.Packages.t)
local Maid = require(ReplicatedStorage.Util.Maid)
local Rx = require(ReplicatedStorage.Util.Rx)
local Rxi = require(ReplicatedStorage.Util.Rxi)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)

local EPSILON = 0.001
local EPSILON_ANGLE = math.rad(1)
local RECORDING_FREQUENCY = 1/30

local function observeRootPart(userId: number)
	return Rxi.playerOfUserId(userId):Pipe {
		Rxi.property("Character"),
		Rxi.findFirstChild("HumanoidRootPart"),
	}
end

local function observeCharacterPivot(userId: number)
	-- We observe the rootPart before emitting GetPivot() values
	return observeRootPart(userId):Pipe {
		Rx.switchMap(function(rootPart)
			if not rootPart then
				return Rx.never
			end
			return Rx.observable(function(sub)
				sub:Fire(rootPart.Parent:GetPivot())
				return task.spawn(function()
					while true do
						task.wait(RECORDING_FREQUENCY)
						sub:Fire(rootPart.Parent:GetPivot())
					end
				end)
			end)
		end)
	}
end

local function isCFrameChanged(cframe: CFrame, timeline)
	if #timeline <= 0 then
		return true
	end

	local lastCFrame = timeline[#timeline][2]
	return (cframe.Position - lastCFrame.Position).Magnitude > EPSILON
		or math.acos(cframe.LookVector:Dot(lastCFrame.LookVector)) > EPSILON_ANGLE
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

export type CharacterRecorderProps = {
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

local function CharacterRecorder(props: CharacterRecorderProps): CharacterRecorder
	assert(checkProps(props))
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap(), props = props, RecorderType = "CharacterRecorder" }

	local Timeline = ValueObject.new({})
	local VisibleTimeline = ValueObject.new({})

	local HumanoidDescription = nil
	local HumanoidRigType = nil
	-- Set the humanoid data as soon as it is available
	-- Very likely happens immediately
	local promise = maid:Add(promiseHumanoidDataFromCharacter(props.PlayerUserId))
	promise:Then(function(humanoidDescription, humanoidRigType)
		HumanoidDescription = humanoidDescription
		HumanoidRigType = humanoidRigType
	end)
	
	function self.FlushToRecord()

		local humanoidDescription = HumanoidDescription
		local humanoidRigType = HumanoidRigType
		if not humanoidDescription or not humanoidRigType then
			humanoidDescription, humanoidRigType = getHumanoidDataFromPlayerUserIdAsync(props.PlayerUserId)
		end

		local record = {
			RecordType = "CharacterRecord",

			PlayerUserId = props.PlayerUserId,
			CharacterId = props.CharacterId,
			CharacterName = props.CharacterName,
			HumanoidDescription = humanoidDescription, 
			HumanoidRigType = humanoidRigType, 

			Timeline = Timeline.Value,
			VisibleTimeline = VisibleTimeline.Value,
		}

		Timeline.Value = {}
		VisibleTimeline.Value = {}
		return record
	end

	function self.Start(startTime)
		
		local originInverse = props.Origin:Inverse()

		local cleanup = {}
		maid._recording = cleanup

		table.insert(cleanup, observeCharacterPivot(props.PlayerUserId)
			:Subscribe(function(rootPartCFrame: CFrame)
				local now = os.clock() - startTime
				local relativeCFrame = originInverse * rootPartCFrame
				local timeline = Timeline.Value
				if isCFrameChanged(relativeCFrame, timeline) then
					table.insert(timeline, {now, relativeCFrame})
				end
			end)
		)

		table.insert(cleanup, observeRootPart(props.PlayerUserId)
			:Subscribe(function(rootPart: BasePart?)
				local now = os.clock() - startTime
				local visible = rootPart ~= nil
				table.insert(VisibleTimeline.Value, {now, visible})
			end)
		)
	end

	function self.Stop()
		maid._recording = nil
	end

	return self
end

export type CharacterRecorder = typeof(CharacterRecorder(nil :: any))


return CharacterRecorder
