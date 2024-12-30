local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Humanoid = require(script.Humanoid)
local Rx = require(ReplicatedStorage.Util.Rx)
local Rxi = require(ReplicatedStorage.Util.Rxi)
local Maid = require(ReplicatedStorage.Util.Maid)
local GoodSignal = require(ReplicatedStorage.Util.GoodSignal)

local HumanoidController = {}

function HumanoidController:Init()
	local self = HumanoidController

	self._maid = Maid.new()
	self._playerHumanoid = {}
	self._humanoidChanged = GoodSignal.new()
end

function HumanoidController:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(self._addPlayer, self, player)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		self:_addPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:_removePlayer(player)
	end)
end

function HumanoidController:_addPlayer(player: Player)
	self._maid[player] = self:_observeHumanoidObject(player):Subscribe(function(humanoid: Humanoid?)
		if self._playerHumanoid[player] then
			self._playerHumanoid[player]:Destroy()
			self._playerHumanoid[player] = nil
		end

		if humanoid then
			self._playerHumanoid[player] = Humanoid.new(humanoid)
			self._playerHumanoid[player]:Init()
		end

		self._humanoidChanged:Fire(player, self._playerHumanoid[player])
	end)
end

function HumanoidController:_removePlayer(player: Player)
	self._maid[player] = nil
end

function HumanoidController:_observeHumanoidObject(player: Player)
	return Rx.of(player):Pipe({
		Rxi.property("Character"),
		Rxi.findFirstChild("Humanoid"),
	})
end

function HumanoidController:ObserveHumanoid(player: Player)
	return Rx.fromSignal(self._humanoidChanged):Pipe {
		Rx.where(function(plr: Player, _humanoid)
			return plr == player
		end),
		Rx.map(function(_plr, humanoid)
			return humanoid
		end),
	}
end

return HumanoidController
