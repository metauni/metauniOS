local TextChatService = game:GetService("TextChatService")

local PermissionsController = {}

function PermissionsController:Start()

	local SystemChannel: TextChannel = TextChatService:WaitForChild("RBXSystem", true)

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
end

return PermissionsController