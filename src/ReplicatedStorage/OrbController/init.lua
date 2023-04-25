local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local OrbClient = require(script.OrbClient)
local Rx = require(ReplicatedStorage.Rx)
local Rxi = require(ReplicatedStorage.Rxi)
local Destructor = require(ReplicatedStorage.Destructor)
local IconController = require(ReplicatedStorage.Icon.IconController)
local Themes = require(ReplicatedStorage.Icon.Themes)

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

	Rxi.tagged("spooky_part"):Subscribe(function(instance: BasePart)

		local destructor = Destructor.new()

		destructor:Add(
			Rx.of(instance):Pipe {
				Rxi.attribute("spooky_transparency"),
			}:Subscribe(function(transparency: Number?)
				if transparency then
					TweenService:Create(instance, TweenInfo.new(
						1.8, -- Time
						Enum.EasingStyle.Linear, -- EasingStyle
						Enum.EasingDirection.Out, -- EasingDirection
						0, -- RepeatCount (when less than zero the tween will loop indefinitely)
						false, -- Reverses (tween will reverse once reaching it's goal)
						0 -- DelayTime
					), {
						Transparency = transparency,
					}):Play()
				end
			end)
		)

		instance.Destroying:Once(function()
			destructor:Destroy()
			destructor = nil
		end)
	end)
end

return OrbController