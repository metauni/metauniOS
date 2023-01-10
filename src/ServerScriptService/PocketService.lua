-- When you step into a pocket portal for the first time, it creates a pocket (identified
-- uniquely by a PlaceId together with an integer, the PocketCounter) using TeleportService
-- ReserveServer. We have to remember the access code for the pocket, and this is stored
-- in the DataStore with a key specific to the particular portal.

-- A Pocket learns its identifier (i.e. PlaceId-PocketCounter) from the first player
-- who enters it, who carries with them the PocketCounter in their TeleportData. This
-- is then stored permanently to the DataStore

-- https://developer.roblox.com/en-us/articles/Teleporting-Between-Places

-- Services
local CollectionService = game:GetService("CollectionService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local HTTPService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires
local Pocket = ReplicatedStorage.Pocket
local Remotes = Pocket.Remotes
local Config = require(Pocket.Config)
local GameAnalytics = require(ReplicatedStorage.Packages.GameAnalytics)

-- Remote Events
local ArriveRemoteEvent = Pocket.Remotes.Arrive
local GotoEvent = Remotes.Goto
local AddGhostEvent = Remotes.AddGhost
local CreatePocketEvent = Remotes.CreatePocket
local FirePortalEvent = Remotes.FirePortal
local ReturnToLastPocketEvent = Remotes.ReturnToLastPocket
local LinkPocketEvent = Remotes.LinkPocket
local UnlinkPortalRemoteEvent = Remotes.UnlinkPortal
local PocketsForPlayerRemoteFunction = Remotes.PocketsForPlayer
local SetTeleportGuiRemoteEvent = Remotes.SetTeleportGui
local GetLaunchDataRemoteFunction = Remotes.GetLaunchData

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	while DataStoreService:GetRequestBudgetForRequestType(requestType) <= 0 do
		task.wait()
	end
end

local ghosts = game.Workspace:FindFirstChild("MetaPortalGhostsFolder")

if ghosts == nil then
	ghosts = Instance.new("Folder")
	ghosts.Name = "MetaPortalGhostsFolder"
	ghosts.Parent = game.Workspace
end

function isPocket()
	return (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0)
end

local MetaPortal = {}
MetaPortal.__index = MetaPortal

function MetaPortal.Init()

	Pocket:SetAttribute("IsPocket", isPocket())

	MetaPortal.TeleportData = {} -- stores information for each player teleporting in
	MetaPortal.PocketInit = false
	MetaPortal.PocketData = nil
	MetaPortal.PocketInitTouchConnections = {}
end

function MetaPortal.Start()
	
	local portals = CollectionService:GetTagged(Config.PortalTag)
	for _, portal in ipairs(portals) do
		task.spawn(MetaPortal.InitPortal, portal)
	end
	
	CollectionService:GetInstanceAddedSignal(Config.PortalTag):Connect(function(portal)
		MetaPortal.InitPortal(portal)
	end)
	
	-- If we are not a pocket we initialise our pocket portals
	-- now, otherwise we wait until the pocket itself has been initialised
	if not isPocket() then
		MetaPortal.InitPocketPortals()
	end
	
	Players.PlayerAdded:Connect(function(plr)
		MetaPortal.PlayerArrive(plr)
	end)
	
	for _, plr in ipairs(Players:GetPlayers()) do
		MetaPortal.PlayerArrive(plr)
	end
	
	GotoEvent.OnServerEvent:Connect(function(plr,pocketText)
		MetaPortal.GotoPocketHandler(plr,pocketText)
	end)
	
	FirePortalEvent.OnServerEvent:Connect(function(plr,portal)
		MetaPortal.FirePortal(portal, plr)
	end)
	
	TeleportService.TeleportInitFailed:Connect(MetaPortal.TeleportFailed)
	CreatePocketEvent.OnServerEvent:Connect(MetaPortal.CreatePocket)
	LinkPocketEvent.OnServerEvent:Connect(MetaPortal.CreatePocketLink)
	ReturnToLastPocketEvent.OnServerEvent:Connect(MetaPortal.ReturnToLastPocket)
	UnlinkPortalRemoteEvent.OnServerEvent:Connect(MetaPortal.UnlinkPortal)
	PocketsForPlayerRemoteFunction.OnServerInvoke = MetaPortal.PocketsForPlayer
	GetLaunchDataRemoteFunction.OnServerInvoke = MetaPortal.GetLaunchData
end

function MetaPortal.GetLaunchData(plr)
	local joinData = plr:GetJoinData()

	-- Workaround for current bug in LaunchData
	local ignoreLaunchData = false
	if joinData.TeleportData ~= nil and joinData.TeleportData.IgnoreLaunchData ~= nil then
		ignoreLaunchData = joinData.TeleportData.IgnoreLaunchData
	end

	if joinData.LaunchData and joinData.LaunchData ~= "" and not ignoreLaunchData then
		return joinData.LaunchData
	end

	return nil
end

local pocketsForPlayerCache = {}
local pocketsForPlayerLastFetched = {}

function MetaPortal.PocketsForPlayer(plr)
	if plr == nil then
		print("[MetaPortal] PocketsForPlayer passed nil player")
		return
	end

	local DataStore = DataStoreService:GetDataStore(Config.PocketDataStoreTag)

	-- This can be triggered via remote function from the client, via GUI
	-- interactions, so to present DOS attack we rate limit these requests
	-- to one every minute
	if pocketsForPlayerLastFetched[plr] ~= nil then
		if pocketsForPlayerLastFetched[plr] > tick() - 60 then
			print("[MetaPortal] Returning cached values for player "..plr.UserId)
			-- return pocketsForPlayerCache[plr] TODO
		end
	end

	local playerKey = MetaPortal.KeyForUser(plr)
	local success, pocketList = pcall(function()
        waitForBudget(Enum.DataStoreRequestType.GetAsync)
		return DataStore:GetAsync(playerKey)
	end)
	if not success then
		print("[MetaPortal] GetAsync fail for " .. playerKey .. " with ".. pocketList)
		return
	end

	if pocketList == nil then
		print("No pocket list for player")
	end

	pocketsForPlayerLastFetched[plr] = tick()
	pocketsForPlayerCache[plr] = pocketList

	if pocketList == nil then return {} end
	return pocketList
end

function MetaPortal.ReturnToLastPocket(player)
	local DataStore = DataStoreService:GetDataStore(Config.DataStoreTag)
	if not DataStore then
        print("[MetaPortal] DataStore not loaded")
        return
    end

	local returnToPocketKey = "return_" .. player.UserId

	local success, returnToPocketData
    success, returnToPocketData = pcall(function()
        waitForBudget(Enum.DataStoreRequestType.GetAsync)
        return DataStore:GetAsync(returnToPocketKey)
    end)
    if not success then
        print("[MetaPortal] GetAsync fail for " .. returnToPocketKey .. " " .. returnToPocketData)
        return
    end

	if returnToPocketData == nil then
		print("[MetaPortal] No return to pocket data")
		return
	end

	local accessCode = returnToPocketData.AccessCode
	local placeId = returnToPocketData.PlaceId
	local pocketCounter = returnToPocketData.PocketCounter

	if accessCode == nil or placeId == nil or pocketCounter == nil then
		print("[MetaPortal] Invalid return to pocket data")
		return
	end

	-- Check that they are not "returning" to the current pocket
	if placeId == game.PlaceId and pocketCounter == MetaPortal.PocketData.PocketCounter then
		print("[MetaPortal] Attempted to return to current pocket, exiting")
		return
	end

	MetaPortal.GotoPocket(player, placeId, pocketCounter, accessCode)
end

function MetaPortal.TeleportFailed(player, teleportResult, errorMessage, placeId)
	print("[MetaPortal] Teleport failed for "..player.Name.." to place "..placeId.." : "..errorMessage)
	player:LoadCharacter()

    local success, err = pcall(function()
		GameAnalytics:addDesignEvent(player.UserId, {
            eventId = "Pockets:TeleportFailed"
        })
	end)	
	
	if not success then
		print("[MetaPortal] GameAnalytics addDesignEvent failed ".. err)
		return {}
	end
end

-- passThrough means we are handing a player off to a pocket, and don't
-- want to make a ghost or show the interstitial GUI
function MetaPortal.GotoPocket(plr, placeId, pocketCounter, accessCode, passThrough, targetBoardPersistId)
	if passThrough == nil then passThrough = false end

	-- Set the teleportGUI on the client
	local pocketName = MetaPortal.PocketTemplateNameFromPlaceId(placeId) .. " " .. pocketCounter
	SetTeleportGuiRemoteEvent:FireClient(plr, pocketName)

	local character = plr.Character

	-- Make a ghost
	if character ~= nil and character.PrimaryPart ~= nil and not passThrough then
		local cFrame = character.PrimaryPart.CFrame
		character.Archivable = true
		local ghost = character:Clone()
		character.Archivable = false

		character:Destroy()
		for _, item in pairs(plr.Backpack:GetChildren()) do
			item:Destroy()
		end

		ghost.Name = plr.Name
		ghost:PivotTo(cFrame)

		for _, desc in ipairs(ghost:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Transparency = 1 - (0.2 * (1 - desc.Transparency))
				desc.CastShadow = false
				desc.CanCollide = false
				desc.Anchored = true
			end
		end

		ghost.Parent = game.Workspace.MetaPortalGhostsFolder

		-- Figure out pocket name
		local pocketName
		for key, val in pairs(Config.PlaceIdOfPockets) do
			if val == placeId then
				pocketName = key
			end
		end
		
		AddGhostEvent:FireAllClients(ghost, pocketName, pocketCounter)

		local sound = Instance.new("Sound")
		sound.Name = "Sound"
		sound.Playing = false
		sound.RollOffMaxDistance = 100
		sound.RollOffMinDistance = 10
		sound.RollOffMode = Enum.RollOffMode.LinearSquare
		sound.SoundId = "rbxassetid://7864771146"
		sound.Volume = 0.3
		sound.Parent = ghost.PrimaryPart

		sound:Play()

		task.delay(60, function() ghost:Destroy() end)
	end

	local teleportOptions = Instance.new("TeleportOptions")
	local teleportData = {
		OriginPlaceId = game.PlaceId,
		OriginJobId = game.JobId,
		PocketCounter = pocketCounter,
		AccessCode = accessCode
	}

    -- Track players across pockets
    local success, augmentedTeleportData = pcall(function()
        return GameAnalytics:addGameAnalyticsTeleportData({plr.UserId}, teleportData)
	end)
	if not success then
		print("[MetaPortal] GameAnalytics addGameAnalyticsTeleportData failed ".. augmentedTeleportData)
    else
        teleportData = augmentedTeleportData
    end

    if targetBoardPersistId ~= nil then
        teleportData.TargetBoardPersistId = targetBoardPersistId
    end

	-- Workaround for current bug in LaunchData
	local joinData = plr:GetJoinData()
	if passThrough then
		teleportData.IgnoreLaunchData = true
	end

	if joinData.TeleportData ~= nil and joinData.TeleportData.IgnoreLaunchData ~= nil then
		print("[MetaPortal] Found IgnoreLaunchData in TeleportData")
		teleportData.IgnoreLaunchData = joinData.TeleportData.IgnoreLaunchData
	end

	MetaPortal.StoreReturnToPocketData(plr, placeId, pocketCounter, accessCode)

	teleportOptions.ReservedServerAccessCode = accessCode
	teleportOptions:SetTeleportData(teleportData)

	local success, errormessage = pcall(function()
		return TeleportService:TeleportAsync(placeId, {plr}, teleportOptions)
	end)
	if not success then
		print("[MetaPortal] TeleportAsync failed: ".. errormessage)
	end

    local success, err = pcall(function()
		GameAnalytics:addDesignEvent(plr.UserId, {
            eventId = "Pockets:GotoPocket"
        })
	end)	
	
	if not success then
		print("[MetaPortal] GameAnalytics addDesignEvent failed ".. err)
		return {}
	end
end

function MetaPortal.StoreReturnToPocketData(plr, placeId, pocketCounter, accessCode)
	-- Store this as the most recent pocket for this player
	local DataStore = DataStoreService:GetDataStore(Config.DataStoreTag)
	if not DataStore then
        print("[MetaPortal] DataStore not loaded")
        return
    end

	if plr == nil or placeId == nil or pocketCounter == nil or accessCode == nil then
		print("[MetaPortal] Bad data passed to StoreReturnToPocketData")
		return
	end

	local returnToPocketData = {
		PocketCounter = pocketCounter,
		AccessCode = accessCode,
		PlaceId = placeId
	}
	local returnToPocketKey = "return_" .. plr.UserId
	local success, errormessage = pcall(function()
        waitForBudget(Enum.DataStoreRequestType.SetIncrementAsync)
		return DataStore:SetAsync(returnToPocketKey, returnToPocketData)
	end)
	if not success then
		print("[MetaPortal] SetAsync fail for " .. returnToPocketKey .. " with ".. errormessage)
		return
	end
end

function MetaPortal.PocketDataFromPocketName(pocketText)
	local DataStore = DataStoreService:GetDataStore(Config.PocketDataStoreTag)
	
	if pocketText == nil or string.len(pocketText) == 0 then
		print("[MetaPortal] Bad pocket name")
		return nil
	end
	
	local strParts = pocketText:split(" ")
	if #strParts <= 1 then
		print("[MetaPortal] Badly formed pocket name")
		return nil
	end
	
	local pocketCounter = tonumber(strParts[#strParts])
	if pocketCounter == nil then
		print("[MetaPortal] Extraction of pocket counter failed")
		return nil
	end
	
	table.remove(strParts, #strParts)
	
	local pocketName = ""
	for i, part in pairs(strParts) do
		pocketName = pocketName .. part
		if i < #strParts then
			pocketName = pocketName .. " "
		end
	end
	
	local placeId = Config.PlaceIdOfPockets[pocketName]
	if placeId == nil then
		print("[MetaPortal] Could not find place ID for pocket name `"..pocketName.."`")
		return nil
	end
	
	local pocketKey = MetaPortal.KeyForPocket(placeId, pocketCounter)
	
	local success, pocketJSON
	success, pocketJSON = pcall(function()
        waitForBudget(Enum.DataStoreRequestType.GetAsync)
		return DataStore:GetAsync(pocketKey)
	end)
	if not success then
		print("[MetaPortal] GetAsync fail for pocket " .. pocketKey .. " " .. pocketJSON)
		return
	end
	
	if not pocketJSON then
		print("[MetaPortal] This pocket does not exist yet")
		return nil
	end
		
	local pocketData = HTTPService:JSONDecode(pocketJSON)
	if pocketData == nil then
		print("[MetaPortal] Failed to decode pocketData")
		return nil
	end

	return placeId, pocketData
end

function MetaPortal.GotoPocketHandler(plr, pocketText, passThrough, targetBoardPersistId)
	if pocketText == "The Rising Sea" then
		MetaPortal.ReturnToRoot(plr)
	end

	if passThrough == nil then passThrough = false end
	local placeId, pocketData = MetaPortal.PocketDataFromPocketName(pocketText)
	if placeId == nil or pocketData == nil then return end
	
	if pocketData.AccessCode == nil or pocketData.PocketCounter == nil then
		print("[MetaPortal] Failed to read access code for pocket")
		return
	end
	
	if isPocket() then
		if placeId == game.PlaceId and pocketData.PocketCounter == MetaPortal.PocketData.PocketCounter then
			print("[MetaPortal] Attempted to goto current pocket, exiting")
			return
		end
	end

	MetaPortal.GotoPocket(plr, placeId, pocketData.PocketCounter, pocketData.AccessCode, passThrough, targetBoardPersistId)
end

function MetaPortal.InitPocketPortals()
	local pockets = CollectionService:GetTagged(Config.PocketTag)

	for _, pocket in ipairs(pockets) do
		task.spawn(MetaPortal.InitPocketPortal, pocket)
	end
end

-- Keys have length 50, placeIds are 10 digits, so pocketCounter
-- is at most 21 digits
function MetaPortal.KeyForPocket(placeId, pocketCounter)
	return "metapocket/pocket/"..placeId.."-"..pocketCounter
end

-- Attempt to recover the identity of this pocket from the DataStore
-- Recall that the identity of a pocket is determined by its PlaceId
-- and by the integer PocketCounter, but we only have access to the
-- latter from the person who created the pocket as they join it
function MetaPortal.InitPocket(data)
	local pocketCounter = data.PocketCounter
	
	if pocketCounter == nil then
		print("[MetaPortal] Insufficient information to initialise pocket")
		return
	end
	
	-- This data is used for interop
	local pocketId = game.PlaceId .. "-" .. data.PocketCounter
	script.Parent:SetAttribute("PocketId", pocketId)
	Pocket:SetAttribute("PocketId", pocketId)
	print("[MetaPortal] PocketId: " .. pocketId)

	local pocketName = MetaPortal.PocketName(data.PocketCounter)
	Pocket:SetAttribute("PocketName", pocketName)
	print("[MetaPortal] PocketName: " .. pocketName)
		
	local DataStore = DataStoreService:GetDataStore(Config.PocketDataStoreTag)
	
	local pocketKey = MetaPortal.KeyForPocket(game.PlaceId, data.PocketCounter)

	local success, pocketJSON
	success, pocketJSON = pcall(function()
        waitForBudget(Enum.DataStoreRequestType.GetAsync)
		return DataStore:GetAsync(pocketKey)
	end)
	if not success then
		print("[MetaPortal] GetAsync fail for pocket " .. pocketKey .. " " .. pocketJSON)
		return
	end
	
    if not pocketJSON then
        print("[MetaPortal] Entered non-initialised pocket")
        return
    end

	local pocketData = HTTPService:JSONDecode(pocketJSON)
	
	local creatorId = pocketData.CreatorId
	if not creatorId then
		print("[MetaPortal] Failed to find CreatorId in pocket")
	else
		local creatorValue = workspace:FindFirstChild("PocketCreatorId")
		if not creatorValue then
			creatorValue = Instance.new("IntValue")
			creatorValue.Name = "PocketCreatorId"
			creatorValue.Value = creatorId
			creatorValue.Parent = workspace
			print("[MetaPortal] PocketCreatorId " .. creatorId)
		end
	end
	
	MetaPortal.PocketData = pocketData
	MetaPortal.PocketInit = true

	-- TODO remove dependence on creatorValue above
	Pocket:SetAttribute("PocketCreatorId", pocketData.CreatorId)
	
	MetaPortal.InitPocketPortals()
end

function MetaPortal.PocketName(pocketCounter)
	local pocketName = MetaPortal.PocketTemplateNameFromPlaceId(game.PlaceId)
	local labelText = ""

	if pocketName ~= nil then
		labelText = labelText .. pocketName
	end

	labelText = labelText .. " " .. tostring(pocketCounter)

	return labelText
end

function MetaPortal.InitPortal(portal)
	if not portal.PrimaryPart then
		print("[MetaPortal] Portal has no PrimaryPart")
		return
	end
	
	local teleportPart = portal.PrimaryPart
	
	teleportPart.Material = Enum.Material.Slate
	teleportPart.Transparency = 0.45
	teleportPart.CastShadow = 0
	teleportPart.CanCollide = false
	teleportPart.Anchored = true
	teleportPart.Color  = Color3.fromRGB(163, 162, 165)
	
	if teleportPart:FindFirstChild("Sound") then teleportPart.Sound:Destroy() end
	local sound = Instance.new("Sound")
	sound.Name = "Sound"
	sound.Playing = false
	sound.RollOffMaxDistance = 100
	sound.RollOffMinDistance = 10
	sound.RollOffMode = Enum.RollOffMode.LinearSquare
	sound.SoundId = "rbxassetid://7864771146"
	sound.Volume = 0.3
	sound.Parent = teleportPart
	
	if teleportPart:FindFirstChild("Fire") then teleportPart.Fire:Destroy() end
	local fire = Instance.new("Fire")
	fire.Color = Color3.fromRGB(236, 139, 70)
	fire.Enabled = true
	fire.Heat = 9
	fire.Name = "Fire"
	fire.SecondaryColor = Color3.fromRGB(139, 80, 55)
	fire.Size = 5
	fire.Parent = teleportPart
	
	-- For game streaming
	CollectionService:AddTag(portal.PrimaryPart, Config.PortalPartTag)
	
	-- NOTE: Attaching touch events is now done on the client
end

function MetaPortal.ReturnToRoot(plr)
	plr.Character:Destroy()
	for _, item in pairs(plr.Backpack:GetChildren()) do
		item:Destroy()
	end

	local teleportOptions = Instance.new("TeleportOptions")
	local teleportData = {
		OriginPlaceId = game.PlaceId,
		OriginJobId = game.JobId
	}

    -- Track players across pockets
    teleportData = GameAnalytics:addGameAnalyticsTeleportData({plr.UserId}, teleportData)

	local placeId = Config.RootPlaceId

	-- Workaround for current bug in LaunchData
	local joinData = plr:GetJoinData()
	if joinData.TeleportData ~= nil and joinData.TeleportData.IgnoreLaunchData ~= nil then
		print("[MetaPortal] Found IgnoreLaunchData in TeleportData")
		teleportData.IgnoreLaunchData = joinData.TeleportData.IgnoreLaunchData
	end
	
	teleportOptions:SetTeleportData(teleportData)
	
	local success, errormessage = pcall(function()
		return TeleportService:TeleportAsync(placeId, {plr}, teleportOptions)
	end)
	if not success then
		print("[MetaPortal] TeleportAsync failed: ".. errormessage)
	end
end

function MetaPortal.FirePortal(portal, plr)
	if portal == nil or plr == nil then
		print("[MetaPortal] FirePortal passed nil inputs")
		return
	end

	local teleportPart = portal.PrimaryPart
	if teleportPart == nil then
		print("[MetaPortal] Portal has nil PrimaryPart")
		return
	end

	-- If the portal specifies a pocket name, hand it off
	if portal:FindFirstChild("PocketName") then
		MetaPortal.GotoPocketHandler(plr,portal.PocketName.Value)
		return
	end

	local placeId = portal.PlaceId.Value
	local returnPortal = portal:FindFirstChild("Return") and portal.Return.Value
	local playerTeleportData = MetaPortal.TeleportData[plr.UserId]
	
	plr.Character:Destroy()
	for _, item in pairs(plr.Backpack:GetChildren()) do
		item:Destroy()
	end

	local teleportOptions = Instance.new("TeleportOptions")
	local teleportData = {
		OriginPlaceId = game.PlaceId,
		OriginJobId = game.JobId
	}
	
	-- If the portal leads to a pocket
	if CollectionService:HasTag(portal, "metapocket") then
		local templateName = MetaPortal.PocketTemplateNameFromPlaceId(placeId)
		if templateName ~= nil then
			local pocketName = templateName .. " " .. portal.PocketCounter.Value
			SetTeleportGuiRemoteEvent:FireClient(plr, pocketName)
			--wait(1) -- let the local teleport GUI get set
		else
			print("[MetaPortal] WARNING: Failed to get pocket name to set TeleportGui")
		end

		teleportData.OriginPersistId = portal.PersistId.Value -- portal you came from
		teleportData.PocketCounter = portal.PocketCounter.Value
		teleportData.CreatorId = portal.CreatorId.Value
		teleportData.AccessCode = portal.AccessCode.Value
		teleportData.ParentPlaceId = game.PlaceId -- TODO
		
		teleportOptions.ReservedServerAccessCode = portal.AccessCode.Value
		
		if isPocket() then	
			-- Pass along our identifying information so the sub-pocket can link back to us
			teleportData.ParentPocketCounter = MetaPortal.PocketData.PocketCounter
			teleportData.ParentAccessCode = MetaPortal.PocketData.AccessCode
		end

		MetaPortal.StoreReturnToPocketData(plr, placeId, portal.PocketCounter.Value, portal.AccessCode.Value)
	elseif returnPortal and isPocket() then
		-- If this is a "return to parent" portal, pass with the TeleportData the particular
		-- portal on the endpoint to teleport to (= where we came from). Recall
		-- that portals are identified by their PersistId

		-- The parent may be a top level server (so all we need is a place ID)
		-- or it could be a pocket itself, in which case we need its PlaceId
		-- PocketCounter and also its access code
		local u = MetaPortal.PocketData.ParentPlaceId
		local v = MetaPortal.PocketData.ParentPocketCounter
		local w = MetaPortal.PocketData.ParentAccessCode
		
		teleportData.TargetPersistId = MetaPortal.PocketData.ParentOriginPersistId
		
		if not u then
			print("[MetaPortal] Badly configured pocket")
			return
		end
		
		placeId = u
		
		if v and w then
			-- The parent is a pocket
			teleportData.PocketCounter = v
			teleportData.AccessCode = w
			teleportOptions.ReservedServerAccessCode = w

			MetaPortal.StoreReturnToPocketData(plr, placeId, v, w)
		end
	end

	-- Workaround for current bug in LaunchData
	local joinData = plr:GetJoinData()
	if joinData.TeleportData ~= nil and joinData.TeleportData.IgnoreLaunchData ~= nil then
		print("[MetaPortal] Found IgnoreLaunchData in TeleportData")
		teleportData.IgnoreLaunchData = joinData.TeleportData.IgnoreLaunchData
	end
	
    -- Track players across pockets
    teleportData = GameAnalytics:addGameAnalyticsTeleportData({plr.UserId}, teleportData)
    
	teleportOptions:SetTeleportData(teleportData)
	
	local success, errormessage = pcall(function()
		return TeleportService:TeleportAsync(placeId, {plr}, teleportOptions)
	end)
	if not success then
		print("[MetaPortal] TeleportAsync failed: ".. errormessage)
	end

    local success, errormessage = pcall(function()
		return GameAnalytics:addDesignEvent(plr.UserId, {
            eventId = "Pockets:FirePortal"
        })
	end)
	if not success then
		print("[MetaPortal] GameAnalytics failed: ".. errormessage)
	end
end

function MetaPortal.HasPocketCreatePermission(plr)
	local perm = plr:GetAttribute("metaadmin_isscribe")
	if perm == nil then return false end
	return perm
end

function MetaPortal.CreatePocketLink(plr, portal, pocketText)
	if portal == nil then
		print("[MetaPortal] Passed bad portal")
		return
	end

	if pocketText == nil or pocketText == "" then
		print("[MetaPortal] Passed bad pocketText to CreatePocketLink")
		return
	end

	local placeId, pocketData = MetaPortal.PocketDataFromPocketName(pocketText)
	if placeId == nil or pocketData == nil then
		print("[MetaPortal] Failed to find pocket data for: `"..pocketText.."`")
		return
	end

	if isPocket() then
		if placeId == game.PlaceId and pocketData.PocketCounter == MetaPortal.PocketData.PocketCounter then
			print("[MetaPortal] Attempted to link to current pocket, exiting")
			return
		end
	end
	
	pocketData.PlaceId = placeId
	pocketData.PocketName = Players:GetNameFromUserIdAsync(pocketData.CreatorId)

	local DataStore = DataStoreService:GetDataStore(Config.PocketDataStoreTag)
	local portalKey = MetaPortal.KeyForPortal(portal)
	local pocketJSON = HTTPService:JSONEncode(pocketData)
	DataStore:SetAsync(portalKey,pocketJSON)

	MetaPortal.AttachValuesToPocketPortal(portal, pocketData)
	local connection = MetaPortal.PocketInitTouchConnections[portal]
	if connection ~= nil then
		connection:Disconnect()
	end

    local success, errormessage = pcall(function()
		GameAnalytics:addDesignEvent(plr.UserId, {
            eventId = "Pockets:CreatePocketLink"
        })
	end)
	if not success then
		print("[MetaPortal] GameAnalytics failed: ".. errormessage)
	end
end

function MetaPortal.AddPocketToListForPlayer(plr, pocketData)
	local DataStore = DataStoreService:GetDataStore(Config.PocketDataStoreTag)

	local playerKey = MetaPortal.KeyForUser(plr)
	local success, updatedList = pcall(function()
        waitForBudget(Enum.DataStoreRequestType.SetIncrementAsync)
		return DataStore:UpdateAsync(playerKey, function(currentTable)
			if currentTable == nil then return {} end

			-- If the pocket already exists, we do not add it
			for _, p in ipairs(currentTable) do
				if p.PlaceId == pocketData.PlaceId and p.PocketCounter == pocketData.PocketCounter then
					return currentTable
				end
			end

			table.insert(currentTable, pocketData)
			return currentTable
		end)
	end)
	if not success then
		print("[MetaPortal] UpdateAsync fail for " .. playerKey .. " with ".. updatedList)
		return
	end
end

function MetaPortal.CreatePocket(plr, portal, pocketChosen)
	local DataStore = DataStoreService:GetDataStore(Config.PocketDataStoreTag)
	local portalKey = MetaPortal.KeyForPortal(portal)
	
	local placeId = Config.PlaceIdOfPockets[pocketChosen]
	if placeId == nil then
		print("[MetaPortal] Could not find selected pocket type")
		return
	end

	local placeKey = "metapocket/place/"..placeId

	-- Increment the counter for this place
	local success, pocketCounter = pcall(function()
        waitForBudget(Enum.DataStoreRequestType.SetIncrementAsync)
		return DataStore:IncrementAsync(placeKey, 1)
	end)
	if success then
		print("[MetaPortal] PlaceID counter is now "..pocketCounter)
	end

	local accessCode = TeleportService:ReserveServer(placeId)
	local pocketData = {
		AccessCode = accessCode,
		CreatorId = plr.UserId,
		PocketName = plr.DisplayName,
		PlaceId = placeId,
		ParentPlaceId = game.PlaceId,
		PocketCounter = pocketCounter,
        ParentOriginPersistId = portal.PersistId.Value
	}

    if isPocket() then	
        -- Pass along our identifying information so the sub-pocket can link back to us
        pocketData.ParentPocketCounter = MetaPortal.PocketData.PocketCounter
        pocketData.ParentAccessCode = MetaPortal.PocketData.AccessCode
    end

	local pocketJSON = HTTPService:JSONEncode(pocketData)
    local pocketKey = MetaPortal.KeyForPocket(placeId, pocketCounter)

    -- This DataStore entry _is_ the pocket
    local success, errormessage = pcall(function()
        waitForBudget(Enum.DataStoreRequestType.SetIncrementAsync)
        return DataStore:SetAsync(pocketKey,pocketJSON)
    end)
    if not success then
        print("[MetaPortal] SetAsync fail for " .. pocketKey .. " with ".. errormessage)
        return
    end

	-- Store association between this portal and this pocket
	local success, errormessage = pcall(function()
        waitForBudget(Enum.DataStoreRequestType.SetIncrementAsync)
		return DataStore:SetAsync(portalKey,pocketJSON)
	end)
	if not success then
		print("[MetaPortal] SetAsync fail for " .. portalKey .. " with ".. errormessage)
		return
	end

    local success, errormessage = pcall(function()
        GameAnalytics:addDesignEvent(plr.UserId, {
            eventId = "Pockets:CreatePocket"
        })
	end)
	if not success then
		print("[MetaPortal] GameAnalytics failed ".. errormessage)
		return
	end

	MetaPortal.AddPocketToListForPlayer(plr, pocketData)
	MetaPortal.AttachValuesToPocketPortal(portal, pocketData)

	local connection = MetaPortal.PocketInitTouchConnections[portal]
	if connection ~= nil then
		connection:Disconnect()
	end
end

function MetaPortal.PocketTemplateNameFromPlaceId(placeId)
	local pocketName = nil
	for key, value in pairs(Config.PlaceIdOfPockets) do
		if value == placeId then
			pocketName = key
		end
	end

	return pocketName
end

local userNameCache = {}

function getNameFromUserId(userId)
	local nameFromCache = userNameCache[userId]
	if nameFromCache then
		return nameFromCache
	end

	local userName
	local success, _ = pcall(function()
		userName = Players:GetNameFromUserIdAsync(userId)
	end)
	if success then
		userNameCache[userId] = userName
		return userName
	end
	
	print("[MetaPortal] Unable to find name for UserId:", userId)
	return nil
end

function MetaPortal.AttachValuesToPocketPortal(portal, data)
	if portal:FindFirstChild("AccessCode") then portal.AccessCode:Destroy() end
	local accessCode = Instance.new("StringValue")
	accessCode.Name = "AccessCode"
	accessCode.Value = data.AccessCode
	accessCode.Parent = portal

	if portal:FindFirstChild("PlaceId") then portal.PlaceId:Destroy() end
	local place = Instance.new("IntValue")
	place.Name = "PlaceId"
	place.Value = data.PlaceId
	place.Parent = portal

	if portal:FindFirstChild("PocketCounter") then portal.PocketCounter:Destroy() end
	local counter = Instance.new("IntValue")
	counter.Name = "PocketCounter"
	counter.Value = data.PocketCounter
	counter.Parent = portal

	if portal:FindFirstChild("CreatorId") then portal.CreatorId:Destroy() end
	local creator = Instance.new("IntValue")
	creator.Name = "CreatorId"
	creator.Value = data.CreatorId
	creator.Parent = portal

	local label = portal:FindFirstChild("Label")
	if label and data.PocketName ~= nil then
		local gui = label.SurfaceGui
		local text = gui.TextLabel	
		local labelText = ""
		local pocketName = MetaPortal.PocketTemplateNameFromPlaceId(data.PlaceId)
		if pocketName ~= nil then
			labelText = labelText .. pocketName
		end
		labelText = labelText .. " " .. tostring(data.PocketCounter)
		text.Text = labelText
	end

	-- Create the creator label
	if label and data.CreatorId ~= nil then
		local creatorName = getNameFromUserId(data.CreatorId)
		if creatorName ~= nil then
			local creatorLabel = label:Clone()
			creatorLabel.Size = 0.4 * label.Size

			local offset = CFrame.new(0,-1.6,0)
			creatorLabel.CFrame = label.CFrame:ToWorldSpace(offset)
			creatorLabel.SurfaceGui.TextLabel.Text = creatorName
			creatorLabel.SurfaceGui.TextLabel.TextTransparency = 0.6
			creatorLabel.Name = "CreatorLabel"
			creatorLabel.Parent = portal
		end
	end

	if portal:FindFirstChild("SurfaceLight") then portal.SurfaceLight:Destroy() end
	local slight = Instance.new("SurfaceLight")
	slight.Name = "SurfaceLight"
	slight.Range = 9
	slight.Brightness = 1
	slight.Parent = portal.PrimaryPart

	portal.IsOpen.Value = true
	CollectionService:AddTag(portal, "metaportal")	
end

function MetaPortal.KeyForUser(plr)
	if plr == nil then
		print("[MetaPortal] KeyForUser passed nil player")
		return
	end

	return "player/" .. plr.UserId
end

function MetaPortal.KeyForPortal(portal)
	if not portal.PersistId then
		print("[MetaPortal] Pocket has no PersistId")
		return
	end
	
	local persistId = portal.PersistId.Value
	
	local portalKey
	
	if isPocket() then
		-- We are in a pocket
		-- and so the key to look up this pocket portal also needs
		-- to involve the unique identifier of the pocket
		local pocketId = script.Parent:GetAttribute("PocketId")
		if not pocketId then
			print("[MetaPortal] Failed to initialise pocket portal")
			return
		end

		portalKey = "metapocket/portal/"..pocketId.."-"..persistId
	else
		-- In the top level server we just use the PersistId as a key
		portalKey = "metapocket/portal/"..persistId
	end
	
	return portalKey
end

function MetaPortal.ConnectBlankPocketPortalTouched(portal)
	local teleportPart = portal.PrimaryPart

	local connection
		
	local db = false -- debounce
	local function onPortalTouch(otherPart)
		if not otherPart then return end
		if not otherPart.Parent then return end

		local humanoid = otherPart.Parent:FindFirstChildWhichIsA("Humanoid")
		if humanoid then
			if not db then
				db = true
				local plr = Players:GetPlayerFromCharacter(otherPart.Parent)
				if plr then	
					if not MetaPortal.HasPocketCreatePermission(plr) and not RunService:IsStudio() then
						print("[MetaPortal] User is not authorised to make pockets")
						wait(0.1)
						db = false
						return
					end
					
					-- Check to see if this player has exceeded their quota of pockets
					local pockets = CollectionService:GetTagged(Config.PocketTag)
					
					local count = 0
					for _, pocket in ipairs(pockets) do
						local creator = pocket:FindFirstChild("CreatorId")
						if creator and creator.Value == plr.UserId then
							count += 1
						end
					end
					
					-- In a pocket the creator can make as many sub-pockets as they wish
					if count >= Config.PocketQuota and not (isPocket() and MetaPortal.PocketData.CreatorId == plr.UserId) then
						print("[MetaPortal] User has reached the pocket quota")
						wait(0.1)
						db = false
						return
					end
					
					CreatePocketEvent:FireClient(plr, portal)
				end
				wait(0.1)
				db = false
			end
		end
	end
	connection = teleportPart.Touched:Connect(onPortalTouch)
	MetaPortal.PocketInitTouchConnections[portal] = connection
end

function MetaPortal.InitPocketPortal(portal)
	local DataStore = DataStoreService:GetDataStore(Config.PocketDataStoreTag)
	
	if not portal.PersistId then
		print("[MetaPortal] Pocket has no PersistId")
		return
	end

	if not portal.PrimaryPart then
		print("[MetaPortal] Pocket has no PrimaryPart")
		return
	end
	
	local persistId = portal.PersistId.Value
	local teleportPart = portal.PrimaryPart
	
	local isOpen = Instance.new("BoolValue")
	isOpen.Value = false
	isOpen.Name = "IsOpen"
	isOpen.Parent = portal
	
	-- See if this pocket portal is in the DataStore
	local portalKey = MetaPortal.KeyForPortal(portal)
	
	local success, pocketJSON
	success, pocketJSON = pcall(function()
		return DataStore:GetAsync(portalKey)
	end)
	if not success then
		print("[MetaPortal] GetAsync fail for pocket portal" .. portalKey .. " " .. pocketJSON)
		return
	end
	
	if pocketJSON then
		-- The pocket has been interacted with already
		local pocketData = HTTPService:JSONDecode(pocketJSON)
		MetaPortal.AttachValuesToPocketPortal(portal, pocketData)
	else
		MetaPortal.ConnectBlankPocketPortalTouched(portal)
	end
end

function MetaPortal.UnlinkPortal(plr, portal)
	if portal:FindFirstChild("CreatorId") == nil or portal.CreatorId.Value == nil then
		print("[MetaPortal] Attempt to unlink malformed portal")
		return
	end

	local isAdmin = plr:GetAttribute("metaadmin_isadmin")
	local canUnlink = false

	if isPocket() then
		-- In a pocket you can unlink a portal if you created it, you
		-- own the pocket, or you have admin privileges
		canUnlink = (plr.UserId == portal.CreatorId.Value) or
					(plr.UserId == MetaPortal.PocketData.CreatorId) or
					isAdmin
	else
		-- Outside of a pocket, you can unlink a portal if you created it
		-- or you are an admin
		canUnlink = (plr.UserId == portal.CreatorId.Value) or
					isAdmin
	end

	if not canUnlink then
		print("[MetaPortal] Player does not have permission to unlink this portal")
		return
	end

    local success, errormessage = pcall(function()
        GameAnalytics:addDesignEvent(plr.UserId, {
            eventId = "Pockets:UnlinkPortal"
        })
	end)
	if not success then
		print("[MetaPortal] GameAnalytics failed ".. errormessage)
		return
	end

	local DataStore = DataStoreService:GetDataStore(Config.PocketDataStoreTag)

	-- Erase the contents stored for this portal
	local portalKey = MetaPortal.KeyForPortal(portal)
	local success, pocketJSON = pcall(function()
		return DataStore:RemoveAsync(portalKey)
	end)
	if not success then
		print("[MetaPortal] SetAsync fail for " .. portalKey .. " with ".. pocketJSON)
		return
	end

	-- Make sure this pocket is in the list of pockets for the player
	local pocketData = HTTPService:JSONDecode(pocketJSON)
	MetaPortal.AddPocketToListForPlayer(plr, pocketData)

	local teleportPart = portal.PrimaryPart
	teleportPart.Material = Enum.Material.Glass
	teleportPart.Fire:Destroy()

	local label = portal:FindFirstChild("Label")
	if label then
		local gui = label.SurfaceGui
		local text = gui.TextLabel	
		text.Text = ""
	end

	local creatorLabel = portal:FindFirstChild("CreatorLabel")
	if creatorLabel then
		creatorLabel.SurfaceGui.TextLabel.Text = ""
	end

	portal.IsOpen.Value = false
	portal.CreatorId:Destroy()

	CollectionService:RemoveTag(portal, Config.PortalTag)
	CollectionService:RemoveTag(portal.PrimaryPart, Config.PortalPartTag)

	MetaPortal.ConnectBlankPocketPortalTouched(portal)
end

-- We do not use PlayerAdded here, because when the server is starting up
-- this may not fire if we Init after the event has been fired
function MetaPortal.PlayerArrive(plr)
	local joinData = plr:GetJoinData()
	local teleportData = joinData.TeleportData

	if teleportData ~= nil then
		MetaPortal.TeleportData[plr.UserId] = teleportData
	end

	if isPocket() and not MetaPortal.PocketInit and teleportData ~= nil then
		MetaPortal.InitPocket(teleportData)
	end

	if joinData.TeleportData and joinData.TeleportData.pocket then
		print("[MetaPortal] Passing user "..plr.DisplayName.." through to "..teleportData.pocket)
		local passThrough = true
		MetaPortal.GotoPocketHandler(plr, teleportData.pocket, passThrough)
		return
	end

	-- Workaround for current bug in LaunchData
	local ignoreLaunchData = false
	if joinData.TeleportData ~= nil and joinData.TeleportData.IgnoreLaunchData ~= nil then
		ignoreLaunchData = joinData.TeleportData.IgnoreLaunchData
	end

	if joinData.LaunchData and joinData.LaunchData ~= "" and not ignoreLaunchData then
        local function processQuery(queryString)
            local q = {}
            -- The strings are "-"-separated "key:value" pairs
            for _, pair in string.split(queryString, "-") do
                local s = string.split(pair, ":")
                if s ~= nil and #s == 2 then
                    q[s[1]] = s[2]
                end
            end
            return q
        end

        local queryDict = processQuery(joinData.LaunchData)

        -- TODO: Currently if you spawn into TRS with a target board we won't help you
		if queryDict["pocket"] ~= nil then
			local pocketName = queryDict["pocket"]
			if pocketName ~= nil and pocketName ~= "" then
				print("[MetaPortal] User "..plr.DisplayName.." arrived with pocket launch data "..pocketName)

				local passThrough = true
                if queryDict["targetBoardPersistId"] ~= nil then
                    local targetBoard = queryDict["targetBoardPersistId"]
                    print("[MetaPortal] User arrived with target board "..targetBoard)
                    MetaPortal.GotoPocketHandler(plr, pocketName, passThrough, targetBoard)
                else
				    MetaPortal.GotoPocketHandler(plr, pocketName, passThrough)		
                end
			end
		end
	end
end

return MetaPortal
