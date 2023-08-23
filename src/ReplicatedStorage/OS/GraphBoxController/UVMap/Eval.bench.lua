local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = ReplicatedStorage.OS.GraphBoxController.UVMap

local Parser = require(root.Parser)
local ArrayExpr = require(root.ArrayExpr)
local RecExpr = require(root.RecExpr)
local DifferentiableFnUtils = require(root.DifferentiableFnUtils)

-- local strExp = "30*sin(2*p*t)"
local strExp = "30*sin(2*p*t) * 30*sin(2*p*30*sin(2*p*t)) + 30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*t))))) + 30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*t))))))))))"

local arrayExpr = Parser.new(strExp, {"t", "p"}, {"sin", "cos", "tan", "exp"}, ArrayExpr):parse()
local recExpr = Parser.new(strExp, {"t", "p"}, {"sin", "cos", "tan", "exp"}, RecExpr):parse()

local funcValues = DifferentiableFnUtils.FunctionValues

local sin = math.sin
local p = math.pi

local stack = table.create(math.ceil(#arrayExpr/2))

return {

	ParameterGenerator = function()
		return math.random()
	end;

	Functions = {
		["ArrayExpr.eval"] = function(Profiler, RandomNumber) -- You can change "Sample A" to a descriptive name for your function

			local x
			for _=1, 1000 do
				x = ArrayExpr.eval(arrayExpr, {["t"] = RandomNumber, ["p"] = math.pi}, funcValues)
			end
		end;
		
		["ArrayExpr.evalNoChecks"] = function(Profiler, RandomNumber) -- You can change "Sample A" to a descriptive name for your function

			local x
			for _=1, 1000 do
				x = ArrayExpr.evalNoChecks(arrayExpr, {["t"] = RandomNumber, ["p"] = math.pi}, funcValues)
			end
		end;

		["ArrayExpr.evalNoChecksReuseStack"] = function(Profiler, RandomNumber) -- You can change "Sample A" to a descriptive name for your function

			local x
			for _=1, 1000 do
				x = ArrayExpr.evalNoChecksReuseStack(arrayExpr, {["t"] = RandomNumber, ["p"] = math.pi}, funcValues, stack)
			end
		end;

		["RecExpr.eval"] = function(Profiler, RandomNumber) -- You can change "Sample A" to a descriptive name for your function

			local x
			for _=1, 1000 do
				x = RecExpr.eval(recExpr, {["t"] = RandomNumber, ["p"] = math.pi}, funcValues)
			end
		end;

		["raw"] = function(Profiler, RandomNumber)
			local x
			for _=1, 1000 do
				-- x = 30*sin(2*p*RandomNumber)
				x = 30*sin(2*p*RandomNumber) * 30*sin(2*p*30*sin(2*p*RandomNumber)) + 30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*RandomNumber))))) + 30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*30*sin(2*p*RandomNumber))))))))))
			end
		end;
	};

}