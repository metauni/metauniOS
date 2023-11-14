local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseObject = require(ReplicatedStorage.Util.BaseObject)
local Rx = require(ReplicatedStorage.Util.Rx)
local Rxi = require(ReplicatedStorage.Util.Rxi)

local EPSILON = 0.001
local EPSILON_ANGLE = math.rad(1)
local RECORDING_FREQUENCY = 1/30

local CharacterRecorder = {}
CharacterRecorder.__index = CharacterRecorder

function CharacterRecorder.new(characterId: string, playerUserId: number, origin: CFrame)
	local self =  setmetatable(BaseObject.new(), CharacterRecorder)

	self.RecorderType = "CharacterRecorder"
	self.CharacterId = characterId
	self.PlayerUserId = playerUserId
	self.Origin = origin

	-- Set the humanoid data as soon as it is available (happens at most once)
	-- Very likely happens immediately
	self._maid:GiveTask(Rxi.playerOfUserId(self.PlayerUserId):Pipe {
		Rxi.property("Character"),
		Rxi.findFirstChild("Humanoid"),
		Rxi.findFirstChild("HumanoidDescription"),
		Rxi.notNil(),
		Rx.take(1),
	}:Subscribe(function(humanoidDescription: HumanoidDescription)
		local humanoid: Humanoid = humanoidDescription.Parent :: any
		self.HumanoidDescription = humanoidDescription:Clone()
		self.HumanoidRigType = humanoid.RigType
	end))

	return self
end

function CharacterRecorder:FlushToRecord()

	local humanoidDescription = self.HumanoidDescription
	local humanoidRigType = self.HumanoidRigType
	if not humanoidDescription or not humanoidRigType then
		-- This is async
		humanoidDescription = Players:GetHumanoidDescriptionFromUserId(self.PlayerUserId)
		humanoidRigType = Enum.HumanoidRigType.R15
	end

	local record = {
		RecordType = "CharacterRecord",

		PlayerUserId = self.PlayerUserId,
		CharacterId = self.CharacterId,
		HumanoidDescription = humanoidDescription, 
		HumanoidRigType = humanoidRigType, 

		Timeline = self.Timeline,
		VisibleTimeline = self.VisibleTimeline,
	}
	self.Timeline = {}
	self.VisibleTimeline = {}
	return record
end

function CharacterRecorder:_observeRootPart()
	return Rxi.playerOfUserId(self.PlayerUserId):Pipe {
		Rxi.property("Character"),
		Rxi.findFirstChild("HumanoidRootPart"),
	}
end

function CharacterRecorder:_observeCharacterPivot()
	-- We observe the rootPart before emitting GetPivot() values
	return self:_observeRootPart():Pipe {
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

function CharacterRecorder:Start(startTime)
	
	local originInverse = self.Origin:Inverse()
	
	-- Start time is passed as argument for consistency between recorders
	self.StartTime = startTime
	self.Timeline = {}
	self.VisibleTimeline = {}

	local cleanup = {}
	self._maid._recording = cleanup

	table.insert(cleanup, self:_observeCharacterPivot()
		:Subscribe(function(rootPartCFrame: CFrame)
			local now = os.clock() - self.StartTime
			print("Y", rootPartCFrame.Y)
			local relativeCFrame = originInverse * rootPartCFrame
			if isCFrameChanged(relativeCFrame, self.Timeline) then
				table.insert(self.Timeline, {now, relativeCFrame})
			end
		end)
	)

	table.insert(cleanup, self:_observeRootPart()
		:Subscribe(function(rootPart: BasePart?)
			local now = os.clock() - self.StartTime
			local visible = rootPart ~= nil
			table.insert(self.VisibleTimeline, {now, visible})
		end)
	)
end

function CharacterRecorder:Stop()
	self._maid._recording = nil
end

return CharacterRecorder
