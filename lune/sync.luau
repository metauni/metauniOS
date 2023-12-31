local process = require "@lune/process"
local stdio = require "@lune/stdio"
local net = require "@lune/net"

local ROJO_PORT = 34872

local function executeAndShow(command: string, quietly: true?): ()
	print("> " ..  command)
	local words = command:split(" ")
	local params = {}
	table.move(words, 2, #words, 1, params)
	local options = {
		stdio = {
			stdout = if quietly then "none" else "inherit",
			stderr = "inherit",
		}
	}
	local result = process.spawn(words[1], params, options)
	if not result.ok then
		process.exit(1)
	end
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

local function checkPortOpen(port)
	local success, handle = pcall(function() return net.serve(port, function(_request) return "boo" end) end)
	if success then
		handle.stop()
	end
	return success
end

if not checkPortOpen(ROJO_PORT) then
	stdio.ewrite(`Cannot start rojo server with port {ROJO_PORT} (in use)`)
	process.exit(1)
end

-- Update submodules (will fail here if there are local uncommitted changes)
executeAndShow("git submodule update --remote")
-- Update wally packages
executeAndShow("wally install")
-- Create sourcemap for wally-package-types
executeAndShow("rojo sourcemap -o sourcemap.json")
-- Add types to wally packages
executeAndShow("wally-package-types --sourcemap sourcemap.json Packages", true)
-- Start rojo server
executeAndShow(`rojo serve --port {ROJO_PORT}`)