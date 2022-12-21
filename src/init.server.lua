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

print("[metauniOS] Initialising")

for _, instance in ipairs(ServerScriptService:GetDescendants()) do
	
	if instance.ClassName == "ModuleScript" and string.match(instance.Name, "Service$") then

		local service = require(instance)

		if service.Init then
			
			print("Initalising "..instance.Name)
			service:Init()
		end
	end
end

print("[metauniOS] Starting Services")

for _, instance in ipairs(ServerScriptService:GetDescendants()) do
	
	if instance.ClassName == "ModuleScript" and string.match(instance.Name, "Service$") then
		
		local service = require(instance)

		if service.Start then
			
			print("Starting "..instance.Name)
			service:Start()
		end
	end
end