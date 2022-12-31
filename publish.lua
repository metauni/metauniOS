local placeIds = require "placeIds"

local args = {...}

if #args > 0 then
	
	local newPlaceIds = {}

	for _, placeName in ipairs(args) do
		
		if placeIds[placeName] then
			
			newPlaceIds[placeName] = placeIds[placeName]
		else

			error(placeName.." not listed in placeIds")
		end
	end

	placeIds = newPlaceIds
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
local hash = capture("git rev-parse --short HEAD")
local branch = capture("git rev-parse --abbrev-ref HEAD")

local uncommittedChanges = string.match(status, "%S+")

hash = string.gsub(hash, '[\n\r]+', '')
branch = string.gsub(branch, '[\n\r]+', '')

local hashVersion = ("%s (%s)"):format(hash..(uncommittedChanges and "*" or ""), branch)

if uncommittedChanges then
	
	print(("The git repo for metauniOS (%s) contains uncommitted modifications."):format(hashVersion))
	
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

for placeName, placeId in pairs(placeIds) do

	print(string.rep("-", 20))
	print(placeName)
	print(string.rep("-", 20))

	print("Downloading placeId "..placeId)
	local game = remodel.readPlaceAsset(placeId)

	-- Remove existing metauniOS(s)

	local existingVersions = {}

	for _, child in ipairs(game.ServerScriptService:GetChildren()) do
		
		if child.Name == "metauniOS" then
			
			local oldVersion do
				
				local existingVersionValue = child:FindFirstChild("version")
				if existingVersionValue then
					
					table.insert(existingVersions, remodel.getRawProperty(existingVersionValue, "Value"))
				end
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
	remodel.writeExistingPlaceAsset(game, placeId)
	print(("Version History: https://www.roblox.com/places/%s/update#"):format(placeId))
end