--[[
	
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Binder = require(ReplicatedStorage.Util.Binder)
local GraphBoxServer = require(script.GraphBoxServer)

local Remotes = ReplicatedStorage.OS.GraphBoxController.Remotes

local GraphBoxService = {}
GraphBoxService.__index = GraphBoxService

function GraphBoxService:Init()
	self._binder = Binder.new("GraphBox", GraphBoxServer)
	self._binder:Init()
end

function GraphBoxService:Start()
	self._binder:Start()

	self._binder:AttachRemoteEvent(Remotes.SetUVMapStrings, "PlayerSetUVMapStrings")
	self._binder:AttachRemoteEvent(Remotes.SetShowGrid, "PlayerSetShowGrid")
end

return GraphBoxService