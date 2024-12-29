--!strict
-- Result.luau
--[[
	Result.luau
	A Result type implementation for handling success/failure operations.

	Usage:
	local Result = require("Result")

	-- Creating Results
	local ok = Result.ok(123)                -- Ok<number>
	local err = Result.err("failed")         -- Err<string>

	-- Function returning Result
	local function divide(a: number, b: number): Result<number, string>
	if b == 0 then
		return Result.err("Division by zero")
	end
		return Result.ok(a / b)
	end

	-- Chaining operations
	local result = divide(10, 2)
	result = Result.andThen(result, function(value)             -- Chain another Result operation
		return divide(value, 2)
	end)
	result = Result.map(result, function(value)                 -- Transform success value
		return value * 2
	end)

	-- Handling Results
	-- Method 1: Pattern matching
	Result.match(result, {
		ok = function(value) print(value) end,
		err = function(reason) warn(reason) end,
	})

	-- Method 2: Unwrapping
	local value = Result.unwrapOr(result, 0)     -- Safe unwrap with default
	local value = Result.unwrap(result)          -- Throws if error

	-- Method 3: Conditional
	if Result.isOk(result) then
		print(result.data)
	else
		warn(result.reason)
	end

	-- Safe pcall wrapper
	local result = Result.pcall(function()
		error("boom")
	end)                                         -- Returns Err instead of throwing

	-- Working with multiple Results
	local results = Result.all({                 -- Combines multiple Results
		Result.ok(1),
		Result.ok(2),
		Result.ok(3),
	})

	API:
	Result.ok(value: T) -> Ok<T>
	Result.err(reason: string) -> Err<string>
	Result.pcall(fn, ...args) -> Result
	Result.unwrap(result) -> T
	Result.unwrapOr(result, default) -> T
	Result.unwrapErr(result) -> string
	Result.isOk(result) -> boolean
	Result.isErr(result) -> boolean
	Result.map(result, fn) -> Result
	Result.mapErr(result, fn) -> Result
	Result.andThen(result, fn) -> Result
	Result.orElse(result, fn) -> Result
	Result.all(results) -> Result
	Result.match(result, { ok, err }) -> U
	Result.toMaybe(result) -> T?
	Result.isResult(value) -> boolean
]]

export type Ok<T> = {
	success: true,
	data: T,
}

export type Err = {
	success: false,
	reason: string,
}

export type Result<T> = Ok<T> | Err

local Result = {}

-- Constructors
function Result.ok<T>(value: T): Ok<T>
	return { success = true, data = value }
end

function Result.err(reason: string): Err
	return { success = false, reason = reason }
end

-- Wraps pcall output in a Result
function Result.pcall<T, U...>(fn: (U...) -> T, ...: U...): Result<T>
	local success, result: any = pcall(fn, ...)
	if success then
		return Result.ok(result)
	else
		return Result.err(tostring(result))
	end
end

-- Unwrapping
function Result.unwrap<T>(result: Result<T>): T
	if not result.success then
		error(result.reason)
	end
	return result.data
end

function Result.unwrapOrError<T>(result: Result<T>): T
	if not result.success then
		error(result.reason)
	end
	return result.data
end

function Result.unwrapOr<T>(result: Result<T>, default: T): T
	if result.success then
		return result.data
	end
	return default
end

function Result.unwrapErr<T>(result: Result<T>): string
	assert(not result.success, "Called unwrapErr on an Ok value")
	return result.reason
end

-- Transforming
function Result.map<T, U>(result: Result<T>, fn: (T) -> U): Result<U>
	if result.success then
		return Result.ok(fn(result.data))
	end
	return result
end

function Result.mapErr<T>(result: Result<T>, fn: (string) -> string): Result<T>
	if result.success then
		return result
	end
	return Result.err(fn(result.reason))
end

-- Chaining
function Result.andThen<T, U>(result: Result<T>, fn: (T) -> Result<U>): Result<U>
	if result.success then
		return fn(result.data)
	end
	return result
end

function Result.orElse<T>(result: Result<T>, fn: (string) -> Result<T>): Result<T>
	if result.success then
		return result
	end
	return fn(result.reason)
end

-- Combining multiple results
function Result.all<T>(results: { Result<T> }): Result<{ T }>
	local values = {}
	for i, result in results do
		if result.success then
			values[i] = result.data
		else
			return Result.err(result.reason)
		end
	end
	return Result.ok(values)
end

-- Match pattern
function Result.match<T, U...>(
	result: Result<T>,
	options: {
		ok: (T) -> U...,
		err: (string) -> U...,
	}
): U...
	if result.success then
		return options.ok(result.data)
	else
		return options.err(result.reason)
	end
end

-- Optional conversion
function Result.toMaybe<T>(result: Result<T>): T?
	if result.success then
		return result.data
	end
	return nil
end

-- Type guard (useful for type narrowing)
function Result.isResult(value: any): boolean
	return type(value) == "table" and (value.success == true or value.success == false)
end

return Result
