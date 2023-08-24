local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(target)

	local Parser = require(script.Parent.Parser)
	local ArrayExpr = require(script.Parent.ArrayExpr)
	local RecExpr = require(script.Parent.RecExpr)
	local DifferentiableFnUtils = require(script.Parent.DifferentiableFnUtils)
	local Blend = require(ReplicatedStorage.Util.Blend)

	local Input = Blend.State("30sin(2*pi*t)")

	local function doEval()
		local text = Input.Value:lower()
		Input.Value = text
		local encoded = text:gsub("pi", "p")
		print(`Parse: {encoded}`)
		local success, err = pcall(function()
			local expr = Parser.new(
				encoded,
				{"t", "u", "v", "p", "e"},
				DifferentiableFnUtils.FunctionNames,
				ArrayExpr):parse()

			print("Result:")
			print(expr)
			print(ArrayExpr.eval(expr, {
				p = math.pi,
				e = math.exp(1),
				u = 2,
				v = 3,
				t = 1.5,
			}, DifferentiableFnUtils.FunctionValues))
		end)

		if not success then
			warn(err)
		end
	end

	local function doDiff()
		local text = Input.Value:lower()
		Input.Value = text
		local encoded = text:gsub("pi", "p")
		print(`Parse: {encoded}`)
		local success, err = pcall(function()
			local expr = Parser.new(
				encoded,
				{"t", "u", "v", "p", "e"},
				DifferentiableFnUtils.FunctionNames,
				RecExpr):parse()

			print("Result:")
			print(expr)
			print(RecExpr.toString(expr))

			print("Diff:")
			local diff = DifferentiableFnUtils.Differentiate(expr, "u")
			print(diff)
			print(RecExpr.toString(diff))
		end)

		if not success then
			warn(err)
		end
	end

	return Blend.New "TextBox" {
		Parent = target,
		Text = Input.Value,
		TextSize = 24,

		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromOffset(400, 100),

		[Blend.OnChange "Text"] = function(text)
			Input.Value = text
		end,
		
		[Blend.OnEvent "FocusLost"] = function(enterPressed: boolean)
			if enterPressed then
				doDiff()
			end
		end,
	}:Subscribe()
end