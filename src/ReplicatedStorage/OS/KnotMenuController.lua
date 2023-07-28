-- Roblox services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local Pocket = ReplicatedStorage.Pocket
local Config = require(Pocket.Config)

local localPlayer = Players.LocalPlayer
local localCharacter = localPlayer.Character or localPlayer.CharacterAdded:Wait()

local modalGuiActive = false

local function StartDecalEntryDisplay(board)
    if modalGuiActive then return end
    modalGuiActive = true

    local remoteEvent = ReplicatedStorage.AddDecalToBoard

    local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BoardDecalDisplay"
	
	local displayWidth = 500

	local textBox = Instance.new("TextBox")
	textBox.Name = "TextBox"
	textBox.BackgroundColor3 = Color3.new(0,0,0)
	textBox.BackgroundTransparency = 0.3
	textBox.Size = UDim2.new(0,displayWidth,0,100)
	textBox.Position = UDim2.new(0.5,-0.5 * displayWidth,0.5,-100)
	textBox.TextColor3 = Color3.new(1,1,1)
	textBox.TextSize = 20
    textBox.Text = ""
    textBox.PlaceholderText = "Enter an asset ID"
	textBox.TextWrapped = true
	textBox.ClearTextOnFocus = false

    local boardPart = if board:IsA("BasePart") then board else board.PrimaryPart
    local decal = boardPart:FindFirstChild("BoardDecal")
	if decal ~= nil then 
		textBox.Text = decal.Texture
	end

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0,10)
	padding.PaddingTop = UDim.new(0,10)
	padding.PaddingRight = UDim.new(0,10)
	padding.PaddingLeft = UDim.new(0,10)
	padding.Parent = textBox

	textBox.Parent = screenGui

    -- Buttons
    local button = Instance.new("TextButton")
	button.Name = "OKButton"
	button.Size = UDim2.new(0,200,0,50)
	button.Position = UDim2.new(0.5,50,0.5,100)
	button.Parent = screenGui
	button.BackgroundColor3 = Color3.fromRGB(0,162,0)
	button.TextColor3 = Color3.new(1,1,1)
	button.TextSize = 25
	button.Text = "OK"
	button.Activated:Connect(function()
        modalGuiActive = false
		screenGui:Destroy()
        remoteEvent:FireServer(board, textBox.Text)
	end)
	Instance.new("UICorner").Parent = button

    button = Instance.new("TextButton")
	button.Name = "CancelButton"
	button.Size = UDim2.new(0,200,0,50)
	button.Position = UDim2.new(0.5,-250,0.5,100)
	button.Parent = screenGui
	button.BackgroundColor3 = Color3.fromRGB(148,148,148)
	button.TextColor3 = Color3.new(1,1,1)
	button.TextSize = 25
	button.Text = "Cancel"
	button.Activated:Connect(function()
        modalGuiActive = false
		screenGui:Destroy()
	end)
	Instance.new("UICorner").Parent = button

	screenGui.Parent = localPlayer.PlayerGui
    textBox:CaptureFocus()
end

local function StartDisplay(board, displayType)
    if modalGuiActive then return end
    modalGuiActive = true

    local boardPersistId = board.PersistId.Value
	
    local isPocket = Pocket:GetAttribute("IsPocket")
    local pocketId = nil
    if isPocket then
        if Pocket:GetAttribute("PocketId") == nil then
            Pocket:GetAttributeChangedSignal("PocketId"):Wait()
        end

        pocketId = Pocket:GetAttribute("PocketId")
    end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BoardDisplay"

	local button = Instance.new("TextButton")
	button.Name = "OKButton"
	button.Size = UDim2.new(0,200,0,50)
	button.Position = UDim2.new(0.5,-100,0.5,150)
	button.Parent = screenGui
	button.BackgroundColor3 = Color3.fromRGB(0,162,0)
	button.TextColor3 = Color3.new(1,1,1)
	button.TextSize = 25
	button.Text = "OK"
	button.Activated:Connect(function()
        modalGuiActive = false
		screenGui:Destroy()
	end)
	Instance.new("UICorner").Parent = button
	
	local dataString
	local displayWidth

    if displayType == "key" then
        displayWidth = 600
        if isPocket then
            dataString = pocketId .. "-" .. boardPersistId
        else
            dataString = boardPersistId
        end
    elseif displayType == "URL" then
        displayWidth = 800
        if isPocket then
            local pocketName = HttpService:UrlEncode(Pocket:GetAttribute("PocketName"))
            dataString = "https://www.roblox.com/games/start?placeId=" .. Config.RootPlaceId
            dataString = dataString .. "&launchData=pocket%3A" .. pocketName
            dataString = dataString .. "-targetBoardPersistId%3A" .. boardPersistId
        else
            dataString = "https://www.roblox.com/games/start?placeId=" .. Config.RootPlaceId
            dataString = dataString .. "&launchData=targetBoardPersistId%3A" .. boardPersistId
        end
    end

	local textBox = Instance.new("TextBox")
	textBox.Name = "TextBox"
	textBox.BackgroundColor3 = Color3.new(0,0,0)
	textBox.BackgroundTransparency = 0.3
	textBox.Size = UDim2.new(0,displayWidth,0,200)
	textBox.Position = UDim2.new(0.5,-0.5 * displayWidth,0.5,-100)
	textBox.TextColor3 = Color3.new(1,1,1)
	textBox.TextSize = 20
	textBox.Text = dataString
	textBox.TextWrapped = true
	textBox.TextEditable = false
	textBox.ClearTextOnFocus = false

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0,10)
	padding.PaddingTop = UDim.new(0,10)
	padding.PaddingRight = UDim.new(0,10)
	padding.PaddingLeft = UDim.new(0,10)
	padding.Parent = textBox

	textBox.Parent = screenGui

	screenGui.Parent = localPlayer.PlayerGui
end

local function EndBoardSelectMode()

	for _, board in CollectionService:GetTagged("metaboard") do
		if board:FindFirstChild("PersistId") == nil then continue end

		local c = board:FindFirstChild("ClickTargetClone")
		if c ~= nil then
			c:Destroy()
		end
	end

	local screenGui = localPlayer.PlayerGui:FindFirstChild("BoardKeyGui")
	if screenGui ~= nil then
		screenGui:Destroy()
	end
end

local boardSelectModeActive = false

local function StartBoardSelectMode(onBoardSelected, displayType)
    if boardSelectModeActive then return end

	local screenGui = localPlayer.PlayerGui:FindFirstChild("BoardKeyGui")
	if screenGui ~= nil then return end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BoardKeyGui"

	local cancelButton = Instance.new("TextButton")
	cancelButton.Name = "CancelButton"
	cancelButton.BackgroundColor3 = Color3.fromRGB(148,148,148)
	cancelButton.Size = UDim2.new(0,200,0,50)
	cancelButton.Position = UDim2.new(0.5,-100,0.9,-50)
	cancelButton.Parent = screenGui
	cancelButton.TextColor3 = Color3.new(1,1,1)
	cancelButton.TextSize = 30
	cancelButton.Text = "Cancel"
	cancelButton.Activated:Connect(function()
		EndBoardSelectMode()
		screenGui:Destroy()
        boardSelectModeActive = false
	end)
	Instance.new("UICorner").Parent = cancelButton

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextLabel"
	textLabel.BackgroundColor3 = Color3.new(0,0,0)
	textLabel.BackgroundTransparency = 0.9
	textLabel.Size = UDim2.new(0,500,0,50)
	textLabel.Position = UDim2.new(0.5,-250,0,100)
	textLabel.TextColor3 = Color3.new(1,1,1)
	textLabel.TextSize = 25
	textLabel.Text = "Select a board"
	textLabel.Parent = screenGui

	screenGui.Parent = localPlayer.PlayerGui

	local boards = CollectionService:GetTagged("metaboard")

	for _, boardPart in boards do
		if boardPart:FindFirstChild("PersistId") == nil then continue end

		local clickClone = boardPart:Clone()
		for _, t in ipairs(CollectionService:GetTags(clickClone)) do
			CollectionService:RemoveTag(clickClone, t)
		end
		clickClone:ClearAllChildren()
		clickClone.Name = "ClickTargetClone"
		clickClone.Transparency = 0
		clickClone.Size = boardPart.Size * 1.02
		clickClone.Material = Enum.Material.SmoothPlastic
		clickClone.CanCollide = false
		clickClone.Parent = boardPart
		clickClone.Color = Color3.new(0.296559, 0.397742, 0.929351)
		clickClone.CFrame = boardPart.CFrame + boardPart.CFrame.LookVector * 1

		local clickDetector = Instance.new("ClickDetector")
		clickDetector.MaxActivationDistance = 500
		clickDetector.Parent = clickClone
		clickDetector.MouseClick:Connect(function()
			onBoardSelected(boardPart, displayType)
            boardSelectModeActive = false
			EndBoardSelectMode()
		end)
	end

    boardSelectModeActive = true
end

local function CreateTopbarItems()
	local Icon = require(game:GetService("ReplicatedStorage").Icon)
	local Themes =  require(game:GetService("ReplicatedStorage").Icon.Themes)

    -- Knot menu
	local icon = Icon.new()
	icon:setImage("rbxassetid://11783868001")
	icon:setOrder(-1)
	icon:setLabel("")
	icon:set("dropdownSquareCorners", true)
	icon:set("dropdownMaxIconsBeforeScroll", 10)
	icon:setDropdown({
		Icon.new()
		:setLabel("Key for Board...")
		:bindEvent("selected", function(self)
			self:deselect()
			icon:deselect()
			StartBoardSelectMode(StartDisplay, "key")
		end),
        Icon.new()
		:setLabel("URL for Board...")
		:bindEvent("selected", function(self)
			self:deselect()
			icon:deselect()
			StartBoardSelectMode(StartDisplay, "URL")
		end),
        Icon.new()
		:setLabel("Decal for Board...")
		:bindEvent("selected", function(self)
			self:deselect()
			icon:deselect()
			StartBoardSelectMode(StartDecalEntryDisplay)
		end)
	}) 

	icon:setTheme(Themes["BlueGradient"])
end

return {

	Start = CreateTopbarItems,
}