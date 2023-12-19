local DebugPanel = require(script.Parent)

return {
	Init = function()
		script.Parent.Remotes.Log.OnClientEvent:Connect(DebugPanel.Log)
	end,
}