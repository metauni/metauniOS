local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")

if not RunService:IsStudio() then
	
	ScriptContext.Error:Connect(function(message, trace, _script)
		
		ReplicatedStorage.RavenErrorLog:FireServer(message, trace)
	end)
end

-- Game analytics
local GameAnalytics = require(ReplicatedStorage.Packages.GameAnalytics)
GameAnalytics:initClient()

-- Wait for metauniOS to distribute files.

if not ReplicatedStorage:GetAttribute("metauniOSInstalled") then
	
	ReplicatedStorage:GetAttributeChangedSignal("metauniOSInstalled"):Wait()
end

-- Require any ModuleScript in PlayerScripts or ReplicatedStorage that ends with "Controller"
-- Then call the Init() method/function if it has one 

for _, instance in ReplicatedStorage:GetDescendants() do
	
	if instance.ClassName == "ModuleScript" and string.match(instance.Name, "Controller$") then

		local controller = require(instance)

		if typeof(controller) == "table" and controller.Init then
			
			controller:Init()
		end
	end
end

-- Same as above but call the Start() method/function this time.
	
for _, instance in ReplicatedStorage:GetDescendants() do
	
	if instance.ClassName == "ModuleScript" and string.match(instance.Name, "Controller$") then
		
		local controller = require(instance)

		if typeof(controller) == "table" and controller.Start then
			
			controller:Start()
		end
	end
end