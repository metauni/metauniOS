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

-- displayType is "key" or "URL"
local function StartDisplay(boardPersistId, displayType)
    if modalGuiActive then return end
    modalGuiActive = true
	
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BoardDisplay"

	local button = Instance.new("TextButton")
	button.Name = "OKButton"
	button.BackgroundColor3 = Color3.fromRGB(148,148,148)
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
        local isPocket = Pocket:GetAttribute("IsPocket")
        if isPocket then
            if Pocket:GetAttribute("PocketId") == nil then
                Pocket:GetAttributeChangedSignal("PocketId"):Wait()
            end

            local pocketId = Pocket:GetAttribute("PocketId")

            dataString = pocketId .. "-" .. boardPersistId
        else
            dataString = boardPersistId
        end
    elseif displayType == "URL" then
        displayWidth = 800

        local isPocket = Pocket:GetAttribute("IsPocket")
        if isPocket then
            if Pocket:GetAttribute("PocketId") == nil then
                Pocket:GetAttributeChangedSignal("PocketId"):Wait()
            end
            
            local pocketName = HttpService:UrlEncode(Pocket:GetAttribute("PocketName"))
            dataString = "https://www.roblox.com/games/start?placeId=" .. Config.RootPlaceId
            dataString = dataString .. "&launchData=pocket%3A" .. pocketName
            dataString = dataString .. "-targetBoardPersistId%3A" .. boardPersistId
        else
            dataString = "No URL available"
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
	local boards = CollectionService:GetTagged("metaboard")

	for _, board in boards do
		if board:FindFirstChild("PersistId") == nil then continue end
		
		local boardPart = if board:IsA("Model") then board.PrimaryPart else board
        if boardPart == nil then continue end -- perhaps due to streaming

		local c = boardPart:FindFirstChild("ClickTargetClone")
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

	for _, board in boards do
		if board:FindFirstChild("PersistId") == nil then continue end

		local boardPart = if board:IsA("Model") then board.PrimaryPart else board
		if boardPart == nil then continue end -- perhaps due to streaming

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
			onBoardSelected(board.PersistId.Value, displayType)
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
		end)
	}) 

	icon:setTheme(Themes["BlueGradient"])
end

return {

	Start = CreateTopbarItems,
}