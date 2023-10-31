local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local BaseObject = require(ReplicatedStorage.Util.BaseObject)
local Promise = require(ReplicatedStorage.Packages.Promise)
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
		Promise.retryWithDelay(function()
			return self:_promiseRestoreData(persistIdValue.Value)
		end, 3, 5)
		:andThen(function()
			self:_spawnSaver(persistIdValue.Value)
		end)
		:catch(warn)
	else
		local data = DEFAULT_DATA
		self:SetValidUVMapStrings(data.XMapStr, data.YMapStr, data.ZMapStr)
		self:SetShowGrid(data.ShowGrid)
	end

	return self
end

function GraphBoxServer:_spawnSaver(persistId: number)
	self:_promiseDataStore()
		:andThen(function(dataStore: DataStore)
			self._maid._saver = self:_observePersistData():Pipe {
				Rx.throttleTime(10, {leading = true, trailing = true}),
			}:Subscribe(function(data)
				local success, msg = pcall(function()
					dataStore:SetAsync(`{persistId}`, data)
				end)
				if not success then
					warn(msg)
				end
			end)
		end)
		:catch(warn)
end

function GraphBoxServer:_promiseDataStore()
	return Promise.new(function(resolve, reject)
	
		local isPocket = Pocket:GetAttribute("IsPocket")
		if isPocket then
			if Pocket:GetAttribute("PocketId") == nil then
				Pocket:GetAttributeChangedSignal("PocketId"):Wait()
			end
			local pocketId = Pocket:GetAttribute("PocketId")
			if not pocketId then
				reject("Bad pocketId")
			end
			resolve(DataStoreService:GetDataStore(`Pocket-{pocketId}-GraphBox`))
		else
			resolve(DataStoreService:GetDataStore("TRS-GraphBox"))
		end
	end)
end

function GraphBoxServer:_promiseRestoreData(persistId: number)
	assert(typeof(persistId) == "number", "Bad persistId")

	return Promise.new(function(resolve, reject)
	
		local isPocket = Pocket:GetAttribute("IsPocket")
		local datastore
		if isPocket then
			if Pocket:GetAttribute("PocketId") == nil then
				Pocket:GetAttributeChangedSignal("PocketId"):Wait()
			end
			local pocketId = Pocket:GetAttribute("PocketId")
			if not pocketId then
				reject("Bad pocketId")
			end
			datastore = DataStoreService:GetDataStore(`Pocket-{pocketId}-GraphBox`)
		else
			datastore = DataStoreService:GetDataStore("TRS-GraphBox")
		end
	
		while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) == 10 do
			task.wait()
		end
		
		local success, msg = pcall(function()
			local data = datastore:GetAsync(`{persistId}`) or DEFAULT_DATA
			self:SetValidUVMapStrings(data.XMapStr, data.YMapStr, data.ZMapStr)
			self:SetShowGrid(data.ShowGrid)
			resolve()
		end)
		if not success then
			reject(msg)
		end
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
		ShowGrid = Rxi.attributeOf(self._obj, "ShowGrid")
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