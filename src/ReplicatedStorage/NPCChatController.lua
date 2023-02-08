local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChatService = game:GetService("Chat")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Fusion = require(ReplicatedStorage.Fusion)

local New = Fusion.New
local Children = Fusion.Children
local State = Fusion.State
local OnEvent = Fusion.OnEvent

local localPlayer = Players.LocalPlayer
local GetNPCPrivacySettings = ReplicatedStorage:WaitForChild("GetNPCPrivacySettings")
local SetNPCPrivacySettings = ReplicatedStorage:WaitForChild("SetNPCPrivacySettings")

local Sift = require(ReplicatedStorage.Packages.Sift)
local Array = Sift.Array

local function getInstancePosition(x)
	if x:IsA("Part") then return x.Position end
	if x:IsA("Model") and x.PrimaryPart ~= nil then
		return x.PrimaryPart.Position
	end
	
	return nil
end

local NPCService = {
    NPCTag = "npcservice_npc"
}

local Perms = {}

local function updateNPCPerms()
    local myPerms = GetNPCPrivacySettings:InvokeServer()
    if not myPerms then
        warn(`[NPCChatController] Received invalid NPC permissions`)
        return
    end

    local npcInstances = CollectionService:GetTagged(NPCService.NPCTag)
    for _, npcInstance in npcInstances do
        Perms[npcInstance]["Read"]:set(myPerms[tostring(npcInstance.PersistId.Value)]["Read"])
        Perms[npcInstance]["Remember"]:set(myPerms[tostring(npcInstance.PersistId.Value)]["Remember"])
    end
end

local function SetupAIMenu()
    -- Can see rbxassetid://12296137041
    -- Can hear rbxassetid://12296137475
    -- Can remember rbxassetid://12296137280

    local AIFrameEnabled = Fusion.State(false)
    local NPCentries = {}
    local selectedColor = Color3.new(0.058823, 0.576470, 0.180392)

    table.insert(NPCentries,
        New "Frame" {
            BackgroundTransparency = 1,

            [Children] = {
                New "TextLabel" {
                    Size = UDim2.new(0, 0, 0, 40),
                    TextColor3 = Color3.new(1, 1, 1),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BackgroundTransparency = 1,
                    TextSize = 20,
                    Text = "",

                    [Children] = New "UISizeConstraint" {
                        MinSize = Vector2.new(40, 0)
                    }
                },
                New "TextLabel" {
                    Size = UDim2.new(0, 0, 0, 40),
                    TextColor3 = Color3.new(1, 1, 1),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BackgroundTransparency = 1,
                    TextSize = 20,
                    Text = "Hear",

                    [Children] = New "UISizeConstraint" {
                        MinSize = Vector2.new(40, 0)
                    }
                },
                New "TextLabel" {
                    Size = UDim2.new(0, 0, 0, 40),
                    TextColor3 = Color3.new(1, 1, 1),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BackgroundTransparency = 1,
                    TextSize = 20,
                    Text = "Read",

                    [Children] = New "UISizeConstraint" {
                        MinSize = Vector2.new(40, 0)
                    }
                },
                New "TextLabel" {
                    Size = UDim2.new(0, 0, 0, 40),
                    TextColor3 = Color3.new(1, 1, 1),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BackgroundTransparency = 1,
                    TextSize = 20,
                    Text = "Remember",

                    [Children] = New "UISizeConstraint" {
                        MinSize = Vector2.new(40, 0)
                    }
                }
            }
        }
    )
    
    local npcs = CollectionService:GetTagged(NPCService.NPCTag)
    local sortedNPCs = Array.sort(npcs, function(npc1, npc2)
		return string.sub(npc1.Name,1,1) < string.sub(npc2.Name,1,1)
	end)

    for _, npc in sortedNPCs do
        Perms[npc] = {}
        Perms[npc]["Hear"] = Fusion.State(false)
        Perms[npc]["Read"] = Fusion.State(false)
        Perms[npc]["Remember"] = Fusion.State(false)

        table.insert(NPCentries, 
            New "Frame" {
                BackgroundTransparency = 1,

                [Children] = {
                    New "TextLabel" {
                        Size = UDim2.new(0, 0, 0, 40),
                        TextColor3 = Color3.new(1, 1, 1),
                        TextXAlignment = Enum.TextXAlignment.Left,
                        BackgroundTransparency = 1,
                        TextSize = 20,
                        Text = npc.Name,

                        [Children] = New "UISizeConstraint" {
                            MinSize = Vector2.new(80, 0)
                        }
                    },
                    -- Hear image
                    New "ImageButton" {
                        Size = UDim2.new(0, 40, 0, 40),
                        BackgroundTransparency = Fusion.Computed(function()
                            if Perms[npc]["Hear"]:get() then
                                return 0
                            else
                                return 1
                            end
                        end),
                        
                        Image = "rbxassetid://12296137475",
                        BackgroundColor3 = selectedColor,
                        [Children] = New "UICorner" {
                            CornerRadius = UDim.new(0, 3)
                        }
                    },
                    -- Read image
                    New "ImageButton" {
                        Size = UDim2.new(0, 40, 0, 40),
                        BackgroundTransparency = Fusion.Computed(function()
                            if Perms[npc]["Read"]:get() then
                                return 0
                            else
                                return 1
                            end
                        end),
                        Image = "rbxassetid://12296137041",
                        BackgroundColor3 = selectedColor,
                        [OnEvent "Activated"] = function()
                            local perm = Perms[npc]["Read"]:get()
                            Perms[npc]["Read"]:set(not perm)
                            SetNPCPrivacySettings:FireServer(npc.PersistId.Value, "Read", not perm)
                        end,
                        [Children] = New "UICorner" {
                            CornerRadius = UDim.new(0, 3)
                        }
                    },
                    -- Remember image
                    New "ImageButton" {
                        Size = UDim2.new(0, 40, 0, 40),
                        BackgroundTransparency = Fusion.Computed(function()
                            if Perms[npc]["Remember"]:get() then
                                return 0
                            else
                                return 1
                            end
                        end),
                        Image = "rbxassetid://12296137280",
                        BackgroundColor3 = selectedColor,
                        [OnEvent "Activated"] = function()
                            local perm = Perms[npc]["Remember"]:get()
                            Perms[npc]["Remember"]:set(not perm)
                            SetNPCPrivacySettings:FireServer(npc.PersistId.Value, "Remember", not perm)
                        end,
                        [Children] = New "UICorner" {
                            CornerRadius = UDim.new(0, 3)
                        }
                    }
                }
            }
        )
    end

    table.insert(NPCentries, New "UITableLayout" {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        FillEmptySpaceColumns = false,
        FillEmptySpaceRows = false,
        Padding = UDim2.new(0, 5, 0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder
    })

    local NPCFrame = New "Frame" {
            AnchorPoint = Vector2.new(0.5,0.5),
            Position = UDim2.fromScale(0.5,0.5),
            Size = UDim2.new(0.9, 0, 0.55, 0),
            BackgroundColor3 = Color3.new(0,0,0),
            BackgroundTransparency = 0.2,

            [Children] = NPCentries
        }

    -- Create the Privacy settings GUI
    local privacyGui = New "ScreenGui" {
        Parent = Players.LocalPlayer.PlayerGui,
    
        Name = "AIPrivacyGui",
        ResetOnSpawn = false,
        ZIndexBehavior = "Sibling",
        Enabled = Fusion.Computed(function()
            return AIFrameEnabled:get()
        end),
    
        [Children] = New "Frame" {
            AnchorPoint = Vector2.new(0.5,0.5),
            Position = UDim2.fromScale(0.5,0.5),
            Size = UDim2.fromOffset(550, 450),
            BackgroundColor3 = Color3.new(0,0,0),
            BackgroundTransparency = 0.2,

            [Children] = { 
                New "TextLabel" {
                    Position = UDim2.fromScale(.5, .1),
                    AnchorPoint = Vector2.new(.5, .5),
                    Size = UDim2.fromScale(0.9, 0.1),
                    TextColor3 = Color3.new(1, 1, 1),
                    BackgroundTransparency = 1,
                    TextSize = 35,
                    Text = "AI Privacy Settings"
                },

                NPCFrame,

                New "TextLabel" {
                    Position = UDim2.fromScale(.5, .85),
                    AnchorPoint = Vector2.new(.5, .5),
                    Size = UDim2.fromScale(0.9, 0.2),
                    TextColor3 = Color3.new(171, 171, 171),
                    BackgroundTransparency = 1,
                    TextSize = 15,
                    TextWrapped = true,
                    Text = "Hear shows if the NPC can hear you via transcription of voice chat. Read shows if the NPC can read your text messages. Remember shows if the NPC remembers summaries of its interactions with you for later reference. Note queries are sent to OpenAI for processing."
                },

                New "UICorner" {
                    CornerRadius = UDim.new(0, 8)
                }
            }
        }
    }

    -- The icon is https://fonts.google.com/icons?selected=Material%20Symbols%20Outlined%3Apsychology%3AFILL%400%3Bwght%40400%3BGRAD%400%3Bopsz%4048
    local iconAssetId = "rbxassetid://12295342491"
    
    local Icon = require(ReplicatedStorage.Icon)
    local Themes =  require(ReplicatedStorage.Icon.Themes)

    local icon = Icon.new()
    icon:setImage(iconAssetId)
    icon:setLabel("AI")
    icon:setOrder(20)
    icon:setEnabled(false)
    icon:setTheme(Themes["BlueGradient"])
    icon.deselectWhenOtherIconSelected = false
    icon:bindEvent("selected", function(self)
        -- Update permissions from the server
        updateNPCPerms()
        AIFrameEnabled:set(true)
    end)
    icon:bindEvent("deselected", function(self)
        AIFrameEnabled:set(false)
    end)

    task.spawn(function()
        while task.wait(3) do
            if localPlayer.Character == nil or localPlayer.Character.PrimaryPart == nil then continue end
            
            local activeAIs = false

            local CUTOFF = 40

            local npcInstances = CollectionService:GetTagged(NPCService.NPCTag)
            for _, npcInstance in npcInstances do
                if not npcInstance:IsDescendantOf(game.Workspace) then continue end
                activeAIs = true

                local npcPos = getInstancePosition(npcInstance)

                if npcInstance:GetAttribute("npcservice_hearing") then
                    Perms[npcInstance]["Hear"]:set(true)
                else
                    Perms[npcInstance]["Hear"]:set(false)
                end
                
                if (getInstancePosition(localPlayer.Character) - npcPos).Magnitude < CUTOFF then
                    if npcInstance:GetAttribute("npcservice_hearing") then
                        Perms[npcInstance]["Hear"]:set(true)
                    else
                        Perms[npcInstance]["Hear"]:set(false)
                    end

                    break
                end
            end

            icon:setEnabled(activeAIs)
        end
    end)
end

local function SetupNPCChatBubbles()
    local maxBubbles = 5
    local bubbleDuration = 40

    local bubbleChatSettings = {}
    bubbleChatSettings.UserSpecificSettings = {}
    local chatSettings = {}

    chatSettings['Youtwice'] = {
        CornerRadius = UDim.new(0, 3),
        TailVisible = true,
        TextSize = 26,
        TextColor3 = Color3.new(0, 0, 0),
        Font = Enum.Font.GrenzeGotisch,
        Padding = 8,
        BubbleDuration = bubbleDuration,
        BubblesSpacing = 4,
        MaxBubbles = maxBubbles,
        VerticalStudsOffset = 1
    }

    chatSettings['Shoal'] = {
        CornerRadius = UDim.new(0, 2),
        TailVisible = false,
        TextSize = 24,
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.Sarpanch,
        Padding = 8,
        BubbleDuration = bubbleDuration,
        BubblesSpacing = 4,
        MaxBubbles = maxBubbles,
        VerticalStudsOffset = 1,
        BackgroundGradient = {
            Enabled = true,
            Rotation = 90,
            Color = ColorSequence.new(Color3.fromRGB(0, 0, 0), Color3.fromRGB(0, 56, 160)),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 0)})
            }
    }

    chatSettings['Ginger'] = {
        CornerRadius = UDim.new(0, 6),
        TailVisible = false,
        TextSize = 18,
        TextColor3 = Color3.new(1, 1, 1),
        Padding = 12,
        BubbleDuration = bubbleDuration,
        BubblesSpacing = 4,
        MaxBubbles = maxBubbles,
        VerticalStudsOffset = 1,
        BackgroundGradient = {
            Enabled = true,
            Rotation = 90,
            Color = ColorSequence.new(Color3.fromRGB(175, 122, 0), Color3.fromRGB(175, 122, 0)),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 0.2)})
            }
    }      
        
    local function setupBubbleChat(npc)
        npc:WaitForChild("Head")
        bubbleChatSettings.UserSpecificSettings[npc.Head:GetFullName()] = chatSettings[npc.Name]
    end

    local npcs = CollectionService:GetTagged(NPCService.NPCTag)
	for _, npc in npcs do
        if npc:IsDescendantOf(game.Workspace) then
            setupBubbleChat(npc)
        end

        -- The NPC moves from replicated storage into workspace, apply the bubble
        -- chat settings to its head after it moves
        
        npc.AncestryChanged:Connect(function(child,parent)
            if npc:IsDescendantOf(game.Workspace) then
                setupBubbleChat(npc)
                ChatService:SetBubbleChatSettings(bubbleChatSettings)
            end
        end)
    end

    ChatService:SetBubbleChatSettings(bubbleChatSettings)
end

local function SetupNPCClient()
    SetupAIMenu()
    SetupNPCChatBubbles()
end

return {
    Start = SetupNPCClient
}