local roblox = require "@lune/roblox"
local fs = require "@lune/fs"
local process = require "@lune/process"
local stdio = require "@lune/stdio"
local task = require "@lune/task"
local assetApi = require "assetApi"

local placeIds = require "placeIds"

local placeIdsToUpdate = {}

if #process.args == 0 then
	
	print("No arguments provided. Specify \"all\" or list place names.")
	print("Usage:")
	print("  lune maintain all")
	print("  lune maintain <place_name> ...")
	return
end

if table.find(process.args, "all") then
	placeIdsToUpdate = placeIds
else
	for _, arg in ipairs(process.args) do
		if placeIds[arg] then
			placeIdsToUpdate[arg] = placeIds[arg]
		else
			error(arg.." not listed in placeIds")
		end
	end
end

for placeName, placeId in pairs(placeIdsToUpdate) do

	stdio.write(stdio.color("blue"))
	print(placeName)
	stdio.write(stdio.color("reset"))

	print("Downloading placeId "..placeId)
	local game = assetApi.downloadPlace(placeId)

	local function removeAllNamed(container, instanceName)
		for _, child in ipairs(container:GetChildren()) do
			if child.Name == instanceName then
				child.Parent = nil
				print(`Removed {container.Name}.{instanceName}`)
			end
		end
	end

	-- UPDATES GO HERE

	local removals = {

		-- Example
		-- [game.Chat] = {
		-- 	"ChatModules",
		-- },
	}

	for container, names in pairs(removals) do
		for _, name in ipairs(names) do
			removeAllNamed(container, name)
		end
	end

	-- UTC timestamp that matches the format used in Version History

	while true do

		local timestamp = os.date("!%m/%d/%Y %I:%M:%S %p")
	
		local response = assetApi.publishExistingPlace(game, placeId)
		
		if response.ok then
			stdio.write(stdio.color("green").." ✔ "..stdio.color("reset").."\n")
			print("Timestamp: "..timestamp)
			print(`Version History: https://www.roblox.com/places/{placeId}/update#`)
			break
		else
			stdio.write(stdio.color("red").." ✘ "..stdio.color("reset").."\n")
			print(
				"Publish failed:",
				tostring(response.statusCode),
				tostring(response.statusMessage)
			)
			print(tostring(response.body))
			stdio.write("Retrying (in 10 seconds)...")
			task.wait(10)
		end
	end
end