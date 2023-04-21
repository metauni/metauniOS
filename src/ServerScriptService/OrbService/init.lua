local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OrbServer = require(script.OrbServer)
local Rx = require(ReplicatedStorage.Rx)
local Rxi = require(ReplicatedStorage.Rxi)
local Remotes = ReplicatedStorage.OrbController.Remotes

local speakerAttachSoundIds = {
	7873470625,
	7873470425,
	7873469842,
	7873470126,
	7864771146,
	7864770493,
	8214755036,
	8214754703
}

local SMALL_DISTANCE = 1e-6

local speakerDetachSoundId = 7864770869

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
	
end

return OrbService