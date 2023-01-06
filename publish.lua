local placeIds = require "placeIds"

local args = {...}

local placeIdsToUpdate = {}

if #args == 0 then
	
	print("No arguments provided. Specify \"all\" or list place names.")
	print("Usage: remodel run publish.lua all")
	print("  remodel run publish.lua all")
	print("  remodel run publish.lua <place_name> ...")
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

local function execute(command)
	print("> " ..  command)
	local success = os.execute(command)
	if not success then
		os.exit(0)
	end
end

local function capture(cmd)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  return s
end

local status = capture("git status -s -uall")
local remoteStatus = capture("git status -uno")
local hash = capture("git rev-parse --short HEAD")
local branch = capture("git rev-parse --abbrev-ref HEAD")

local uncommittedChanges = string.match(status, "%S+")
local outOfSyncWithRemote = string.match(remoteStatus, "%S+")

hash = string.gsub(hash, '[\n\r]+', '')
branch = string.gsub(branch, '[\n\r]+', '')

local hashVersion = ("%s (%s)"):format(hash..(uncommittedChanges and "*" or ""), branch)

if uncommittedChanges or outOfSyncWithRemote then
	
	if uncommittedChanges and outOfSyncWithRemote then
		print(("The git repo for metauniOS (%s) contains uncommitted modifications and is out of sync with remote branch."):format(hashVersion))
		print(status)
		print(remoteStatus)
	elseif uncommittedChanges then
		print(("The git repo for metauniOS (%s) contains uncommitted modifications."):format(hashVersion))
		print(status)
	elseif outOfSyncWithRemote then
		print(("The git repo for metauniOS (%s) is out of sync with remote branch."):format(hashVersion))
		print(remoteStatus)
	end
	
	local answer
	local answerMap = { [""] = "y", y = "y", yes = "y", no = "n", n = "n" }
	
	repeat
		io.write("Publish anyway (Y/n)? ")
		io.flush()
		
		answer = answerMap[io.read("*line"):gsub("%s+", ""):lower()]
	until answer
	
	if answer == "n" then
		return
	end
end

local buildFileName = "metauniOS.rbxmx"
execute(
	("rojo build -o \"%s\" \"%s\"")
	:format(buildFileName, "release.project.json")
)

local build = remodel.readModelFile(buildFileName)[1]
local versionValue = Instance.new("StringValue")
versionValue.Name = "version"
remodel.setRawProperty(versionValue, "Value", "String", hashVersion)
versionValue.Parent = build

for placeName, placeId in pairs(placeIdsToUpdate) do

	print(string.rep("-", 20))
	print(placeName)
	print(string.rep("-", 20))

	print("Downloading placeId "..placeId)
	local game = remodel.readPlaceAsset(placeId)

	-- Remove existing metauniOS(s)

	local existingVersions = {}

	for _, child in ipairs(game.ServerScriptService:GetChildren()) do
		
		if child.Name == "metauniOS" then
			
			local existingVersionValue = child:FindFirstChild("version")
			if existingVersionValue then
				
				table.insert(existingVersions, remodel.getRawProperty(existingVersionValue, "Value"))
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

	print("metauniOS: "..table.concat(existingVersions, ", ").." => "..hashVersion)

	-- UTC timestamp that matches the format used in Version History

	while true do
		
		local timestamp = os.date("!%m/%d/%Y %I:%M:%S %p")
	
		local updateLogScript = game:GetService("ServerStorage"):FindFirstChild("metauniOSUpdateLog")
		if not updateLogScript or updateLogScript.ClassName ~= "ModuleScript" then
	
			updateLogScript = Instance.new("ModuleScript")
			updateLogScript.Name = "metauniOSUpdateLog"
			updateLogScript.Parent = game:GetService("ServerStorage")
	
			remodel.setRawProperty(updateLogScript, "Source", "String", "-- metauniOS Update Log\n")
		end
	
		local existingLog = remodel.getRawProperty(updateLogScript, "Source")
	
		remodel.setRawProperty(updateLogScript, "Source", "String", existingLog.."-- "..hashVersion.." "..timestamp.."\n")
	
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
