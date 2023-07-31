local Players = game:GetService("Players")

local LegacyGuiService = {}

local function shouldResetOnSpawn(instance: Instance)
	local hasResetOnSpawnProperty = pcall(function()
		local _ = (instance :: any):GetPropertyChangedSignal("ResetOnSpawn")
		return true
	end)
	return not hasResetOnSpawnProperty or (instance :: any).ResetOnSpawn
end

-- Does what StarterGui does, so we avoid source controlling StarterGui
function LegacyGuiService.Init()
	local self = LegacyGuiService
	
	self._guis = script:GetChildren()
	self._guisResetOnSpawn = {}

	for _, gui in self._guis do
		gui:SetAttribute("LegacyGuiService", true)
		if shouldResetOnSpawn(gui) then
			table.insert(self._guisResetOnSpawn, gui)
		end
	end

	local function setupPlayer(player: Player)
		self:_giveGuis(player)
	
		if player.Character then
			player.CharacterAdded:Connect(function()
				-- Use task.defer because this seems to fire before PlayerGui is cleared
				task.defer(function()
					self:_replaceResetGuis(player)
				end)
			end)
		else
			-- We only want to replace the ResetOnSpawn guis
			-- on subsequent recents (not the first).
			player.CharacterAdded:Once(function()
				player.CharacterAdded:Connect(function()
					task.defer(function()
						self:_replaceResetGuis(player)
					end)
				end)
			end)
		end
	end

	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	
	Players.PlayerAdded:Connect(setupPlayer)
end

function LegacyGuiService:_giveGuis(player: Player)
	for _, gui in self._guis do
		gui:Clone().Parent = player.PlayerGui
	end
end

function LegacyGuiService:_replaceResetGuis(player: Player)
	for _, gui in player.PlayerGui:GetChildren() do
		if gui:GetAttribute("LegacyGuiService") then
			if shouldResetOnSpawn(gui) then
				-- This should have been deleted already ¯\_(ツ)_/¯
				gui:Destroy()
			end
		end
	end
	for _, gui in self._guisResetOnSpawn do
		gui:Clone().Parent = player.PlayerGui
	end
end

return LegacyGuiService