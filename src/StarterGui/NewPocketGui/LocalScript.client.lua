local Pocket = game:GetService("ReplicatedStorage").Pocket
local VRService = game:GetService("VRService")
local Config = require(Pocket.Config)

local CreatePocketEvent = Pocket.Remotes.CreatePocket
local LinkPocketEvent = Pocket.Remotes.LinkPocket
local PocketsForPlayerRemoteFunction = Pocket.Remotes.PocketsForPlayer

local screenGui = script.Parent
local pocketBackgrounds = Config.PocketButtonBackgrounds

local currentPortal = nil
local lastInteractionTime = {} -- maps portals to our last interaction time

local function normalButtonActivated(name)
	if currentPortal == nil then
		print("[MetaPortal] Portal was nil")
		return
	end

	CreatePocketEvent:FireServer(currentPortal, name)
	lastInteractionTime[currentPortal] = tick()
	screenGui.Enabled = false
end

local function pocketNameFromPlaceId(placeId)
	local pocketName = nil
	for key, value in pairs(Config.PlaceIdOfPockets) do
		if value == placeId then
			pocketName = key
		end
	end

	return pocketName
end

local function showLinkGui()
	local linkButton = screenGui.ButtonFrame:FindFirstChild("_PocketLink Button")
	local linkText = screenGui.ButtonFrame:FindFirstChild("_PocketLink Text")
	local box = screenGui.ButtonFrame:FindFirstChild("_PocketLink TextBox")
	local button = screenGui.ButtonFrame:FindFirstChild("_PocketLink TextButton")
	local scrollingFrame = screenGui:FindFirstChild("_PocketLink ScrollingFrame")
	local pocketListText = screenGui:FindFirstChild("_PocketLink ListTextLabel")
	
	linkButton.Visible = false
	linkText.Visible = false
	box.Visible = true
	button.Visible = true
	box:CaptureFocus()
	
	local playerPockets = PocketsForPlayerRemoteFunction:InvokeServer()
	if playerPockets ~= nil and #playerPockets > 0 then
		scrollingFrame.Visible = true
		pocketListText.Visible = true
		scrollingFrame.CanvasSize = UDim2.new(0,300,0,#playerPockets * 30)

		for i, pocketData in ipairs(playerPockets) do
			local textButton = Instance.new("TextButton")
			textButton.Size = UDim2.new(1,0,0,30)
			textButton.Position = UDim2.new(0,0,0,30*(i-1))
			textButton.BackgroundTransparency = 1
			textButton.TextColor3 = Color3.new(1,1,1)
			textButton.TextScaled = false
			textButton.TextSize = 13
			textButton.ZIndex = 2
			textButton.TextXAlignment = Enum.TextXAlignment.Left
			textButton.Parent = scrollingFrame


			local pocketName = pocketNameFromPlaceId(pocketData.PlaceId)
			if pocketName == nil or pocketData.PocketCounter == nil then
				pocketName = ""
			else
				pocketName = pocketName .. " " .. pocketData.PocketCounter
			end
			
			textButton.Text = pocketName
			
			textButton.Activated:Connect(function()
				box.Text = pocketName
			end)
		end
	end
end

local function hideLinkGui()
	local linkButton = screenGui.ButtonFrame:FindFirstChild("_PocketLink Button")
	local linkText = screenGui.ButtonFrame:FindFirstChild("_PocketLink Text")
	local box = screenGui.ButtonFrame:FindFirstChild("_PocketLink TextBox")
	local button = screenGui.ButtonFrame:FindFirstChild("_PocketLink TextButton")
	local scrollingFrame = screenGui:FindFirstChild("_PocketLink ScrollingFrame")
	local pocketListText = screenGui:FindFirstChild("_PocketLink ListTextLabel")
	
	linkButton.Visible = true
	linkText.Visible = true
	box.Visible = false
	button.Visible = false
	scrollingFrame.Visible = false
	pocketListText.Visible = false
end

local buttonNames = {unpack(Config.AvailablePockets)}
table.insert(buttonNames, 1, "_PocketLink")

-- Create the pocket buttons
for i, name in ipairs(buttonNames) do
	if pocketBackgrounds[name] == nil then
		print("[MetaPortal] Could not find background image for pocket background")
		continue
	end
	
	local button = Instance.new("ImageButton")
	button.Name = name .. " Button"
	button.Position = UDim2.new(0.5, -150, 0, 20 + (i-1)*80)
	button.Size = UDim2.new(0, 300, 0, 60)
	button.BorderColor3 = Color3.new(1,1,1)
	button.BorderMode = Enum.BorderMode.Outline
	button.BorderSizePixel = 1
	button.Image = pocketBackgrounds[name]
	button.ZIndex = 1
	button.Parent = screenGui.ButtonFrame
	
	if name ~= "_PocketLink" then
		button.Activated:Connect(function()
			normalButtonActivated(name)
		end)
	else
		button.Activated:Connect(showLinkGui)
	end
	
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = name .. " Text"
	textLabel.Position = UDim2.new(0.5, -150, 0, 20 + (i-1)*80)
	textLabel.Size = UDim2.new(0, 300, 0, 60)
	textLabel.TextSize = 25
	textLabel.TextColor3 = Color3.new(1,1,1)
	textLabel.BackgroundTransparency = 1
	textLabel.TextStrokeTransparency = 0.1
	
	if name ~= "_PocketLink" then
		textLabel.Text = name
	else
		textLabel.Text = "Link to existing pocket"
	end
	
	textLabel.ZIndex = 5
	textLabel.Font = Enum.Font.SourceSans
	textLabel.Parent = screenGui.ButtonFrame
end

-- Create the link button GUI
do
	local linkButton = screenGui.ButtonFrame:FindFirstChild("_PocketLink Button")

	local textBox = Instance.new("TextBox")
	textBox.CursorPosition = 1
	textBox.TextEditable = true
	textBox.Name = "_PocketLink TextBox"
	textBox.Position = linkButton.Position + UDim2.new(0,-15,0,0)
	textBox.Size = linkButton.Size + UDim2.new(0,-30, 0, 0)
	textBox.TextSize = 15
	textBox.TextScaled = false
	textBox.TextColor3 = Color3.new(1,1,1)
	textBox.BackgroundTransparency = 1
	textBox.PlaceholderColor3 = Color3.fromRGB(178,178,178)
	textBox.PlaceholderText = "Alpha Cove 11"
	textBox.BackgroundColor3 = Color3.new(0,0,0)
	textBox.BackgroundTransparency = 0.8
	textBox.Visible = false
	textBox.Text = ""
	textBox.Parent = screenGui.ButtonFrame
	
	local frame = screenGui.ButtonFrame
		
	local pocketListFrame = Instance.new("ScrollingFrame")
	pocketListFrame.Name = "_PocketLink ScrollingFrame"
	pocketListFrame.Position = UDim2.new(UDim.new(frame.Position.X.Scale, frame.Position.X.Offset + frame.Size.X.Offset + 30),
		frame.Position.Y)
	pocketListFrame.Size = UDim2.new(0,300,0,300)
	pocketListFrame.BackgroundColor3 = Color3.new(0,0,0)
	pocketListFrame.BackgroundTransparency = 0.75
	pocketListFrame.Visible = false
	pocketListFrame.Parent = screenGui
	
	local pocketListText = Instance.new("TextLabel")
	pocketListText.Name = "_PocketLink ListTextLabel"
	pocketListText.TextSize = 15
	pocketListText.Position = UDim2.new(pocketListFrame.Position.X,
		UDim.new(pocketListFrame.Position.Y.Scale,pocketListFrame.Position.Y.Offset - 30))
	pocketListText.Size = UDim2.new(0,100,0,30)
	pocketListText.BackgroundTransparency = 1
	pocketListText.TextColor3 = Color3.new(1,1,1)
	pocketListText.Text = "Your pockets:"
	pocketListText.Visible = false
	pocketListText.Parent = screenGui
	
	local textButton = Instance.new("TextButton")
	textButton.Name = "_PocketLink TextButton"
	textButton.Position = linkButton.Position + UDim2.new(0,255,0,0)
	textButton.Size = UDim2.new(0,60,0,60)
	textButton.Visible = false
	textButton.Text = "OK"
	textButton.BackgroundColor3 = Color3.fromRGB(0,162,0)
	textButton.TextSize = 15
	textButton.TextColor3 = Color3.new(1,1,1)
	textButton.Parent = screenGui.ButtonFrame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0,8)
	corner.Parent = textButton
	
	textButton.Activated:Connect(function()
		LinkPocketEvent:FireServer(currentPortal, textBox.Text)
		lastInteractionTime[currentPortal] = tick()
		
		hideLinkGui()
		screenGui.Enabled = false
	end)
end

local cancelButton = screenGui.ButtonFrame.CancelButton

local function isPortalExcluded(portal)
	if lastInteractionTime[portal] == nil then
		return false
	end
	
	if lastInteractionTime[portal] > tick() - 5 then
		return true
	end
	
	return false
end

CreatePocketEvent.OnClientEvent:Connect(function(portal)
	if isPortalExcluded(portal) then return end
	if VRService.VREnabled then return end
	
	currentPortal = portal
	screenGui.Enabled = true
	lastInteractionTime[portal] = tick()
end)

cancelButton.Activated:Connect(function()
	hideLinkGui()
	screenGui.Enabled = false
end)