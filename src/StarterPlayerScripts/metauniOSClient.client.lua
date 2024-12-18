local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local Players = game:GetService("Players")
local VRService = game:GetService("VRService")

local Icon = require(ReplicatedStorage.Packages.Icon :: any)
local Themes =  require(ReplicatedStorage.Packages.Icon.Themes :: any)

local Pocket = ReplicatedStorage.OS.Pocket
local PocketMenu = require(Pocket.UI.PocketMenu)
local PocketConfig = require(Pocket.Config)
local Remotes = ReplicatedStorage.OS.Remotes

local pocketMenuGui = nil

local function createPocketMenu()
    local pocketMenu = PocketMenu.new()
	
	local pockets = {
		{Name = "The Rising Sea", Image = "rbxassetid://10571156964"},
        {Name = "Symbolic Wilds 50", Image = PocketConfig.PocketTeleportBackgrounds["Symbolic Wilds"]},
		{Name = "Symbolic Wilds 36", Image = PocketConfig.PocketTeleportBackgrounds["Symbolic Wilds"]},
		{Name = "Moonlight Forest 8", Image = PocketConfig.PocketTeleportBackgrounds["Moonlight Forest"]},
		{Name = "Delta Plains 41", Image = PocketConfig.PocketTeleportBackgrounds["Delta Plains"]},
		{Name = "Storyboard 1", Image = PocketConfig.PocketTeleportBackgrounds["Storyboard"]},
		{Name = "Big Sir 2", Image = PocketConfig.PocketTeleportBackgrounds["Big Sir"]},
		{Name = "Overland 1", Image = PocketConfig.PocketTeleportBackgrounds["Overland"]},
        {Name = "Elements 1", Image = PocketConfig.PocketTeleportBackgrounds["Elements"]},
	}

	-- Add metauni-dev world for Billy and Dan
	if Players.LocalPlayer.UserId == 2293079954 or Players.LocalPlayer.UserId == 2211421151 then
		table.insert(pockets, {Name = "metauni-dev", Image = "rbxassetid://10571156964"})
	end

	pocketMenu:SetPockets(pockets :: {PocketMenu.PocketData})

	task.spawn(function()
		pocketMenu:SetSchedule(Remotes.GetSeminarSchedule:InvokeServer())
	end)
	
    pocketMenuGui = pocketMenu:render()
	pocketMenuGui.Parent = Players.LocalPlayer.PlayerGui
end

if game.PlaceId == PocketConfig.RootPlaceId and not VRService.VREnabled then
	createPocketMenu()
end

-- Knot menu
local icon = Icon.new()
require(ReplicatedStorage.Packages.Icon.IconController :: any).voiceChatEnabled = true
icon:setImage("rbxassetid://11783868001")
icon:setOrder(-1)
icon:setLabel("metauni")
icon:bindEvent("selected", function(self)
    self:deselect()
    icon:deselect()
    if not pocketMenuGui or pocketMenuGui.Parent ~= Players.LocalPlayer.PlayerGui then
        createPocketMenu()
    end
end)

icon:setTheme(Themes["BlueGradient"])

if not RunService:IsStudio() then
	
	ScriptContext.Error:Connect(function(message, trace, _script)
		
		ReplicatedStorage.OS.RavenErrorLog:FireServer(message, trace)
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
			warn(`[metauniOS (client)] Waiting for {table.concat(notDead, ',')}`)
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


local moduleScripts = {} :: {[ModuleScript]: true}

-- Find any descendent of ReplicatedStorage (but not Packages) ending with "Controller"

for _, instance in ReplicatedStorage:GetDescendants() do

	if instance:IsDescendantOf(ReplicatedStorage.Packages) then
		continue
	end
	
	if instance.ClassName == "ModuleScript" and string.match(instance.Name, "Controller$") then
		moduleScripts[instance] = true
	end
end

print("[metauniOS (client)] Importing controllers")

local IMPORT_TIMEOUT = 4.5
local controllers = {} :: {[ModuleScript]: any}

doJobsAsync({
	source = moduleScripts,
	makeJob = function(instance)
		return function()
			controllers[instance] = require(instance)
		end
	end,
	jobTimeout = IMPORT_TIMEOUT,
	onTimeOut = function(instance)
		warn(`[metauniOS (client)] Controller {instance:GetFullName()} took too long to import (>{IMPORT_TIMEOUT}s)`)
	end,
	onFailure = function(instance, _, err)
		local msg = `[metauniOS (client)] Controller {instance:GetFullName()} failed to import`
		warn(msg)
		warn(err)
		if not RunService:IsStudio() then
			ReplicatedStorage.OS.RavenErrorLog:FireServer(msg..'\n'..err)
		end
	end
})

print("[metauniOS (client)] Initialising controllers")

local INIT_TIMEOUT = 4.5
doJobsAsync({
	source = controllers,
	makeJob = function(_instance, controller)
		if typeof(controller) == "table" and typeof(controller.Init) == "function" then
			return function()
				controller:Init()
			end
		end
		return nil
	end,
	jobTimeout = INIT_TIMEOUT,
	onTimeOut = function(instance, _controller)
		controllers[instance] = nil
		warn(`[metauniOS (client)] Controller {instance:GetFullName()} took too long to finish :Init() (>{INIT_TIMEOUT}s)})`)
	end,
	onFailure = function(instance, _controller, err)
		controllers[instance] = nil
		local msg = `[metauniOS (client)] Controller {instance:GetFullName()} failed to :Init()`
		warn(msg)
		warn(err)
		if not RunService:IsStudio() then
			ReplicatedStorage.OS.RavenErrorLog:FireServer(msg..'\n'..err)
		end
	end
})

print("[metauniOS (client)] Starting controllers")

local START_TIMEOUT = 4.5
doJobsAsync {
	source = controllers,
	makeJob = function(_instance, controller)
		if typeof(controller) == "table" and typeof(controller.Start) == "function" then
			return function()
				controller:Start()
			end
		end
		return nil
	end,
	jobTimeout = START_TIMEOUT,
	onTimeOut = function(instance, _controller)
		controllers[instance] = nil
		warn(`[metauniOS (client)] Controller {instance:GetFullName()} took too long to finish :Start() (>{START_TIMEOUT}s)`)
	end,
	onFailure = function(instance, _controller, err)
		controllers[instance] = nil
		local msg = `[metauniOS (client)] Controller {instance:GetFullName()} failed to :Start()`
		warn(msg)
		warn(err)
		if not RunService:IsStudio() then
			ReplicatedStorage.OS.RavenErrorLog:FireServer(msg..'\n'..err)
		end
	end
}

print("[metauniOS (client)] Startup complete")