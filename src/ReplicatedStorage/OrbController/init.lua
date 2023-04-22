local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local OrbClient = require(script.OrbClient)
local Rx = require(ReplicatedStorage.Rx)
local Rxi = require(ReplicatedStorage.Rxi)
local IconController = require(ReplicatedStorage.Icon.IconController)
local Themes = require(ReplicatedStorage.Icon.Themes)
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Value = Fusion.Value
local Icon = require(ReplicatedStorage.Icon)


local Remotes = script.Remotes

local OrbController = {
	Orbs = {} :: {[Part]: Orb}
}

function OrbController:Start()

	IconController.setGameTheme(Themes["BlueGradient"])

	local observedAttachedOrb = Rx.of(ReplicatedStorage.OrbController):Pipe {
		Rxi.findFirstChild("PlayerToOrb"),
		Rxi.findFirstChildWithClass("ObjectValue", tostring(Players.LocalPlayer.UserId)),
		Rxi.property("Value"),
	}

	-- Use SoundService:SetListener() to listen from orb/playerhead/camera
	Rx.combineLatest{
		AttachedOrbEarPart = observedAttachedOrb:Pipe{
			Rxi.findFirstChildWithClass("Part", "EarPart"),
		},
		PlayerHead = Rx.of(Players.LocalPlayer):Pipe{
			Rxi.property("Character"),
			Rxi.findFirstChildWithClassOf("BasePart", "Head"),
		},
	}:Subscribe(function(data)
		if data.AttachedOrbEarPart then
			SoundService:SetListener(Enum.ListenerType.ObjectCFrame, data.AttachedOrbEarPart)
		elseif data.PlayerHead then
			SoundService:SetListener(Enum.ListenerType.ObjectCFrame, data.PlayerHead)
		else
			SoundService:SetListener(Enum.ListenerType.Camera)
		end
	end)

	Rxi.tagged("metaorb"):Subscribe(function(instance: BasePart)
		if not instance:IsA("BasePart") then
			error(`[OrbService] {instance:GetFullName()} is a Model. Must tag PrimaryPart with "metaorb".`)
		end

		if self.Orbs[instance] then
			return
		end

		self.Orbs[instance] = OrbClient.new(instance, observedAttachedOrb)
	end)

	Rxi.untagged("metaorb"):Subscribe(function(instance: BasePart)
		if self.Orbs[instance] then
			self.Orbs[instance]:Destroy()
			self.Orbs[instance] = nil
		end
	end)
end

return OrbController