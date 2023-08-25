--[[
	
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Binder = require(ReplicatedStorage.Util.Binder)
local Blend = require(ReplicatedStorage.Util.Blend)
local Rx = require(ReplicatedStorage.Util.Rx)
local GraphBoxClient = require(script.GraphBoxClient)
local GraphMenu = require(script.GraphMenu)

local Remotes = script.Remotes

local GraphBoxController = {}

function GraphBoxController:Init()

	self._editingGraphBox = Blend.State(nil)
	
	self.GraphBoxBinder = Binder.new("GraphBox", GraphBoxClient, self)
	self.GraphBoxBinder:Init()
end

function GraphBoxController:Start()

	self.GraphBoxBinder:GetClassRemovingSignal():Connect(function(graphBox)
		if graphBox == self._editingGraphBox.Value then
			self._editingGraphBox.Value = nil
		end
	end)

	self._graphMenu = GraphMenu.new({
		Visible = self._editingGraphBox:Observe():Pipe {
			Rx.map(function(graphBox)
				return graphBox ~= nil
			end)
		},
		OnSetUVMapStrings = function(xMapStr: string, yMapStr: string, zMapStr: string)
			local graphBox = self._editingGraphBox.Value
			if graphBox then
				Remotes.SetUVMapStrings:FireServer(graphBox._obj,
					xMapStr,
					yMapStr,
					zMapStr)
			end
		end,
		OnClose = function()
			self._editingGraphBox.Value = nil
		end,
		ShowGrid = self._editingGraphBox:Observe():Pipe {
			Rx.switchMap(function(graphBox)
				return if graphBox then graphBox:ObserveShowGrid() else Rx.never
			end)
		},
		OnToggleShowGrid = function()
			local graphBox = self._editingGraphBox.Value
			if graphBox then
				Remotes.SetShowGrid:FireServer(graphBox._obj, not graphBox:GetShowGrid())
			end
		end,
		UVMap = self._editingGraphBox:Observe():Pipe {
			Rx.switchMap(function(graphBox)
				return if graphBox then graphBox:ObserveUVMap() else Rx.never
			end),
		},
	})

	Blend.mount(Players.LocalPlayer.PlayerGui, {
		Blend.New "ScreenGui" {
			Name = "GraphBoxController",
			
			self._graphMenu:render()
		}
	})

	UserInputService.InputBegan:Connect(
		function(inputObject: InputObject, gameProcessedEvent: boolean)
			if not gameProcessedEvent and inputObject.KeyCode == Enum.KeyCode.G then
				self:CloseMenu()
			end
		end
	)

	self.GraphBoxBinder:Start()
end

function GraphBoxController:OpenMenuWith(graphBoxClient)
	self._editingGraphBox.Value = graphBoxClient
end

function GraphBoxController:CloseMenu()
	self._editingGraphBox.Value = nil
end

function GraphBoxController:ObserveEditingGraphBox()
	return self._editingGraphBox:Observe()
end

return GraphBoxController