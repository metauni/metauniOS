local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Maid = require(script.Parent.Maid)
local Rx = require(script.Parent.Rx)
local Fusion = require(ReplicatedStorage.Packages.Fusion)

-- Rxf provides Rx primitives for interfacing with Fusion.
local export = {}

-- Returns an observable that emits values from a Fusion StateObject
function export.fromState(state: Fusion.StateObject): Rx.Observable
	return Rx.observable(function(sub): Maid.Task
		sub:Fire(state:get(false))
		local conn = Fusion.Observer(state):onChange(function()
			sub:Fire(state:get())
		end)
		return conn
	end)
end

return table.freeze(export)