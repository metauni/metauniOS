local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Humanoid = require(script.Humanoid)
local Rx = require(ReplicatedStorage.OS.Rx)
local Rxi = require(ReplicatedStorage.OS.Rxi)
local Maid = require(ReplicatedStorage.OS.Maid)

local HumanoidController = {}

function HumanoidController:Init()
	local self = HumanoidController

	self._maid = Maid.new()
	self._playerHumanoid = {}
end

function HumanoidController:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(self._addPlayer, self, player)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		self:_addPlayer(player)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		self:removePlayer(player)
	end)
end

function HumanoidController:_addPlayer(player: Player)
	self._maid:Assign(player, self:_observeHumanoid(player):Subscribe(function(humanoid: Humanoid?)
		if self._playerHumanoid[player] then
			self._playerHumanoid[player]:Destroy()
			self._playerHumanoid[player] = nil
		end
		
		if humanoid then
			self._playerHumanoid[player] = Humanoid.new(humanoid)
			self._playerHumanoid[player]:InitSounds()
		end
	end))
end

function HumanoidController:_removePlayer(player: Player)
	self._maid:Clean(player)
end

function HumanoidController:_observeHumanoid(player: Player)
	return Rx.of(player):Pipe({
		Rxi.property("Character"),
		Rxi.findFirstChild("Humanoid"),
	})
end

return HumanoidController