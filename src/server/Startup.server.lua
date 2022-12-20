local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

do
	-- Move folder/guis around if this is the package version
	local Common = script.Parent:FindFirstChild("metauniOSCommon")
	if Common then
		Common.Parent = ReplicatedStorage
	end
	
	local Player = script.Parent:FindFirstChild("metauniOSPlayer")
	if Player then
		Player.Parent = StarterPlayer.StarterPlayerScripts
	end
	
	local Gui = script.Parent:FindFirstChild("metauniOSGui")
	if Gui then
		-- Gui's need to be top level children of StarterGui in order for
		-- ResetOnSpawn=false to work properly
		for _, guiObject in ipairs(Gui:GetChildren()) do
			guiObject.Parent = StarterGui
		end
	end
end

local AIChatService = require(script.Parent.AIChatService)
AIChatService.Init()