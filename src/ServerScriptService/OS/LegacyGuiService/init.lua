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
			print("ShouldReset", gui.Name)
			table.insert(self._guisResetOnSpawn, gui)
		end
	end

	local function setupPlayer(player: Player)
		print("Giving guis")
		self:_giveGuis(player)
	
		if player.Character then
			print("had character immediately")
			player.CharacterAdded:Connect(function()
				print("Already had character at first, this is a newer character")
				task.defer(function()
					self:_replaceResetGuis(player)
				end)
			end)
		else
			-- We only want to replace the ResetOnSpawn guis
			-- on subsequent recents (not the first).
			player.CharacterAdded:Once(function()
				print("Ignoring first character added")
				player.CharacterAdded:Connect(function()
					print("Not ignoring later character added")
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
				print("DELETING", gui.Name, "which should be gone already but w/e")
				gui:Destroy()
			end
		end
	end
	for _, gui in self._guisResetOnSpawn do
		print("Cloning new", gui.Name, "for reset")
		gui:Clone().Parent = player.PlayerGui
	end
end

return LegacyGuiService