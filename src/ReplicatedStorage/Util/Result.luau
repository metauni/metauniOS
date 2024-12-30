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

	-- Function wrapping
	-- Using Result.pcall to handle errors directly
	local riskyFn = function(x: number)
		if x < 0 then error("Must be positive") end
		return x * 2
	end
	local result = Result.pcall(riskyFn, -1) -- Returns Err with error message

	-- Using Result.wrap to create safe function
	local safeFn = Result.wrap(riskyFn) -- Creates new function returning Result
	local result = safeFn(-1) -- Same behavior but as reusable function

	-- Chaining operations
	local result = divide(10, 2)
	result = Result.andThen(result, function(value)             -- Chain another Result operation
		return divide(value, 2)
	end)
	result = Result.map(result, function(value)                 -- Transform success value
		return value * 2
	end)

	-- Handling Results
	-- Pattern matching
	Result.match(result, {
		ok = function(value) print(value) end,
		err = function(reason) warn(reason) end,
	})

	-- Unwrapping
	local value = Result.unwrapOr(result, 0)     -- Safe unwrap with default
	local value = Result.unwrap(result)          -- Throws if error

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
	Result.wrap(fn) -> (args...) -> Result
	Result.retryAsync(options, fn, ...args) -> Result
	Result.unwrap(result) -> T
	Result.unwrapOr(result, default) -> T
	Result.unwrapErr(result) -> string
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

-- Calls pcall with fn and args and wraps output in a Result
function Result.pcall<T, U...>(fn: (U...) -> T, ...: U...): Result<T>
	local success, result: any = pcall(fn, ...)
	if success then
		return Result.ok(result)
	else
		return Result.err(tostring(result))
	end
end

-- Turn a function that errors into a function that returns a Result
function Result.wrap<T, U...>(fn: (U...) -> T): (U...) -> Result<T>
	return function(...)
		return Result.pcall(fn, ...)
	end
end

--[[
	Retries a Result-returning operation with configurable attempts and delays.

	Parameters:
		options: Configuration table
			maxAttempts (number?, default: 3) - Maximum number of retry attempts
			delaySeconds (number?, default: 0) - Delay between retries in seconds
		fn: Function that returns a Result<T>
		...: Arguments passed to fn

	Returns: Result<T>
		Ok<T> on success
		Err on max attempts exceeded with combined error info
]]
function Result.retryAsync<T, U...>(
	options: { maxAttempts: number?, delaySeconds: number? },
	fn: (U...) -> Result<T>,
	...: U...
): Result<T>
	local maxAttempts = options.maxAttempts or 3
	local delaySeconds = options.delaySeconds or 0

	assert(maxAttempts > 0, "maxAttempts must be greater than 0")
	assert(delaySeconds >= 0, "delaySeconds must be non-negative")

	local lastError
	for attempt = 1, maxAttempts do
		local result = fn(...)

		if result.success then
			return result
		end

		lastError = result.reason

		-- If this isn't the last attempt, wait before trying again
		if attempt < maxAttempts and delaySeconds > 0 then
			task.wait(delaySeconds)
		end
	end

	return Result.err(`Failed after {maxAttempts} attempts. Last error: {lastError}`)
end

-- Unwrapping
function Result.unwrap<T>(result: Result<T>): T
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
