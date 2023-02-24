--
-- NotificationService
--
-- Interfaces with the metauniService webserver, allowing
-- web and email notifications of in-world events

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- IP 34.116.106.66
local metauniServiceAddress = "https://www.metauniservice.com"

local function isPocket()
	return (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0)
end

local NotificationService = {}
NotificationService.__index = NotificationService

function NotificationService.GetNumberOfSubscribers()
    local pocketId = ""
    if isPocket() then
        pocketId = ReplicatedStorage.Pocket:GetAttribute("PocketId")
    end
	
	local json = HttpService:JSONEncode({RequestType = "GetBoardNotificationSubscriberNumbers", 
		Content = pocketId})

	local success, response = pcall(function()
		return HttpService:PostAsync(
			metauniServiceAddress,
			json,
			Enum.HttpContentType.ApplicationJson,
			false)
	end)	
	
	if success then
		if response == nil then
			print("[NotificationService] Got a bad response from PostAsync")
			return {}
		end

		local successJson, responseData = pcall(function()
			return HttpService:JSONDecode(response)
		end)

		if successJson then
			if responseData == nil then
				print("[NotificationService] JSONDecode on response failed")
				return {}
			end
		else
			print("[NotificationService] Can't parse JSON")
			return {}
		end

		return responseData
	else
		print("[NotificationService] PostAsync failed. ".. response)
		return {}
	end
end

function NotificationService.SendNotification(note)
	local json = HttpService:JSONEncode({RequestType = "Notification", 
		Content = note})

	local success, response = pcall(function()
		return HttpService:PostAsync(
			metauniServiceAddress,
			json,
			Enum.HttpContentType.ApplicationJson,
			false)
	end)

	if success then
		if response == nil then
			print("[NotificationService] Got a bad response from PostAsync")
			return nil
		end
		
		local successJson, responseData = pcall(function()
			return HttpService:JSONDecode(response)
		end)
		
		if successJson then
			if responseData == nil then
				print("[NotificationService] JSONDecode on response failed")
				return nil
			end
		else
			print("[NotificationService] Can't parse JSON")
			return
		end

		local responseText = responseData["text"]
		return responseText
	else
		print("[NotificationService] HTTPService PostAsync failed ".. response)
		return nil
	end
end

function NotificationService.UpdateBoardSubscriberDisplays()
    local subscriberCountForBoards = NotificationService.GetNumberOfSubscribers()

    local boards = CollectionService:GetTagged("metaboard")
	for _, board in boards do
		if board:FindFirstChild("PersistId") == nil then continue end
		if not board:IsDescendantOf(game.Workspace) then continue end
		
		local boardKey = tostring(board.PersistId.Value)
		
		if (not subscriberCountForBoards[boardKey]) or subscriberCountForBoards[boardKey] == 0 then
			local countPart = board:FindFirstChild("SubscriberCountPart")
			if countPart ~= nil then countPart:Destroy() end
			continue
		end
		
		local subscriberCount = tonumber(subscriberCountForBoards[boardKey])
		
        -- On the old-school "large" boards, like the ones in TRS, which are
        -- 27, 20.25, 0.113 we use a display of size 7 x 1.125. We scale
        -- proportionately for other boards

        local scaleFactor = board.Size.Y / 20.25
		local countPartWidth = 7 * scaleFactor
		local countPartHeight = 1.125 * scaleFactor
		
		local countPart = board:FindFirstChild("SubscriberCountPart")
		if not countPart then
			
			countPart = Instance.new("Part")
			countPart.Name = "SubscriberCountPart"
			countPart.Size = Vector3.new(countPartWidth, countPartHeight, 0.1)
			countPart.CFrame = board.CFrame * CFrame.new(-board.Size.X/2 + countPartWidth/2, -board.Size.Y/2 - countPartHeight/2, 0.01)
			countPart.Anchored = true
			countPart.CastShadow = false
			countPart.CanCollide = false
			countPart.Transparency = 1
			countPart.Parent = board
			
			local boardSurfaceGui = Instance.new("SurfaceGui")
			boardSurfaceGui.Name = "SurfaceGui"
			boardSurfaceGui.Adornee = countPart
			boardSurfaceGui.Parent = countPart
			boardSurfaceGui.CanvasSize = Vector2.new(800,200)
			
			local textLabel = Instance.new("TextLabel")
			textLabel.Name = "TextLabel"
			textLabel.TextScaled = true
			textLabel.TextColor3 = Color3.new(1,1,1)
			textLabel.Size = UDim2.new(1,0,1,0)
			textLabel.BackgroundTransparency = 1
			textLabel.TextXAlignment = Enum.TextXAlignment.Right
			textLabel.Parent = boardSurfaceGui
			
			local uiPadding = Instance.new("UIPadding")
			uiPadding.PaddingRight = UDim.new(0,40)
			uiPadding.Parent = textLabel
		end
		
		local countText = tostring(subscriberCount)
		if subscriberCount > 1 then
			countText = countText .. " subscribers"
		else
			countText = countText .. " subscriber"
		end
		countPart.SurfaceGui.TextLabel.Text = countText
	end
end

function NotificationService.BoardsToNotify(delay)
    local boardsDelta = {}

    local boards = CollectionService:GetTagged("metaboard")
	for _, board in boards do
        if board:FindFirstChild("PersistId") == nil then continue end
        if not board:IsDescendantOf(game.Workspace) then continue end

        local boardId = tostring(board.PersistId.Value)
        if NotificationService.BoardsModified[boardId] == nil then continue end

        if NotificationService.BoardsModified[boardId] + delay < tick() then
            NotificationService.BoardsModified[boardId] = nil
            local boardKey = boardId
            
            if isPocket() then
                local pocketId = ReplicatedStorage.Pocket:GetAttribute("PocketId")
                boardKey = pocketId .. "-" .. boardKey
            end

			table.insert(boardsDelta, boardKey)
		end
	end
	
	return boardsDelta
end

function NotificationService.BoardModificationTimes()
    return NotificationService.BoardsModified
end

function NotificationService.Init()
    NotificationService.BoardsModified = {} -- Maps persistIds (as strings) to times

    game:BindToClose(function()
        local boardsDelta = NotificationService.BoardsToNotify(0)
    
        if #boardsDelta > 0 then
            NotificationService.SendNotification(boardsDelta)
        end
    end)

    task.delay(10, function()
		local boards = CollectionService:GetTagged("metaboard")
		for _, board in boards do
            if board:FindFirstChild("PersistId") == nil then continue end
            if not board:IsDescendantOf(game.Workspace) then continue end
            
            if not board:GetAttribute("BoardServerInitialised") then
                board:GetAttributeChangedSignal("BoardServerInitialised"):Wait()
            end
                    
            board:WaitForChild("metaboardRemotes")
            local boardKey = tostring(board.PersistId.Value)
                    
            local events = {"FinishDrawingTask", "Undo", "Redo", "Clear"}
            for _, e in events do
                local remoteEvent = board.metaboardRemotes:FindFirstChild(e)
                if remoteEvent == nil then
                    print("[NotificationService] Failed to get event for board")
                    continue
                end
                
                remoteEvent.OnServerEvent:Connect(function(plr)
                    NotificationService.BoardsModified[boardKey] = tick()
                end)	
            end
		end
			
		NotificationService.UpdateBoardSubscriberDisplays()
			
		local WAIT_TIME = 60
		task.spawn(function()
            while task.wait(WAIT_TIME) do
                -- Send notifications to the server about board changes
                local boardsDelta = NotificationService.BoardsToNotify(60)
                
                if #boardsDelta > 0 then
                    NotificationService.SendNotification(boardsDelta)
                end
                
                NotificationService.UpdateBoardSubscriberDisplays()
            end
		end)
	end)
end

return NotificationService
