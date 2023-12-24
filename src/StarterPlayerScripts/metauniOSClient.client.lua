local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local Players = game:GetService("Players")

local Icon = require(ReplicatedStorage.Packages.Icon)
local Themes =  require(ReplicatedStorage.Packages.Icon.Themes)

local Pocket = ReplicatedStorage.OS.Pocket
local PocketMenu = require(Pocket.UI.PocketMenu)
local PocketConfig = require(Pocket.Config)
local Remotes = ReplicatedStorage.OS.Remotes

local pocketMenuGui = nil

local function createPocketMenu()
    local pocketMenu = PocketMenu.new()
	
	local pockets = {
		{Name = "The Rising Sea", Image = "rbxassetid://10571156964"},
		{Name = "Symbolic Wilds 36", Image = PocketConfig.PocketTeleportBackgrounds["Symbolic Wilds"]},
		{Name = "Moonlight Forest 8", Image = PocketConfig.PocketTeleportBackgrounds["Moonlight Forest"]},
		{Name = "Delta Plains 41", Image = PocketConfig.PocketTeleportBackgrounds["Delta Plains"]},
		{Name = "Storyboard 1", Image = PocketConfig.PocketTeleportBackgrounds["Storyboard"]},
		{Name = "Big Sir 2", Image = PocketConfig.PocketTeleportBackgrounds["Big Sir"]},
		{Name = "Overland 1", Image = PocketConfig.PocketTeleportBackgrounds["Overland"]},
        {Name = "Cstar Bridge 1", Image = PocketConfig.PocketTeleportBackgrounds["Cstar Bridge"]},
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

if game.PlaceId == PocketConfig.RootPlaceId then
	createPocketMenu()
end

-- Knot menu
local icon = Icon.new()
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