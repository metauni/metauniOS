local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

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

ReplicatedStorage:SetAttribute("metauniOSReady", true)

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
