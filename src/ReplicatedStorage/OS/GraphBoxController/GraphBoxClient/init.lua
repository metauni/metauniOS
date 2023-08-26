--[[
	
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseObject = require(ReplicatedStorage.Util.BaseObject)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)
local BoardController = require(ReplicatedStorage.OS.BoardController)
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local Feather = require(ReplicatedStorage.Packages.Feather)
local Rx = require(ReplicatedStorage.Util.Rx)
local Rxi = require(ReplicatedStorage.Util.Rxi)
local UVMap = require(script.Parent.UVMap)
local UVCanvas = require(script.UVCanvas)

local GraphBoxClient = setmetatable({}, BaseObject)
GraphBoxClient.__index = GraphBoxClient

function GraphBoxClient.new(model: Model, service)
	if not model:IsDescendantOf(workspace) then
		return nil
	end

	local self = setmetatable(BaseObject.new(model), GraphBoxClient)

	self._service = service
	
	local boardObject = model:FindFirstChild("Board")
	assert(boardObject, "Bad Board")
	-- assert(boardObject:HasTag("metaboard"), "Board not tagged")
	self._board = BoardController:WaitForBoard(boardObject)

	self._showPrompt = Instance.new("BoolValue")
	self._showPrompt.Value = true

	self._uvMap = ValueObject.new()
	self._maid:GiveTask(Rx.combineLatest {
		xMap = Rxi.attributeOf(self._obj, "xMap"):Pipe{Rxi.notNil(), Rx.defaultsTo("u")},
		yMap = Rxi.attributeOf(self._obj, "yMap"):Pipe{Rxi.notNil(), Rx.defaultsTo("v")},
		zMap = Rxi.attributeOf(self._obj, "zMap"):Pipe{Rxi.notNil(), Rx.defaultsTo("0.1+0.05cos(3piu)+0.05sin(4piv)")},
	}:Pipe {
		Rx.map(function(state)
			local uvMap
			local success, msg = pcall(function()
				uvMap = UVMap.newSymbolic(state.xMap, state.yMap, state.zMap)
			end)
	
			if success then
				return uvMap
			else
				warn(msg)
				return nil
			end
		end)
	})

	self._maid:GiveTask(Blend.Computed(self._uvMap,
		function(uvMap)
			if uvMap then
				self._maid._graph = self:_render({
					UVMap = uvMap,
				})
			else
				self._maid._graph = nil
			end
		end):Subscribe()
	)

	self._maid:GiveTask(Blend.Computed(self._uvMap, self:ObserveShowGrid(),
		function(uvMap, showGrid)
			if uvMap and showGrid then
				self._maid._grid = self:_renderGrid({
					UVMap = uvMap,
				})
			else
				self._maid._grid = nil
			end
		end):Subscribe()
	)

	self._maid:GiveTask(Blend.New "ProximityPrompt" {
		Parent = Rxi.propertyOf(self._obj, "PrimaryPart"),
		Enabled = Blend.Computed(self._service:ObserveEditingGraphBox(), function(graphBox)
			return graphBox == nil
		end),
		ActionText = "",
		KeyboardKeyCode = Enum.KeyCode.G,
		UIOffset = Vector2.new(0,-25),
		MaxActivationDistance = 10,
		RequiresLineOfSight = false,
		
		[Blend.OnEvent "Triggered"] = function()
			if not self._uvMap.Value then
				warn("No uvMap available")
				return
			end

			self._service:OpenMenuWith(self)
		end,
	}:Subscribe())

	return self
end

function GraphBoxClient:ObserveUVMap()
	return self._uvMap:Observe()
end

function GraphBoxClient:GetUVMap()
	return self._uvMap.Value
end

function GraphBoxClient:ObserveShowGrid()
	return Rxi.attributeOf(self._obj, "ShowGrid")
end

function GraphBoxClient:GetShowGrid()
	return self._obj:GetAttribute("ShowGrid") == true
end

function GraphBoxClient:_renderGrid(props)
	local maid = Maid.new()

	do
		local NUM_SEGMENTS = 50
		local gridFigures = {}
		for i=0, 10 do
			local hPoints = {}
			local vPoints = {}
			for j=0, NUM_SEGMENTS do
				table.insert(vPoints, Vector2.new(i/10,j/NUM_SEGMENTS))
				table.insert(hPoints, Vector2.new(j/NUM_SEGMENTS,i/10))
			end
			gridFigures[`horizontal{i}`] = {
				Id = `horizontal{i}`,
				Type = "Curve",
				Points = hPoints,
				Width = 0.01,
				Color = Color3.fromRGB(229, 229, 229),
				ZIndex = 0,
			}
			gridFigures[`vertical{i}`] = {
				Id = `vertical{i}`,
				Type = "Curve",
				Points = vPoints,
				Width = 0.01,
				Color = Color3.fromRGB(229, 229, 229),
				ZIndex = 0,
			}
		end

		local gridTree = Feather.mount(Feather.createElement(UVCanvas, {

			Figures = gridFigures,
			FigureMaskBundles = {},

			CanvasSize = self._board.SurfaceSize,
			CanvasCFrame = self._board.SurfaceCFrame,

			UVMap = props.UVMap,
			PartProps = {
	
				Transparency = 0.5,
				Material = Enum.Material.SmoothPlastic,
				TopSurface = Enum.SurfaceType.Smooth,
				BottomSurface = Enum.SurfaceType.Smooth,
				Anchored = true,
				CanCollide = false,
				CastShadow = false ,
				CanTouch = false, -- Do not trigger Touch events
				CanQuery = false, -- Does not take part in e.g. GetPartsInPart
			}
		}), workspace, "Grid"..tostring(self._board.PersistId or game:GetService("HttpService"):GenerateGUID(false)))

		maid:GiveTask(function()
			Feather.unmount(gridTree)
		end)
	end

	return maid
end

-- This does a bunch of work that metaboard should provide an API for.
function GraphBoxClient:_render(props)

	local maid = Maid.new()
	
	local function renderElement()
		local figures = table.clone(self._board.Figures)
		local figureMaskBundles = {}
		for taskId, drawingTask in pairs(self._board.DrawingTasks) do

			if drawingTask.Type == "Erase" then

				local figureIdToFigureMask = metaboard.DrawingTask.Render(drawingTask)

				for figureId, figureMask in pairs(figureIdToFigureMask) do
					local bundle = figureMaskBundles[figureId] or {}
					bundle[taskId] = figureMask
					figureMaskBundles[figureId] = bundle
				end
			else
				figures[taskId] = metaboard.DrawingTask.Render(drawingTask)
			end
		end

		return Feather.createElement(UVCanvas, {

			Figures = figures,
			FigureMaskBundles = figureMaskBundles,

			CanvasSize = self._board.SurfaceSize,
			CanvasCFrame = self._board.SurfaceCFrame,

			UVMap = props.UVMap,
		})
	end
	
	local name = "Graph"..tostring(self._board.PersistId or game:GetService("HttpService"):GenerateGUID(false))
	local tree = Feather.mount(renderElement(), workspace, name)
	
	local connection = self._board.DataChangedSignal:Connect(function()
		Feather.update(tree, renderElement())
	end)
	maid:GiveTask(function()
		connection:Disconnect()
	end)

	maid:GiveTask(function()
		Feather.unmount(tree)
	end)
	
	return maid
end

return GraphBoxClient