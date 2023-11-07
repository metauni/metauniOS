local HttpService = game:GetService("HttpService")
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

function CharacterRecorder.new(playerUserId: number, origin: CFrame)
	local self =  setmetatable(BaseObject.new(), CharacterRecorder)

	self.Origin = origin
	self.PlayerUserId = playerUserId

	return self
end

function CharacterRecorder:_observeRootPartCFrame()
	return Rx.of(Players):Pipe {
		Rxi.findFirstChild(tostring(self.PlayerUserId)),
		Rxi.property("Character"),
		Rxi.findFirstChild("HumanoidRootPart"),
		Rx.switchMap(function(rootPart)
			if not rootPart then
				return Rx.of(nil)
			end
			return Rx.observable(function(sub)
				sub:Fire(rootPart.CFrame)
				return task.spawn(function()
					while true do
						task.wait(RECORDING_FREQUENCY)
						sub:Fire(rootPart.CFrame)
					end
				end)
			end)
		end)
	}
end

function CharacterRecorder:_isCFrameChanged(cframe: CFrame?)
	if #self.Timeline > 0 then
		return true
	end

	local lastCFrame = self.Timeline[#self.Timeline][2]
	if not lastCFrame then
		return cframe ~= nil
	elseif not cframe then
		return lastCFrame ~= nil
	end

	return (cframe.Position - lastCFrame.Position).Magnitude > EPSILON
		or math.acos(cframe.LookVector:Dot(lastCFrame.LookVector)) > EPSILON_ANGLE
end

function CharacterRecorder:Start(startTime)
	
	local originInverse = self.Origin:Inverse()
	
	-- Start time is passed as argument for consistency between recorders
	self.StartTime = startTime
	self.Timeline = {}

	self._maid._recording = self:_observeRootPartCFrame()
		:Subscribe(function(rootPart: BasePart?)
			local now = os.clock() - self.StartTime
			local relativeCFrame = rootPart and originInverse * rootPart.CFrame or nil
			if not self:_isCFrameChanged(relativeCFrame) then
				return
			end
			table.insert(self.Timeline, {now, relativeCFrame})
		end)
end

function CharacterRecorder:Stop()
	self._maid._recording = nil
end

function CharacterRecorder:FlushTimelineToRecord()
	local record = {
		Timeline = self.Timeline,
	}
	self.Timeline = {}
	return record
end

local NUM_LENGTH_EST = 20 -- Average is about 19.26
local SCAFFOLD = #[[{"Timeline":{}}]]
local EVENT_SIZE = #HttpService:JSONEncode({os.clock(), })

function CharacterRecorder:GetRecordSizeEstimate()
	-- events * (maxsize * numNums + eventbraces + eventComma)
	return #self.Timeline * (NUM_LENGTH_EST * 2 + 2 + 1) + SCAFFOLD
end

return CharacterRecorder
