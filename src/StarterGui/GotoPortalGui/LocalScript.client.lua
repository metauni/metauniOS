local screenGui = script.Parent
local backgroundFrame = screenGui.Frame
local teleportButton = backgroundFrame.TeleportButton
local cancelButton = backgroundFrame.CancelButton
local textBox = backgroundFrame.TextBox

local Pocket = game:GetService("ReplicatedStorage").Pocket
local ContextActionService = game:GetService("ContextActionService")

local GotoEvent = Pocket.Remotes.Goto
local ACTION_TELEPORT = "GotoPocketTeleport"

local function teleportActivated()
	screenGui.Enabled = false
	GotoEvent:FireServer(textBox.Text)
end

teleportButton.Activated:Connect(teleportActivated)

local function teleportCancelled()
	screenGui.Enabled = false
end

cancelButton.Activated:Connect(teleportCancelled)

local function handleAction(actionName, inputState, inputObject)
	if actionName == ACTION_TELEPORT and inputState == Enum.UserInputState.End then
		teleportActivated()
	end
end

local actionBound = false

screenGui.Changed:Connect(function()
	if screenGui.Enabled and not actionBound then		
		ContextActionService:BindAction(ACTION_TELEPORT, handleAction, false, Enum.KeyCode.Return)		
	end
	
	if not screenGui.Enabled and actionBound then
		ContextActionService:UnbindAction(ACTION_TELEPORT)
	end
end)
