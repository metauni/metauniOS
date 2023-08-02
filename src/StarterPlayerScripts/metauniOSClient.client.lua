local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local Players = game:GetService("Players")

local Pocket = ReplicatedStorage.OS.Pocket
local PocketMenu = require(Pocket.UI.PocketMenu)
local PocketImages = require(Pocket.Config).PocketTeleportBackgrounds

local pocketMenu = PocketMenu.new()

pocketMenu:SetPockets({
	{Name = "The Rising Sea", Image = "rbxassetid://10571156964"},
	{Name = "Symbolic Wilds 37", Image = PocketImages["Symbolic Wilds"]},
	{Name = "Moonlight Forest 8", Image = PocketImages["Moonlight Forest"]},
	{Name = "Delta Plains 41", Image = PocketImages["Delta Plains"]},
	{Name = "Storyboard 1", Image = PocketImages["Storyboard"]},
	{Name = "Big Sir 2", Image = PocketImages["Big Sir"]},
	{Name = "Overland 1", Image = PocketImages["Overland"]},
} :: {PocketMenu.PocketData})

pocketMenu:render().Parent = Players.LocalPlayer.PlayerGui

if not RunService:IsStudio() then
	
	ScriptContext.Error:Connect(function(message, trace, _script)
		
		ReplicatedStorage.OS.RavenErrorLog:FireServer(message, trace)
	end)
end

-- Game analytics
local GameAnalytics = require(ReplicatedStorage.Packages.GameAnalytics)
GameAnalytics:initClient()

-- Initialise & Start Controllers

local Promise = require(ReplicatedStorage.Packages.Promise)
local Sift = require(ReplicatedStorage.Packages.Sift)

print("[metauniOS] Importing controllers")

local controllerPromises = {}

-- Find an import any descendent of ReplicatedStorage ending with "Controller"

for _, instance in ReplicatedStorage:GetDescendants() do

	if instance:IsDescendantOf(ReplicatedStorage.Packages) then
		continue
	end
	
	if instance.ClassName == "ModuleScript" and string.match(instance.Name, "Controller$") then

		controllerPromises[instance] = Promise.new(function(resolve, reject)
			local success, result = xpcall(require, function()
				reject("[metauniOS] Failed to import "..instance.Name)
			end, instance)

			if success then
				resolve(result)
			end
		end):catch(warn)
	end
end

-- Yield until every promise has resolved or rejected
local function awaitAll(promises)
	for _, promise in promises do
		promise:await()
	end
end

-- Yield for imports to finish
awaitAll(controllerPromises)

print("[metauniOS] Initialising controllers")

controllerPromises = Sift.Dictionary.map(controllerPromises, function(promise, instance)
	
	return promise
		:tap(function(controller)
			if typeof(controller) == "table" and typeof(controller.Init) == "function" then
				controller:Init()
			end
		end)
		:catch(function(...)
			
			warn("[metauniOS] "..instance.Name..".Init failed")
			warn(...)
			if not RunService:IsStudio() then
				ReplicatedStorage.OS.RavenErrorLog:FireServer(instance.Name..".Init failed", ...)
			end
		end)
end)

-- Yield for Inits to finish
awaitAll(controllerPromises)

print("[metauniOS] Starting controllers")
controllerPromises = Sift.Dictionary.map(controllerPromises, function(promise, instance)
	
	return promise
		:tap(function(controller)
			if typeof(controller) == "table" and typeof(controller.Start) == "function" then
				controller:Start()
			end
		end)
		:catch(function(...)
			
			warn("[metauniOS] "..instance.Name..".Start failed")
			warn(...)
			if not RunService:IsStudio() then
				ReplicatedStorage.OS.RavenErrorLog:FireServer(instance.Name..".Start failed", ...)
			end
		end)
end)

awaitAll(controllerPromises)

print("[metauniOS] Startup complete")