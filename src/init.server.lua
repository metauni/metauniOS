local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local ScriptContext = game:GetService("ScriptContext")
local RunService = game:GetService("RunService")

local versionValue = script:FindFirstChild("version")
print("[metauniOS] Version: "..(versionValue and versionValue.Value or "dev"))

local function migrate(source, target)

	for _, instance in source:GetChildren() do
		
		instance.Parent = target
	end
end

migrate(script.ReplicatedStorage, ReplicatedStorage)
script.Packages.Parent = ReplicatedStorage
migrate(script.ServerScriptService, ServerScriptService)
migrate(script.StarterGui, StarterGui)
migrate(script.StarterPlayerScripts, StarterPlayer.StarterPlayerScripts)

--
-- Error Logging
--

local SecretService = require(ServerScriptService.SecretService)

local Raven = require(ServerScriptService.Raven)
local client = Raven:Client(SecretService.SENTRY_DSN)
-- NOTE: This is what Sentry now calls the Deprecated DSN

local function onError(message, trace, script)
	
	if not RunService:IsStudio() then
		client:SendException(Raven.ExceptionType.Server, message, trace)
	end
end
ScriptContext.Error:Connect(onError)

local RavenErrorLogRemoteEvent = Instance.new("RemoteEvent")
RavenErrorLogRemoteEvent.Name = "RavenErrorLog"
RavenErrorLogRemoteEvent.Parent = ReplicatedStorage
client:ConnectRemoteEvent(RavenErrorLogRemoteEvent)

--
-- GameAnalytics
--

local GameAnalytics = require(ReplicatedStorage.Packages.GameAnalytics)
--GameAnalytics:setEnabledInfoLog(true)
--GameAnalytics:setEnabledVerboseLog(true)
GameAnalytics:initServer(SecretService.GAMEANALYTICS_GAME_KEY, SecretService.GAMEANALYTICS_SECRET_KEY)

ReplicatedStorage:SetAttribute("metauniOSInstalled", true)

-- Initialise & Start Services

print("[metauniOS] Initialising Services")

for _, container in {ServerScriptService, ReplicatedStorage} do

	for _, instance in container:GetDescendants() do
		
		if instance.ClassName == "ModuleScript" and string.match(instance.Name, "Service$") then
	
			local service = require(instance)
	
			if typeof(service) == "table" and service.Init then
				
				service:Init()
			end
		end
	end
end

print("[metauniOS] Starting Services")

for _, container in {ServerScriptService, ReplicatedStorage} do
	
	for _, instance in container:GetDescendants() do
		
		if instance.ClassName == "ModuleScript" and string.match(instance.Name, "Service$") then
			
			local service = require(instance)
	
			if typeof(service) == "table" and service.Start then
				
				service:Start()
			end
		end
	end
end
