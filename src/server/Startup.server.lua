local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local ScriptContext = game:GetService("ScriptContext")
local ServerScriptService = game:GetService("ServerScriptService")

local SecretService = require(ServerScriptService.SecretService)

-- 
-- Code distribution
--

-- metauniOS
do
	local Common = script.Parent:FindFirstChild("metauniOSCommon")

	if Common then
        if Common:FindFirstChild("GameAnalytics") then
            Common.GameAnalytics.Parent = ReplicatedStorage
        end

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

-- metaportal
local metaPortalFolder = ServerScriptService.metaportal
do
	-- Move folder/guis around if this is the package version
	local metaPortalCommon = metaPortalFolder:FindFirstChild("MetaPortalCommon")
	if metaPortalCommon then
		if ReplicatedStorage:FindFirstChild("Icon") == nil then
			metaPortalCommon.Packages.Icon.Parent = ReplicatedStorage
		end
		metaPortalCommon.Parent = ReplicatedStorage
	end
	
	local metaPortalPlayer = metaPortalFolder:FindFirstChild("MetaPortalPlayer")
	if metaPortalPlayer then
		metaPortalPlayer.Parent = game:GetService("StarterPlayer").StarterPlayerScripts
	end
	
	local metaPortalGui = metaPortalFolder:FindFirstChild("MetaPortalGui")
	if metaPortalGui then
		local StarterGui = game:GetService("StarterGui")
		-- Gui's need to be top level children of StarterGui in order for
		-- ResetOnSpawn=false to work properly
		for _, guiObject in ipairs(metaPortalGui:GetChildren()) do
			guiObject.Parent = StarterGui
		end
	end
end

-- orb
local orbFolder = ServerScriptService.orb
do
	local orbCommon = orbFolder:FindFirstChild("OrbCommon")
	if orbCommon then
		if ReplicatedStorage:FindFirstChild("Icon") == nil then
			orbCommon.Packages.Icon.Parent = ReplicatedStorage
		end
		orbCommon.Parent = ReplicatedStorage
	end

	local orbPlayer = orbFolder:FindFirstChild("OrbPlayer")
	if orbPlayer then
		orbPlayer.Parent = game:GetService("StarterPlayer").StarterPlayerScripts
	end
end

--
-- Error Logging
--

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

--
-- GameAnalytics
--

local GameAnalytics = require(ReplicatedStorage.GameAnalytics)
--GameAnalytics:setEnabledInfoLog(true)
--GameAnalytics:setEnabledVerboseLog(true)
GameAnalytics:initServer(SecretService.GAMEANALYTICS_GAME_KEY, SecretService.GAMEANALYTICS_SECRET_KEY)

--
-- MetaPortal
--

local MetaPortal = require(metaPortalFolder.MetaPortal)
MetaPortal.Init()

--
-- Orb
--

local Orb = require(orbFolder.Orb)
Orb.Init()

--
-- AI
--

local AIChatService = require(script.Parent.AIChatService)
AIChatService.Init()

--
-- Notifications
--
-- (depends on MetaPortal)

task.wait(10)
local NotificationService = require(script.Parent.NotificationService)
NotificationService.Init()