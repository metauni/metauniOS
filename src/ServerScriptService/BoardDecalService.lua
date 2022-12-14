--
-- BoardDecalService
--
-- Client code is in ReplicatedStorage > KnotMenuController

-- Roblox services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local Pocket = ReplicatedStorage.Pocket

-- Utils
local function waitForBudget(requestType: Enum.DataStoreRequestType)

	while DataStoreService:GetRequestBudgetForRequestType(requestType) <= 0 do
		task.wait()
	end
end

local function decalKeyForBoard(board)
	local persistId = board:FindFirstChild("PersistId")
	if persistId == nil then return end
	
	return "decal/metaboard"..tostring(persistId.Value)
end

local BoardDecalService = {}
BoardDecalService.__index = BoardDecalService

function BoardDecalService.SetDecal(board, assetId)
	local boardPart = if board:IsA("BasePart") then board else board.PrimaryPart
	local decal = boardPart:FindFirstChild("BoardDecal")
	if decal == nil then 
		decal = Instance.new("Decal")
		decal.Name = "BoardDecal"
		decal.Parent = boardPart
	end
	
	decal.Texture = assetId
end

function BoardDecalService.Init()
    local remoteEvent = Instance.new("RemoteEvent")
    remoteEvent.Name = "AddDecalToBoard"
    remoteEvent.Parent = ReplicatedStorage

    remoteEvent.OnServerEvent:Connect(function(plr, board, assetId)
        local perm = plr:GetAttribute("metaadmin_isscribe")
        if not perm then
            warn("[Metaboard] Player does not have permission to add decal")
            return
        end
        
        BoardDecalService.SetDecal(board, assetId)
        
        local dataStoreName = "boarddecals" -- for TRS
        if Pocket:GetAttribute("IsPocket") then
            dataStoreName = "Pocket-" .. Pocket:GetAttribute("PocketId")
        end

        local DataStore = DataStoreService:GetDataStore(dataStoreName)
        local decalKey = decalKeyForBoard(board)
        DataStore:SetAsync(decalKey, assetId)
    end)
end

function BoardDecalService.Start()
    local dataStoreName = "boarddecals"

    if Pocket:GetAttribute("IsPocket") then
        if Pocket:GetAttribute("PocketId") == nil then
            Pocket:GetAttributeChangedSignal("PocketId"):Wait()
        end

	    dataStoreName = "Pocket-" .. Pocket:GetAttribute("PocketId")
    end
	local DataStore = DataStoreService:GetDataStore(dataStoreName)
	
	local boards = CollectionService:GetTagged("metaboard")
	
	for _, board in boards do
		task.spawn(function()
			
			if not board:IsDescendantOf(game.Workspace) then return end
			if board:FindFirstChild("PersistId") == nil then return end
			
			waitForBudget(Enum.DataStoreRequestType.GetAsync)
			
			local decalKey = decalKeyForBoard(board)
			local assetId = DataStore:GetAsync(decalKey)
			if assetId then
				BoardDecalService.SetDecal(board, assetId)
			end
		end)
	end
end

return BoardDecalService