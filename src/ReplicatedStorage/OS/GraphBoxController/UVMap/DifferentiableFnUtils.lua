--[[
	Differentiable functions
]]

local RecExpr = require(script.Parent.RecExpr)

local DifferentiableFnUtils = {}


local FUNCTION_VALUES = {
	sin = math.sin,
	cos = math.cos,
	tan = math.tan,
	exp = math.exp,
	log = function(x)
		return math.log(x, math.exp(1))
	end,
}

local FUNCTION_NAMES = {}
for key in FUNCTION_VALUES do
	table.insert(FUNCTION_NAMES, key)
end

--[[ 
	Math functions for evaluating in expressions
 ]]
DifferentiableFnUtils.FunctionValues = FUNCTION_VALUES
DifferentiableFnUtils.FunctionNames = FUNCTION_NAMES

-- Doesn't include multiplying by du/dx in chain rule
local FUNCTION_DERIVATIVE = {
	sin = function(u) return RecExpr.appOne("cos", u) end,
	cos = function(u) return RecExpr.appTwo("*", -1, RecExpr.appOne("sin", u)) end,
	tan = function(u) return RecExpr.appTwo("/", 1, RecExpr.appTwo("^", RecExpr.appOne("cos", u), 2)) end,
	exp = function(u) return RecExpr.appOne("exp", u) end,
	log = function(u) return RecExpr.appTwo("/", 1, u) end,
}

function DifferentiableFnUtils.Differentiate(recExpr, var)
	assert(typeof(var) == "string", "bad var")

	local function diff(innerExp)
		if typeof(innerExp) == "number" then
			return 0
		elseif typeof(innerExp) == "string" then
			if innerExp == var then
				return 1
			end
	
			return 0
		elseif typeof(innerExp) == "table" then
	
			local op = innerExp[1]
			local u, v = innerExp[2], innerExp[3]
			if op == "+" or op == "-" then
				-- u+v, u-v
				local du = diff(u)
				local dv = diff(v)
				if du == 0 then
					return dv
				end
				if dv == 0 then
					return du
				end
				return RecExpr.appTwo(op, diff(u), diff(v))
			elseif op == "*" then
				-- u*v
				local du = diff(u)
				local dv = diff(v)

				if du == 0 and dv == 0 then
					return 0
				end
				if du == 0 then
					if dv == 1 then
						return u
					end
					return RecExpr.appTwo("*", u, dv)
				end
				if dv == 0 then
					if du == 1 then
						return v
					end
					return RecExpr.appTwo("*", du, v)
				end

				local duv = RecExpr.appTwo("*", du, v)
				local udv = RecExpr.appTwo("*", u, dv)

				if du == 1 and dv == 1 then
					return RecExpr.appTwo("+", u, v)
				end
				if du == 1 then
					return RecExpr.appTwo("+", udv, v)
				end
				if dv == 1 then
					return RecExpr.appTwo("+", u, duv)
				end

				return RecExpr.appTwo("+", udv, duv)
			elseif op == "/" then
				-- u/v
				local vdu = RecExpr.appTwo("*", v, diff(u))
				local udv = RecExpr.appTwo("*", u, diff(v))
				local numerator = RecExpr.appTwo("-", vdu, udv)
				local vsquared = RecExpr.appTwo("^", v, 2)
				return RecExpr.appTwo("/", numerator, vsquared)
			elseif op == "^" then
				-- u^v
				if typeof(v) == "number" then
					if v == 0 then
						return 0
					end
					local du = diff(u)
					return RecExpr.appTwo("*", du, RecExpr.appTwo("^", u, v-1))
				end

				local upowv = innerExp -- u^v
				local du = diff(u)
				local dv = diff(v)
				local logu = RecExpr.appOne("log", u)
				local vdivu = RecExpr.appTwo("/", v, u)
				local sum = RecExpr.appTwo("+", RecExpr.appTwo("*", dv, logu), RecExpr.appTwo("*", vdivu, du))

				return RecExpr.appTwo("*", upowv, sum)
			end

			local func_derivative = FUNCTION_DERIVATIVE[op]
			if func_derivative then
				return RecExpr.appTwo("*", diff(u), func_derivative(u))
			end

			error(`Cannot differentiate function {op}`)
		else
			error("Expression type not recognised")
		end
	end

	return diff(recExpr)
end


return DifferentiableFnUtils