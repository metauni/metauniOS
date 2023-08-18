-- --[[
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- --]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Imports
local Destructor = require(ReplicatedStorage.OS.Destructor)
local Rx = require(ReplicatedStorage.Util.Rx)
local Rxi = require(ReplicatedStorage.Util.Rxi)
local Remotes = ReplicatedStorage.OS.Drone.Remotes

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

	droneCharacter.Humanoid.PlatformStand = true

	destructor:Add(function()

		droneCharacter.Humanoid.PlatformStand = false
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

	local function observePlayerByUserId(userId: number)
		return Rx.merge({
			Rx.of(Players:GetPlayerByUserId(userId)),
			Rx.fromSignal(Players.PlayerAdded):Pipe {
				Rx.map(function(plr: Player)
					if plr.UserId == userId then
						return plr
					end
				end)
			},
			Rx.fromSignal(Players.PlayerRemoving):Pipe {
				Rx.map(function(plr: Player)
					if plr.UserId == userId then
						return nil
					end
				end)
			},
		})
	end

local function observeCompleteCharacter(obsPlayer: Rx.Observable): Rx.Observable
	local obsChar = obsPlayer:Pipe({Rxi.property("Character")})

	return Rx.combineLatest {
		obsChar,
		obsChar:Pipe({Rxi.findFirstChildOfClass("Humanoid")}),
		obsChar:Pipe({Rxi.findFirstChildWithClass("Part", "HumanoidRootPart")}),
	}:Pipe {
		Rx.map(function(data)
			if data[1] and data[2] and data[3] then
				return data[1]
			end
		end)
	}
end

	local attachDestructor = Destructor.new()

	local subscription = Rx.combineLatest {
		DroneCharacter = Rx.of(player):Pipe {
			observeCompleteCharacter
		},
		HostCharacter = observePlayerByUserId(self.HostUserId):Pipe {
			observeCompleteCharacter
		},
	}:Subscribe(function(data)
		
		attachDestructor:Destroy()
		if data.DroneCharacter and data.HostCharacter then
			self:_attachToHost(data.DroneCharacter, data.HostCharacter)
		end
	end)

	self._destructor:Add(subscription)

	return self
end

function Drone:Destroy()
	
	self._destructor:Destroy()
end

return Drone