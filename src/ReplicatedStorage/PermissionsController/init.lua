local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local PermissionsController = {}

function PermissionsController:Start()

	local SystemChannel: TextChannel = TextChatService:WaitForChild("TextChannels"):WaitForChild("RBXSystem", true)

	SystemChannel.OnIncomingMessage = function(textChatMessage: TextChatMessage)
		local hexColor = textChatMessage.Metadata:match("^#?%x%x%x%x%x%x$")
		if hexColor then
			local overrideProperties = Instance.new("TextChatMessageProperties")
			overrideProperties.Text = `<font color='{hexColor}'>{textChatMessage.Text}</font>`
			return overrideProperties
		end
	end

	script.Remotes.DisplaySystemMessage.OnClientEvent:Connect(function(message, color)
		local metadata = color and "#"..color:ToHex():upper() or "#FDE541"
		SystemChannel:DisplaySystemMessage(message, metadata)
	end)

	-- Fix for topbarplus positioning (it doesn't detect chat button with new TextChatService)
	task.spawn(function()
		while true do
			if StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat) then
				local IconController = require(ReplicatedStorage.Icon.IconController)
				IconController.updateTopbar() -- Fixes positioning
				return
			end
			task.wait(1/4)
		end
	end)
end

return PermissionsController