--[[
	
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Binder = require(ReplicatedStorage.Util.Binder)
local GraphBoxClient = require(script.GraphBoxClient)

local GraphBoxController = {}

function GraphBoxController:Init()
	
	self.GraphBoxBinder = Binder.new("GraphBox", GraphBoxClient)
	self.GraphBoxBinder:Init()
end

function GraphBoxController:Start()
	self.GraphBoxBinder:Start()
end

return GraphBoxController