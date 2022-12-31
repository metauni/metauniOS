local Players = game:GetService("Players")
local Common = script.Parent

local Gui = require(script.Parent.Gui)
local Halos = require(script.Parent.Halos)

return {
	
	Start = function()
		
		if Common:GetAttribute("OrbServerInitialised") == nil then
				Common:GetAttributeChangedSignal("OrbServerInitialised"):Wait()
		end
		
		local localPlayer = Players.LocalPlayer
		local localCharacter = localPlayer.Character or localPlayer.CharacterAdded:Wait()
		
		Gui.Init()
		Halos.Init()

		Players.LocalPlayer.CharacterAdded:Connect(function(character)
			-- When resetting
			Gui.OnResetCharacter()
		end)
		
		Players.LocalPlayer.CharacterRemoving:Connect(function()
			Gui.Detach()
			Gui.RemoveEar()
		end)
	end
}

