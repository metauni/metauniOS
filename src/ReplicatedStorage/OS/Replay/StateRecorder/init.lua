local ReplicatedStorage = game:GetService("ReplicatedStorage")

local t = require(ReplicatedStorage.Packages.t)
local Maid = require(ReplicatedStorage.Util.Maid)
local Rx = require(ReplicatedStorage.Util.Rx)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)

export type StateRecord = {
	RecordType: "StateRecord",
	StateType: string,
	StateInfo: {[any]: any?},
	Timeline: {any},
}

local function checkJSONable(value)
	if typeof(value) == "number"
		or typeof(value) == "string"
		or typeof(value) == "boolean"
		or typeof(value) == "nil"
	then
		return true
	end
	if typeof(value) ~= "table" then
		return false, `JSONable type expected, got {typeof(value)}`
	end

	for key, item in value do
		if typeof(key) ~= "number" and typeof(key) ~= "string" then
			return false, `JSONable keys expected, got {typeof(key)} key`
		end
		local ok, msg = checkJSONable(item)
		if not ok then
			return false, `[JSONable] Bad value at key {key}: {msg}`
		end
	end
	return true
end

local checkProps = t.strictInterface {
	Observable = function(value)
		if Rx.isObservable(value) then
			return true
		else
			return false, `Observable expected, got {typeof(value)}`
		end
	end,
	StateType = t.string,
	StateInfo = t.every(t.table, checkJSONable),
}

local function StateRecorder(props: {
		Observable: Rx.Observable,
		StateType: string,
		StateInfo: {[any]: any?},
	}): StateRecorder

	assert(checkProps(props))
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap(), props = props, RecorderType = "StateRecorder" }

	local Timeline = maid:Add(ValueObject.new({}))
	
	function self.FlushToRecord(): StateRecord
		local record = {
			RecordType = "StateRecord",
			StateType = props.StateType,
			StateInfo = props.StateInfo,
			Timeline = Timeline.Value,
		}
		Timeline.Value = {}
		return record
	end

	function self.Start(startTime)
		maid._recording = props.Observable:Subscribe(function(state: any)
			local now = os.clock() - startTime
			assert(checkJSONable(state))
			table.insert(Timeline.Value, {now, state})
		end)
	end

	function self.Stop()
		maid._recording = nil
	end

	return self
end

export type StateRecorder = typeof(StateRecorder(nil :: any))

return StateRecorder