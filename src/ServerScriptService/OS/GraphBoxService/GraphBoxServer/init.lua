local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local BaseObject = require(ReplicatedStorage.Util.BaseObject)
local Result = require(ReplicatedStorage.Util.Result)
local Rx = require(ReplicatedStorage.Util.Rx)
local Rxi = require(ReplicatedStorage.Util.Rxi)
local UVMap = require(ReplicatedStorage.OS.GraphBoxController.UVMap)

local Pocket = ReplicatedStorage.OS.Pocket

local DEFAULT_DATA = {
	-- It's a torus
	XMapStr = "(1 + 0.5cos(piv))*cos(piu)",
	YMapStr = "(1 + 0.5cos(piv))*sin(piu)",
	ZMapStr = "1 + 0.5sin(piv)",
	ShowGrid = true,
}

--[[
	Server class for GraphBox
]]
local GraphBoxServer = setmetatable({}, BaseObject)
GraphBoxServer.__index = GraphBoxServer

function GraphBoxServer.new(model: Model)
	assert(model.PrimaryPart, "Bad graphbox model")
	assert(model:FindFirstChild("Board"), "Bad graphbox model")
	local self = setmetatable(BaseObject.new(model), GraphBoxServer)

	self._obj.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local persistIdValue = self._obj:FindFirstChild("Board"):FindFirstChild("PersistId")
	if persistIdValue and persistIdValue.Value then
		task.spawn(function()
			local result = Result.retryAsync({ maxAttempts = 3, delaySeconds = 5 }, function()
				return self:_restoreDataAsync(persistIdValue.Value)
			end)

			if result.success then
				self:_spawnSaver(persistIdValue.Value)
			else
				warn(result.reason)
			end
		end)
	else
		local data = DEFAULT_DATA
		self:SetValidUVMapStrings(data.XMapStr, data.YMapStr, data.ZMapStr)
		self:SetShowGrid(data.ShowGrid)
	end

	return self
end

function GraphBoxServer:_spawnSaver(persistId: number)
	task.spawn(function()
		local datastoreResult = self:_getDataStore()
		if not datastoreResult.success then
			warn(datastoreResult.reason)
			return
		end

		local datastore = datastoreResult.data
		self._maid._saver = self:_observePersistData()
			:Pipe {
				Rx.throttleTime(10, { leading = true, trailing = true }),
			}
			:Subscribe(function(data)
				local result = Result.pcall(function()
					datastore:SetAsync(`{persistId}`, data)
				end)
				if not result.success then
					warn(result.reason)
				end
			end)
	end)
end

function GraphBoxServer:_getDataStore(): Result.Result<DataStore>
	local isPocket = Pocket:GetAttribute("IsPocket")
	if isPocket then
		if Pocket:GetAttribute("PocketId") == nil then
			Pocket:GetAttributeChangedSignal("PocketId"):Wait()
		end
		local pocketId = Pocket:GetAttribute("PocketId")
		if not pocketId then
			return Result.err("Bad pocketId")
		end
		return Result.ok(DataStoreService:GetDataStore(`Pocket-{pocketId}-GraphBox`))
	else
		return Result.ok(DataStoreService:GetDataStore("TRS-GraphBox"))
	end
end

function GraphBoxServer:_restoreDataAsync(persistId: number): Result.Result<nil>
	return Result.pcall(function()
		assert(typeof(persistId) == "number", "Bad persistId")

		local datastore = Result.unwrap(self:_getDataStore())

		while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) <= 0 do
			task.wait()
		end

		local data = datastore:GetAsync(`{persistId}`) or DEFAULT_DATA
		self:SetValidUVMapStrings(data.XMapStr, data.YMapStr, data.ZMapStr)
		self:SetShowGrid(data.ShowGrid)
	end)
end

function GraphBoxServer:SetValidUVMapStrings(xMapStr: string, yMapStr: string, zMapStr: string)
	self._obj:SetAttribute("xMap", xMapStr)
	self._obj:SetAttribute("yMap", yMapStr)
	self._obj:SetAttribute("zMap", zMapStr)
end

function GraphBoxServer:_observePersistData()
	return Rx.combineLatest {
		XMapStr = Rxi.attributeOf(self._obj, "xMap"),
		YMapStr = Rxi.attributeOf(self._obj, "yMap"),
		ZMapStr = Rxi.attributeOf(self._obj, "zMap"),
		ShowGrid = Rxi.attributeOf(self._obj, "ShowGrid"),
	}
end

function GraphBoxServer:PlayerSetUVMapStrings(_player: Player, xMapStr: string, yMapStr: string, zMapStr: string)
	local success, msg = pcall(function()
		UVMap.parse(xMapStr)
		UVMap.parse(yMapStr)
		UVMap.parse(zMapStr)
	end)
	if not success then
		warn(msg)
		return
	end

	self:SetValidUVMapStrings(xMapStr, yMapStr, zMapStr)
end

function GraphBoxServer:SetShowGrid(showGrid: boolean)
	self._obj:SetAttribute("ShowGrid", showGrid)
end

function GraphBoxServer:PlayerSetShowGrid(_player: Player, showGrid: boolean)
	self:SetShowGrid(showGrid)
end

return GraphBoxServer
