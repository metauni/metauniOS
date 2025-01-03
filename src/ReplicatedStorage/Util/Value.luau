local GoodSignal = require(script.Parent.GoodSignal)
local Stream = require(script.Parent.Stream)

export type Value<T> = {
	Value: T,
	Changed: GoodSignal.Signal<T>,
	Stream: (self: any) -> Stream.Stream<T>,
	Destroy: (self: any) -> (),
}

local Value = { ClassName = "Value" }

function Value.Stream<T>(self: Value<T>): Stream.Stream<T>
	return (self :: any)._stream
end

function Value.Destroy<T>(self: Value<T>)
	rawset(self, "_value", nil)
	local signal = rawget(self, "Changed")
	if signal then
		signal:Destroy()
	end
	table.clear(self)
	setmetatable(self, nil)
end

function Value.__index<T>(self: Value<T>, index)
	if index == "Value" then
		return rawget(self, "_value")
	elseif index == "Changed" then
		return rawget(self, "Changed")
	elseif Value[index] then
		return Value[index]
	else
		error(`{index} is not a readable member of Value object`)
	end
end

function Value.__newindex<T>(self: Value<T>, index: "Value", value: T)
	if index ~= "Value" then
		error(`{index} is not a writable member of Value object`)
	end
	local oldValue = rawget(self, "_value")
	if value ~= oldValue then
		rawset(self, "_value", value)
		self.Changed:Fire(value)
	end
end

table.freeze(Value)

return function<T>(initial: T): Value<T>
	local self = {
		_value = initial,
		Changed = GoodSignal.new(),
	}

	-- Create this closure just once here
	function self._stream(listener: (T) -> ())
		listener(rawget(self, "_value"))
		return self.Changed:Connect(listener)
	end

	return setmetatable(self :: any, Value)
end
