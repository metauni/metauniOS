--[[
	
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseObject = require(ReplicatedStorage.Util.BaseObject)
local Blend = require(ReplicatedStorage.Util.Blend)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)
local BoardController = require(ReplicatedStorage.OS.BoardController)
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
	
	self._boardPart = model:FindFirstChild("Board")
	assert(self._boardPart, "Bad Board")
	-- assert(self._boardPart:HasTag("metaboard"), "Board not tagged")

	self._showPrompt = Instance.new("BoolValue")
	self._showPrompt.Value = true

	self._uvMap = ValueObject.new()
	self._maid:GiveTask(Rx.combineLatest {
		xMap = Rxi.attributeOf(self._obj, "xMap"):Pipe{Rxi.notNil(), Rx.defaultsTo("u")},
		yMap = Rxi.attributeOf(self._obj, "yMap"):Pipe{Rxi.notNil(), Rx.defaultsTo("v")},
		zMap = Rxi.attributeOf(self._obj, "zMap"):Pipe{Rxi.notNil(), Rx.defaultsTo("0.1+0.05cos(3piu)+0.05sin(4piv)")},
	}:Subscribe(function(state)
		local uvMap
		local success, msg = pcall(function()
			uvMap = UVMap.newSymbolic(state.xMap, state.yMap, state.zMap)
		end)

		if success then
			self._uvMap.Value = uvMap
		else
			warn(msg)
		end
	end))

	self._maid:GiveTask(Blend.mount(workspace, {
		UVCanvas.renderFromBoard({
			Name = "Graph",
			Board = self:_observeBoard(),
			CanvasPart = self._boardPart,
			UVMap = self._uvMap:Observe(),
		}),

		self:_renderGrid()
	}))

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

function GraphBoxClient:_renderGrid()
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

	return UVCanvas.render({
		Name = "Grid",
		BoardState = {
			Figures = gridFigures,
			DrawingTasks = {},
		},
		CanvasPart = self._boardPart,
		UVMap = self._uvMap,
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
		},
	})
end

function GraphBoxClient:_observeBoard()
	return Rx.observable(function(sub)
		return BoardController.Boards:StreamKey(self._boardPart)(function(board)
			sub:Fire(board)
		end)
	end)
end

return GraphBoxClient