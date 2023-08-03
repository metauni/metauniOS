local CameraUtils = {}

function CameraUtils.ViewBoardsAtFOV(boards: {Board}, verticalFOV: number, viewportSize: Vector2, buffer: Vector2)
	local targets = table.create(#boards)
	local surfaceCFrames = table.create(#boards)
	for _, board in ipairs(boards) do
		table.insert(targets, board._instance)
		table.insert(surfaceCFrames, board.SurfaceCFrame)
	end
	return CameraUtils.ViewTargetSurfacesAtFOV(targets, surfaceCFrames, verticalFOV, viewportSize, buffer)
end

function CameraUtils.ViewTargetSurfacesAtFOV(targets: {Part}, surfaceCFrames: {Vector3}, verticalFOV: number, viewportSize: Vector2, buffer: Vector2)
	assert(#targets > 0, "Expected at least one target")
	assert(#targets == #surfaceCFrames, "Expected targets to correspond to targetCFrames")
	
	-- This is positioned at the centroid of all targets,
	-- and is facing the *average* direction of all the surfaceCFrames
	-- Our away is to slide along this ray (and turn around) such that the targets all fit in the frame
	local centre: CFrame do
		local centrePos = Vector3.zero
		local centreLook = Vector3.zero
		for _, cframe in surfaceCFrames do
			centrePos += cframe.Position
			centreLook += cframe.LookVector * Vector3.new(1,0,1)
		end
		centrePos /= #surfaceCFrames
		centreLook /= #surfaceCFrames
		centre = CFrame.lookAt(centrePos, centrePos + centreLook, Vector3.yAxis)
	end

	-- The positions of the part vertices
	local extremities = {}
	for _, target in ipairs(targets) do
		local halfSize = 0.5 * target.Size
		local cframe = target.CFrame
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new( 1, 1, 1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new( 1,-1, 1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new(-1, 1, 1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new(-1,-1, 1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new( 1, 1,-1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new( 1,-1,-1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new(-1, 1,-1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new(-1,-1,-1))).Position)
	end

	-- Project extremities onto the plane perpendicular to centre.LookVector
	-- Then calculate correct camera zDistance along centre.LookVector to fit extremity
	-- Take maximum such value, relative to centre.Position
	local maxZDistanceToCentre = 0

	
	
	for _, point in ipairs(extremities) do
		local v = (point - centre.Position)
		local zDelta = v:Dot(centre.LookVector.Unit)
		do -- Vertical
			-- local halfHeight = math.abs(v:Dot(centre.UpVector.Unit))
			local halfHeight = math.abs(v:Dot(centre.UpVector.Unit)) * (1 + buffer.Y / (0.5 * viewportSize.Y))
			local zDistance = halfHeight / math.tan(math.rad(verticalFOV/2))
			maxZDistanceToCentre = math.max(maxZDistanceToCentre, zDistance + zDelta)
		end
		do -- Horizontal
			local halfWidth = math.abs(v:Dot(centre.RightVector.Unit)) * (1 + buffer.X / (0.5 * viewportSize.X))
			local halfHeight = halfWidth / (viewportSize.X / viewportSize.Y)
			local zDistance = halfHeight / math.tan(math.rad(verticalFOV/2))
			maxZDistanceToCentre = math.max(maxZDistanceToCentre, zDistance + zDelta)
		end
	end

	-- Move forward away from targets (-Z is forward), then turn around look back.
	-- Also return focal point
	return centre * CFrame.new(0, 0, -maxZDistanceToCentre) * CFrame.Angles(0, math.pi, 0), centre.Position
end

function CameraUtils.FitTargetsAlongCFrameRay(cframeRay: CFrame, targets: {Part}, verticalFOV: number, viewportSize: Vector2, buffer: Vector2)
	assert(#targets > 0, "Expected at least one target")

	-- The positions of the part vertices
	local extremities = {}
	for _, target in ipairs(targets) do
		local halfSize = 0.5 * target.Size
		local cframe = target.CFrame
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new( 1, 1, 1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new( 1,-1, 1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new(-1, 1, 1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new(-1,-1, 1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new( 1, 1,-1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new( 1,-1,-1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new(-1, 1,-1))).Position)
		table.insert(extremities, (cframe * CFrame.new(halfSize * Vector3.new(-1,-1,-1))).Position)
	end

	-- Project extremities onto the plane perpendicular to centre.LookVector
	-- Then calculate correct camera zDistance along centre.LookVector to fit extremity
	-- Take maximum such value, relative to centre.Position
	local maxZDistanceToCentre = 0
	
	for _, point in ipairs(extremities) do
		local v = (point - cframeRay.Position)
		local zDelta = -v:Dot(cframeRay.LookVector.Unit)
		do -- Vertical
			local halfHeight = math.abs(v:Dot(cframeRay.UpVector.Unit)) * (1 + buffer.Y / (0.5 * viewportSize.Y))
			local zDistance = halfHeight / math.tan(math.rad(verticalFOV/2))
			maxZDistanceToCentre = math.max(maxZDistanceToCentre, zDistance + zDelta)
		end
		do -- Horizontal
			local halfWidth = math.abs(v:Dot(cframeRay.RightVector.Unit)) * (1 + buffer.X / (0.5 * viewportSize.X))
			local halfHeight = halfWidth / (viewportSize.X / viewportSize.Y)
			local zDistance = halfHeight / math.tan(math.rad(verticalFOV/2))
			maxZDistanceToCentre = math.max(maxZDistanceToCentre, zDistance + zDelta)
		end
	end

	return cframeRay * CFrame.new(0, 0, maxZDistanceToCentre)
end

return CameraUtils