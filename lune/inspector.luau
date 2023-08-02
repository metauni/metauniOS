local roblox = require "@lune/roblox"
-- local fs = require "@lune/fs"
-- local process = require "@lune/process"
local stdio = require "@lune/stdio"
local task = require "@lune/task"
local assetApi = require "assetApi"
local metauni = require "metauni"

local inspector = {}

-- Doesn't work yet because of https://github.com/filiptibell/lune/issues/76
function inspector.iterPlaces()
	if true then
		error("NOT WORKING")
	end
	-- if true then
	-- end
	local co = coroutine.create(function () 
		for placeName, placeId in metauni.PlaceIds do
			local game = assetApi.downloadPlace(placeId)
			coroutine.yield(placeName, game)
		end
	end)
	return function ()
		local success, res = coroutine.resume(co)
		if not success then
			error(res)
		end
		return res
	end
end

function inspector.forPlaces(callback: (string, roblox.DataModel) -> ())
	for placeName, placeId in metauni.PlaceIds do
		local game = assetApi.downloadPlace(placeId)
		callback(placeName, game)
	end
end

function inspector.scriptsMatching(game: roblox.DataModel, pattern: string)
	local scripts = {}

	for _, desc in game:GetDescendants() do
		if table.find({"Script", "LocalScript", "ModuleScript"}, desc.ClassName) then
			if string.match(desc.Source, pattern) then
				table.insert(scripts, desc)
			end
		end
	end

	return scripts
end

function inspector.linesMatchingInScript(script: Script | ModuleScript | LocalScript, pattern: string)
	local lines = {}

	for line in script.Source:gmatch("[^\r\n]+") do
		if string.match(line, pattern) then
			table.insert(lines, line)
		end
	end

	return lines
end

function inspector.linesMatching(game: roblox.DataModel, pattern: string)
	local scripts = inspector.scriptsMatching(game, pattern)
	local scriptLinePairs = {}
	for _, script in scripts do
		for _, line in inspector.linesMatchingInScript(script, pattern) do
			table.insert(scriptLinePairs, {script, line})
		end
	end
	return scriptLinePairs
end

function inspector.findDuplicates(instance: roblox.Instance | roblox.DataModel)
	for _, desc in instance:GetDescendants() do
		if desc:GetFullName():match("AvatarEditorBuild") then
			continue
		end
		local counts = {} -- [name] -> count
		for _, child in desc:GetChildren() do
			counts[child.Name] = (counts[child.Name] or 0) + 1
		end

		for name, count in counts do
			if count > 1 then
				print(`{desc:GetFullName()}.{name} (x{count})`)
			end
		end
	end
end

return inspector