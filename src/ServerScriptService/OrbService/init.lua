local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OrbServer = require(script.OrbServer)
local Rx = require(ReplicatedStorage.Rx)
local Rxi = require(ReplicatedStorage.Rxi)

local OrbService = {
	Orbs = {} :: {[Part]: Orb}
}

function OrbService:Start()

	Rxi.tagged("metaorb"):Subscribe(function(instance: BasePart)
		if not instance:IsA("BasePart") then
			error(`[OrbService] {instance:GetFullName()} is a Model. Must tag PrimaryPart with "metaorb".`)
		end

		if self.Orbs[instance] then
			return
		end

		self.Orbs[instance] = OrbServer.new(instance)
	end)

	Rxi.untagged("metaorb"):Subscribe(function(instance: BasePart)
		if self.Orbs[instance] then
			self.Orbs[instance]:Destroy()
			self.Orbs[instance] = nil
		end
	end)

	-- We don't use waypoints anymore, but we must still hide them if they are there.
	for _, waypoint in CollectionService:GetTagged("metaorb_waypoint") do
		waypoint.Transparency = 1
		waypoint.Anchored = true
		waypoint.CanCollide = false
		waypoint.CastShadow = false
	end
	
end

return OrbService