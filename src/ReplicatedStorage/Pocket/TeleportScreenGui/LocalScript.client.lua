local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local VRService = game:GetService("VRService")

local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
local rotationAngle = Instance.new("NumberValue")
local tweenComplete = false

local cameraOffset = Vector3.new(0, 30, 40)
local rotationTime = 40  -- Time in seconds
local rotationDegrees = 360
local rotationRepeatCount = -1  -- Use -1 for infinite repeats
local lookAtTarget = true  -- Whether the camera tilts to point directly at the target

-- In VR do nothing to the camera
if VRService.VREnabled then return end

-- If this is a normal teleport we simply rotate the camera from a distance
-- looking at the player location. If it is a pocket then we zoom in to
-- look at the entrance portal

StarterGui:SetCore("TopbarEnabled", false)

--local portalTarget = script.TeleportProgressScreenGui.Portal.Value
local portalTarget = nil

if portalTarget == nil then
	local target = Players.LocalPlayer.Character.PrimaryPart
	
	local function updateCamera()
		if not target then return end
		camera.Focus = target.CFrame
		local rotatedCFrame = CFrame.Angles(0, math.rad(rotationAngle.Value), 0)
		rotatedCFrame = CFrame.new(target.Position) * rotatedCFrame
		camera.CFrame = rotatedCFrame:ToWorldSpace(CFrame.new(cameraOffset))
		if lookAtTarget == true then
			camera.CFrame = CFrame.new(camera.CFrame.Position, target.Position)
		end
	end

	-- Set up and start rotation tween
	local tweenInfo = TweenInfo.new(rotationTime, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, rotationRepeatCount)
	local tween = TweenService:Create(rotationAngle, tweenInfo, {Value=rotationDegrees})
	tween.Completed:Connect(function()
		tweenComplete = true
	end)
	tween:Play()

	-- Update camera position while tween runs
	RunService.RenderStepped:Connect(function()
		if tweenComplete == false then
			updateCamera()
		end
	end)
else
	local targetPart = portalTarget.PrimaryPart
	local lookFrom = (targetPart.CFrame + 10 * targetPart.CFrame.LookVector).Position
	local lookTo = targetPart.CFrame.Position
	
	local tweenInfo = TweenInfo.new(
		5, -- Time
		Enum.EasingStyle.Quad, -- EasingStyle
		Enum.EasingDirection.Out, -- EasingDirection
		0, -- RepeatCount (when less than zero the tween will loop indefinitely)
		false, -- Reverses (tween will reverse once reaching it's goal)
		0 -- DelayTime
	)

	cameraTween = TweenService:Create(camera, tweenInfo, 
		{CFrame = CFrame.new(lookFrom, lookTo)})
	
	cameraTween:Play()
end