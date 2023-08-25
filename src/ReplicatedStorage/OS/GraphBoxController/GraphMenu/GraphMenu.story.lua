local GraphMenu = require(script.Parent)
local UVMap = require(script.Parent.Parent.UVMap)

return function(target)

	local showGrid = Instance.new("BoolValue")
	showGrid.Value = true

	local visible = Instance.new("BoolValue")
	visible.Value = false

	local graphMenu
	graphMenu = GraphMenu.new({

		ShowGrid = showGrid,
		OnToggleShowGrid = function()
			showGrid.Value = not showGrid.Value
		end,
		Visible = visible,
		OnSetUVMapStrings = function(xMapStr: string, yMapStr: string, zMapStr: string)
			print(xMapStr, yMapStr, zMapStr)
		end,
		OnClose = function()
			visible.Value = false
			task.delay(0.5, function()
				pcall(function()
					graphMenu:Destroy()
				end)
			end)
		end,
		UVMap = UVMap.newSymbolic("u", "v", "u+v"),
	})

	return graphMenu:render():Subscribe(function(instance)
		instance.Parent = target
		visible.Value = true
	end)
end