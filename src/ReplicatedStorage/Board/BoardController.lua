-- --[[
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- --]]

-- Services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VRService = game:GetService("VRService")

-- Imports
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local Config = metaboard.Config
local BoardClient = require(script.Parent.BoardClient)
local ViewStateManager = require(script.Parent.ViewStateManager)

local BoardController = {}
BoardController.__index = BoardController

function BoardController:Init()
	
	self.Boards = {}
end

function BoardController:Start()
	
	-- VR Chalk

	if VRService.VREnabled then
		task.spawn(function()
			local chalk = script.Parent.Chalk:Clone()
			chalk.Parent = Players.LocalPlayer:WaitForChild("Backpack")
		end)
	end

	-- Local Canvases for boards

	local viewStateManager = ViewStateManager.new()
	task.spawn(function()
		while true do
			viewStateManager:UpdateWithAllActive(self.Boards)
			task.wait(0.5)
		end
	end)
	
	--------------------------------------------------------------------------------
	
	local function bindInstanceAsync(instance)
	
		-- Ignore if already seen this board
		if self.Boards[instance] then
			return
		end
	
		if not instance:GetAttribute("BoardServerInitialised") then
			
			instance:GetAttributeChangedSignal("BoardServerInitialised"):Wait()
		end
	
		local board = BoardClient.new(instance)
		
		local data = board.Remotes.GetBoardData:InvokeServer()
		
		board:ConnectRemotes()
	
		board:LoadData(data)
	
		self.Boards[instance] = board
	
		instance:GetPropertyChangedSignal("Parent"):Connect(function()
			
			if instance.Parent == nil then
				
				self.Boards[instance] = nil
			end
		end)
	end
	
	-- Bind regular metaboards
	
	for _, instance in ipairs(CollectionService:GetTagged(Config.BoardTag)) do
		
		task.spawn(bindInstanceAsync, instance)
	end
	
	CollectionService:GetInstanceAddedSignal(Config.BoardTag):Connect(bindInstanceAsync)
	
	-- TODO: Think about GetInstanceRemovedSignal (destroying metaboards)
	
	-- Bind personal boards
	
	for _, instance in ipairs(CollectionService:GetTagged("metaboard_personal_board")) do
		
		task.spawn(bindInstanceAsync, instance)
	end
	
	CollectionService:GetInstanceAddedSignal("metaboard_personal_board"):Connect(function(instance)
			
		bindInstanceAsync(instance)
	end)
end

return BoardController
