local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage.OS.TransportOrbController.Remotes
local Config = require(ReplicatedStorage.OS.TransportOrbController.Config)

local function getInstancePosition(x)
	if x:IsA("BasePart") then return x.Position end
	if x:IsA("Model") and x.PrimaryPart ~= nil then
		return x.PrimaryPart.Position
	end

	return nil
end

local function transportNextStop(orb)
	local orbPart = if orb:IsA("BasePart") then orb else orb.PrimaryPart
	orbPart.Anchored = false
	
	local nextStop = orb.NextStop.Value
	local numStops = orb.NumStops.Value

	nextStop += 1

	if nextStop > numStops then
		nextStop = 1
	end

	orb.NextStop.Value = nextStop

	local stopModel = orb.Stops:FindFirstChild(tostring(nextStop)).Value
	local stopMarker = stopModel.Marker
	local stopTime = stopModel.TimeToThisStop.Value
	
	local alignPos = orbPart:FindFirstChild("AlignPosition")
	if alignPos ~= nil then
		alignPos:Destroy()
	end
	
	alignPos = Instance.new("AlignPosition")
	alignPos.Attachment0 = orbPart.AttachmentAlign
	alignPos.Name = "AlignPosition"
	alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment	
	alignPos.Enabled = true
	alignPos.RigidityEnabled = false	
	alignPos.MaxForce = math.huge
	alignPos.Position = stopMarker.Position
	alignPos.MaxVelocity = (getInstancePosition(orb) - stopMarker.Position).Magnitude / stopTime
	alignPos.Parent = orbPart
	
	task.delay( stopTime + Config.TransportWaitTime, transportNextStop, orb )
end

local function initTransportOrb(orb)
	local attachAlign = orb:FindFirstChild("AttachmentAlign")
	if attachAlign == nil then
		attachAlign = Instance.new("Attachment")
		attachAlign.Name = "AttachmentAlign"
		attachAlign.Orientation = Vector3.new(0,0,-90)
		attachAlign.Parent = if orb:IsA("BasePart") then orb else orb.PrimaryPart
		attachAlign.Position = Vector3.new(0,0,0)
	end

	local stopsFolder = orb:FindFirstChild("Stops")
	if stopsFolder == nil then
		stopsFolder = Instance.new("Folder")
		stopsFolder.Name = "Stops"
		stopsFolder.Parent = orb
	end

	local nextStop = orb:FindFirstChild("NextStop")
	if nextStop == nil then
		nextStop = Instance.new("IntValue")
		nextStop.Name = "NextStop"
		nextStop.Value = 0
		nextStop.Parent = orb
	end

	local numStops = orb:FindFirstChild("NumStops")
	if numStops == nil then
		numStops = Instance.new("IntValue")
		numStops.Name = "NumStops"
		numStops.Value = 0
		numStops.Parent = orb
	end

	-- Verify that the stops folder has the appropriate structure
	-- It should contain ObjectValues named 1, 2, ... , n for some
	-- n >= 0, each one of which has as its value a Model containing
	-- two instances, one Part named "Marker" and one NumberValue
	-- named "TimeToThisStop" with a positive value
	local i = 0
	while true do
		local objectValue = stopsFolder:FindFirstChild(tostring(i+1))
		if not objectValue then break end
		if not objectValue:IsA("ObjectValue") then break end

		local object = objectValue.Value

		if not object then break end
		if not object:IsA("Model") then break end

		local markerPart = object:FindFirstChild("Marker")
		local timeValue = object:FindFirstChild("TimeToThisStop")

		if not markerPart then break end
		if not markerPart:IsA("BasePart") then break end
		if not timeValue then break end
		if not timeValue:IsA("NumberValue") then break end
		if timeValue.Value <= 0 then break end

		-- This is a valid stop
		markerPart.Anchored = true
		markerPart.Transparency = 1
		markerPart.CanCollide = false

		i += 1
	end

	numStops.Value = i
	
	if i > 0 then
		transportNextStop(orb)
	end
end

Remotes.TransportOrbAttach.OnServerEvent:Connect(function(plr, orb)
	-- Make rope
	local attach0 = Instance.new("Attachment")
	attach0.Name = "Attachment0" .. tostring(plr.UserId)
	attach0.Orientation = Vector3.new(0,0,-90)
	attach0.Parent = if orb:IsA("BasePart") then orb else orb.PrimaryPart
	local orbSize = if orb:IsA("BasePart") then orb.Size else orb.PrimaryPart.Size
	attach0.Position = Vector3.new(0,-orbSize.Y/2, 0)

	local attach1 = Instance.new("Attachment")
	attach1.Name = "TransportOrbAttachment1"
	attach1.Orientation = Vector3.new(0,0,-90)
	attach1.Parent = plr.Character.PrimaryPart
	attach1.Position = Vector3.new(0,0,0)

	local rope = Instance.new("RopeConstraint")
	rope.Name = "RopeConstraint" .. tostring(plr.UserId)
	rope.Parent = if orb:IsA("BasePart") then orb else orb.PrimaryPart
	rope.Attachment0 = attach0
	rope.Attachment1 = attach1
	rope.Length = Config.RopeLength + math.random(1,10)
	rope.Visible = true
end)

local function detachPlayerFromOrb(plr, orb)
	
	if not plr.Character or not plr.Character.PrimaryPart then return end
	
	local attachName = "Attachment0" .. tostring(plr.UserId)
	local attach0 = if orb:IsA("BasePart") then orb:FindFirstChild(attachName) else orb.PrimaryPart:FindFirstChild(attachName)
	if attach0 then
		attach0:Destroy()
	end
	
	-- WARNING: if you are attached to two orbs, this might destroy the wrong thing
	local attach1 = plr.Character.PrimaryPart:FindFirstChild("TransportOrbAttachment1")
	if attach1 then
		attach1:Destroy()
	end
	
	local ropeName = "RopeConstraint"..tostring(plr.UserId)
	local rope = if orb:IsA("BasePart") then orb:FindFirstChild(ropeName) else orb.PrimaryPart:FindFirstChild(ropeName)
	if rope then
		rope:Destroy()
	end
end

Remotes.TransportOrbDetach.OnServerEvent:Connect(detachPlayerFromOrb)

-- Remove leaving players as listeners and speakers
Players.PlayerRemoving:Connect(function(plr)
	for _, orb in CollectionService:GetTagged(Config.TransportOrbTag) do
		detachPlayerFromOrb(plr, orb)
	end
end)

return {
	Start = function()
		for _, orb in CollectionService:GetTagged(Config.TransportOrbTag) do
			initTransportOrb(orb)
		end

		CollectionService:GetInstanceAddedSignal(Config.TransportOrbTag):Connect(initTransportOrb)
	end
}

