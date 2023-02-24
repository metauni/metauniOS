--
-- BuilderService
--

-- Services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Imports
local Destructor = require(ReplicatedStorage.Destructor)

-- Globals
local _infoOfPlayer = {}
local BuildingStorage = nil
local WorkspaceFolder = nil
local GRID_SIZE = 3

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

function BuilderService.Init()
    local event = newRemoteEvent("BuilderPlaceBlock")
    event.OnServerEvent:Connect(function(plr, pos, blockData)
        local block = Instance.new("Part")
        block.Size = Vector3.new(GRID_SIZE,GRID_SIZE,GRID_SIZE)
        block.Anchored = true
        block.Color = blockData.Color
        block.Material = blockData.Material
        block.Transparency = blockData.Transparency
        block.Parent = game.Workspace
        block.Position = pos
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