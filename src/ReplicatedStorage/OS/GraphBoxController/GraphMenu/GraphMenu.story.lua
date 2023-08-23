local GraphMenu = require(script.Parent)
local UVMap = require(script.Parent.Parent.UVMap)

return function(target)

	local showGrid = Instance.new("BoolValue")
	showGrid.Value = true

	local graphMenu
	graphMenu = GraphMenu.new({

		Parent = target,
		InitialUVMap = UVMap.newSymbolic("u", "v", "0"),
		OnSetUVMapStrings = function(xMapStr, yMapStr, zMapStr)
			print(`x={xMapStr}, y={yMapStr}, z={zMapStr}`)
		end,
		OnClose = function()
			graphMenu:Destroy()
		end,
		ShowGrid = showGrid,
		OnToggleShowGrid = function()
			showGrid.Value = not showGrid.Value
		end,
	})

	return graphMenu._maid:Wrap()
end