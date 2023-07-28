local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VRService = game:GetService("VRService")
local TweenService = game:GetService("TweenService")

if VRService.VREnabled then return end

-- Only show the loading screen in TRS
if game.PlaceId ~= 8165217582 then return end

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local teleportData = TeleportService:GetLocalPlayerTeleportData()

-- If a player is passing through, they may have a teleport GUI set
local teleportGui = TeleportService:GetArrivingTeleportGui()
if teleportGui ~= nil then	
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	TeleportService:SetTeleportGui(teleportGui)
	teleportGui.Parent = playerGui
	return
end

-- If we have teleported from somewhere, no more to do
if teleportData ~= nil then return end

-- Remove the default loading screen and show black
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
ReplicatedFirst:RemoveDefaultLoadingScreen()

local viewportSize = workspace.CurrentCamera.ViewportSize

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BlackLoading"
screenGui.IgnoreGuiInset = true

local frame = Instance.new("Frame")
frame.Name = "Frame"
frame.Parent = screenGui
frame.Size = UDim2.new(1,0,1,0)
frame.BackgroundTransparency = 0
frame.BackgroundColor3 = Color3.new(0,0,0)

local width = 0.8
local height = 0.6
local image = Instance.new("ImageLabel")
image.Name = "ImageLabel"
image.Size = UDim2.new(width,0,height,0)
image.Position = UDim2.new(0.5*(1-width),0,0.5*(1-height),0)
image.SizeConstraint = Enum.SizeConstraint.RelativeXY
image.ScaleType = Enum.ScaleType.Fit
image.BackgroundTransparency = 1
image.Parent = screenGui

local trsImages = {
	"rbxassetid://10571155928",
	"rbxassetid://10571156395",
	"rbxassetid://10571156964",
	"rbxassetid://10571157328"
}

-- image.Image = trsImages[math.random(1,#trsImages)]

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0,8)
uiCorner.Parent = image

screenGui.Parent = playerGui

-- Launch data is set if we have joined the world with a URL, and are
-- thus about to be redirected
local GetLaunchDataRemoteFunction = ReplicatedStorage:WaitForChild("OS"):WaitForChild("Pocket"):WaitForChild("Remotes"):WaitForChild("GetLaunchData")
local launchData = GetLaunchDataRemoteFunction:InvokeServer()

local function fadeIn(fadeTime)
	local tweenInfo = TweenInfo.new(
		fadeTime, -- Time
		Enum.EasingStyle.Linear, -- EasingStyle
		Enum.EasingDirection.Out, -- EasingDirection
		0, -- RepeatCount (when less than zero the tween will loop indefinitely)
		false, -- Reverses (tween will reverse once reaching it's goal)
		0 -- DelayTime
	)

	local tweenFrame = TweenService:Create(frame, tweenInfo, 
		{BackgroundTransparency = 1})
	tweenFrame:Play()

	local tween = TweenService:Create(image, tweenInfo, 
		{BackgroundTransparency = 1,
			ImageTransparency = 1})
	tween:Play()

	tween.Completed:Connect(function()
		screenGui:Destroy()	
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	end)
end

-- If there is no pocket launch data, and the game is loaded, just spawn in
if game:IsLoaded() and (launchData == nil or launchData["pocket"] == nil) then
	fadeIn(2)
	return
end
	
-- If we have pocket launch data, do not fade into seeing the world, just
-- hold on for the teleport (but with a long delay in case it fails)
if launchData and launchData["pocket"] ~= nil then
	fadeIn(30)
	return
end

-- Otherwise, just fade in once the world is loaded
if not game:IsLoaded() then
	game.Loaded:Wait()
	fadeIn(2)
	return
end



