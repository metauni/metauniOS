local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NexusVRBackpack = ReplicatedStorage.Packages.NexusVRBackpack :: ModuleScript

return {

	Init = function()
		NexusVRBackpack.Parent = ReplicatedStorage
		local NexusVRBackpackModule = require(NexusVRBackpack)
		NexusVRBackpackModule:Load()
	end,
}