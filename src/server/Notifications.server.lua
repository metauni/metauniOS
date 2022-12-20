local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

NotificationService = require(script.Parent.NotificationService)
local metaPortal = ServerScriptService:FindFirstChild("metaportal")

local pocketId = nil

if metaPortal and game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
	if metaPortal:GetAttribute("PocketId") == nil then
		metaPortal:GetAttributeChangedSignal("PocketId"):Wait()
	end

	pocketId = metaPortal:GetAttribute("PocketId")
end
	
local boardModified = {}

local boards = CollectionService:GetTagged("metaboard")

for _, board in boards do
	if board:FindFirstChild("PersistId") == nil then continue end
	if not board:IsDescendantOf(game.Workspace) then continue end
	
	board:WaitForChild("metaboardRemotes")
	local events = {"FinishDrawingTask", "Undo", "Redo", "Clear"}
	for _, e in events do
		local remoteEvent = board.metaboardRemotes:WaitForChild(e)
		remoteEvent.OnServerEvent:Connect(function()
			boardModified[board] = tick()
		end)	
	end
end

-- Return boards that have changed, but remained
-- static for at least delay seconds
local function boardsToNotify(delay)
	local boardsDelta = {}

	for _, board in boards do
		if boardModified[board] ~= nil and 
			boardModified[board] + delay < tick() then
			local boardKey = tostring(board.PersistId.Value)
			if pocketId then
				boardKey = pocketId .. "-" .. boardKey
			end
			
			table.insert(boardsDelta, boardKey)
			boardModified[board] = nil
		end
	end
	
	return boardsDelta
end

local function updateBoardSubscriberDisplays(subscriberCountForBoards)
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

        local boardPart = if board:IsA("Model") then board.PrimaryPart else board

        local scaleFactor = boardPart.Size.Y / 20.25
		local countPartWidth = 7 * scaleFactor
		local countPartHeight = 1.125 * scaleFactor
		
		local countPart = board:FindFirstChild("SubscriberCountPart")
		if not countPart then
			
			countPart = Instance.new("Part")
			countPart.Name = "SubscriberCountPart"
			countPart.Size = Vector3.new(countPartWidth, countPartHeight, 0.1)
			countPart.CFrame = boardPart.CFrame * CFrame.new(-boardPart.Size.X/2 + countPartWidth/2, -boardPart.Size.Y/2 - countPartHeight/2, 0.01)
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

task.wait(10)

-- Sync the indicators of number of board subscribers
local subscriberCountForBoards = NotificationService.GetNumberOfSubscribers(pocketId)
updateBoardSubscriberDisplays(subscriberCountForBoards)

local WAIT_TIME = 60
task.spawn(function()
	while task.wait(WAIT_TIME) do
		-- Send notifications to the server about board changes
		local boardsDelta = boardsToNotify(60)
		
		if #boardsDelta > 0 then
			NotificationService.SendNotification(boardsDelta)
		end
		
		-- Sync the indicators of number of board subscribers
		local subscriberCountForBoards = NotificationService.GetNumberOfSubscribers(pocketId)
		updateBoardSubscriberDisplays(subscriberCountForBoards)
	end
end)

game:BindToClose(function()
	local boardsDelta = boardsToNotify(0)

	if #boardsDelta > 0 then
		NotificationService.SendNotification(boardsDelta)
	end
end)