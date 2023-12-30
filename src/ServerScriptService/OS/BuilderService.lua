--
-- BuilderService
--

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Destructor = require(ReplicatedStorage.OS.Destructor)

local _infoOfPlayer = {}
local BuildingStorage = nil
local WorkspaceFolder = nil
local GRID_SIZE = 3
local BLOCKTAG = "builderservice_block"

-- Utils
local function newRemoteEvent(name)
    if ReplicatedStorage:FindFirstChild(name) then
        warn(`[NPCService] Remote event {name} already exists`)
        return
    end

    local r = Instance.new("RemoteEvent")
    r.Name = name
    r.Parent = ReplicatedStorage
    return r
end

local BuilderService = {}
BuilderService.__index = BuilderService

local function initPlayer(player)
	local destructor = Destructor.new()

	local function initTool(character)
			
		local tool = Instance.new("Tool")
		tool.Name = "Builder Tools"
        tool.RequiresHandle = false
		tool.Parent = player.Backpack

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
	
	_infoOfPlayer[player] = {
		Destroy = function()
			destructor:Destroy()
		end,
	}
end

function BuilderService.DestroyBlock(pos)
    local size = 1/10 * GRID_SIZE
    local boxSize = Vector3.new(size, size, size)
    local params = OverlapParams.new()
    params.CollisionGroup = "Default"
    params.FilterDescendantsInstances = { WorkspaceFolder }
    params.FilterType = Enum.RaycastFilterType.Include
    params.MaxParts = 50

    local nearbyParts = game.Workspace:GetPartBoundsInBox(CFrame.new(pos), boxSize)
    for _, part in nearbyParts do
        part:Destroy()
        break
    end

    return
end

function BuilderService.PlaceBlock(pos, blockData)
    local block = Instance.new("Part")
    block.Size = Vector3.new(GRID_SIZE,GRID_SIZE,GRID_SIZE)
    block.Anchored = true
    block.Color = blockData.Color
    block.Material = blockData.Material
    block.Transparency = blockData.Transparency
    block.Parent = WorkspaceFolder
    block.Position = pos
    CollectionService:AddTag(block, BLOCKTAG)
end

function BuilderService.Init()
    local buildEvent = newRemoteEvent("BuilderPlaceBlock")
    local destroyEvent = newRemoteEvent("DestroyBlockEvent")

    buildEvent.OnServerEvent:Connect(function(plr, pos, blockData)
        BuilderService.PlaceBlock(pos, blockData)
    end)

    destroyEvent.OnServerEvent:Connect(function(plr, part, pos)
        if part then
            part:Destroy()
            return
        end

        -- This may have been a locally created temporary part, look for a block in the same position
        local intersectPart = Instance.new("Part")
        intersectPart.Size = Vector3.new(0.1,0.1,0.1)
        intersectPart.Transparency = 1
        intersectPart.CanCollide = false
        intersectPart.Anchored = true
        intersectPart.Position = pos
        intersectPart.Parent = game.Workspace

        for _, otherPart in game.Workspace:GetPartsInPart(intersectPart) do
            if CollectionService:HasTag(otherPart, BLOCKTAG) then
                otherPart:Destroy()
                break
            end
        end

        intersectPart:Destroy()
    end)
end

function BuilderService.Start()
    if not BuildingStorage then
        BuildingStorage = Instance.new("Folder")
        BuildingStorage.Name = "BuildingStorage"
        BuildingStorage.Parent = ReplicatedStorage
    end

    if not WorkspaceFolder then
        WorkspaceFolder = Instance.new("Folder")
        WorkspaceFolder.Name = "BuildingFolder"
        WorkspaceFolder.Parent = workspace
    end
    
    for _, player in ipairs(Players:GetPlayers()) do
        initPlayer(player)
    end

    Players.PlayerRemoving:Connect(function(player)
        local info = _infoOfPlayer[player]
        
        if info then
            info:Destroy()
        end

        _infoOfPlayer[player] = nil
    end)

    Players.PlayerAdded:Connect(initPlayer)
end

return BuilderService