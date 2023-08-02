--!nocheck
local roblox = require "@lune/roblox"

--[[
	This must be kept up to date with changes to rojo file structure
]]
return function(build: roblox.DataModel, target: roblox.DataModel)

	local function replaceAllChildren(from, to)
		for _, fromChild in from:GetChildren() do

			-- First delete any existing children of "to" with the same name
			for _, toChild in to:GetChildren() do
				if toChild.Name == fromChild.Name then
					toChild:Destroy()
				end
			end

			fromChild:Clone().Parent = to
		end
	end

	replaceAllChildren(build.ServerScriptService, target.ServerScriptService)
	replaceAllChildren(build.ReplicatedStorage, target.ReplicatedStorage)
	replaceAllChildren(build.StarterPlayer.StarterPlayerScripts, target.StarterPlayer.StarterPlayerScripts)
end