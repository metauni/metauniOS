-- --[[
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- --]]

-- Services
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Imports
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local Config = metaboard.Config
local DataStoreService = metaboard.Config.Persistence.DataStoreService
local BoardServer = require(script.BoardServer)
local Persistence = metaboard.Persistence
local Sift = require(ReplicatedStorage.Packages.Sift)
local Array, Set, Dictionary = Sift.Array, Sift.Set, Sift.Dictionary

-- Helper Functions
local indicateInvalidBoard = require(script.indicateInvalidBoard)

local BoardService = {

	Boards = {},
	ChangedSinceStore = {}
}
BoardService.__index = BoardService

function BoardService:Start()
	
	--[[
		Retrieve the datastore name (possibly waiting for MetaPortal)
	--]]
	local dataStore do
		local dataStoreName
		-- TODO: this fails to distinguish between places in Studio.
		-- See (PrivateServerKey appearance delay #14 issue)
		local Pocket = ReplicatedStorage.Pocket
	
		if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
	
			if Pocket:GetAttribute("PocketId") == nil then
				Pocket:GetAttributeChangedSignal("PocketId"):Wait()
			end
	
			local pocketId = Pocket:GetAttribute("PocketId")
	
			dataStoreName = "Pocket-"..pocketId
	
		else
	
			dataStoreName = Config.Persistence.DataStoreName
		end
	
		print("[metaboard] Using "..dataStoreName.." for Persistence DataStore")
	
		if not dataStoreName then
			warn("[metaboard] No DataStoreName given, not loading any boards")
			return
		end
	
		if Config.Persistence.RestoreDelay then
			
			task.wait(Config.Persistence.RestoreDelay)
		end
	
		dataStore = DataStoreService:GetDataStore(dataStoreName)
	end
	
	local function bindInstanceAsync(instance: Model | Part)
		
		if not instance:IsDescendantOf(workspace) then
	
			return
		end
	
		local persistIdValue = instance:FindFirstChild("PersistId")
		local persistId = persistIdValue and persistIdValue.Value
	
		local board = BoardServer.new(instance)
	
		-- Indicate that the board has been setup enough for clients to do their setup
		-- and request the board data.
		instance:SetAttribute("BoardServerInitialised", true)
	
		local handleBoardDataRequest = function(player)
			
			board.Watchers[player] = true
	
			return {
				
				Figures = board.Figures,
				DrawingTasks = board.DrawingTasks,
				PlayerHistories = board.PlayerHistories,
				NextFigureZIndex = board.NextFigureZIndex,
				EraseGrid = nil,
				ClearCount = nil
			}
		end
	
		if not persistId then
	
			board:ConnectRemotes(nil)
			board.Remotes.GetBoardData.OnServerInvoke = handleBoardDataRequest
	
		else
	
			local boardKey = Config.Persistence.PersistIdToBoardKey(persistId)
	
			local success, result = Persistence.Restore(dataStore, boardKey, board)
	
			if success then
				
				board:LoadData({
	
					Figures = result.Figures,
					DrawingTasks = {},
					PlayerHistories = {},
					NextFigureZIndex = result.NextFigureZIndex,
					EraseGrid = result.EraseGrid,
					ClearCount = result.ClearCount,
				})
	
				board.DataChangedSignal:Connect(function()
	
					self.ChangedSinceStore[persistId] = board
				end)
	
				local beforeClear = function()
					task.spawn(function()
						board.ClearCount += 1
						local historyKey = Config.Persistence.BoardKeyToHistoryKey(boardKey, board.ClearCount)
						Persistence.StoreWhenBudget(dataStore, historyKey, board)
					end)
				end
	
				board:ConnectRemotes(beforeClear)
				board.Remotes.GetBoardData.OnServerInvoke = handleBoardDataRequest
	
			else
	
				indicateInvalidBoard(board, result)
	
			end
		end
	
		-- For external code to access 
		BoardService.Boards[instance] = board
	end
	
	for _, instance in ipairs(CollectionService:GetTagged(Config.BoardTag)) do
	
		task.spawn(bindInstanceAsync, instance)
	end
	
	CollectionService:GetInstanceAddedSignal(Config.BoardTag):Connect(bindInstanceAsync)
	
	if Config.Persistence.ReadOnly then
	
		warn("[metaboard] Persistence is in ReadOnly mode, no changes will be saved.")
	else
	
		-- Once all boards are restored, trigger auto-saving
		game:BindToClose(function()
	
			if next(self.ChangedSinceStore) then
				
				print(
					string.format(
						"[metaboard] Storing %d boards on-close. SetIncrementAsync budget is %s.",
						Dictionary.count(self.ChangedSinceStore),
						DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync)
					)
				)
			end
	
			for persistId, board in pairs(self.ChangedSinceStore) do
	
				local boardKey = Config.Persistence.PersistIdToBoardKey(persistId)
				Persistence.StoreNow(dataStore, boardKey, board)
			end
	
			self.ChangedSinceStore = {}
		end)
	
		task.spawn(function()
			while true do
	
				task.wait(Config.Persistence.AutoSaveInterval)
	
				if next(self.ChangedSinceStore) then
					print(("[BoardService] Storing %d boards"):format(Dictionary.count(self.ChangedSinceStore)))
				end
	
				for persistId, board in pairs(self.ChangedSinceStore) do
	
					local boardKey = Config.Persistence.PersistIdToBoardKey(persistId)
					task.spawn(Persistence.StoreWhenBudget, dataStore, boardKey, board)
				end
	
				self.ChangedSinceStore = {}
			end
		end)
	end

end

return BoardService