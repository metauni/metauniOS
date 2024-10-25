local GoodSignal = require(script.Parent.GoodSignal)
local Stream = require(script.Parent.Stream)

export type Stream<T...> = Stream.Stream<T...>
export type Signal<T...> = GoodSignal.Signal<T...>
export type CleanupTask = Stream.CleanupTask

export type Map<K,V> = {
	-- If you modify .Map directly, .Changed won't fire
	Map: {[K]: V},
	Get: (self: Map<K,V>, key: K) -> V?,
	-- Updates self.Map[key], fires a change if it's different
	Set: (self: Map<K,V>, key: K, value: V?) -> (),
	Changed: Signal<K,V?>,
	
	StreamPairs: (self: Map<K,V>) -> Stream<K,V?>,
	StreamKey: (self: Map<K,V>, key: K) -> Stream<V?>,
	SetTidy: (self: Map<K,V>, key: K, value: V?, cleanup: CleanupTask) -> (),
	Wait: (self: Map<K,V>, key: K) -> V,
	ListenTidyPairs: (self: Map<K,V>, tidyListender: (K,V?) -> CleanupTask) -> CleanupTask,
	Destroy: (self: Map<K,V>) -> (),
}

local Map = {}
Map.__index = Map
Map.ClassName = "Map"

function Map.Get<K,V>(self: Map<K,V>, key: K): V?
	return self.Map[key]
end

function Map.Set<K,V>(self: Map<K,V>, key: K, value: V?)
	local oldValue = self.Map[key]
	if value == oldValue then
		return
	end
	Stream.clean((self :: any)._keyCleanups[key])
	;(self :: any)._keyCleanups[key] = nil
	self.Map[key] = value :: any
	self.Changed:Fire(key, value)
end

--[[
	Same as `Map:Set(key, value)`, but stores a cleanup task that will be cleaned
	up the next time the value at `key` is changed.
]]
function Map.SetTidy<K,V>(self: Map<K,V>, key: K, value: V?, cleanup: CleanupTask): ()
	local oldValue = self.Map[key]
	if value ~= oldValue then
		Stream.clean((self :: any)._keyCleanups[key])
		;(self :: any)._keyCleanups[key] = nil
		self.Map[key] = value :: any
	end

	if cleanup ~= nil then
		local existing = (self :: any)._keyCleanups[key]
		if existing then
			table.insert(existing, cleanup)
		else
			(self :: any)._keyCleanups[key] = {cleanup}
		end
	end

	if value ~= oldValue then
		self.Changed:Fire(key, value)
	end
end

function Map.StreamPairs<K,V>(self: Map<K,V>): Stream<K,V?>
	return (self :: any)._stream
end

function Map.StreamKey<K,V>(self: Map<K,V>, key: K): Stream<V?>
	return function(listener)
		--[[
			This is probably suboptimal, but I think using this is an anti-pattern
			anyway.
		]]
		return (self :: any)._stream(function(changedKey, value)
			if changedKey == key then
				listener(value)
			end
		end)
	end
end

function Map.Wait<K,V>(self: Map<K,V>, key: K): V
	if self.Map[key] ~= nil then
		return self.Map[key]
	end
	
	while true do
		local changedKey, value = self.Changed:Wait()
		if changedKey == key and value ~= nil then
			return value
		end
	end
end

function Map.ListenTidyPairs<K,V>(self: Map<K,V>, tidyListender: (K,V?) -> CleanupTask): CleanupTask
	return Stream.listenTidyPairs((self :: any)._stream, tidyListender)
end

function Map.Destroy<K,V>(self: Map<K,V>)
	self.Changed:Destroy()
	local key, cleanup = next((self :: any)._keyCleanups)
	while cleanup ~= nil do
		Stream.clean(cleanup)
		;(self :: any)._keyCleanups[key :: any] = nil
		key, cleanup = next((self :: any)._keyCleanups)
	end
	table.clear(self)
	setmetatable(self, nil)
end

table.freeze(Map)

return function<K,V>(initial: {[K]: V}?): Map<K,V>
	local self = {
		Map = if typeof(initial)=="table" then initial else {},
		Changed = GoodSignal.new(),
	}

	self._stream = function(listener)
		for key, value in self.Map do
			listener(key, value)
		end

		return self.Changed:Connect(listener)
	end :: Stream<K,V?>

	self._keyCleanups = {}

	return setmetatable(self, Map) :: any
end