--[[
	
]]
local Parser = require(script.Parser)
local ArrayExpr = require(script.ArrayExpr)
local RecExpr = require(script.RecExpr)
local DifferentiableFnUtils = require(script.DifferentiableFnUtils)

local UVMap = {}
UVMap.__index = UVMap

export type UVMapType = (Vector2, Vector2) -> Vector3

local function PROJECTION(u: number, v: number)
	return Vector3.new(u, v, 0)
end

local function ZNORMAL(_u: number, _v: number)
	return Vector3.new(0, 0, 1)
end

local VAR_NAMES = {"u", "v", "p", "e"}

function UVMap.new(positionMap: UVMapType?, normalMap: UVMapType?)
	local self = setmetatable({}, UVMap)

	self.PositionMap = positionMap or PROJECTION
	self.NormalMap = normalMap or ZNORMAL

	return self
end

function UVMap.newSymbolic(xMapStr, yMapStr, zMapStr)

	local xExpr = UVMap.parse(xMapStr:lower():gsub("pi", "p"))
	local yExpr = UVMap.parse(yMapStr:lower():gsub("pi", "p"))
	local zExpr = UVMap.parse(zMapStr:lower():gsub("pi", "p"))

	local _stack = {}

	local xArrayExpr = ArrayExpr.fromRecExpr(xExpr)
	local yArrayExpr = ArrayExpr.fromRecExpr(yExpr)
	local zArrayExpr = ArrayExpr.fromRecExpr(zExpr)
	
	local positionMap = function(u: number, v: number)
		local varValues = {u = u, v = v, p = math.pi, e = math.exp(1)}
		return Vector3.new(
			ArrayExpr.evalNoChecksReuseStack(xArrayExpr, varValues, DifferentiableFnUtils.FunctionValues, _stack),
			ArrayExpr.evalNoChecksReuseStack(yArrayExpr, varValues, DifferentiableFnUtils.FunctionValues, _stack),
			ArrayExpr.evalNoChecksReuseStack(zArrayExpr, varValues, DifferentiableFnUtils.FunctionValues, _stack)
		)
	end
	
	local xduExpr = DifferentiableFnUtils.Differentiate(xExpr, "u")
	local yduExpr = DifferentiableFnUtils.Differentiate(yExpr, "u")
	local zduExpr = DifferentiableFnUtils.Differentiate(zExpr, "u")
	
	local xdvExpr = DifferentiableFnUtils.Differentiate(xExpr, "v")
	local ydvExpr = DifferentiableFnUtils.Differentiate(yExpr, "v")
	local zdvExpr = DifferentiableFnUtils.Differentiate(zExpr, "v")

	local xduArrayExpr = ArrayExpr.fromRecExpr(xduExpr)
	local yduArrayExpr = ArrayExpr.fromRecExpr(yduExpr)
	local zduArrayExpr = ArrayExpr.fromRecExpr(zduExpr)

	local xdvArrayExpr = ArrayExpr.fromRecExpr(xdvExpr)
	local ydvArrayExpr = ArrayExpr.fromRecExpr(ydvExpr)
	local zdvArrayExpr = ArrayExpr.fromRecExpr(zdvExpr)

	local normalMap = function(u: number, v: number)
		local varValues = {u = u, v = v, p = math.pi, e = math.exp(1)}
		return Vector3.new(
			ArrayExpr.evalNoChecksReuseStack(xduArrayExpr, varValues, DifferentiableFnUtils.FunctionValues, _stack),
			ArrayExpr.evalNoChecksReuseStack(yduArrayExpr, varValues, DifferentiableFnUtils.FunctionValues, _stack),
			ArrayExpr.evalNoChecksReuseStack(zduArrayExpr, varValues, DifferentiableFnUtils.FunctionValues, _stack)
		):Cross(Vector3.new(
			ArrayExpr.evalNoChecksReuseStack(xdvArrayExpr, varValues, DifferentiableFnUtils.FunctionValues, _stack),
			ArrayExpr.evalNoChecksReuseStack(ydvArrayExpr, varValues, DifferentiableFnUtils.FunctionValues, _stack),
			ArrayExpr.evalNoChecksReuseStack(zdvArrayExpr, varValues, DifferentiableFnUtils.FunctionValues, _stack)
		)).Unit
	end

	local uvMap = UVMap.new(positionMap, normalMap)
	uvMap.XMapStr = xMapStr
	uvMap.YMapStr = yMapStr
	uvMap.ZMapStr = zMapStr

	return uvMap
end

function UVMap.parse(input: string)
	assert(typeof(input) == "string", "Bad input")

	local parser = Parser.new(input:lower():gsub("pi", "p"), VAR_NAMES, DifferentiableFnUtils.FunctionNames, RecExpr)
	return parser:parse()
end

return UVMap