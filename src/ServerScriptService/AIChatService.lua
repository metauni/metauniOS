--
-- AIChat
--
-- Manages the chatbot endpoints for AI services

local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Players = game:GetService("Players")

local GameAnalytics = require(ReplicatedStorage.Packages.GameAnalytics)
local AIService = require(script.Parent.AIService)
local OrbService = require(ServerScriptService.OrbService)
local BoardService = require(ServerScriptService.BoardService)

local AskQuestionRemoteEvent = ReplicatedStorage.Orb.Remotes.AskQuestion

local function getInstancePosition(x)
	if x:IsA("BasePart") then return x.Position end
	if x:IsA("Model") and x.PrimaryPart ~= nil then
		return x.PrimaryPart.Position
	end

	return nil
end

local AIChatService = {}
AIChatService.__index = AIChatService

function AIChatService.Init()
    AIChatService.ChatHistory = {} -- maps chat endpoints to history
    AIChatService.Billboards = {} -- maps chat endpoints to billboards
    AIChatService.PlayerThumbnails = {} -- caches thumbnails

    local chatpoints = CollectionService:GetTagged("aiservice_chatpoint")

    for _, chatpoint in chatpoints do
        local messageFolder = Instance.new("Folder")
        messageFolder.Name = "Messages"
        messageFolder.Parent = chatpoint

        local messageTemplate = chatpoint:FindFirstChild("MessageTemplate")
        if messageTemplate == nil or messageTemplate.PrimaryPart == nil then
            print("[AIChat] Failed to get message template")
        end

        AIChatService.ChatHistory[chatpoint] = {}
        AIChatService.Billboards[chatpoint] = {}
    end

    AskQuestionRemoteEvent.OnServerEvent:Connect(function(plr, orb, questionText)
        -- Determine the closest chatpoint to the orb
        local orbPart = if orb:IsA("Model") then orb.PrimaryPart else orb
        local distance = math.huge
        local closestChatpoint = nil
        for _, chatpoint in chatpoints do
            local d = (chatpoint.MessageTemplate.PrimaryPart.Position - orbPart.Position).Magnitude
            if d < distance then
                distance = d
                closestChatpoint = chatpoint
            end
        end

        if closestChatpoint ~= nil and distance < 150 then
            AIChatService.HandleQuestion(plr, orb, questionText, closestChatpoint)
        else
            print("[AIChatService] Could not find chatpoint close enough")
        end
    end)
end

function AIChatService.FetchPlayerThumbnail(userId)
	if AIChatService.PlayerThumbnails[userId] ~= nil then return end

	-- fetch the thumbnail
	local thumbType = Enum.ThumbnailType.HeadShot
	local thumbSize = Enum.ThumbnailSize.Size420x420
	local content, isReady = Players:GetUserThumbnailAsync(userId, thumbType, thumbSize)

	if isReady then
		AIChatService.PlayerThumbnails[userId] = content
	end
end

function AIChatService.HandleQuestion(plr, orb, questionText, chatpoint)
    AIChatService.FetchPlayerThumbnail(plr.UserId)

    local success, err = pcall(function()
		GameAnalytics:addDesignEvent(plr.UserId, {
            eventId = "AI:Question"
        })
	end)	
	
	if not success then
		print("[AIChatService] GameAnalytics addDesignEvent failed ".. err)
		return {}
	end

    local messageFolder = chatpoint.Messages
	local messageTemplate = chatpoint.MessageTemplate
    local billboards = AIChatService.Billboards[chatpoint]
    local history = AIChatService.ChatHistory[chatpoint]

    -- Figure out what the orbcam is looking at, in order to make substitutions in the question text
    local questionSubText = questionText

    local orbPart = if orb:IsA("Model") then orb.PrimaryPart else orb
    local poi, poiPos = OrbService.PointOfInterest(orbPart.Position)

    if poi ~= nil then
        -- The poi could be a board (it will be tagged "metaboard")
        -- or it could be a metaorb_poi, in which case it may have
        -- targets
        if CollectionService:HasTag(poi, "metaboard") then
            if string.match(questionSubText, "board") then
                
                local board = BoardService.Boards[poi]
                if board == nil then
                    print("[AIChatService] Failed to fetch board data from BoardService")
                else

                    local boardText = AIService.OCRBoard(board)
                    if boardText ~= nil then
                        questionSubText = string.gsub(questionSubText, "board", "\"" .. boardText .. "\"")
                    end
                end
            end
		else
            local targets = {}
            for _, c in ipairs(poi:GetChildren()) do
                if c:IsA("ObjectValue") and c.Name == "Target" then
                    if c.Value ~= nil then
                        table.insert(targets, c.Value)
                    end
                end
            end

            if #targets == 2 then
                -- The Poi target is always a part, it may either be the PrimaryPart
                -- of a metaboard, or the metaboard itself
                local function isValidTarget(x)
                    if CollectionService:HasTag(x, "metaboard") then return true end

                    if x.Parent:IsA("Model") and CollectionService:HasTag(x.Parent, "metaboard") and x.Parent.PrimaryPart == x then
                        return true
                    end
                    
                    return false
                end

                local function boardInstanceFromTarget(x)
                    if CollectionService:HasTag(x, "metaboard") then
                        return x
                    else
                        return x.Parent
                    end
                end

                if isValidTarget(targets[1]) and isValidTarget(targets[2]) then
                    -- Discover which target is "leftboard" and which is "rightboard"
                    local poiPos = getInstancePosition(poi)
                    local orbPos = getInstancePosition(orb)
                    local cameraPos = Vector3.new(orbPos.X, poiPos.Y, orbPos.Z)
                    local cameraCFrame = CFrame.lookAt(cameraPos, poiPos)

                    local camera = workspace.CurrentCamera
                    local oldCameraCFrame = camera.CFrame
                    local oldCameraFieldOfView = camera.FieldOfView
                    camera.CFrame = cameraCFrame
                    camera.FieldOfView = 70
                    
                    local extremeLeftCoord, extremeRightCoord
                    local extremeLeft, extremeRight

                    for _, t in ipairs(targets) do
                        local extremities = {}
                        local unitVectors = { X = Vector3.new(1,0,0),
                                                Y = Vector3.new(0,1,0),
                                                Z = Vector3.new(0,0,1)}

                        for _, direction in ipairs({"X", "Y", "Z"}) do
                            local extremeOne = t.CFrame * CFrame.new(0.5 * unitVectors[direction] * t.Size[direction])
                            local extremeTwo = t.CFrame * CFrame.new(-0.5 * unitVectors[direction] * t.Size[direction])
                            table.insert(extremities, {Position=extremeOne.Position, Owner=t})
                            table.insert(extremities, {Position=extremeTwo.Position, Owner=t})
                        end

                        for _, e in ipairs(extremities) do
                            local screenPos = camera:WorldToScreenPoint(e.Position)
                            if extremeLeftCoord == nil or screenPos.X < extremeLeftCoord then
                                extremeLeftCoord = screenPos.X
                                extremeLeft = e
                            end

                            if extremeRightCoord == nil or screenPos.X > extremeRightCoord then
                                extremeRightCoord = screenPos.X
                                extremeRight = e
                            end
                        end
                    end

                    camera.CFrame = oldCameraCFrame
                    camera.FieldOfView = oldCameraFieldOfView

                    local leftBoardInstance, rightBoardInstance

                    if extremeLeft and extremeLeft['Owner'] and extremeRight and extremeRight['Owner'] then
                        leftBoardInstance = boardInstanceFromTarget(extremeLeft.Owner)
                        rightBoardInstance = boardInstanceFromTarget(extremeRight.Owner)
                    else
                        print("[AIChatService] Failed to identify left and right boards")
                        leftBoardInstance = targets[1].Parent
                        rightBoardInstance = targets[2].Parent
                    end

                    if string.match(questionSubText, "leftboard") then

                        local board = BoardService.Boards[leftBoardInstance]

                        if board == nil then

                            print("[AIChatService] Failed to fetch board data from BoardService")
                        else

                            local boardText = AIService.OCRBoard(board)	
                            if boardText ~= nil then
                                questionSubText = string.gsub(questionSubText, "leftboard", "\"" .. boardText .. "\"")
                            else
                                print("[AIChatService] Failed to OCR left board")
                            end
                        end
                    end

                    if string.match(questionSubText, "rightboard") then
                        
                        local board = BoardService.Boards[rightBoardInstance]

                        if board == nil then

                            print("[AIChatService] Failed to fetch board data from BoardService")
                        else

                            local boardText = AIService.OCRBoard(board)	
                            if boardText ~= nil then
                                questionSubText = string.gsub(questionSubText, "rightboard", "\"" .. boardText .. "\"")
                            else
                                print("[AIChatService] Failed to OCR right board")
                            end
                        end
                    end
                end
            end
        end
    end

	-- 1000 tokens is about 750 words
	local maxTokens = 60
    questionSubText = questionSubText .. " Answer in 60 words or less."
	local responseText = AIService.GPTPrompt(questionSubText, maxTokens, plr)
	if responseText == nil then return end
	
	responseText = AIService.CleanGPTResponse(responseText)
	
	local billboardQ = messageTemplate:Clone()
	billboardQ.Parent = messageFolder
	billboardQ.Name = "Question"
	billboardQ.PrimaryPart.Transparency = 0
    billboardQ.PrimaryPart.Color = Color3.fromRGB(240, 244, 253)
	billboardQ.PrimaryPart.SurfaceGui.TextLabel.TextColor3 = Color3.new(0,0,0)
	if AIChatService.PlayerThumbnails[plr.UserId] ~= nil then
		local thumbnailPart = billboardQ.Thumbnail
		thumbnailPart.SurfaceGui.ImageLabel.Visible = true
		thumbnailPart.SurfaceGui.ImageLabel.Image = AIChatService.PlayerThumbnails[plr.UserId]
	end
	table.insert(billboards, billboardQ)
	AIChatService.PositionBillboards(chatpoint)

	local billboard = messageTemplate:Clone()
	billboard.Parent = messageFolder
	billboard.Name = "Answer"
	billboard.PrimaryPart.Transparency = 0.2

	table.insert(billboards, billboard)
	AIChatService.PositionBillboards(chatpoint)

	table.insert(history, {Input = questionText, Output = responseText, Player = plr.UserId})

	local filteredPrompt = TextService:FilterStringAsync(questionText, plr.UserId)
	local filteredPromptText = filteredPrompt:GetNonChatStringForBroadcastAsync()
	billboardQ.PrimaryPart.SurfaceGui.TextLabel.Text = filteredPromptText
	
	local filteredResponse = TextService:FilterStringAsync(responseText, plr.UserId)
	local filteredText = filteredResponse:GetNonChatStringForBroadcastAsync()
	billboard.PrimaryPart.SurfaceGui.TextLabel.Text = filteredText
end

function AIChatService.PositionBillboards(chatpoint)
    local billboards = AIChatService.Billboards[chatpoint]
	local heightOffset = billboards[#billboards].PrimaryPart.Size.Y

	for i = 1, #billboards - 1 do
		local billboard = billboards[i]
		billboard:PivotTo(billboard.PrimaryPart.CFrame * CFrame.new(0,heightOffset,0))
	end
end

return AIChatService