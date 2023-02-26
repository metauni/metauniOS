-- Roblox services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Other services
local Fusion = require(ReplicatedStorage.Fusion)
local New = Fusion.New
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

-- Globals
local BLOCKTAG = "builderservice_block"
local localPlayer = Players.LocalPlayer
local placeBlockEvent = ReplicatedStorage:WaitForChild("BuilderPlaceBlock")
local destroyBlockEvent = ReplicatedStorage:WaitForChild("DestroyBlockEvent")
local buildingFolder = game.Workspace:WaitForChild("BuildingFolder")
local virtualBlock = nil

local BuilderUIEnabled = Fusion.State(false)
local CurrentBlock = Fusion.State("Concrete")

local blockTypes = { ["Concrete"] = { Color = Color3.fromRGB(159, 161, 172),
                                          Material = Enum.Material.Concrete,
                                          Transparency = 0 },
                     ["Redwood"] = { Color = Color3.fromRGB(178, 67, 37),
                                         Material = Enum.Material.WoodPlanks,
                                         Transparency = 0 },
                     ["Glass"] = { Color = Color3.fromRGB(163, 162, 165),
                                         Material = Enum.Material.Glass,
                                         Transparency = 0.9},
                     ["Destroy"] = { Color = Color3.fromRGB(210, 25, 25),
                                         Material = Enum.Material.SmoothPlastic,
                                         Transparency = 0.5}, }

local availableBlockTypes = { "Concrete", "Redwood", "Glass", "Destroy" }

local GRID_SIZE = 3
local PLACE_DISTANCE = 30

local function projectToGrid(v)
    local x = math.round(1/GRID_SIZE * v.X) * GRID_SIZE
    local y = math.round(1/GRID_SIZE * v.Y) * GRID_SIZE
    local z = math.round(1/GRID_SIZE * v.Z) * GRID_SIZE
    return Vector3.new(x,y,z)
end

local function placePosFromHitPos(pos, ray, normal)
    --return projectToGrid(pos - 0.05 * ray.Direction)
    return projectToGrid(pos + 0.05 * normal)
end

local function handleInputChanged(input)
    if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

    local mouseLocation = UserInputService:GetMouseLocation()
    local ray = game.Workspace.CurrentCamera:ScreenPointToRay(mouseLocation.X, mouseLocation.Y)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {virtualBlock, localPlayer.Character}
    local raycastResult = workspace:Raycast(ray.Origin, PLACE_DISTANCE * ray.Direction, raycastParams)
    if not raycastResult then return end

    local btype = CurrentBlock:get()
        
    local hitPosition
    if btype ~= "Destroy" then
        hitPosition = placePosFromHitPos(raycastResult.Position, ray, raycastResult.Normal)
    else
        hitPosition = raycastResult.Position
    end

    -- Place a virtual block
    if not virtualBlock then
        virtualBlock = Instance.new("Part")
        virtualBlock.Size = Vector3.new(GRID_SIZE,GRID_SIZE,GRID_SIZE)
        virtualBlock.Anchored = true
        virtualBlock.CanCollide = false
        virtualBlock.CastShadow = false
        virtualBlock.Color = blockTypes[CurrentBlock:get()].Color
        virtualBlock.Material = blockTypes[CurrentBlock:get()].Material
        virtualBlock.Parent = buildingFolder
        virtualBlock.Transparency = 0.5
    end

    virtualBlock.Position = hitPosition
end

local function handleInput(input, gameProcessedEvent)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if gameProcessedEvent then return end

    local mouseLocation = UserInputService:GetMouseLocation()
    local ray = game.Workspace.CurrentCamera:ScreenPointToRay(mouseLocation.X, mouseLocation.Y)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {virtualBlock, localPlayer.Character}
    local raycastResult = workspace:Raycast(ray.Origin, PLACE_DISTANCE * ray.Direction, raycastParams)
    if not raycastResult then return end

    local hitPosition = placePosFromHitPos(raycastResult.Position, ray, raycastResult.Normal)

    local btype = CurrentBlock:get()
    local color = blockTypes[btype].Color
    local material = blockTypes[btype].Material
    local transparency = blockTypes[btype].Transparency

    if btype ~= "Destroy" then
        placeBlockEvent:FireServer(hitPosition, blockTypes[btype])

        local block = Instance.new("Part")
        block.Size = Vector3.new(GRID_SIZE,GRID_SIZE,GRID_SIZE)
        block.Anchored = true
        block.Color = color
        block.Material = material
        block.Transparency = transparency
        block.Parent = buildingFolder
        block.Position = hitPosition
        CollectionService:AddTag(block, BLOCKTAG)

        -- Destroy the local block once the server copy replicates
        task.delay(5, function()
            block:Destroy()
        end)
    else
        local hitPart = raycastResult.Instance
        if hitPart and CollectionService:HasTag(hitPart, BLOCKTAG) then
            hitPart:Destroy()
            destroyBlockEvent:FireServer(hitPart, hitPart.Position)
        end
    end
end

local function Setup()
    local inputConnection = nil
    local inputChangedConnection = nil
    local tool = localPlayer.Backpack:WaitForChild("Builder Tools")
    tool.Enabled = false

    if localPlayer:GetAttribute("metaadmin_isscribe") then
        tool.Enabled = true
    end

    localPlayer:GetAttributeChangedSignal("metaadmin_isscribe"):Connect(function()
        tool.Enabled = localPlayer:GetAttribute("metaadmin_isscribe")
    end)

    tool.Equipped:Connect(function()
        inputConnection = UserInputService.InputBegan:Connect(handleInput)
        inputChangedConnection = UserInputService.InputChanged:Connect(handleInputChanged)
        BuilderUIEnabled:set(true)
    end)

    local function tearDown()
        BuilderUIEnabled:set(false)

        if inputConnection then
            inputConnection:Disconnect()
            inputConnection = nil
        end

        if inputChangedConnection then
            inputChangedConnection:Disconnect()
            inputChangedConnection = nil
        end

        if virtualBlock then
            virtualBlock:Destroy()
            virtualBlock = nil
        end
    end

    tool.Unequipped:Connect(function()
        tearDown()
    end)

    -- The block choosing UI
    local blockGuis = {}
    for i, t in pairs(availableBlockTypes) do
        table.insert(blockGuis, New "TextButton" {
                    Size = UDim2.new(0, 80, 0, 40),
                    Position = UDim2.new(0, 0, 0, (i-1)*40),
                    TextColor3 = Color3.new(1, 1, 1),
                    TextXAlignment = Enum.TextXAlignment.Center,
                    BackgroundTransparency = 1,
                    TextSize = 10,
                    Text = t,
                    [OnEvent "Activated"] = function()
                        CurrentBlock:set(t)

                        if virtualBlock then
                            virtualBlock.Color = blockTypes[CurrentBlock:get()].Color
                            virtualBlock.Material = blockTypes[CurrentBlock:get()].Material
                        end
                    end,
                    [Children] = New "UIStroke" {
                        Enabled = Fusion.Computed(function()
                            return CurrentBlock:get() == t
                        end),
                        Thickness = 1,
                        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                        Color = Color3.new(1,1,1)
                    }
                })
    end

    New "ScreenGui" {
        Parent = Players.LocalPlayer.PlayerGui,
    
        Name = "BuilderGui",
        ResetOnSpawn = true,
        ZIndexBehavior = "Sibling",
        Enabled = Fusion.Computed(function()
            return BuilderUIEnabled:get()
        end),
    
        [Children] = New "Frame" {
            AnchorPoint = Vector2.new(0,0.5),
            Position = UDim2.new(0,10,0.5,0),
            Size = UDim2.fromOffset(80, #blockGuis * 40),
            BackgroundColor3 = Color3.new(0,0,0),
            BackgroundTransparency = 0.7,

            [Children] = blockGuis
        }
    }
end

Players.LocalPlayer.CharacterAdded:Connect(function(character)
    Setup()
end)

return {
    Start = Setup
}