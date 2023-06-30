local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OrbServer = require(script.OrbServer)
local Rxi = require(ReplicatedStorage.Rxi)
local OrbPlayer = require(script.OrbPlayer)
local Ring = require(script.Ring)

local OrbService = {
	Orbs = {} :: {[Part]: Orb}
}

function OrbService:Start()

	self:MakeHaloTemplates()

	Rxi.tagged("metaorb"):Subscribe(function(instance: BasePart)
		if CollectionService:HasTag(instance, "metaorb_transport") then
			return
		end
		if not instance:IsA("BasePart") then
			error(`[OrbService] {instance:GetFullName()} is a Model. Must tag PrimaryPart with "metaorb".`)
		end

		if self.Orbs[instance] then
			return
		end

		self.Orbs[instance] = OrbServer.new(instance)
	end)

	Rxi.untagged("metaorb"):Subscribe(function(instance: BasePart)
		if CollectionService:HasTag(instance, "metaorb_transport") then
			return
		end
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
	
	local playerDestructors = {}

	task.spawn(function()
		Rxi.playerLifetime():Subscribe(function(player: Player, added: boolean)
	
			if playerDestructors[player] then
				playerDestructors[player]:Destroy()
				playerDestructors[player] = nil
			end
			
			if not added then
				return
			end
	
			playerDestructors[player] = OrbPlayer(player)
		end)
	end)
end

function OrbService:MakeHaloTemplates()

	local earHalo: UnionOperation = Ring {
		Name = "EarHalo",
		Parent = script,
		Material = Enum.Material.Neon,
		Color = Color3.new(1,1,1),
		CastShadow = false,
		CanCollide = false,

		InnerDiameter = 1.5 + 0.1,
		OuterDiameter = 1.5 + 0.5,
	}

	local eyeHalo: UnionOperation = Ring {
		Name = "EyeHalo",
		Parent = script,
		Material = Enum.Material.Neon,
		Color = Color3.new(0,0,0),
		CastShadow = false,
		CanCollide = false,

		InnerDiameter = 1.5 + 0.5,
		OuterDiameter = 1.5 + 1,
	}

	local earWeld = Instance.new("WeldConstraint")
	earWeld.Part0 = earHalo
	earWeld.Parent = earHalo

	local eyeWeld = Instance.new("WeldConstraint")
	eyeWeld.Part0 = eyeHalo
	eyeWeld.Parent = eyeHalo
end

return OrbService