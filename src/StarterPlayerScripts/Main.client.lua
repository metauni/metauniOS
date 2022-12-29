local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for metauniOS to distribute files.

if not ReplicatedStorage:GetAttribute("metauniOSReady") then
	
	ReplicatedStorage:GetAttributeChangedSignal("metauniOSReady"):Wait()
end

-- Require any ModuleScript in PlayerScripts or ReplicatedStorage that ends with "Controller"
-- Then call the Init() method/function if it has one 

for _, instance in ReplicatedStorage:GetDescendants() do
	
	if instance.ClassName == "ModuleScript" and string.match(instance.Name, "Controller$") then

		local controller = require(instance)

		if typeof(controller) == "table" and controller.Init then
			
			print("Initalising "..instance.Name)
			controller:Init()
		end
	end
end

-- Same as above but call the Start() method/function this time.
	
for _, instance in ReplicatedStorage:GetDescendants() do
	
	if instance.ClassName == "ModuleScript" and string.match(instance.Name, "Controller$") then
		
		local controller = require(instance)

		if typeof(controller) == "table" and controller.Start then
			
			print("Starting "..instance.Name)
			controller:Start()
		end
	end
end