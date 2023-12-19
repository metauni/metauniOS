local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rxi = require(ReplicatedStorage.Util.Rxi)
local DebugPanel = require(script.Parent)

return {
	Init = function()
		script.Parent.Remotes.Log.OnClientEvent:Connect(DebugPanel.Log)
	end,
}