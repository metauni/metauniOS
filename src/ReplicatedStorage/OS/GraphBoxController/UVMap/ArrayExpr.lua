--[[
	Expression datatype, stored as an array using prefix notation
]]

local ArrayExpr = {}
ArrayExpr.__index = ArrayExpr

function ArrayExpr.appOne(op, arg)
	local expression = {op}
	if typeof(arg) == "table" then
		table.move(arg, 1, #arg, 2, expression)
	else
		table.insert(expression, arg)
	end

	return expression
end

function ArrayExpr.appTwo(op, first, second)
	local expression = {op}
	if typeof(first) == "table" then
		table.move(first, 1, #first, 2, expression)
	else
		table.insert(expression, first)
	end

	if typeof(second) == "table" then
		table.move(second, 1, #second, #expression+1, expression)
	else
		table.insert(expression, second)
	end
	
	return expression
end

-- function Expression._validateExpr(expr, funcSet, varSet)
-- 	if typeof(expr) == "number" then
-- 		return
-- 	elseif typeof(expr) == "string" then
-- 		if varSet and not varSet[varSet] then
-- 			error(`Var {expr} not recognised`)
-- 		end
-- 		return
-- 	elseif typeof(expr) == "table" then

-- 		assert(#expr ~= 0, "Expression empty")

-- 		if #expr == 2 then
-- 			local func = expr[1]
-- 			if not func or (funcSet and not funcSet[func]) then
-- 				error(`Function {func} not recognised in expression`)
-- 			end
-- 		end
-- 	else
-- 		error(`Cannot evaluate expression '{expression}'`)
-- 	end
-- end

function ArrayExpr.fromRecExpr(recExpr)
	-- TODO: write validator for RecExpr

	if typeof(recExpr) == "number" or typeof(recExpr) == "string" then
		return recExpr
	end

	if #recExpr == 2 then
		return ArrayExpr.appOne(recExpr[1], ArrayExpr.fromRecExpr(recExpr[2]))
	elseif #recExpr == 3 then
		return ArrayExpr.appTwo(recExpr[1], ArrayExpr.fromRecExpr(recExpr[2]), ArrayExpr.fromRecExpr(recExpr[3]))
	else
		error(`Unexpected expression table size: {#recExpr}`)
	end
end

function ArrayExpr.evalNoChecksReuseStack(expression: {string | number}, varValues: {[string]: number}, funcValues: {[string]: (number) -> number}, evalStack: {number}): number?
	
	if typeof(expression) == "number" then
		return expression
	elseif typeof(expression) == "string" then
		return varValues[expression]
	elseif typeof(expression) == "table" then
		-- local evalStack = table.create(math.ceil(#expression/2))
		local s = 0 -- stack pointer

		for i=#expression, 1, -1 do
			local token = expression[i]
			if typeof(token) == "number" then
				s += 1
				evalStack[s] = token
			elseif typeof(token) == "string" then
				local varValue = varValues[token]

				if varValue then
					s += 1
					evalStack[s] = varValue
					
				-- INFIX OPERATORS
				elseif token == "+" then
					evalStack[s-1] = evalStack[s] + evalStack[s-1]
					s -= 1
				elseif token == "-" then
					evalStack[s-1] = evalStack[s] - evalStack[s-1]
					s -= 1
				elseif token == "*" then
					evalStack[s-1] = evalStack[s] * evalStack[s-1]
					s -= 1
				elseif token == "/" then
					evalStack[s-1] = evalStack[s] / evalStack[s-1]
					s -= 1
				elseif token == "^" then
					evalStack[s-1] = evalStack[s] ^ evalStack[s-1]
					s -= 1

				-- FUNCTION APPLICATION
				else
					local funcValue = funcValues[token]
					local arg = evalStack[s]
					evalStack[s] = funcValue(arg)
				end
			end
		end

		return evalStack[1]
	end

	return nil
end

function ArrayExpr.evalNoChecks(expression: {string | number}, varValues: {[string]: number}, funcValues: {[string]: (number) -> number}): number?
	
	if typeof(expression) == "number" then
		return expression
	elseif typeof(expression) == "string" then
		return varValues[expression]
	elseif typeof(expression) == "table" then
		local evalStack = table.create(math.ceil(#expression/2))
		local s = 0 -- stack pointer

		for i=#expression, 1, -1 do
			local token = expression[i]
			if typeof(token) == "number" then
				s += 1
				evalStack[s] = token
			elseif typeof(token) == "string" then
				local varValue = varValues[token]

				if varValue then
					s += 1
					evalStack[s] = varValue
					
				-- INFIX OPERATORS
				elseif token == "+" then
					evalStack[s-1] = evalStack[s] + evalStack[s-1]
					s -= 1
				elseif token == "-" then
					evalStack[s-1] = evalStack[s] - evalStack[s-1]
					s -= 1
				elseif token == "*" then
					evalStack[s-1] = evalStack[s] * evalStack[s-1]
					s -= 1
				elseif token == "/" then
					evalStack[s-1] = evalStack[s] / evalStack[s-1]
					s -= 1
				elseif token == "^" then
					evalStack[s-1] = evalStack[s] ^ evalStack[s-1]
					s -= 1

				-- FUNCTION APPLICATION
				else
					local funcValue = funcValues[token]
					local arg = evalStack[s]
					evalStack[s] = funcValue(arg)
				end
			end
		end

		return evalStack[1]
	end

	return nil
end

function ArrayExpr.eval(expression: {string | number}, varValues: {[string]: number}, funcValues: {[string]: (number) -> number}): number
	
	if typeof(expression) == "number" then
		return expression
	elseif typeof(expression) == "string" and expression:match("%-?%a") then
		local value = varValues[expression]
		if not value then
			error(`No value given for variable '{expression}'`)
		end
		
		assert(typeof(value) == "number", `Value {value} for variable '{expression}' is not a number.`)
		return value
	elseif typeof(expression) == "table" then
		assert(#expression ~= 0, "Cannot evaluate empty expression")
		local evalStack = {}

		for i=#expression, 1, -1 do
			local token = expression[i]
			if typeof(token) == "number" then
				table.insert(evalStack, token)
			elseif typeof(token) == "string" then
				local varValue = varValues[token]

				if varValue then
					table.insert(evalStack, varValue)
					
				-- INFIX OPERATORS
				elseif token == "+" then
					assert(#evalStack >= 2, "Failed stack eval, not enough args")
					local first = evalStack[#evalStack]
					evalStack[#evalStack] = nil
					local second = evalStack[#evalStack]
					evalStack[#evalStack] = nil
					table.insert(evalStack, first + second)
				elseif token == "-" then
					assert(#evalStack >= 2, "Failed stack eval, not enough args")
					local first = evalStack[#evalStack]
					evalStack[#evalStack] = nil
					local second = evalStack[#evalStack]
					evalStack[#evalStack] = nil
					table.insert(evalStack, first - second)
				elseif token == "*" then
					assert(#evalStack >= 2, "Failed stack eval, not enough args")
					local first = evalStack[#evalStack]
					evalStack[#evalStack] = nil
					local second = evalStack[#evalStack]
					evalStack[#evalStack] = nil
					table.insert(evalStack, first * second)
				elseif token == "/" then
					assert(#evalStack >= 2, "Failed stack eval, not enough args")
					local first = evalStack[#evalStack]
					evalStack[#evalStack] = nil
					local second = evalStack[#evalStack]
					evalStack[#evalStack] = nil
					table.insert(evalStack, first / second)
				elseif token == "^" then
					assert(#evalStack >= 2, "Failed stack eval, not enough args")
					local first = evalStack[#evalStack]
					evalStack[#evalStack] = nil
					local second = evalStack[#evalStack]
					evalStack[#evalStack] = nil
					table.insert(evalStack, first ^ second)

				-- FUNCTION APPLICATION
				else
					local funcValue = funcValues[token]
					if not funcValue then
						error(`No value given for function '{expression}'`)
					end
					assert(#evalStack >= 1, "Failed stack eval, not enough args")
					local arg = evalStack[#evalStack]
					evalStack[#evalStack] = nil
					table.insert(evalStack, funcValue(arg))
				end
			end
		end

		if #evalStack ~= 1 then
			error(`Eval stack finished with {#evalStack} elements`)
		end

		local value = evalStack[1]
		if typeof(value) ~= "number" then
			error("Evaluation failed: {"..table.concat(evalStack, ",").."}")
		end

		return value
	else
		error(`Cannot evaluate expression '{expression}'`)
	end
end

return ArrayExpr