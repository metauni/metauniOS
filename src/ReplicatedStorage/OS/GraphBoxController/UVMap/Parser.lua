--[[
	Parser.lua
]]

local TOKENS = {
	LEFTBR = "(",
	RIGHTBR = ")",
	
	ADD = "+",
	MUL = "*",
	SUB = "-",
	DIV = "/",
	POW = "^",
}

local TOKEN_PATTERNS = {
	LEFTBR = "%(",
	RIGHTBR = "%)",
	
	ADD = "%+",
	MUL = "%*",
	SUB = "%-",
	DIV = "%/",
	POW = "%^",
}

local INFIX_PRECEDENCE = {
	["+"] = 1,
	["-"] = 1,
	["*"] = 2,
	["/"] = 2,
	["^"] = 3,
}

local INFIX_LEFT_ASSOC = {
	["+"] = false,
	["-"] = true,
	["*"] = false,
	["/"] = true,
	["^"] = false,
}

local Parser = {}
Parser.__index = Parser

function Parser.new(input, variableNames, funcNames, exprClass)
	for _, var in variableNames do
		assert(string.match(var, "^%a$"), "Variables should be single alphabet characters")
		assert(var, "Bad variable")
	end

	for _, func in funcNames do
		assert(string.match(func, "^%a+$"), "Function names should be alphanumeric")
		assert(func, "Bad function name")
	end

	local self = setmetatable({}, Parser)
	self.input = input
	self.cursor = 1
	self._exprClass = exprClass

	self.varSet = {}
	for _, var in variableNames do
		self.varSet[var] = true
	end
	
	self.funcSet = {}
	for _, func in funcNames do
		self.funcSet[func] = true
	end

	return self
end

function Parser:parse()
	if not self.input:match("%S") then
		error("Cannot parse empty expression")
	end
	self.cursor = 1
	local expression = self:parseExpression()
	if self.cursor ~= #self.input + 1 then
		if self:_peekNextToken() == TOKENS.RIGHTBR then
			error(`Unexpected closing parend ')' at: {self.cursor}`)
		end
		error(`Expression {self.input} ended early at {self.cursor-1}`)
	end

	return expression
end

--[[
	@returns token, nextCursor
]]
function Parser:_peekNextToken()
	local startTokenCursor = self.input:find("%S", self.cursor)
	if not startTokenCursor then
		return nil, #self.input + 1
	end

	-- Look for operators or parends or unary minus (same as SUB)
	for name, pattern in TOKEN_PATTERNS do
		local _, endPos = self.input:find("^"..pattern, startTokenCursor)
		if endPos then
			return TOKENS[name], endPos + 1
		end
	end

	do -- Look for float
		local _, endPos = self.input:find("^%d+%.%d+", startTokenCursor)
		if endPos then
			return tonumber(self.input:sub(startTokenCursor, endPos)), endPos + 1
		end
	end

	do -- Look for integer
		local _, endPos = self.input:find("^%d+", startTokenCursor)
		if endPos then
			return tonumber(self.input:sub(startTokenCursor, endPos)), endPos + 1
		end
	end

	-- Look for functions
	for func in self.funcSet do
		local _, endPos = self.input:find("^"..func, startTokenCursor)
		if endPos then
			return func, endPos + 1 
		end
	end

	-- If the next possible token is a variable followed by 0 or more variables
	-- then that's the token, (cannot be followed by non-variable alphabetic characters)
	local maybeVar = self.input:sub(startTokenCursor, startTokenCursor)
	local alphTail = self.input:match("^%a+", startTokenCursor+1)
	if self.varSet[maybeVar] then
		if startTokenCursor == #self.input or not alphTail then
			return maybeVar, startTokenCursor + 1
		elseif not self.funcSet[alphTail] then
			for i=1, #alphTail do
				if not self.varSet[alphTail:sub(i,i)] then
					error(`Unrecognised var {alphTail:sub(i,i)} at position {startTokenCursor+i}`)
				end
			end
			return maybeVar, startTokenCursor + 1
		end
	elseif startTokenCursor == #self.input or self.input:match(`^%a%A`, startTokenCursor) then
		error(`Unrecognised var {maybeVar} at position {startTokenCursor}`)
	else
		error(`Unrecognised expression at position {startTokenCursor}`)
	end

	return nil, #self.input + 1
end

function Parser:parseExpression(precedence)
	precedence = precedence or 0
	local sign = 1
	local token, nextCursor
	repeat
		token, nextCursor = self:_peekNextToken()
		self.cursor = nextCursor
		if token == "-" then
			sign *= -1
		end
	until token ~= "-"

	if not token then
		return nil
	end
	
	local left
	if typeof(token) == "number" then
		local argToken, _ = self:_peekNextToken()

		if self.varSet[argToken] or self.funcSet[argToken] then
			local argExp = self:parseExpression(2)
			left = self._exprClass.appTwo("*", token, argExp)
		else
			left = token
		end
	elseif self.varSet[token] then
		left = token
		local argToken, _ = self:_peekNextToken()

		if self.varSet[argToken] or argToken == TOKENS.LEFTBR then
			local argExp = self:parseExpression(2)
			left = self._exprClass.appTwo("*", token, argExp)
		else
			left = token
		end
	elseif self.funcSet[token] then
		local leftBrToken, argCursor = self:_peekNextToken()
		if leftBrToken ~= TOKENS.LEFTBR then
			error(`Open parend '(' expected after {token}`)
		end
		self.cursor = argCursor

		local argExp = self:parseExpression()
		left = self._exprClass.appOne(token, argExp)

		local rightBrToken, afterPrefixCursor = self:_peekNextToken()
		if rightBrToken ~= TOKENS.RIGHTBR then
			error(`Close parend ')' expected after arg to {token}`)
		end
		self.cursor = afterPrefixCursor
	elseif token == TOKENS.LEFTBR then
		left = self:parseExpression()

		local rightBrToken, afterPrefixCursor = self:_peekNextToken()
		if rightBrToken ~= TOKENS.RIGHTBR then
			error("Unbalanced parends, expected close parend ')'")
		end
		self.cursor = afterPrefixCursor
	elseif INFIX_PRECEDENCE[token] then
		error(`Infix operator {token} used in prefix position. Cursor: {self.cursor}.`)
	elseif token == TOKENS.RIGHTBR then
		error(`Unexpected closing parend ')' at position {self.cursor-1}`)
	else
		error(`Unexpected failure, case not handled. Cursor: {self.cursor}. Token: {token}`)
	end

	if sign == -1 then
		if typeof(left) == "number" then
			left = -left
		else
			left = self._exprClass.appTwo("*", -1, left)
		end
	end

	while true do
		local infixToken, rightArgCursor = self:_peekNextToken()

		local infixPrecedence = INFIX_PRECEDENCE[infixToken]

		if not infixPrecedence then
			-- not an infix operator, might be a close bracket or end of input
			break
		end

		if infixPrecedence < precedence then
			-- Successfully captured left arg of operator with given precedence
			break
		end

		self.cursor = rightArgCursor
		local recursivePrecedence = if INFIX_LEFT_ASSOC[infixToken] then infixPrecedence+1 else infixPrecedence
		local right = self:parseExpression(recursivePrecedence)
		if right == nil then
			error(`Expected second argument to {infixToken} at position {rightArgCursor}`)
		end
		left = self._exprClass.appTwo(infixToken, left, right)
	end

	return left
end

return Parser