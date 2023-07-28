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
	print("Usage: lune publish.luau all")
	print("  lune publish.luau all")
	print("  lune publish.luau <place_name> ...")
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

placeIdsToUpdate = {
	["metauni-dev"] = 10325447437,
}

local function executeAndShow(command: string): ()
	print("> " ..  command)
	local words = command:split(" ")
	local args = {}
	table.move(words, 2, #words, 1, args)
	local result = process.spawn(words[1], args)
	if not result.ok then
		stdio.ewrite(result.stderr)
		process.exit(1)
	end
	print(result.stdout)
end

local function capture(command: string): string
	local words = command:split(" ")
	local args = {}
	table.move(words, 2, #words, 1, args)
	local result = process.spawn(words[1], args)
	if not result.ok then
		stdio.ewrite(result.stderr)
		process.exit(1)
	end

	return result.stdout
end

local status = capture("git status -sb")
local changes = capture("git status -s -uall")
local hash = capture("git rev-parse --short HEAD")
local branch = capture("git rev-parse --abbrev-ref HEAD")

local uncommittedChanges = string.match(changes, "%S+")
local outOfSyncWithRemote = string.match(status, "%[ahead %d+%]") or string.match(status, "%[behind %d+%]")

hash = string.gsub(hash, '[\n\r]+', '')
branch = string.gsub(branch, '[\n\r]+', '')

local hashVersion = (`{hash..(uncommittedChanges and "*" or "")} ({branch})`)

if uncommittedChanges or outOfSyncWithRemote then
	
	if uncommittedChanges and outOfSyncWithRemote then
		stdio.write(stdio.color("yellow"))
		print(`The git repo for metauniOS ({hashVersion}) contains uncommitted modifications and is out of sync with remote branch.`)
		stdio.write(stdio.color("reset"))
		executeAndShow("git status -sb")
	elseif uncommittedChanges then
		stdio.write(stdio.color("yellow"))
		print(`The git repo for metauniOS ({hashVersion}) contains uncommitted modifications.`)
		stdio.write(stdio.color("reset"))
		executeAndShow("git status -sb")
	elseif outOfSyncWithRemote then
		stdio.write(stdio.color("yellow"))
		print(`The git repo for metauniOS ({hashVersion}) is out of sync with remote branch.`)
		stdio.write(stdio.color("reset"))
		executeAndShow("git status -sb")
	end
	
	local doit = stdio.prompt("confirm", "Publish anyway?")
	if not doit then
		process.exit(0)
	end
end

local buildFileName = "metauniOS.rbxm"
local cmd, args = "rojo", {"build", "release.project.json", "-o", buildFileName}
print(">", cmd, table.unpack(args))
local result = process.spawn(cmd, args)
if not result.ok then
	stdio.ewrite(result.stderr)
	process.exit(1)
end

local buildFile = fs.readFile(buildFileName)
local build = roblox.deserializeModel(buildFile)[1]
local versionValue = roblox.Instance.new("StringValue")
versionValue.Name = "version"
versionValue.Value = hashVersion
versionValue.Parent = build

for placeName, placeId in placeIdsToUpdate do

	stdio.write(stdio.color("blue"))
	print(placeName)
	stdio.write(stdio.color("reset"))

	print("Downloading placeId "..placeId)
	local game = assetApi.downloadPlace(placeId)

	-- Remove existing metauniOS(s)

	local existingVersions = {}

	for _, child in game.ServerScriptService:GetChildren() do
		
		if child.Name == "metauniOS" then
			
			local existingVersionValue = child:FindFirstChild("version")
			if existingVersionValue then
				
				table.insert(existingVersions, existingVersionValue.Value)
			end

			child.Parent = nil
		end
	end

	-- Replace with new metauniOS

	build.Parent = game.ServerScriptService

	-- Remove duplicate version values 

	for _, child in ipairs(game.ServerScriptService:GetChildren()) do
		
		if child.ClassName == "StringValue" and child.Name == "version" then
			
			child.Parent = nil
		end
	end

	stdio.write("Updating: "..table.concat(existingVersions, ", ").." => "..hashVersion)

	while true do
		
		-- UTC timestamp that matches the format used in Version History
		local timestamp = os.date("!%m/%d/%Y %I:%M:%S %p")
	
		local updateLogScript = game:GetService("ServerStorage"):FindFirstChild("metauniOSUpdateLog")
		if not updateLogScript or updateLogScript.ClassName ~= "ModuleScript" then
	
			updateLogScript = roblox.Instance.new("ModuleScript")
			updateLogScript.Name = "metauniOSUpdateLog"
			updateLogScript.Parent = game:GetService("ServerStorage")
	
			updateLogScript.Source = "-- metauniOS Update Log\n"
		end
	
		local existingLog = updateLogScript.Source
	
		updateLogScript.Source = existingLog.."-- "..hashVersion.." "..timestamp.."\n"
	
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
