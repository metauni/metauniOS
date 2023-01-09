-- --[[
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- --]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Imports
local Destructor = require(ReplicatedStorage.Destructor)
local Remotes = ReplicatedStorage.Drone.Remotes

local Drone = {}
Drone.__index = Drone


function Drone:_attachToHost(droneCharacter: Model, hostCharacter: Model)

	local destructor = Destructor.new()

	local hideDescendant = function(descendant)

		if descendant:IsA("BasePart") then
			
			local originalTransparency = descendant.Transparency
			
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			
			destructor:Add(function()
					
				descendant.Transparency = originalTransparency
				descendant.CanCollide = true
				descendant.CanQuery = true
				descendant.CanTouch = true
				descendant.Massless = false
			end)
		end

		if descendant:IsA("Decal") then

			local originalTransparency = descendant.Transparency
			
			descendant.Transparency = 1

			destructor:Add(function()
				
				descendant.Transparency = originalTransparency
			end)
		end
	end
	
	for _, descendant in ipairs(droneCharacter:GetDescendants()) do
		
		hideDescendant(descendant)
	end

	destructor:Add(droneCharacter.DescendantAdded:Connect(hideDescendant))

	droneCharacter:WaitForChild("Humanoid").PlatformStand = true

	destructor:Add(function()

		droneCharacter:WaitForChild("Humanoid").PlatformStand = false
	end)

	droneCharacter:PivotTo(hostCharacter:GetPivot())

	local weldConstraint = Instance.new("WeldConstraint")
	
	weldConstraint.Part0 = droneCharacter:WaitForChild("HumanoidRootPart")
	weldConstraint.Part1 = hostCharacter:WaitForChild("HumanoidRootPart")

	weldConstraint.Parent = droneCharacter

	destructor:Add(weldConstraint)

	droneCharacter:SetAttribute("DroneAttachedToHostUserId", true)
	
	destructor:Add(function()
		
		droneCharacter:SetAttribute("DroneAttachedToHostUserId", nil)
	end)

	local droneStringValue = Instance.new("IntValue")
	droneStringValue.Name = "AttachedDrone"
	droneStringValue.Value = self.Player.UserId
	droneStringValue.Parent = hostCharacter

	destructor:Add(droneStringValue)

	return destructor
end


function Drone.new(player: Player, hostUserId: number)

	local self = setmetatable({

		Player = player,
		HostUserId = hostUserId,
	}, Drone)
	
	self._destructor = Destructor.new()

	local function initHostPlayer(host)

		local hostDestructor = Destructor.new()
		local attachDestructor = Destructor.new()
		
		hostDestructor:Add(attachDestructor)
		self._destructor:Add(hostDestructor)

		self._destructor:Add(function()
			self.Player.Character:SetAttribute("DroneHostUserId", nil)
		end)

		local function maybeBothThere()
			if self.Player.Character and host.Character then
				self.Player.Character:SetAttribute("DroneHostUserId", self.HostUserId)
				attachDestructor:Add(self:_attachToHost(self.Player.Character, host.Character))
			end
		end

		local function notBothThere()
			attachDestructor:Destroy()
			self.Player.Character:SetAttribute("DroneHostUserId", nil)
		end

		maybeBothThere()
		
		hostDestructor:Add(host.CharacterAdded:Connect(function()
			Players.LocalPlayer.Character:SetAttribute("DroneHostUserId", self.HostUserId)
			maybeBothThere()
		end))
		
		hostDestructor:Add(self.Player.CharacterAdded:Connect(maybeBothThere))

		hostDestructor:Add(host.CharacterRemoving:Connect(notBothThere))
		
		hostDestructor:Add(self.Player.CharacterRemoving:Connect(notBothThere))

		hostDestructor:Add(Players.PlayerRemoving:Connect(function(removingPlayer)
			
			if removingPlayer == host then
				
				hostDestructor:Destroy()
			end
		end))

		hostDestructor:Add(Remotes.DetachDrone.OnServerEvent:Connect(function(_player, droneUserId)
			if droneUserId == self.Player.UserId then
				attachDestructor:Destroy()
			end
		end))

		Remotes.ReattachDrone.OnServerEvent:Connect(function(_player, droneUserId)
			if droneUserId == self.Player.UserId then
				maybeBothThere()
			end
		end)
	end

	local host = Players:GetPlayerByUserId(hostUserId)

	if host then
		
		initHostPlayer(host)
	end

	self._destructor:Add(Players.PlayerAdded:Connect(function(addedPlayer)
		
		if addedPlayer.UserId == hostUserId then

			initHostPlayer(addedPlayer)
		end
	end))

	local connection
	connection = Players.PlayerRemoving:Connect(function(removingPlayer)
		
		if removingPlayer == player then
			
			connection:Disconnect()
			self._destructor:Destroy()
		end
	end)

	return self
end

function Drone:Destroy()
	
	self._destructor:Destroy()
end

return Drone