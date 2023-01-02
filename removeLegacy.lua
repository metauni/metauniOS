local ReplicatedStorage = game:GetService("ReplicatedStorage")
local placeIds = require "placeIds"

local args = {...}

local placeIdsToUpdate = {}

if #args == 0 then
	
	print("No arguments provided. Specify \"all\" or list place names.")
	print("Usage: remodel run removeLegacy.lua all")
	print("  remodel run removeLegacy.lua all")
	print("  remodel run removeLegacy.lua <place_name> ...")
	return
end

if #args == 1 and args[1] == "all" then

	placeIdsToUpdate = placeIds

elseif #args > 1 then

	for _, placeName in ipairs(args) do
		
		if placeIds[placeName] then
			
			placeIdsToUpdate[placeName] = placeIds[placeName]
		else

			error(placeName.." not listed in placeIds")
		end
	end
end

for placeName, placeId in pairs(placeIdsToUpdate) do

	print(string.rep("-", 20))
	print(placeName)
	print(string.rep("-", 20))

	print("Downloading placeId "..placeId)
	local game = remodel.readPlaceAsset(placeId)

	local function removeAll(container, instanceName)
		
		for _, child in ipairs(container:GetChildren()) do
			
			if child.Name == instanceName then
				
				child.Parent = nil
				print(("Removed %s.%s"):format(container.Name, instanceName))
			end
		end
	end

	-- REMOVALS GO HERE
	removeAll(game.ServerScriptService, "astrotube")

	-- UTC timestamp that matches the format used in Version History

	local timestamp = os.date("!%m/%d/%Y %I:%M:%S %p")

	print("Publishing updated place to "..placeId, "(timestamp: "..timestamp..")")
	remodel.writeExistingPlaceAsset(game, placeId)
	print(("Version History: https://www.roblox.com/places/%s/update#"):format(placeId))
end