local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local ScriptContext = game:GetService("ScriptContext")
local ServerScriptService = game:GetService("ServerScriptService")

local SecretService = require(ServerScriptService.SecretService)

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

-- AI services
local AIChatService = require(script.Parent.AIChatService)
AIChatService.Init()

-- Error logging using Sentry & Raven
local Raven = require(script.Parent.Raven)
local client = Raven:Client(SecretService.SENTRY_DSN)
-- NOTE: This is what Sentry now calls the Deprecated DSN

local function onError(message, trace, script)
    client:SendException(Raven.ExceptionType.Server, message, trace)
end
ScriptContext.Error:Connect(onError)

local RavenErrorLogRemoteEvent = Instance.new("RemoteEvent", ReplicatedStorage)
RavenErrorLogRemoteEvent.Name = "RavenErrorLog"
client:ConnectRemoteEvent(RavenErrorLogRemoteEvent)