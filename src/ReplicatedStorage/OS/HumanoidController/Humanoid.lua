local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local Rx = require(ReplicatedStorage.Util.Rx)
local Rxi = require(ReplicatedStorage.Util.Rxi)
local BaseObject = require(ReplicatedStorage.Util.BaseObject)
local Maid = require(ReplicatedStorage.Util.Maid)

local Humanoid = setmetatable({}, BaseObject)
Humanoid.__index = Humanoid

function Humanoid.new(humanoid: Humanoid)
	local self = setmetatable(BaseObject.new(humanoid), Humanoid)

	return self
end

function Humanoid:Init()
	self._animator = self._obj:WaitForChild("Animator") :: Animator

	self:_initSounds()
	self:_initControls()
end

function Humanoid:_initSounds()
	local RUNNING_SOUND_ID = "rbxassetid://14260445447"
	-- Normalised to WalkSpeed = 16
	local RUNNING_PLAYBACK_FACTOR = 2.3
	local RUNNING_VOLUME = 0.1

	local runningMaid = Maid.new()
	self._maid._runningMaid = runningMaid

	-- Softer running sound
	runningMaid._ = self:_observeSound("Running")
		:Subscribe(function(sound: Sound?)
			if sound then
				-- chopped and EQ'd from https://www.fesliyanstudios.com/royalty-free-sound-effects-download/footsteps-on-grass-284
				-- "Footsteps In Grass Slow A Sound Effect"
				sound.SoundId = RUNNING_SOUND_ID
			end
		end)

	-- Scale playback speed with walkspeed
	runningMaid._ = Rx.combineLatest {
		Sound = self:_observeSound("Running"),
		WalkSpeed = self:_observeWalkSpeed(),
	}:Subscribe(function(state)
		if state.Sound and state.WalkSpeed then
			local nonlinear = math.sqrt(state.WalkSpeed/16)
			state.Sound.PlaybackSpeed = math.max(nonlinear, 1) * RUNNING_PLAYBACK_FACTOR
			state.Sound.Volume = nonlinear * RUNNING_VOLUME
		end
	end)

	-- Restart sound when humanoid stops
	runningMaid._ = Rx.combineLatest {
		Sound = self:_observeSound("Running"),
		MoveDirection = self:_observeMoveDirection(),
	}:Subscribe(function(state)
		if state.Sound and state.MoveDirection then
			if state.MoveDirection.Magnitude == 0 then
				state.Sound.TimePosition = 0
			end
		end
	end)
end

function Humanoid:SetWalkSpeed(speed: number)
	assert(type(speed) == "number", "Bad speed")
	assert(speed > 0, "Bad speed")
	self._walkSpeed = speed
	if not self._sprinting then
		self._obj.WalkSpeed = self._walkSpeed
	end
end

function Humanoid:SetSprintSpeed(speed: number)
	assert(type(speed) == "number", "Bad speed")
	assert(speed > 0, "Bad speed")
	self._sprintSpeed = speed
	if self._sprinting then
		self._obj.WalkSpeed = self._sprintSpeed
	end
end

function Humanoid:_initControls()
	self._sprinting = false
	self:SetWalkSpeed(16)
	self:SetSprintSpeed(24)

	local function handler(BindName, InputState)
		if InputState == Enum.UserInputState.Begin and BindName == 'RunBind' then
			self._sprinting = true
			self._obj.WalkSpeed = self._sprintSpeed
		elseif InputState == Enum.UserInputState.End and BindName == 'RunBind' then
			self._sprinting = false
			self._obj.WalkSpeed = self._walkSpeed 
		end
	end
	
	ContextActionService:BindAction('RunBind', handler, true, Enum.KeyCode.LeftShift)

	self._maid._ = function()
		ContextActionService:UnbindAction("RunBind")
	end
end


export type StateName = 
"Climbing" | "Died" | "FreeFalling" |
"GettingUp" | "Jumping" | "Landing" |
"Running" | "Splash" | "Swimming"


function Humanoid:_observeSound(stateName: StateName)
	return Rx.of(self._obj):Pipe {
		Rxi.property("Parent"),
		Rxi.property("PrimaryPart"),
		Rxi.findFirstChild(stateName),
	}
end

function Humanoid:_observeWalkSpeed()
	return Rx.of(self._obj):Pipe({
		Rxi.property("WalkSpeed"),
	})
end

function Humanoid:_observeMoveDirection()
	return Rx.of(self._obj):Pipe({
		Rxi.property("MoveDirection"),
	})
end

return Humanoid