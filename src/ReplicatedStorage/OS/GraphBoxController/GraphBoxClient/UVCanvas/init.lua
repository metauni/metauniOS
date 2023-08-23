local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Feather = require(ReplicatedStorage.Packages.Feather)

-- Components
local UVCurve = require(script.UVCurve)

return function(props, oldProps)
	
	local deltaChildren = {}

	local changeAll =
		oldProps.Figures == nil
		or
		props.CanvasCFrame ~= oldProps.CanvasCFrame
		or
		props.CanvasSize ~= oldProps.CanvasSize
		or
		props.UVMap ~= oldProps.UVMap
		or
		props.NormalMap ~= oldProps.NormalMap
		or
		props.PartProps ~= oldProps.PartProps
		

	for figureId, figure in props.Figures do
		
		if
			changeAll
			or
			figure ~= oldProps.Figures[figureId]
			or
			props.FigureMaskBundles[figureId] ~= oldProps.FigureMaskBundles[figureId] then
			
			deltaChildren[figureId] = Feather.createElement(UVCurve, {
	
				Curve = figure,
				Masks = props.FigureMaskBundles[figureId],
				CanvasSize = props.CanvasSize,
				CanvasCFrame = props.CanvasCFrame,
				UVMap = props.UVMap,
				PartProps = props.PartProps,
			})
		end

	end

	if oldProps.Figures then
		
		for figureId, _ in oldProps.Figures do
			
			if not props.Figures[figureId] then
				
				deltaChildren[figureId] = Feather.SubtractChild
			end
		end
	end

	return Feather.createElement("Model", {
		
		[Feather.DeltaChildren] = deltaChildren
	})
end