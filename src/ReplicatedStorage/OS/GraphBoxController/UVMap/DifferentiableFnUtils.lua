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
	
			--[[ 
				ATTENTION
				The u and v here are not as in the UV mapping, they are just the
				arguments to the main operator (not the var being diff'd)

				RecExpr.appTwoSimplify simplifies expressions w.r.t. the given operator's
				identities, (i.e. x + 0 = x), and also evaluates when both args are numbers
				(i.e. 1 + 2 = 3)
			]]
			local op = innerExp[1]
			local u, v = innerExp[2], innerExp[3]
			if op == "+" or op == "-" then
				return RecExpr.appTwoSimplify(op, diff(u), diff(v))
			elseif op == "*" then
				-- u*v
				local duv = RecExpr.appTwoSimplify("*", diff(u), v)
				local udv = RecExpr.appTwoSimplify("*", u, diff(v))
				return RecExpr.appTwoSimplify("+", udv, duv)
			elseif op == "/" then
				-- u/v -> (v*du - u*dv)/(v^2)
				
				if v == 0 then
					error(`Cannot differentiate division by 0 {RecExpr.toString(innerExp)}`)
				end

				-- appTwoSimplify doesn't handle this case
				if typeof(v) == "number" then
					return RecExpr.appTwoSimplify("/", diff(u), v)
				end

				local vdu = RecExpr.appTwoSimplify("*", v, diff(u))
				local udv = RecExpr.appTwoSimplify("*", u, diff(v))
				local numerator = RecExpr.appTwoSimplify("-", vdu, udv)
				local vsquared = RecExpr.appTwoSimplify("^", v, 2)
				return RecExpr.appTwo("/", numerator, vsquared)
			elseif op == "^" then
				-- u^v
				if typeof(v) == "number" then
					if v == 0 then
						return 0
					end
					local du = diff(u)
					-- This will simplify u^0 = 1 for when v = 1
					local lessOnePower = RecExpr.appTwoSimplify("^", u, v-1)
					return RecExpr.appTwoSimplify("*", du, lessOnePower)
				end

				-- For general case: u^v * (du*log(u) + (v/u)*du)
				-- u^v
				local upowv = innerExp
				-- log(u)
				local logu = RecExpr.appOne("log", u)
				-- v/u
				local vdivu = RecExpr.appTwoSimplify("/", v, u)
				-- du*log(u) + (v/u)*du
				local sum = RecExpr.appTwoSimplify("+", RecExpr.appTwoSimplify("*", diff(u), logu), RecExpr.appTwoSimplify("*", vdivu, diff(u)))
				return RecExpr.appTwoSimplify("*", upowv, sum)
			end

			local func_derivative = FUNCTION_DERIVATIVE[op]
			if func_derivative then
				return RecExpr.appTwoSimplify("*", diff(u), func_derivative(u))
			end

			error(`Cannot differentiate function {op}`)
		else
			error("Expression type not recognised")
		end
	end

	return diff(recExpr)
end


return DifferentiableFnUtils