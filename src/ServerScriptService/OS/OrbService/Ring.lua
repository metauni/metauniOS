local ReplicatedStorage = game:GetService("ReplicatedStorage")
local U = require(ReplicatedStorage.Util.U)

return function(props)
	-- Make the ring by subtracting two cylinders
	local ringOuter = U.new "Part" {
		Size = Vector3.new(0.10, props.OuterDiameter, props.OuterDiameter),
		CFrame = CFrame.new(0, 0, 0),
		Shape = "Cylinder",
		Color = props.Color,
	}

	local ringInner = U.new "Part" {
		Size = Vector3.new(0.15, props.InnerDiameter, props.InnerDiameter),
		CFrame = CFrame.new(0, 0, 0),
		Shape = "Cylinder",
		Color = props.Color,
	}

	ringOuter.Parent = workspace
	ringInner.Parent = workspace

	-- Pass through all other props to resulting ring instance
	local passThroughProps = table.clone(props)
	passThroughProps.InnerDiameter = nil
	passThroughProps.OuterDiameter = nil
	passThroughProps.Size = nil
	passThroughProps.Color = nil

	local ring = ringOuter:SubtractAsync({ ringInner })
	U.bind(ring, passThroughProps)

	ringOuter:Destroy()
	ringInner:Destroy()

	return ring
end
