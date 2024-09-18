local U = require(script.Parent.Parent.Parent.Util.U)
local UI = require(script.Parent.Parent.UIStream)

local function story(render: (controls: any) -> Instance)
	return function (props: any)

		local cleanup = {}
		local controls = {}
		for key, value in props.controls do
			controls[key] = U.Value(cleanup, value)
		end

		table.insert(cleanup, props.subscribe(function(values, _infos)
			for key, value in values do
				if controls[key] then
					controls[key].Value = value
				end
			end
		end))

		local instance = render(controls)
		instance.Parent = props.target
		return function()
			print(debug.traceback())
			instance:Destroy()
		end
	end
end

return {
	controls = {
		Title = "metauni"
	},
	render = story(function(controls)
		return UI.TitledWindow {
			Size = UDim2.fromOffset(400, 400),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),

			Title = controls.Title,
			OnClose = function()
				print("Closing window")
			end,
		}
	end),
}
