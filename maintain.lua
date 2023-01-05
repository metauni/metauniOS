local placeIds = require "placeIds"

print("START")

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

elseif #args >= 1 then

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
	
	local function writeFromModelFile(container, filename)
		
		local model = remodel.readModelFile(filename)[1]

		model.Parent = container
		print(("Added %s.%s"):format(container.Name, model.Name))
	end

	-- UPDATES GO HERE

	local removals = {

		[game.ReplicatedStorage] = {
			"GiveVRChalk",
			"MetaChalk",
			"MetaAdmin",
			"Chalk",
		},
	
		[game.ServerScriptService] = {
			"metaportal",
			"orb",
			"ManageVRChalk",
			"metaboard",
		},
	
		[game.StarterPlayer.StarterPlayerScripts] = {
			"ManageVRChalk",
		},

		[game.Chat] = {
			"ChatModules",
		},
	}

	for container, names in pairs(removals) do
		
		for _, name in ipairs(names) do
			
			removeAll(container, name)
		end
	end

	writeFromModelFile(game.ReplicatedStorage, "Chalk.rbxmx")
	writeFromModelFile(game.Chat, "ChatModules.rbxm")

	-- UTC timestamp that matches the format used in Version History

	while true do

		local timestamp = os.date("!%m/%d/%Y %I:%M:%S %p")

		print("Publishing updated place to "..placeId, "(timestamp: "..timestamp..")")
		local success, result = pcall(remodel.writeExistingPlaceAsset, game, placeId)
		
		if success then
			
			print(("Version History: https://www.roblox.com/places/%s/update#"):format(placeId))
			break
		else
			
			print("Publish failed:", result)
			print("Retrying (in 10 seconds)...")
			os.execute("sleep " .. tostring(10))
		end
	end
end