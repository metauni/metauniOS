local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ScriptContext = game:GetService("ScriptContext")
local RunService = game:GetService("RunService")

local versionValue = script:FindFirstChild("version")
local Version = (versionValue and versionValue.Value or "dev")
print("[metauniOS] Version: "..Version)

do -- Convert Model metaboards to Part metaboards
	require(script.Parent.OS.patchLegacymetaboards)()
end

--
-- Error Logging
--

-- Manually installed in ServerScriptService
local SecretService = (require)(ServerScriptService:FindFirstChild("SecretService"))
local Raven = require(ServerScriptService.OS.Raven)

-- NOTE: This is what Sentry now calls the Deprecated DSN
local ravenClient = Raven:Client(SecretService.SENTRY_DSN, {
	release = Version,
	tags = {
		PlaceId = game.PlaceId,
		PlaceVersion = game.PlaceVersion,
	}
})

if not RunService:IsStudio() then

	ScriptContext.Error:Connect(function(message, trace, _script)
	
		ravenClient:SendException(Raven.ExceptionType.Server, message, trace)
	end)
	
	ravenClient:ConnectRemoteEvent(ReplicatedStorage.OS.RavenErrorLog)
	
	task.spawn(function()
		
		if game.PlaceId == 8165217582 then
			
			ravenClient.config.tags.PocketName = "The Rising Sea"
		else
			
			ravenClient.config.tags.PocketName = ReplicatedStorage.OS.Pocket:GetAttribute("PocketName")
			ReplicatedStorage.OS.Pocket:GetAttributeChangedSignal("PocketName"):Connect(function()
				
				ravenClient.config.tags.PocketName = ReplicatedStorage.OS.Pocket:GetAttribute("PocketName")
			end)
		end
	end)
end

--
-- GameAnalytics
--

local GameAnalytics = require(ReplicatedStorage.Packages.GameAnalytics)
--GameAnalytics:setEnabledInfoLog(true)
--GameAnalytics:setEnabledVerboseLog(true)
if RunService:IsStudio() then
	GameAnalytics:setEnabledDebugLog(false) -- The Debug log seems more annoying than useful in Studio
end
GameAnalytics:initServer(SecretService.GAMEANALYTICS_GAME_KEY, SecretService.GAMEANALYTICS_SECRET_KEY)

-- Initialise & Start Services

local Promise = require(ReplicatedStorage.Packages.Promise)
local Sift = require(ReplicatedStorage.Packages.Sift)

print("[metauniOS] Importing services")

local servicePromises = {}

for _, container in {ServerScriptService, ReplicatedStorage} do
	for _, instance in container:GetDescendants() do

		if instance:IsDescendantOf(ReplicatedStorage.Packages) then
			continue
		end
		
		if instance.ClassName == "ModuleScript" and string.match(instance.Name, "Service$") then
	
			servicePromises[instance] = Promise.new(function(resolve, reject)
				local success, result = xpcall(require, function()
					reject("[metauniOS] Failed to import "..instance.Name)
				end, instance)

				if success then
					resolve(result)
				end
			end):catch(warn)
		end
	end
end

-- Yield until every promise has resolved or rejected

local function awaitAll(promises)
	for instance, promise in promises do
		local timeoutMsg = `{instance:GetFullName()} took too long to import`
		local success, result = promise:timeout(3, timeoutMsg):await()
		if not success then
			warn(result)
		end
	end
end

awaitAll(servicePromises)

print("[metauniOS] Initialising services")

servicePromises = Sift.Dictionary.map(servicePromises, function(promise, instance)
	
	return promise
		:tap(function(service)
			if typeof(service) == "table" and typeof(service.Init) == "function" then
				service:Init()
			end
		end)
		:catch(function(...)
			
			warn("[metauniOS] "..instance.Name..".Init failed")
			warn(...)
			if not RunService:IsStudio() then
				ravenClient:SendException(Raven.ExceptionType.Server, instance.Name..".Init failed", ...)
			end
		end)
end)

awaitAll(servicePromises)

print("[metauniOS] Starting services")

servicePromises = Sift.Dictionary.map(servicePromises, function(promise, instance)
	
	return promise
		:tap(function(service)
			if typeof(service) == "table" and typeof(service.Start) == "function" then
				service:Start()
			end
		end)
		:catch(function(...)
			
			warn("[metauniOS] Start failed for "..instance.Name)
			warn(...)
			if not RunService:IsStudio() then
				ravenClient:SendException(Raven.ExceptionType.Server, instance.Name..".Start failed", ...)
			end
		end)
end)

awaitAll(servicePromises)

print("[metauniOS] Startup complete")