local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Feather = require(ReplicatedStorage.Packages.Feather)
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local BoardState = require(ReplicatedStorage.Packages.metaboard.BoardState)
local Blend = require(ReplicatedStorage.Util.Blend)
local Brio = require(ReplicatedStorage.Util.Brio)
local Maid = require(ReplicatedStorage.Util.Maid)
local Rx = require(ReplicatedStorage.Util.Rx)

-- Components
local UVCurve = require(script.UVCurve)

local function component(props, oldProps)
	
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

	return Feather.createElement("Folder", {
		
		[Feather.DeltaChildren] = deltaChildren
	})
end

local UVCanvas = {}

function UVCanvas.renderFromBoard(props): Rx.Observable
	
	return UVCanvas.render({
		Name = props.Name,
		BoardState = props.Board:Pipe {
			Rx.switchMap(function(board)
				if not board then
					return Rx.of(nil)
				end
				return board:ObserveCombinedState()
			end)
		},
		CanvasPart = props.CanvasPart,
		UVMap = props.UVMap,
		PartProps = props.PartProps,
	})
end

function UVCanvas.render(props): Rx.Observable
	assert(typeof(props.CanvasPart) == "Instance", "Bad CanvasPart")

	return Rx.observable(function(sub)

		local cleanup = {}

		local model = Instance.new("Model")
		table.insert(cleanup, model)
		table.insert(cleanup, Blend.mount(model, {
			Name = props.Name,
		}))
		
		local canvasTree = nil
		table.insert(cleanup, function()
			if canvasTree then
				Feather.unmount(canvasTree)
				canvasTree = nil
			end
		end)

		table.insert(cleanup, Rx.combineLatest {
			BoardState = Blend.toPropertyObservable(props.BoardState) or Rx.of(props.BoardState),
			CanvasSize = metaboard.BoardUtils.observeSurfaceSize(props.CanvasPart :: any),
			CanvasCFrame = metaboard.BoardUtils.observeSurfaceCFrame(props.CanvasPart :: any),
			UVMap = Blend.toPropertyObservable(props.UVMap) or Rx.of(props.UVMap),
		}:Subscribe(function(state)
			local figures, figureMaskBundles
			if state.BoardState then
				figures, figureMaskBundles = metaboard.BoardState.render(state.BoardState)
			else
				figures, figureMaskBundles = {}, {}
			end
			local element = Feather.createElement(component, {
				
				Figures = figures,
				FigureMaskBundles = figureMaskBundles,
				
				CanvasSize = state.CanvasSize,
				CanvasCFrame = state.CanvasCFrame,

				UVMap = state.UVMap,
				PartProps = props.PartProps,
			})

			if not canvasTree then
				canvasTree = Feather.mount(element, model, "Figures")
			else
				Feather.update(canvasTree, element)
			end
		end))

		sub:Fire(model)

		return cleanup
	end)
end

return UVCanvas
