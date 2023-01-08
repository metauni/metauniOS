local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChatService = game:GetService("Chat")
local ServerScriptService = game:GetService("ServerScriptService")

local NPCService = {
    NPCTag = "npcservice_npc"
}

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
        
    local npcs = CollectionService:GetTagged(NPCService.NPCTag)
	for _, npc in npcs do
        npc:WaitForChild("Head")

        bubbleChatSettings.UserSpecificSettings[npc.Head:GetFullName()] = chatSettings[npc.Name]
    end
    
    ChatService:SetBubbleChatSettings(bubbleChatSettings)
end

return {
    Start = SetupNPCChatBubbles
}