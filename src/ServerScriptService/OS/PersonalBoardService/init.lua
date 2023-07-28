-- --[[
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- --]]

-- Services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Imports
local BoardModel = script.BoardModels.BlackBoardMini
local Destructor = require(ReplicatedStorage.OS.Destructor)

-- Globals
local _destructors = {}
local BoardStorage = nil
local WorkspaceFolder = nil

local function initPlayer(player)
	
	local model = BoardModel:Clone()
	model.Name = player.Name.."-personalboard"
	CollectionService:AddTag(model.PrimaryPart, "metaboard")
	CollectionService:AddTag(model.PrimaryPart, "metaboard_personal_board")
	model.Parent = BoardStorage

	local destructor = Destructor.new()

	destructor:Add(model)
	
	local function initTool(character)
			
		local tool = Instance.new("Tool")
		tool.Name = "Personal Board"
		tool.Parent = player.Backpack

		model.Parent = BoardStorage

		tool.AncestryChanged:Connect(function()

			local backpack = player:FindFirstChild("Backpack")

			if backpack and tool.Parent then
				
				if tool.Parent == backpack then
					
					model.Parent = BoardStorage
					
				else
					
					--TODO: Move curves and board to new cframe

					model:PivotTo(character:GetPivot() * CFrame.new(0,2,-5) * CFrame.Angles(0, math.pi, 0))
					
					model.Parent = WorkspaceFolder
				end
			end
		end)

		do
			local connection
			connection = player.CharacterRemoving:Connect(function()
				
				tool:Destroy()
				connection:Disconnect()
			end)
		end
	end
	
	if player.Character then
		
		initTool(player.Character)
	end

	destructor:Add(player.CharacterAdded:Connect(initTool))

	
	_destructors[player] = destructor
end

return {

	Start = function()

		if not BoardStorage then
			
			BoardStorage = Instance.new("Folder")
			BoardStorage.Name = "PersonalBoardStorage"
			BoardStorage.Parent = ReplicatedStorage
		end

		if not WorkspaceFolder then
			
			WorkspaceFolder = Instance.new("Folder")
			WorkspaceFolder.Name = "PersonalBoards"
			WorkspaceFolder.Parent = workspace
		end
		
		Players.PlayerAdded:Connect(initPlayer)
		for _, player in ipairs(Players:GetPlayers()) do
			initPlayer(player)
		end

		Players.PlayerRemoving:Connect(function(player)
			
			local destructor = _destructors[player]
			if destructor then
				destructor:Destroy()
				_destructors[player] = nil
			end
		end)

	end
} 