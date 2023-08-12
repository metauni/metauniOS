local BaseObject = require(script.Parent.BaseObject)
local Binder = require(script.Parent.Binder)
local PersistIdBoard = require(script.PersistIdBoard)

local PersistIdManager = setmetatable({}, BaseObject)
PersistIdManager.__index = PersistIdManager

function PersistIdManager.new()
	local self = setmetatable(BaseObject.new(), PersistIdManager)

	self._guiContainer = Instance.new("Folder")
	self._guiContainer.Name = "PersistIdManager"
	self._guiContainer.Parent = game:GetService("CoreGui")
	self._maid:AssignEach(self._guiContainer)
	
	return self
end

function PersistIdManager:Start()
	if self._boardBinder then
		return
	end
	
	self._boardBinder = Binder.new("metaboard", PersistIdBoard, self._guiContainer, self)
	self._boardBinder:Init()
	self._boardBinder:Start()
end

function PersistIdManager:Stop()
	if self._boardBinder then
		self._boardBinder:Destroy()
		self._boardBinder = nil
	end
end

return PersistIdManager
