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

--[[
	Do multiple jobs (functions) asynchronously, with timeout and error handling.
	Yields until all jobs are finished or timed-out.
]]
local function doJobsAsync<K,V>(
	props: {
		source: {[K]: V},
		makeJob: (K,V) -> (() -> ())?,
		jobTimeout: number,
		onTimeOut: (K,V) -> (),
		onFailure: (K,V,string) -> (),
	}
)
	local startTimes = {}
	local threads = {}

	for key, value in props.source do
		local job = props.makeJob(key, value)
		if not job then
			continue
		end
		threads[key] = coroutine.create(function()
			xpcall(function()
				startTimes[key] = os.clock()
				job()
			end, function(err)
				props.onFailure(key, value, debug.traceback(err))
			end)
		end)
	end

	for _, thread in threads do
		coroutine.resume(thread)
	end

	local watcher = task.defer(function()
		while true do
			local notDead = {}
			for key, thread in threads do
				if coroutine.status(thread) ~= "dead" then
					table.insert(notDead, tostring(key))
				end
			end
			warn(`[metauniOS] Waiting for {table.concat(notDead, ',')}`)
			task.wait(1)
		end
	end)

	while true do
		for key, thread in threads do
			if coroutine.status(thread) == "dead" then
				threads[key] = nil
			elseif props.jobTimeout < os.clock() - startTimes[key] then
				props.onTimeOut(key, props.source[key])
				coroutine.close(threads[key])
				threads[key] = nil
			end
		end
		if next(threads) == nil then
			break
		end
		task.wait()
	end

	coroutine.close(watcher)
end

-- Initialise & Start Service

local scripts = {} :: {[ModuleScript]: true}

for _, container in {ServerScriptService, ReplicatedStorage} do
	for _, instance in container:GetDescendants() do
		if instance:IsDescendantOf(ReplicatedStorage.Packages) then
			continue
		end
		
		if instance.ClassName == "ModuleScript" and string.match(instance.Name, "Service$") then
			scripts[instance] = true
		end
	end
end

print("[metauniOS] Importing services")

local IMPORT_TIMEOUT = 4.5
local services = {} :: {[ModuleScript]: any}

doJobsAsync({
	source = scripts,
	makeJob = function(instance)
		return function()
			services[instance] = require(instance)
		end
	end,
	jobTimeout = IMPORT_TIMEOUT,
	onTimeOut = function(instance)
		warn(`[metauniOS] Service {instance:GetFullName()} took too long to import (>{IMPORT_TIMEOUT}s)`)
	end,
	onFailure = function(instance, _, err)
		local msg = `[metauniOS] Service {instance:GetFullName()} failed to import`
		warn(msg)
		warn(err)
		if not RunService:IsStudio() then
			ravenClient:SendException(Raven.ExceptionType.Server, msg..'\n'..err)
		end
	end
})

print("[metauniOS] Initialising services")

local INIT_TIMEOUT = 4.5
doJobsAsync({
	source = services,
	makeJob = function(_instance, service)
		if typeof(service) == "table" and typeof(service.Init) == "function" then
			return function()
				service:Init()
			end
		end
		return nil
	end,
	jobTimeout = INIT_TIMEOUT,
	onTimeOut = function(instance, _service)
		services[instance] = nil
		warn(`[metauniOS] Service {instance:GetFullName()} took too long to finish :Init() (>{INIT_TIMEOUT}s)})`)
	end,
	onFailure = function(instance, _service, err)
		services[instance] = nil
		local msg = `[metauniOS] Service {instance:GetFullName()} failed to :Init()`
		warn(msg)
		warn(err)
		if not RunService:IsStudio() then
			ravenClient:SendException(Raven.ExceptionType.Server, msg..'\n'..err)
		end
	end
})

print("[metauniOS] Starting services")

local START_TIMEOUT = 4.5
doJobsAsync {
	source = services,
	makeJob = function(_instance, service)
		if typeof(service) == "table" and typeof(service.Start) == "function" then
			return function()
				service:Start()
			end
		end
		return nil
	end,
	jobTimeout = START_TIMEOUT,
	onTimeOut = function(instance, _service)
		services[instance] = nil
		warn(`[metauniOS] Service {instance:GetFullName()} took too long to finish :Start() (>{START_TIMEOUT}s)`)
	end,
	onFailure = function(instance, _service, err)
		services[instance] = nil
		local msg = `[metauniOS] Service {instance:GetFullName()} failed to :Start()`
		warn(msg)
		warn(err)
		if not RunService:IsStudio() then
			ravenClient:SendException(Raven.ExceptionType.Server, msg..'\n'..err)
		end
	end
}

print("[metauniOS] Startup complete")