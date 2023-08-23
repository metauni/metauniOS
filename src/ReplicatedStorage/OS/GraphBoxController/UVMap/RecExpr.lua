--[[
	Expression data type stored recursively
]]

local RecExpr = {}
RecExpr.__index = RecExpr

function RecExpr.appOne(op: string, arg)
	return {op, arg}
end

function RecExpr.appTwo(op: string, first, second)
	return {op, first, second}
end

-- local EPS = 1e-6
-- function RecExpr.simplify(expr)

-- 	--[[ 
-- 		TODO: 
-- 			- push all numbers to the left in operations, then simplify
-- 			- cancel u/u, u * 1/u, u-u, u + (-1)*u
-- 	 ]]

-- 	if typeof(expr) == "number" then
-- 		if math.abs(expr) < EPS then
-- 			return 0
-- 		end
-- 		-- TODO: Will this cause more divide by zeros?
-- 	elseif typeof(expr) == "string" then
		
-- 	elseif typeof(expr) == "table" then
-- 		local op = expr[1]
-- 		local u, v = expr[2], expr[3]

-- 		-- TODO
-- 	else
-- 		error("Bad expr")
-- 	end
-- end

function RecExpr.eval(expr, varValues: {[string]: number}, funcValues: {[string]: (number) -> number})
	
	if typeof(expr) == "number" then
		return expr
	elseif typeof(expr) == "string" and expr:match("%a") then
		local value = varValues[expr]
		if not value then
			error(`No value given for variable '{expr}'`)
		end
		
		assert(typeof(value) == "number", `Value {value} for variable '{expr}' is not a number.`)
		return value
	elseif typeof(expr) == "table" then
		
		if #expr == 0 then
			error("Cannot evaluate empty expression")
		elseif #expr == 1 then
			error(`Cannot evaluate operation {expr[1]} with no arguments`)
		elseif #expr == 2 then
			local token = expr[1] :: string
			if typeof(token) ~= "string" then
				error(`Bad function name {token}`)
			end

			local funcValue = funcValues[token]
			if funcValue then
				return funcValue(RecExpr.eval(expr[2], varValues, funcValues))
			else
				error(`No function value given for {token}`)
			end
		elseif #expr == 3 then
			local token = expr[1] :: string
			if typeof(token) ~= "string" then
				error(`Bad operator {token}`)
			end

			if token == "+" then
				return RecExpr.eval(expr[2], varValues, funcValues) + RecExpr.eval(expr[3], varValues, funcValues)
			elseif token == "-" then
				return RecExpr.eval(expr[2], varValues, funcValues) - RecExpr.eval(expr[3], varValues, funcValues)
			elseif token == "*" then
				return RecExpr.eval(expr[2], varValues, funcValues) * RecExpr.eval(expr[3], varValues, funcValues)
			elseif token == "/" then
				return RecExpr.eval(expr[2], varValues, funcValues) / RecExpr.eval(expr[3], varValues, funcValues)
			elseif token == "^" then
				return RecExpr.eval(expr[2], varValues, funcValues) ^ RecExpr.eval(expr[3], varValues, funcValues)
			else
				error(`Unknown operator {token}`)
			end
		else
			error(`Expression has too many arguments {#expr}`)
		end
	else
		error(`Cannot evaluate expression '{expr}'`)
	end
end

function RecExpr.toString(expr)
	
	if typeof(expr) == "number" or typeof(expr) == "string" then
		return tostring(expr)
	elseif typeof(expr) == "table" then
		if #expr == 0 then
			return "<bad expr 0>"
		elseif #expr == 1 then
			return "<bad expr 1>"
		elseif #expr == 2 then
			local func = expr[1] :: string
			if typeof(func) ~= "string" then
				func = "<bad func>"
			end

			return func.."("..RecExpr.toString(expr[2])..")"
		elseif #expr == 3 then
			local op = expr[1] :: string
			if typeof(op) ~= "string" then
				op = "<bad op>"
			end

			return "("..RecExpr.toString(expr[2])..op..RecExpr.toString(expr[3])..")"
		else
			error(`Expression has too many arguments {#expr}`)
		end
	else
		return "<bad expr type>"
	end
end

local KEYWORDS = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
}

function RecExpr.toLuaSourceWithoutFunctionSource(expression, inputVariables: {string})

	local function rec(exp)
		if typeof(exp) == "number" then
			return tostring(exp)
		elseif typeof(exp) == "string" and exp:match("%a") then
			return exp
		elseif typeof(exp) == "table" then
			if #exp == 0 then
				error("Cannot convert empty expression")
			elseif #exp == 1 then
				if typeof(exp[1]) == "string" then
					error(`Cannot convert operation {exp[1]} with no arguments`)
				else
					error("Cannot convert operation with no arguments")
				end
			elseif #exp == 2 then
				local token = exp[1] :: string
				if typeof(token) ~= "string" then
					error("Bad function name")
				elseif not token:match("^%a+$") then
					error(`Bad function name {token}`)
				elseif KEYWORDS[token] then
					error(`Bad function name {token} (it's a keyword)`)
				end

				local sourceArg = rec(exp[2])
	
				return token.."("..sourceArg..")"
			elseif #exp == 3 then
				local token = exp[1] :: string
				if typeof(token) ~= "string" then
					error(`Bad operator {token}`)
				end
	
				if token == "+" then
					return "("..rec(exp[2]).."+"..rec(exp[3])..")"
				elseif token == "-" then
					return "("..rec(exp[2]).."-"..rec(exp[3])..")"
				elseif token == "*" then
					return "("..rec(exp[2]).."*"..rec(exp[3])..")"
				elseif token == "/" then
					return "("..rec(exp[2]).."/"..rec(exp[3])..")"
				elseif token == "^" then
					return "("..rec(exp[2]).."^"..rec(exp[3])..")"
				else
					error(`Unknown operator {token}`)
				end
			else
				error(`Expression has too many arguments {#exp}`)
			end
		else
			error(`Cannot evaluate expression '{exp}'`)
		end
	end

	for _, var in inputVariables do
		if typeof(var) ~= "string" or not var:match("^%a$") then
			error(`Bad var {var}`)
		end
	end

	return `return function({table.concat(inputVariables, ",")}) return {rec(expression)} end`
end

local SAFE_FUNCTION_STUB =
	[[local sin = math.sin
local cos = math.cos
local tan = math.cos
local exp = math.cos
local p = math.pi
local e = math.exp(0)]]

-- This is useless because we cannot set ModuleScript.Source at runtime
function RecExpr.toLuaSourceWithStandardFunctions(expression, inputVariables: {string})
	return SAFE_FUNCTION_STUB.."\n"..RecExpr.toLuaSourceWithoutFunctionSource(expression, inputVariables)
end

return RecExpr