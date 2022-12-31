local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local VRService = game:GetService("VRService")
local Players = game:GetService("Players")

local Remotes = script.Parent.Remotes
local Config = require(script.Parent.Config)
local EmojiList = require(script.Parent.EmojiList)

local OrbAttachRemoteEvent = Remotes.OrbAttach
local OrbDetachRemoteEvent = Remotes.OrbDetach
local OrbAttachSpeakerRemoteEvent = Remotes.OrbAttachSpeaker
local OrbDetachSpeakerRemoteEvent = Remotes.OrbDetachSpeaker
local OrbSpeakerMovedRemoteEvent = Remotes.OrbSpeakerMoved
local OrbTeleportRemoteEvent = Remotes.OrbTeleport
local OrbTweeningStartRemoteEvent = Remotes.OrbTweeningStart
local OrbTweeningStopRemoteEvent = Remotes.OrbTweeningStop
local OrbListenOnRemoteEvent = Remotes.OrbListenOn
local OrbListenOffRemoteEvent = Remotes.OrbListenOff
local OrbcamOnRemoteEvent = Remotes.OrbcamOn
local OrbcamOffRemoteEvent = Remotes.OrbcamOff
local VRSpeakerChalkEquipRemoteEvent = Remotes.VRSpeakerChalkEquip
local VRSpeakerChalkUnequipRemoteEvent = Remotes.VRSpeakerChalkUnequip
local SpecialMoveRemoteEvent = Remotes.SpecialMove
local AskQuestionRemoteEvent = Remotes.AskQuestion
local NewEmojiRemoteEvent = Remotes.NewEmoji

local localPlayer

local storedCameraOffset = nil
local storedCameraFOV = nil
local targetForOrbTween = {} -- orb to target position and poi of tween

local Gui = {}
Gui.__index = Gui

local function getInstancePosition(x)
	if x:IsA("BasePart") then return x.Position end
	if x:IsA("Model") and x.PrimaryPart ~= nil then
		return x.PrimaryPart.Position
	end

	return nil
end

function Gui.Init()
    localPlayer = Players.LocalPlayer
    Gui.Listening = false
    Gui.Speaking = false

    Gui.Orb = nil
    Gui.RunningConnection = nil
    Gui.VROrbcamConnection = nil
    Gui.ViewportOn = false
    Gui.HasSpeakerPermission = true
    Gui.Orbcam = false
    Gui.CameraTween = nil
    Gui.Head = nil
    Gui.Ear = nil
    Gui.EarConnection = nil
    Gui.CharacterChildAddedConnection = nil
    Gui.ListenIcon = nil
    Gui.OrbcamIcon = nil
    Gui.SpeakerIcon = nil
    Gui.LuggageIcon = nil
    Gui.OrbReturnIcon = nil
    Gui.BoardcamIcon = nil
    Gui.EmojiIcon = nil
    Gui.OrbcamGuiOff = false
    Gui.PoiHighlightConnection = nil
    Gui.Boardcam = false
    Gui.BoardcamHighlightConnection = nil

    Gui.InitEar()

    -- 
    -- Listening
    --

    local function toggleListen()
        if Gui.Listening then
            Gui.ListenOff()
        else
            Gui.ListenOn()
        end
    end

    -- 
    -- Attach and detach
    --

    OrbAttachSpeakerRemoteEvent.OnClientEvent:Connect(function(speaker,orb)
        wait(0.5) -- wait to make sure we have replicated values
        Gui.RefreshAllPrompts()
    end)
    OrbDetachSpeakerRemoteEvent.OnClientEvent:Connect(function(orb)
        wait(0.5) -- wait to make sure we have replicated values
        Gui.RefreshAllPrompts()
    end)

    Gui.SetupEmojiGui()
    NewEmojiRemoteEvent.OnClientEvent:Connect(Gui.HandleNewEmoji)

    -- If the Admin system is installed, the permission specified there
	-- overwrites the default "true" state of HasWritePermission
	local adminEvents = ReplicatedStorage:FindFirstChild("MetaAdmin")
	if adminEvents then
		local isScribeRF = adminEvents:WaitForChild("IsScribe")

		if isScribeRF then
			Gui.HasSpeakerPermission = isScribeRF:InvokeServer()
		end

		-- Listen for updates to the permissions
		local permissionUpdateRE = adminEvents:WaitForChild("PermissionsUpdate")
		permissionUpdateRE.OnClientEvent:Connect(function()
			-- Request the new permission
			if isScribeRF then
				Gui.HasSpeakerPermission = isScribeRF:InvokeServer()
			end

            -- Update the visibility of speaker prompts
            Gui.RefreshAllPrompts()
		end)
	end

    -- Give speaker permissions in Studio
    if RunService:IsStudio() then
        Gui.HasSpeakerPermission = true
    end

    for _, orb in CollectionService:GetTagged(Config.ObjectTag) do
        Gui.SetupProximityPrompts(orb)
    end

    CollectionService:GetInstanceAddedSignal(Config.ObjectTag):Connect(function(orb)
		Gui.SetupProximityPrompts(orb)
	end)

    CollectionService:GetInstanceRemovedSignal(Config.ObjectTag):Connect(function(orb)
		Gui.DestroyProximityPrompts(orb)
	end)

    -- Setup Orbcam
    local ORBCAM_MACRO_KB = {Enum.KeyCode.LeftShift, Enum.KeyCode.C}
    local function CheckMacro(macro)
        for i = 1, #macro - 1 do
            if not UserInputService:IsKeyDown(macro[i]) then
                return
            end
        end

        -- Do not allow Shift-C to turn _off_ orbcam that was turned on
        -- via the topbar button
        if Gui.Orbcam and not Gui.OrbcamGuiOff then return end

        -- Do not allow the shortcut when not attached
        if Gui.Orb == nil then return end

        if Gui.OrbcamIcon:getToggleState() == "selected" then
            Gui.OrbcamIcon:deselect()
            Gui.OrbcamGuiOff = false
        else
            Gui.OrbcamGuiOff = true
            Gui.OrbcamIcon:select()
        end
    end

    local function HandleActivationInput(action, state, input)
        if state == Enum.UserInputState.Begin then
            if input.KeyCode == ORBCAM_MACRO_KB[#ORBCAM_MACRO_KB] then
                CheckMacro(ORBCAM_MACRO_KB)
            end
        end
        return Enum.ContextActionResult.Pass
    end

    ContextActionService:BindAction("OrbcamToggle", HandleActivationInput, false, ORBCAM_MACRO_KB[#ORBCAM_MACRO_KB])

    local ORBCAMVIEW_MACRO_KB = {Enum.KeyCode.LeftShift, Enum.KeyCode.L}

    local function OrbcamViewActivate(action, state, input)
        if state ~= Enum.UserInputState.Begin then return end
        if input.KeyCode ~= ORBCAMVIEW_MACRO_KB[#ORBCAMVIEW_MACRO_KB] then return end

        -- Check to see the correct key combination is being pressed
        for i = 1, #ORBCAMVIEW_MACRO_KB - 1 do
            if not UserInputService:IsKeyDown(ORBCAMVIEW_MACRO_KB[i]) then
                return
            end
        end
        
        if Gui.Orb == nil then return end
        if not Gui.Orbcam then return end

        local orbPos = getInstancePosition(Gui.Orb)
        local poi = Gui.PointOfInterest(orbPos)
        
        local targets = {}
        for _, c in ipairs(poi:GetChildren()) do
            if c:IsA("ObjectValue") and c.Name == "Target" then
                if c.Value ~= nil then
                    table.insert(targets, c.Value)
                end
            end
        end

        if #targets < 2 then return end

        local camera = workspace.CurrentCamera
        local cameraPos = camera.CFrame.Position
        local focusPos = getInstancePosition(targets[1])

        local newCameraPos = (targets[1].CFrame * CFrame.new(0,0,-20)).Position

        local verticalFOV = Gui.FOVForTargets(newCameraPos, focusPos, {targets[1]}) * 1.1
        
        local tweenInfo = TweenInfo.new(
			2, -- Time
			Enum.EasingStyle.Quad, -- EasingStyle
			Enum.EasingDirection.Out, -- EasingDirection
			0, -- RepeatCount (when less than zero the tween will loop indefinitely)
			false, -- Reverses (tween will reverse once reaching it's goal)
			0 -- DelayTime
		)

        local poiPos = getInstancePosition(targets[1])
        
        if verticalFOV == nil then
            Gui.CameraTween = TweenService:Create(camera, tweenInfo, 
                {CFrame = CFrame.lookAt(newCameraPos, poiPos)})
        else
            Gui.CameraTween = TweenService:Create(camera, tweenInfo, 
                {CFrame = CFrame.lookAt(newCameraPos, poiPos),
                FieldOfView = verticalFOV})
        end

        Gui.CameraTween:Play()

        return Enum.ContextActionResult.Pass
    end

    ContextActionService:BindAction("OrbcamViewToggle", OrbcamViewActivate, false, ORBCAMVIEW_MACRO_KB[#ORBCAMVIEW_MACRO_KB])

    OrbTweeningStartRemoteEvent.OnClientEvent:Connect(Gui.OrbTweeningStart)
    OrbTweeningStopRemoteEvent.OnClientEvent:Connect(Gui.OrbTweeningStop)

    SpecialMoveRemoteEvent.OnClientEvent:Connect(Gui.SpecialMove)

    if VRService.VREnabled then
        -- In VR we need to tell other clients when we equip the chalk
        local chalkTool = localPlayer.Backpack:WaitForChild("MetaChalk", 20)
        if chalkTool ~= nil then
            chalkTool.Equipped:Connect(function()
                if Gui.Orb == nil then return end
                if Gui.Speaking == false then return end
                VRSpeakerChalkEquipRemoteEvent:FireServer(Gui.Orb)
            end)
            chalkTool.Unequipped:Connect(function()
                if Gui.Orb == nil then return end
                if Gui.Speaking == false then return end
                VRSpeakerChalkUnequipRemoteEvent:FireServer(Gui.Orb)
            end)
        else
            print("[MetaOrb] Failed to find MetaChalk tool")
        end

        -- Jump to exit orbcam
        UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Gamepad1 then return end
    
            if Gui.Orbcam and input.KeyCode == Enum.KeyCode.ButtonA then
                Gui.OrbcamOff()
            end
        end)
    end
	
    Gui.HandleVR()
    Gui.CreateTopbarItems()
    Gui.HandleAskQuestionGui()

	print("[Orb] Gui Initialised")
end

function Gui.OnResetCharacter()
    Gui.RefreshTopbarItems()
    Gui.InitEar()
end

function Gui.SetupEmojiGui()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EmojiGui"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = localPlayer.PlayerGui
end

function Gui.AddEmojiToScreen(emojiName:string)
    local emojiText = EmojiList[emojiName]
    if emojiText == nil then
        print("[Gui] Bad emoji name")
        return
    end

    local xOffset = math.random(-10,10)
    local yOffset = math.random(-5,5)
    local originalPos = UDim2.new(0, 50 + xOffset, 0.7, yOffset)
    local finalPos = UDim2.new(0, 50 + 1.5 * xOffset, 0.2, 0)

    local textLabel = Instance.new("TextLabel")
    textLabel.Text = emojiText
    textLabel.BackgroundTransparency = 1
    textLabel.TextScaled = true
    textLabel.Size = UDim2.new(0,50,0,50)
    textLabel.Position = originalPos
    textLabel.Parent = localPlayer.PlayerGui.EmojiGui

    local tweenInfo = TweenInfo.new(
        1.4, -- Time
        Enum.EasingStyle.Linear, -- EasingStyle
        Enum.EasingDirection.Out, -- EasingDirection
        0, -- RepeatCount (when less than zero the tween will loop indefinitely)
        false, -- Reverses (tween will reverse once reaching it's goal)
        0 -- DelayTime
    )

    local tween = TweenService:Create(textLabel, tweenInfo, 
                {Position = finalPos,
                TextTransparency = 1})
    
    tween:Play()

    tween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			textLabel:Destroy()
		end
	end)
end

function Gui.HandleNewEmoji(sourcePlayer:instance, orb:instance, emojiName:string)
    if orb ~= Gui.Orb then return end
    if sourcePlayer == localPlayer then return end -- already handled
    Gui.AddEmojiToScreen(emojiName)
end

function Gui.HandleAskQuestionGui()
    local screenGui = localPlayer.PlayerGui:WaitForChild("AskQuestionGui")
    local textBox = screenGui.ButtonFrame.TextBox
    local ACTION = "SubmitMessage"
    
    local function sendAction()
        if Gui.Orb == nil then
            print("[Orb] Triggered Ask Question event without being attached to an orb")
            return
        end
        
        screenGui.Enabled = false
        AskQuestionRemoteEvent:FireServer(Gui.Orb, textBox.Text)
        textBox.Text = ""
    end
    
    local sendButton = screenGui.ButtonFrame.SendButton
    sendButton.Activated:Connect(sendAction)
    
    local function cancelAction()
        screenGui.Enabled = false
        textBox.Text = ""
    end
    
    local cancelButton = screenGui.ButtonFrame.CancelButton
    cancelButton.Activated:Connect(cancelAction)
    
    local function handleAction(actionName, inputState, inputObject)
        if actionName == ACTION and inputState == Enum.UserInputState.End then
            sendAction()
        end
    end
end

function Gui.DestroyProximityPrompts(orb)
    -- Does nothing
end

function Gui.SetupProximityPrompts(orb)
    local promptActivationDistance = 24
    if VRService.VREnabled then
        promptActivationDistance = 24
    end

    local function getInstancePart(x)
        if x:IsA("BasePart") then return x end
        if x:IsA("Model") then return x.PrimaryPart end
        return nil
    end

    local function isNormalOrb(orb)
        return not CollectionService:HasTag(orb, Config.TransportTag)
    end

    local function isTransportOrb(orb)
        return CollectionService:HasTag(orb, Config.TransportTag)
    end

    local orbPart = getInstancePart(orb)
    
    local promptNames = {"LuggagePrompt", "NormalPrompt", "SpeakerPrompt",
        "SpecialMovePrompt", "VROrbcamPrompt", "VRDetachPrompt", "AskPrompt" }
    local promptText = {
        ["LuggagePrompt"] = "Attach as Luggage",
        ["NormalPrompt"] = "Attach as Listener",
        ["SpeakerPrompt"] = "Attach as Speaker",
        ["SpecialMovePrompt"] = "Special Move",
        ["VROrbcamPrompt"] = "Enable Orbcam",
        ["VRDetachPrompt"] = "Detach",
        ["AskPrompt"] = "Ask the AI"
    }

    for _, promptName in promptNames do
        local prompt = orbPart:FindFirstChild(promptName)
        if prompt ~= nil then
            prompt:Destroy()
        end

        if promptName == "LuggagePrompt" and not isTransportOrb(orb) then continue end
        if promptName ~= "LuggagePrompt" and isTransportOrb(orb) then continue end
        if promptName == "VROrbcamPrompt" and not VRService.VREnabled then continue end
        if promptName == "VRDetachPrompt" and not VRService.VREnabled then continue end

        prompt = Instance.new("ProximityPrompt")
        prompt.Name = promptName
        prompt.ActionText = promptText[promptName]
        prompt.MaxActivationDistance = promptActivationDistance
        prompt.HoldDuration = 1
        prompt.ObjectText = "Orb"
        prompt.RequiresLineOfSight = false

        if promptName == "SpeakerPrompt" then
            prompt.UIOffset = Vector2.new(0,75)
            prompt.KeyboardKeyCode = Enum.KeyCode.F
            prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
            prompt.Enabled = Gui.HasSpeakerPermission
        end

        if promptName == "AskPrompt" then
            --prompt.UIOffset = Vector2.new(0,-75)
            prompt.KeyboardKeyCode = Enum.KeyCode.G
            prompt.GamepadKeyCode = Enum.KeyCode.ButtonA
            prompt.Enabled = false
        end

        if promptName == "SpecialMovePrompt" then
            prompt.UIOffset = Vector2.new(0,3 * 75)
            prompt.KeyboardKeyCode = Enum.KeyCode.H
            prompt.GamepadKeyCode = Enum.KeyCode.ButtonL2
            prompt.Enabled = false    
        end

        if promptName == "VRDetachPrompt" then
            prompt.UIOffset = Vector2.new(0,75)
            prompt.KeyboardKeyCode = Enum.KeyCode.F
            prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
        end

        prompt.Parent = orbPart

        if VRService.VREnabled and promptName == "LuggagePrompt" then
            prompt.Enabled = false
        end

        ProximityPromptService.PromptTriggered:Connect(function(promptTriggered, player)
            if promptTriggered ~= prompt then return end

            if promptName == "LuggagePrompt" or promptName == "NormalPrompt" then
                OrbAttachRemoteEvent:FireServer(orb)
                Gui.Attach(orb)
            end

            if promptName == "SpeakerPrompt" then
                if orb.Speaker.Value == nil then
                    OrbAttachSpeakerRemoteEvent:FireServer(orb)
                    Gui.AttachSpeaker(orb)
                end
            end

            if promptName == "AskPrompt" then
                local askGui = localPlayer.PlayerGui:WaitForChild("AskQuestionGui")
                if askGui ~= nil then
                    askGui.Enabled = true
                    prompt.Enabled = false
                    askGui.ButtonFrame.SendButton.Activated:Connect(function()
                        prompt.Enabled = true
                    end)
                    askGui.ButtonFrame.CancelButton.Activated:Connect(function()
                        prompt.Enabled = true
                    end)
                    
                    if UserInputService.KeyboardEnabled then
                        local keyHeld = UserInputService:IsKeyDown(prompt.KeyboardKeyCode)
                        if keyHeld then
                            UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
                                if gameProcessedEvent then return end
                                
                                if input.KeyCode == prompt.KeyboardKeyCode then
                                    RunService.RenderStepped:Wait()
                                    askGui.ButtonFrame.TextBox:CaptureFocus()
                                end
                            end)
                        end
                    else
                        askGui.ButtonFrame.TextBox:CaptureFocus()
                    end
                end
            end

            if promptName == "SpecialMovePrompt" then
                local waypoint = Gui.NearestWaypoint(orb:GetPivot().Position)
                if waypoint == nil then return end
                if waypoint:FindFirstChild("SpecialMove") == nil then return end
                if orb:GetAttribute("tweening") then return end
                if Gui.Orb ~= orb then return end
                if not Gui.Speaking then return end

                SpecialMoveRemoteEvent:FireServer(Gui.Orb)
            end

            if promptName == "VROrbcamPrompt" then
                Gui.OrbcamOn()
            end

            if promptName == "VRDetachPrompt" then
                Gui.Detach(orb)
            end
        end)
    end
end

function Gui.SpecialMove(orb, specialMove, tweenTime)
    if not Gui.Orbcam then return end
    if Gui.Orb ~= orb then return end

    if specialMove == nil then
        print("[Orb] OrbcamTweeningStart passed a nil position")
        return
    end

    local camera = workspace.CurrentCamera

    -- Change camera instantly for VR players
    if VRService.VREnabled then
        if Gui.VROrbcamConnection ~= nil then
            Gui.VROrbcamConnection:Disconnect()
        end

        Gui.VROrbcamConnection = RunService.RenderStepped:Connect(function(dt)
			workspace.CurrentCamera.CFrame = specialMove.CFrame
		end)
        
        return
    end

	local tweenInfo = TweenInfo.new(
			tweenTime, -- Time
			Enum.EasingStyle.Quad, -- EasingStyle
			Enum.EasingDirection.Out, -- EasingDirection
			0, -- RepeatCount (when less than zero the tween will loop indefinitely)
			false, -- Reverses (tween will reverse once reaching it's goal)
			0 -- DelayTime
		)

    Gui.CameraTween = TweenService:Create(camera, tweenInfo, 
        {CFrame = specialMove.CFrame})

    Gui.CameraTween:Play()
end

function Gui.MakePlayerTransparent(plr, transparency)
    if plr == nil then
        print("[MetaOrb] Passed nil player to MakePlayerTransparent")
        return
    end

    local character = plr.Character

    if character == nil then return end

    for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = 1 - (transparency * (1 - desc.Transparency))
			desc.CastShadow = false
		end
	end

    -- origTransparency = 1 - 1/0.2 * (1 - newTransparency)
end

function Gui.HandleVR()
    VRSpeakerChalkEquipRemoteEvent.OnClientEvent:Connect(function(speaker)
		if Gui.Orb == nil then return end
        if Gui.Orb.Speaker.Value == nil then return end
        if Gui.Orb.Speaker.Value ~= speaker then return end

        if speaker == localPlayer then return end
        Gui.MakePlayerTransparent(speaker, 0.2)
	end)

    VRSpeakerChalkUnequipRemoteEvent.OnClientEvent:Connect(function(speaker)
		if Gui.Orb == nil then return end
        if Gui.Orb.Speaker.Value == nil then return end
        if Gui.Orb.Speaker.Value ~= speaker then return end

        if speaker == localPlayer then return end
        Gui.MakePlayerTransparent(speaker, 1/0.2)
	end)
end

-- We create a part inside the player's head, whose CFrame
-- is tracked by SetListener
function Gui.InitEar()
    if not Config.ListenFromPlayer then
        SoundService:SetListener(Enum.ListenerType.Camera)
        return
    end

    local character = localPlayer.Character
    local head = character:WaitForChild("Head")

    local camera = workspace.CurrentCamera
	if not camera then return end

    local lookDirection = camera.CFrame.LookVector

    local ear = character:FindFirstChild(Config.EarName)
    if ear then
        ear:Destroy()
    end

    ear = Instance.new("Part")
    ear.Name = Config.EarName
    ear.Size = Vector3.new(0.1,0.1,0.1)
    ear.CanCollide = false
    ear.CastShadow = false
    ear.CFrame = CFrame.lookAt(head.Position, head.Position + lookDirection)
    ear.Transparency = 1
    ear.Parent = character

    Gui.Ear = ear
    Gui.Head = head
    SoundService:SetListener(Enum.ListenerType.ObjectCFrame, ear)

    -- When the avatar editor is used, a new head may be parented to the character
    -- NOTE: that the old head may _not_ be destroyed, so you can't just check for nil
    Gui.CharacterChildAddedConnection = localPlayer.Character.ChildAdded:Connect(function(child)
        if child.Name ~= "Head" then return end
        Gui.Head = child
    end)

    Gui.EarConnection = RunService.RenderStepped:Connect(function(delta)
        local nowCamera = workspace.CurrentCamera
	    if not nowCamera then return end
        
        -- The head may be destroyed
        if Gui.Head == nil then
            Gui.Head = localPlayer.Character:FindFirstChild("Head")
            if Gui.Head == nil then return end
        end

        ear.CFrame = CFrame.lookAt(Gui.Head.Position, 
            Gui.Head.Position + nowCamera.CFrame.LookVector)
    end)
end

function Gui.RemoveEar()
    if Gui.EarConnection then
        Gui.EarConnection:Disconnect()
        Gui.EarConnection = nil
    end

    if Gui.CharacterChildAddedConnection then
        Gui.CharacterChildAddedConnection:Disconnect()
        Gui.CharacterChildAddedConnection = nil
    end

    if Gui.Ear then
        Gui.Ear:Destroy()
    end
end

function Gui.RefreshAllPrompts()
    local orbs = CollectionService:GetTagged(Config.ObjectTag)
    for _, orb in ipairs(orbs) do
        Gui.RefreshPrompts(orb)
    end
end

function Gui.NearestWaypoint(pos)
	local waypoints = CollectionService:GetTagged(Config.WaypointTag)
	if #waypoints == 0 then return nil end

	local minDistance = math.huge
	local minWaypoint = nil

	for _, waypoint in ipairs(waypoints) do
		if not waypoint:IsDescendantOf(game.Workspace) then continue end

		local distance = (waypoint.Position - pos).Magnitude
		if distance < minDistance then
			minDistance = distance
			minWaypoint = waypoint
		end
	end

	return minWaypoint
end

function Gui.RefreshPrompts(orb)
    if orb == nil then
        print("[MetaOrb] Passed nil orb to RefreshPrompts")
        return
    end

    local prompts = {}

    local speakerPrompt = if orb:IsA("BasePart") then orb:FindFirstChild("SpeakerPrompt") else orb.PrimaryPart:FindFirstChild("SpeakerPrompt")
    local normalPrompt = if orb:IsA("BasePart") then orb:FindFirstChild("NormalPrompt") else orb.PrimaryPart:FindFirstChild("NormalPrompt")
    local askPrompt = if orb:IsA("BasePart") then orb:FindFirstChild("AskPrompt") else orb.PrimaryPart:FindFirstChild("AskPrompt")
    local specialMovePrompt = if orb:IsA("BasePart") then orb:FindFirstChild("SpecialMovePrompt") else orb.PrimaryPart:FindFirstChild("SpecialMovePrompt")
    if speakerPrompt ~= nil then table.insert(prompts, speakerPrompt) end
    if normalPrompt ~= nil then table.insert(prompts, normalPrompt) end
    if askPrompt ~= nil then table.insert(prompts, askPrompt) end
    if specialMovePrompt ~= nil then table.insert(prompts, specialMovePrompt) end

    local vrOrbcamPrompt, vrDetachPrompt
    if VRService.VREnabled then
        vrOrbcamPrompt = if orb:IsA("BasePart") then orb:FindFirstChild("VROrbcamPrompt") else orb.PrimaryPart:FindFirstChild("VROrbcamPrompt")
        vrDetachPrompt = if orb:IsA("BasePart") then orb:FindFirstChild("VRDetachPrompt") else orb.PrimaryPart:FindFirstChild("VRDetachPrompt")
        if vrOrbcamPrompt ~= nil then table.insert(prompts, vrOrbcamPrompt) end
        if vrDetachPrompt ~= nil then table.insert(prompts, vrDetachPrompt) end
    end

    local luggagePrompt
    if CollectionService:HasTag(orb, Config.TransportTag) then
        luggagePrompt = if orb:IsA("BasePart") then orb.LuggagePrompt else orb.PrimaryPart.LuggagePrompt
        table.insert(prompts, luggagePrompt)
    end
    
    -- When an orb is moving, no prompts are active
    if orb:GetAttribute("tweening") then
        for _, p in ipairs(prompts) do
            p.Enabled = false
        end
        
        return
    end

    if Gui.Orb ~= orb then
        if normalPrompt ~= nil then normalPrompt.Enabled = true end
        if askPrompt ~= nil then askPrompt.Enabled = false end
        if speakerPrompt ~= nil then
            speakerPrompt.Enabled = Gui.HasSpeakerPermission and orb.Speaker.Value == nil
        end
        if specialMovePrompt ~= nil then specialMovePrompt.Enabled = false end

        if VRService.VREnabled then
            if vrOrbcamPrompt ~= nil then vrOrbcamPrompt.Enabled = false end
            if vrDetachPrompt ~= nil then vrDetachPrompt.Enabled = false end
        end

        if luggagePrompt ~= nil then luggagePrompt.Enabled = true end
    else
        if normalPrompt ~= nil then normalPrompt.Enabled = false end
        if askPrompt ~= nil then askPrompt.Enabled = true end
        if speakerPrompt ~= nil then speakerPrompt.Enabled = false end
        if specialMovePrompt ~= nil then
            local waypoint = Gui.NearestWaypoint(orb:GetPivot().Position)
            specialMovePrompt.Enabled = Gui.Speaking and (waypoint ~= nil) and (waypoint:FindFirstChild("SpecialMove") ~= nil)
        end

        if VRService.VREnabled then
            if vrOrbcamPrompt ~= nil then vrOrbcamPrompt.Enabled = true end
            if vrDetachPrompt ~= nil then vrDetachPrompt.Enabled = true end
        end

        if luggagePrompt ~= nil then luggagePrompt.Enabled = false end
    end
end

-- A point of interest is any object tagged with either
-- metaboard or metaorb_poi. Returns the closest point
-- of interest to the current orb and its position and nil if none can
-- be found. Note that a point of interest is either nil,
-- a BasePart or a Model with non-nil PrimaryPart
function Gui.PointOfInterest(orbPos)
    local boards = CollectionService:GetTagged("metaboard")
    local pois = CollectionService:GetTagged(Config.PointOfInterestTag)

    if #boards == 0 and #pois == 0 then return nil end

    -- Find the closest board
    local closestPoi = nil
    local closestPos = nil
    local minDistance = math.huge

    local families = {boards, pois}

    for _, family in ipairs(families) do
        for _, p in ipairs(family) do
			if CollectionService:HasTag(p, "metaboard_personal") then continue end

            local pos = p:GetPivot().Position

            if pos ~= nil then
                local distance = (pos - orbPos).Magnitude
                if distance < minDistance then
                    minDistance = distance
                    closestPos = pos
                    closestPoi = p
                end
            end
        end
    end

    return closestPoi
end

function Gui.ListenOn()
    Gui.Listening = true

    if Gui.Orb then
        -- Enum.ListenerType.ObjectPosition (if player rotates camera, it changes angle of sound sources)
        -- Enum.LIstenerType.ObjectCFrame (sound from the position and angle of object)
        -- Note that the orb's EarRingTracker points at the current speaker (if there is one)
        -- and at the current point of interest otherwise
        SoundService:SetListener(Enum.ListenerType.ObjectCFrame, Gui.Orb.EarRingTracker)
    end

    OrbListenOnRemoteEvent:FireServer()
end

function Gui.ListenOff()
    Gui.Listening = false

    if Config.ListenFromPlayer and Gui.Ear ~= nil then
        SoundService:SetListener(Enum.ListenerType.ObjectCFrame, Gui.Ear)
    else
        SoundService:SetListener(Enum.ListenerType.Camera)
    end

    OrbListenOffRemoteEvent:FireServer()
end

-- Detach, as listener or speaker
function Gui.Detach()
    if Gui.Orb == nil then return end
    local orb = Gui.Orb

    if CollectionService:HasTag(orb, Config.TransportTag) then
        local luggagePrompt = if orb:IsA("BasePart") then orb.LuggagePrompt else orb.PrimaryPart.LuggagePrompt
        luggagePrompt.Enabled = true
        Gui.OrbcamOff()
    else
        Gui.ListenOff()
        Gui.OrbcamOff()
        Gui.Speaking = false
        
        if Gui.RunningConnection then
            Gui.RunningConnection:Disconnect()
            Gui.RunningConnection = nil
        end

        -- Make the VR speaker visible again
        local speaker = orb.Speaker.Value
        if speaker ~= nil and orb.VRSpeakerChalkEquipped.Value then
            Gui.MakePlayerTransparent(speaker, 1/0.2)
        end

        Gui.DisablePoiHighlights(orb)
    end

    localPlayer.PlayerGui.EmojiGui:ClearAllChildren() -- remove emojis
    OrbDetachRemoteEvent:FireServer(orb)
    Gui.Orb = nil
    Gui.RefreshAllPrompts()
    Gui.RefreshTopbarItems()
end

function Gui.AttachSpeaker(orb)
    if Gui.Orb ~= nil then Gui.Detach() end
    Gui.Orb = orb
    Gui.Speaking = true

    Gui.RefreshAllPrompts()
    Gui.RefreshTopbarItems()

    local function fireSpeakerMovedEvent()
        local character = localPlayer.Character
        if character == nil then return end    
        local waypoint = Gui.NearestWaypoint(character.PrimaryPart.Position)
        if waypoint ~= nil then
            OrbSpeakerMovedRemoteEvent:FireServer(Gui.Orb, waypoint.Position)
        else
            print("[MetaOrb] Could not find nearby waypoint")
        end
    end

    local humanoid = localPlayer.Character:WaitForChild("Humanoid")
    if VRService.VREnabled then
        local counter = 0
        local timeTillPositionCheck = 2
        local playerPosAtLastCheck = localPlayer.Character.PrimaryPart.Position

        Gui.RunningConnection = RunService.Heartbeat:Connect(function(step)
            counter = counter + step
            if counter >= timeTillPositionCheck then
                counter -= timeTillPositionCheck
                
                if localPlayer.Character ~= nil and localPlayer.Character.PrimaryPart ~= nil then
                    if (localPlayer.Character.PrimaryPart.Position - playerPosAtLastCheck).Magnitude > 2 then
                        fireSpeakerMovedEvent() 
                    end
                    playerPosAtLastCheck = localPlayer.Character.PrimaryPart.Position
                end
            end
        end)
    else
        Gui.RunningConnection = humanoid.Running:Connect(function(speed)
            if speed > 0 then
                Gui.EnablePoiHighlights(Gui.Orb)
            end

            if speed == 0 then
                -- They were moving and then stood still
                Gui.DisablePoiHighlights(Gui.Orb)
                fireSpeakerMovedEvent()
            end
        end)
    end
end

function Gui.RefreshTopbarItems()
    Gui.OrbcamIcon:setEnabled(false)
    Gui.ListenIcon:setEnabled(false)
    Gui.SpeakerIcon:setEnabled(false)
    Gui.OrbReturnIcon:setEnabled(false)
    Gui.LuggageIcon:setEnabled(false)
    Gui.EmojiIcon:setEnabled(false)

    local orb = Gui.Orb
    if orb == nil then return end

    if CollectionService:HasTag(orb, Config.TransportTag) then
        Gui.LuggageIcon:setEnabled(true)
        Gui.LuggageIcon:select()
        Gui.OrbcamIcon:setEnabled(true)
        return
    end

    if Gui.Speaking then
        Gui.SpeakerIcon:setEnabled(true)
        Gui.SpeakerIcon:select()
        Gui.OrbcamIcon:setEnabled(true)
        Gui.OrbReturnIcon:setEnabled(true)
        Gui.EmojiIcon:setEnabled(true)
    else
        if not VRService.VREnabled then
            Gui.ListenIcon:setEnabled(true)
            Gui.ListenIcon:select()
            Gui.OrbcamIcon:setEnabled(true)
            Gui.OrbReturnIcon:setEnabled(true)
            Gui.EmojiIcon:setEnabled(true)
        end
    end
end

function Gui.CreateTopbarItems()
    if ReplicatedStorage:FindFirstChild("Icon") == nil then
        print("[Orb] Could not find Icon module")
        return
    end
    
    -- ear icon is https://fonts.google.com/icons?icon.query=hearing
    -- eye icon is https://fonts.google.com/icons?icon.query=eye
    -- luggage is https://fonts.google.com/icons?icon.query=luggage
    -- return is https://fonts.google.com/icons?icon.query=back
    local earIconAssetId = "rbxassetid://11877012409"
    local eyeIconAssetId = "rbxassetid://11877012219"
    local returnIconAssetId = "rbxassetid://11877012097"
    local speakerIconAssetId = "rbxassetid://11877027636"

    local Icon = require(game:GetService("ReplicatedStorage").Icon)
    local Themes =  require(game:GetService("ReplicatedStorage").Icon.Themes)
    
    local icon, iconEye, iconSpeaker, iconLuggage, iconReturn, iconBoardcam, iconEmoji

    icon = Icon.new()
    icon:setImage(earIconAssetId)
    icon:setLabel("Listener")
    icon:setOrder(2)
    icon:setEnabled(false)
    icon.deselectWhenOtherIconSelected = false
    icon:bindEvent("deselected", function(self)
        if iconEye.isSelected then
            iconEye:deselect()
        end
        
        Gui.Detach()
        Gui.RefreshTopbarItems()
    end)
    icon:setTheme(Themes["BlueGradient"])
    Gui.ListenIcon = icon

    iconSpeaker = Icon.new()
    iconSpeaker:setImage(speakerIconAssetId)
    iconSpeaker:setOrder(2)
    iconSpeaker:setLabel("Speaker")
    iconSpeaker:setTheme(Themes["BlueGradient"])
    iconSpeaker:setEnabled(false)
    iconSpeaker.deselectWhenOtherIconSelected = false
    iconSpeaker:bindEvent("deselected", function(self)
        if iconEye.isSelected then
            iconEye:deselect()
        end
        
        Gui.Detach()
        Gui.RefreshTopbarItems()
    end)
    Gui.SpeakerIcon = iconSpeaker

    iconLuggage = Icon.new()
    iconLuggage:setImage("rbxassetid://9679458066")
    iconLuggage:setOrder(2)
    iconLuggage:setLabel("Luggage")
    iconLuggage:setTheme(Themes["BlueGradient"])
    iconLuggage:setEnabled(false)
    iconLuggage.deselectWhenOtherIconSelected = false
    iconLuggage:bindEvent("deselected", function(self)
        if iconEye.isSelected then
            iconEye:deselect()
        end
        
        Gui.Detach()
        Gui.RefreshTopbarItems()
    end)
    Gui.LuggageIcon = iconLuggage

    iconEye = Icon.new()
    iconEye:setImage(eyeIconAssetId)
    iconEye:setLabel("Orbcam")
    iconEye:setOrder(3)
    iconEye:setTheme(Themes["BlueGradient"])
    iconEye:setEnabled(false)
    iconEye.deselectWhenOtherIconSelected = false
    iconEye:bindEvent("selected", function(self)
        iconBoardcam:deselect()
        Gui.ToggleOrbcam(false)
    end)
    iconEye:bindEvent("deselected", function(self)
        Gui.ToggleOrbcam(false)
    end)
    Gui.OrbcamIcon = iconEye

    iconReturn = Icon.new()
    iconReturn:setImage(returnIconAssetId)
    iconReturn:setOrder(6)
    iconReturn:setTheme(Themes["BlueGradient"])
    iconReturn:setEnabled(false)
    iconReturn:bindEvent("selected", function(self)
        OrbTeleportRemoteEvent:FireServer(Gui.Orb)
        iconReturn:deselect()
    end)
    Gui.OrbReturnIcon = iconReturn

    availableEmojis = {":thumbsup:",":thumbsdown:",":smiley:",":grimacing:",":mind_blown:",
            ":pray:",":fire:",":ok_hand:",":100:",":repeat:"}

    iconEmoji = Icon.new()
    iconEmoji:setLabel("😃")
    iconEmoji:setOrder(5)
    iconEmoji:setEnabled(false)
    iconEmoji:set("dropdownSquareCorners", true)
	iconEmoji:set("dropdownMaxIconsBeforeScroll", 7)

    emojiIcons = {}
    for _, e in availableEmojis do
        table.insert(emojiIcons, Icon.new()
                                    :setLabel(EmojiList[e])
                                    :bindEvent("selected", function(self)
                                        self:deselect()
                                        iconEmoji:deselect()
                                        NewEmojiRemoteEvent:FireServer(Gui.Orb, e)
                                        Gui.AddEmojiToScreen(e)
                                    end))
    end

	iconEmoji:setDropdown(emojiIcons)
    Gui.EmojiIcon = iconEmoji

    iconBoardcam = Icon.new()
    iconBoardcam:setImage(eyeIconAssetId)
    iconBoardcam:setLabel("Look")
    iconBoardcam:setOrder(4)
    iconBoardcam:setTheme(Themes["BlueGradient"])
    iconBoardcam:setEnabled(true)
    iconBoardcam.deselectWhenOtherIconSelected = false
    iconBoardcam:bindEvent("selected", function(self)
        iconEye:deselect()
        Gui.ToggleBoardcam()
    end)
    iconBoardcam:bindEvent("deselected", function(self)
        Gui.ToggleBoardcam()
    end)
    iconBoardcam:bindEvent("hoverStarted", function(self)
        Gui.BoardcamHoverStarted()
    end)
    iconBoardcam:bindEvent("hoverEnded", function(self)
        Gui.BoardcamHoverEnded()
    end)
    Gui.BoardcamIcon = iconBoardcam
end

function Gui.Attach(orb)
    if orb == nil then
        print("[MetaOrb] Attempted to attach to nil orb")
        return
    end

    if Gui.Orb ~= nil then Gui.Detach() end
    Gui.Orb = orb

    Gui.RefreshAllPrompts()
    Gui.RefreshTopbarItems()

    if not CollectionService:HasTag(orb, Config.TransportTag) then
        Gui.ListenOn()

        -- Set up initial transparency for VR speakers
        local speaker = Gui.Orb.Speaker.Value
        if speaker ~= nil and orb.VRSpeakerChalkEquipped.Value then
            Gui.MakePlayerTransparent(speaker, 0.2)
        end
    end
end

-- 
-- Orbcam
--

local function resetCameraSubject()
	local camera = workspace.CurrentCamera
	if not camera then return end

    local character = localPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		workspace.CurrentCamera.CameraSubject = humanoid
	end

    if storedCameraOffset then
	    if character.Head then
		    camera.CFrame = CFrame.lookAt(character.Head.Position + storedCameraOffset, character.Head.Position)
	    end

        storedCameraOffset = nil
    else
        print("ERROR: storedCameraOffset not set.")
    end
end

function Gui.OrbTweeningStart(orb, pos, poi)
    -- Start camera moving if it is enabled, and the tweening
    -- orb is the one we are attached to
    if orb == Gui.Orb and Gui.Orbcam then
        Gui.OrbcamTweeningStart(pos, poi)
    end

    -- Store this so people attaching mid-flight can just jump to the target CFrame and FOV
    targetForOrbTween[orb] = { Position = pos, Poi = poi:Clone() }

    orb:SetAttribute("tweening", true)
    Gui.RefreshPrompts(orb)
end

function Gui.OrbTweeningStop(orb)
    targetForOrbTween[orb] = nil
    orb:SetAttribute("tweening", false)
    Gui.RefreshPrompts(orb)
end

function Gui.OrbcamTweeningStart(newPos, poi)
    if not Gui.Orbcam then return end
    if newPos == nil then
        print("[Orb] OrbcamTweeningStart passed a nil position")
        return
    end
    
    if poi == nil then
        print("[Orb] OrbcamTweeningStart passed a nil poi")
        return
    end

    local poiPos = poi:GetPivot().Position

    local camera = workspace.CurrentCamera

    -- By default the camera looks from (newPos.X, poiPos.Y, newPos.Z)
    -- but this can be overridden by specifying a Camera ObjectValue
    local orbCameraPos = Vector3.new(newPos.X, poiPos.Y, newPos.Z)

    local cameraOverride = poi:FindFirstChild("Camera")
    if cameraOverride ~= nil then
        local cameraPart = cameraOverride.Value
        if cameraPart ~= nil then
            orbCameraPos = cameraPart.Position
        end
    end

    -- Change camera instantly for VR players
    if VRService.VREnabled then
        if Gui.VROrbcamConnection ~= nil then
            Gui.VROrbcamConnection:Disconnect()
        end

        Gui.VROrbcamConnection = RunService.RenderStepped:Connect(function(dt)
			workspace.CurrentCamera.CFrame = CFrame.lookAt(orbCameraPos, poiPos)
		end)
        
        return
    end

	local tweenInfo = TweenInfo.new(
			Config.TweenTime, -- Time
			Enum.EasingStyle.Quad, -- EasingStyle
			Enum.EasingDirection.Out, -- EasingDirection
			0, -- RepeatCount (when less than zero the tween will loop indefinitely)
			false, -- Reverses (tween will reverse once reaching it's goal)
			0 -- DelayTime
		)

    local targets = {}
    for _, c in ipairs(poi:GetChildren()) do
        if c:IsA("ObjectValue") and c.Name == "Target" then
            if c.Value ~= nil then
                table.insert(targets, c.Value)
            end
        end
    end

    local verticalFOV = Gui.FOVForTargets(orbCameraPos, poi:GetPivot().Position, targets)

    if verticalFOV == nil then
        Gui.CameraTween = TweenService:Create(camera, tweenInfo, 
            {CFrame = CFrame.lookAt(orbCameraPos, poiPos)})
    else
        Gui.CameraTween = TweenService:Create(camera, tweenInfo, 
            {CFrame = CFrame.lookAt(orbCameraPos, poiPos),
            FieldOfView = verticalFOV})
    end

    Gui.CameraTween:Play()
end


-- Computes the vertical FOV for the player's camera at the given poi
function Gui.FOVForTargets(cameraPos, focusPos, targets)
    local camera = workspace.CurrentCamera

    if #targets == 0 then
        return camera.FieldOfView
    end

    local cameraCFrame = CFrame.lookAt(cameraPos, focusPos)
    local oldCameraCFrame = camera.CFrame
    local oldCameraFieldOfView = camera.FieldOfView
    camera.CFrame = cameraCFrame
    camera.FieldOfView = 70

    -- Find the most extreme points among all targets
    local extremeLeftCoord, extremeRightCoord, extremeTopCoord, extremeBottomCoord
    local extremeLeft, extremeRight, extremeTop, extremeBottom

    for _, t in ipairs(targets) do
        local extremities = {}
        local unitVectors = { X = Vector3.new(1,0,0),
                                Y = Vector3.new(0,1,0),
                                Z = Vector3.new(0,0,1)}

        for _, direction in ipairs({"X", "Y", "Z"}) do
            local extremeOne = t.CFrame * CFrame.new(0.5 * unitVectors[direction] * t.Size[direction])
            local extremeTwo = t.CFrame * CFrame.new(-0.5 * unitVectors[direction] * t.Size[direction])
            table.insert(extremities, extremeOne.Position)
            table.insert(extremities, extremeTwo.Position)
        end

        for _, pos in ipairs(extremities) do
            local screenPos = camera:WorldToScreenPoint(pos)
            if extremeLeftCoord == nil or screenPos.X < extremeLeftCoord then
                extremeLeftCoord = screenPos.X
                extremeLeft = pos
            end

            if extremeRightCoord == nil or screenPos.X > extremeRightCoord then
                extremeRightCoord = screenPos.X
                extremeRight = pos
            end

            if extremeTopCoord == nil or screenPos.Y < extremeTopCoord then
                extremeTopCoord = screenPos.Y
                extremeTop = pos
            end

            if extremeBottomCoord == nil or screenPos.Y > extremeBottomCoord then
                extremeBottomCoord = screenPos.Y
                extremeBottom = pos
            end
        end
    end

    if extremeTop == nil or extremeBottom == nil or extremeLeft == nil or extremeRight == nil then
        camera.CFrame = oldCameraCFrame
        camera.FieldOfView = oldCameraFieldOfView
        return
    end

    -- Compute the angles made with the current camera and the top and bottom
    local leftProj = camera.CFrame:ToObjectSpace(CFrame.new(extremeLeft)).Position
    local rightProj = camera.CFrame:ToObjectSpace(CFrame.new(extremeRight)).Position
    local topProj = camera.CFrame:ToObjectSpace(CFrame.new(extremeTop)).Position
    local bottomProj = camera.CFrame:ToObjectSpace(CFrame.new(extremeBottom)).Position
    local xMid = 0.5 * (leftProj.X + rightProj.X)
    local yMid = 0.5 * (topProj.Y + bottomProj.Y)
    
    local avgZ = 0.25 * ( leftProj.Z + rightProj.Z + topProj.Z + bottomProj.Z )
    topProj = Vector3.new(xMid, topProj.Y, avgZ)
    bottomProj = Vector3.new(xMid, bottomProj.Y, avgZ)
    leftProj = Vector3.new(leftProj.X, yMid, avgZ)
    rightProj = Vector3.new(rightProj.X, yMid, avgZ)
    
    --for _, apos in ipairs({leftProj, rightProj, topProj, bottomProj}) do
    --	if apos ~= nil then
    --		local pos = camera.CFrame:ToWorldSpace(CFrame.new(apos)).Position
    --		local p = Instance.new("Part")
    --		p.Name = "Bounder"
    --		p.Shape = Enum.PartType.Ball
    --		p.Color = Color3.new(0,0,1)
    --		p.Size = Vector3.new(0.5, 0.5, 0.5)
    --		p.Position = pos
    --		p.Anchored = true
    --		p.Parent = game.workspace
    --	end
    --end

    -- Compute the horizontal angle subtended by rectangle we have just defined
    local A = leftProj.Magnitude
    local B = rightProj.Magnitude
    local cosgamma = leftProj:Dot(rightProj) * 1/A * 1/B
    local horizontalAngle = nil

    if cosgamma < -1 or cosgamma > 1 then 
        camera.CFrame = oldCameraCFrame
        camera.FieldOfView = oldCameraFieldOfView
        return
    end
    
    horizontalAngle = math.acos(cosgamma)
    
    -- https://en.wikipedia.org/wiki/Field_of_view_in_video_games
    local aspectRatio = camera.ViewportSize.Y / camera.ViewportSize.X
    local verticalRadian = 2 * math.atan(math.tan(horizontalAngle / 2) * aspectRatio)
    local verticalFOV = math.deg(verticalRadian)
    verticalFOV = verticalFOV * Config.FOVFactor

    -- Return camera to its original configuration
    camera.CFrame = oldCameraCFrame
    camera.FieldOfView = oldCameraFieldOfView

    return verticalFOV
end

function Gui.BoardcamHoverEnded()
    if Gui.BoardcamHighlightConnection ~= nil then
        Gui.BoardcamHighlightConnection:Disconnect()
        Gui.BoardcamHighlightConnection = nil
    end

    local boardcamHighlightFolder = game.Workspace:FindFirstChild("BoardcamHighlights")
    if boardcamHighlightFolder ~= nil then
        boardcamHighlightFolder:ClearAllChildren()
    end
end

function Gui.BoardcamHoverStarted()
    -- Don't show highlights while Boardcam is on
    if Gui.Boardcam then return end

    if Gui.BoardcamHighlightConnection ~= nil then
        Gui.BoardcamHighlightConnection:Disconnect()
    end

    local lastPoi = nil

    local boardcamHighlightFolder = game.Workspace:FindFirstChild("BoardcamHighlights")
    if boardcamHighlightFolder == nil then
        boardcamHighlightFolder = Instance.new("Folder")
        boardcamHighlightFolder.Name = "BoardcamHighlights"
        boardcamHighlightFolder.Parent = game.Workspace
    end

    Gui.BoardcamHighlightConnection = RunService.RenderStepped:Connect(function(dt)
        local character = localPlayer.Character
        if character == nil then return end

        local function nearbyWaypoint(pos)
            local w = Gui.NearestWaypoint(pos)
            -- if (w.Position - pos).Magnitude > 10 then return nil end
            return w
        end
    
        local charPos = character.PrimaryPart.Position
        local waypoint = nearbyWaypoint(charPos)
        local waypointPos = waypoint.Position
        local poi = Gui.PointOfInterest(waypointPos)
        
        if poi == nil then return end

        if poi == lastPoi then
            -- Don't remake highlights for the same objects
            return
        else
            local boardcamHighlightFolder = game.Workspace:FindFirstChild("BoardcamHighlights")
            if boardcamHighlightFolder ~= nil then
                boardcamHighlightFolder:ClearAllChildren()
            end
            lastPoi = poi
        end

        local instancesToHighlight = {}
        
        for _, c in ipairs(poi:GetChildren()) do
            if c:IsA("ObjectValue") and c.Name == "Target" then
                if c.Value ~= nil then
                    table.insert(instancesToHighlight, c.Value)
                end
            end
        end

        if #instancesToHighlight == 0 then
            table.insert(instancesToHighlight, poi)
        end

        for _, x in instancesToHighlight do
            local xPart = if x:IsA("BasePart") then x else x.PrimaryPart
            local highlight = Instance.new("Highlight")
            highlight.Adornee = xPart
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Enabled = true
            highlight.FillTransparency = 0.9
            highlight.OutlineColor = Color3.fromRGB(231, 227, 170)
            highlight.Name = "Highlight"
            highlight.Parent = boardcamHighlightFolder
        end
    end)
end

function Gui.BoardcamOn()
    local character = localPlayer.Character
    if character == nil or character.PrimaryPart == nil then
        print("[Orb] Cannot activate boardcam with nil character")
        return
    end

    local camera = workspace.CurrentCamera
	storedCameraFOV = camera.FieldOfView
	if character.Head then
		storedCameraOffset = camera.CFrame.Position - character.Head.Position
	end

    -- We prefer the following views, in order of preference
    --
    -- 1. From a nearby waypoint (as though in Orbcam)
    -- 2. A nearby board
    --
    -- However (2) divides into two cases
    --
    -- 2a. There is a clearest nearby single board
    -- 2b. There are two roughly equidistant boards
    --
    -- In the former case we look at the board, in the latter we
    -- figure out a reasonable place to look from to view both
    -- boards

    local function nearbyWaypoint(pos)
        local w = Gui.NearestWaypoint(pos)
        -- if (w.Position - pos).Magnitude > 10 then return nil end
        return w
    end

    local charPos = character.PrimaryPart.Position
    local waypoint = nearbyWaypoint(charPos)
    local waypointPos = waypoint.Position

    if waypoint ~= nil then
        Gui.LastWaypointForBoardcam = waypoint
        local poi = Gui.PointOfInterest(waypointPos)
        if poi == nil then
            print("[Orb] Could not find point of interest to look at")
            return
        end
        local poiPos = getInstancePosition(poi)

        if camera.CameraType ~= Enum.CameraType.Scriptable then
            camera.CameraType = Enum.CameraType.Scriptable
        end

        local cameraPos = Vector3.new(waypointPos.X, poiPos.Y, waypointPos.Z)
        camera.CFrame = CFrame.lookAt(cameraPos, poiPos)

        local targets = {}
        for _, c in ipairs(poi:GetChildren()) do
            if c:IsA("ObjectValue") and c.Name == "Target" then
                if c.Value ~= nil then
                    table.insert(targets, c.Value)
                end
            end
        end

        local verticalFOV = Gui.FOVForTargets(cameraPos, getInstancePosition(poi), targets)
        camera.FieldOfView = verticalFOV
    else
        print("[Orb] Not near a waypoint")
    end
    
    Gui.Boardcam = true
end

function Gui.BoardcamOff()

    local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
    if storedCameraFOV ~= nil then
        camera.FieldOfView = storedCameraFOV
    else
        camera.FieldOfView = 70
    end

	resetCameraSubject()
    Gui.Boardcam = false
end

function Gui.OrbcamOn()
    local guiOff = Gui.OrbcamGuiOff
    OrbcamOnRemoteEvent:FireServer()

    if Gui.Orb == nil then return end
    local orb = Gui.Orb
    
	local camera = workspace.CurrentCamera
	storedCameraFOV = camera.FieldOfView
    
    local character = localPlayer.Character
	if character and character.Head then
		storedCameraOffset = camera.CFrame.Position - character.Head.Position
	end
    
    if CollectionService:HasTag(Gui.Orb, Config.TransportTag) then
        -- A transport orb looks from the next stop back to the orb as it approaches
        camera.CameraType = Enum.CameraType.Watch
        camera.CameraSubject = if orb:IsA("BasePart") then orb else orb.PrimaryPart

        local nextStop = orb.NextStop.Value
        local nextStopPart = orb.Stops:FindFirstChild(tostring(nextStop)).Value.Marker

        camera.CFrame = CFrame.new(nextStopPart.Position + Vector3.new(0,20,0))

        if guiOff then
            StarterGui:SetCore("TopbarEnabled", false)
        end
    
        Gui.Orbcam = true
        return
    else
        if VRService.VREnabled then
            local vrOrbcamPrompt = if orb:IsA("BasePart") then orb:FindFirstChild("VROrbcamPrompt") else orb.PrimaryPart:FindFirstChild("VROrbcamPrompt")
            vrOrbcamPrompt.Enabled = false
        end
    end

    -- If the orb is tweening, we use the stored data for poi
    local tweenData = targetForOrbTween[orb]

    local poi = nil
    local orbPos = nil

    if tweenData ~= nil then
        poi = tweenData.Poi
        orbPos = tweenData.Position
    else
        orbPos = getInstancePosition(orb)
        poi = Gui.PointOfInterest(orbPos)
    end

    if poi == nil or orbPos == nil then
        print("[Orb] Could not find point of interest to look at")
        return
    end

    if camera.CameraType ~= Enum.CameraType.Scriptable then
        camera.CameraType = Enum.CameraType.Scriptable
    end

    local poiPos = getInstancePosition(poi)

    -- By default the camera looks from (orbPos.X, poiPos.Y, orbPos.Z)
    -- but this can be overridden by specifying a Camera ObjectValue
    local orbCameraPos = Vector3.new(orbPos.X, poiPos.Y, orbPos.Z)

    local cameraOverride = poi:FindFirstChild("Camera")
    if cameraOverride ~= nil then
        local cameraPart = cameraOverride.Value
        if cameraPart ~= nil then
            orbCameraPos = cameraPart.Position
        end
    end
    
    if VRService.VREnabled then
        if Gui.VROrbcamConnection ~= nil then
            Gui.VROrbcamConnection:Disconnect()
        end

        Gui.VROrbcamConnection = RunService.RenderStepped:Connect(function(dt)
			workspace.CurrentCamera.CFrame = CFrame.lookAt(orbCameraPos, poiPos)
		end)
    else
        camera.CFrame = CFrame.lookAt(orbCameraPos, poiPos)

        local targets = {}
        for _, c in ipairs(poi:GetChildren()) do
            if c:IsA("ObjectValue") and c.Name == "Target" then
                if c.Value ~= nil then
                    table.insert(targets, c.Value)
                end
            end
        end

        local verticalFOV = Gui.FOVForTargets(orbCameraPos, poi:GetPivot().Position, targets)
        camera.FieldOfView = verticalFOV
    end

    if guiOff then
        StarterGui:SetCore("TopbarEnabled", false)
    end

    Gui.Orbcam = true
end

function Gui.OrbcamOff()
    local guiOff = Gui.OrbcamGuiOff
    OrbcamOffRemoteEvent:FireServer()

	if Gui.CameraTween then Gui.CameraTween:Cancel() end

    if guiOff then
	    StarterGui:SetCore("TopbarEnabled", true)
    end
	
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
    if storedCameraFOV ~= nil then
        camera.FieldOfView = storedCameraFOV
    else
        camera.FieldOfView = 70
    end
	
    if VRService.VREnabled then
        local orb = Gui.Orb
        if orb ~= nil then
            local vrOrbcamPrompt = if orb:IsA("BasePart") then orb:FindFirstChild("VROrbcamPrompt") else orb.PrimaryPart:FindFirstChild("VROrbcamPrompt")
            if vrOrbcamPrompt then
                vrOrbcamPrompt.Enabled = true
            end
        end

        if Gui.VROrbcamConnection ~= nil then
            Gui.VROrbcamConnection:Disconnect()
        end
    end

	resetCameraSubject()
    Gui.Orbcam = false
end

function Gui.ToggleBoardcam()
    if Gui.Boardcam then
        Gui.BoardcamOff()
        if Gui.BoardcamIcon.hovering then
            Gui.BoardcamHoverStarted()
        end
    else
        if Gui.Orbcam then
            Gui.ToggleOrbcam()
        end

        Gui.BoardcamOn()
        Gui.BoardcamHoverEnded()
    end
end

function Gui.ToggleOrbcam()
    if Gui.Orbcam then
		Gui.OrbcamOff()
	elseif not Gui.Orbcam and Gui.Orb ~= nil then
        if Gui.Boardcam then
            Gui.ToggleBoardcam()
        end

        Gui.OrbcamOn()
	end
end

function Gui.EnablePoiHighlights(orb)
    if Gui.PoiHighlightConnection ~= nil then
        Gui.PoiHighlightConnection:Disconnect()
    end

    local lastPoi = nil

    Gui.PoiHighlightConnection = RunService.RenderStepped:Connect(function(dt)
        local character = localPlayer.Character
        if character == nil then return end

        local waypoint = Gui.NearestWaypoint(character.PrimaryPart.Position)
        local poi = Gui.PointOfInterest(waypoint.Position)
        if poi == nil then return end

        if poi == lastPoi then
            -- Don't remake highlights for the same objects
            return
        else
            lastPoi = poi
        end

        for _, highlight in orb:GetChildren() do
            if highlight.Name ~= "Highlight" then continue end
            highlight:Destroy() 
        end

        local instancesToHighlight = {}
        
        for _, c in ipairs(poi:GetChildren()) do
            if c:IsA("ObjectValue") and c.Name == "Target" then
                if c.Value ~= nil then
                    table.insert(instancesToHighlight, c.Value)
                end
            end
        end

        if #instancesToHighlight == 0 then
            table.insert(instancesToHighlight, poi)
        end

        for _, x in instancesToHighlight do
            local xPart = if x:IsA("BasePart") then x else x.PrimaryPart
            local highlight = Instance.new("Highlight")
            highlight.Adornee = xPart
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Enabled = true
            highlight.FillTransparency = 0.9
            highlight.OutlineColor = Color3.new(1,1,1)
            highlight.Name = "Highlight"
            highlight.Parent = orb
        end
    end)
end

function Gui.DisablePoiHighlights(orb)
    if Gui.PoiHighlightConnection ~= nil then
        Gui.PoiHighlightConnection:Disconnect()
        Gui.PoiHighlightConnection = nil
    end

    for _, highlight in orb:GetChildren() do
        if highlight.Name ~= "Highlight" then continue end
        highlight:Destroy() 
    end
end

return Gui