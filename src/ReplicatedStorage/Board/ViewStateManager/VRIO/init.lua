-- --[[
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- --]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HapticService = game:GetService("HapticService")
local VRService = game:GetService("VRService")

-- Imports
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local Config = metaboard.Config

local toolFunctions = require(script.toolFunctions)
local Pen = require(script.Pen)
local Eraser = require(script.Eraser)

local isVibrationSupported = HapticService:IsVibrationSupported(Enum.UserInputType.Gamepad1)
local rightRumbleSupported = false

if isVibrationSupported then
	rightRumbleSupported = HapticService:IsMotorSupported(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.RightHand)
end

local localPlayer = Players.LocalPlayer

local function toScalar(position, canvasCFrame, canvasSize)
	local projPos = canvasCFrame:ToObjectSpace(CFrame.new(position))
	local sizeX = canvasSize.X
	local sizeY = canvasSize.Y
	local relX = (-projPos.X + 0.5*sizeX)/sizeY
	local relY = (-projPos.Y + 0.5*sizeY)/sizeY
	return Vector2.new(relX,relY)
end

local function distanceToBoard(self, pos)
	local boardLookVector = self.props.Board.SurfaceCFrame.LookVector
	local vector = pos - self.props.Board.SurfaceCFrame.Position
	local normalDistance = boardLookVector:Dot(vector)
	return normalDistance
end

local function inRange(self, pos)
	local boardRightVector = self.props.Board.SurfaceCFrame.RightVector
	local vector = pos - self.props.Board.SurfaceCFrame.Position
	local strafeDistance = boardRightVector:Dot(vector)

	local normalDistance = distanceToBoard(self, pos)
	
	return (- 5 * self.PenActiveDistance <= normalDistance) and (normalDistance <= self.PenActiveDistance)
		and math.abs(strafeDistance) <= self.props.Board.SurfaceSize.X/2 + 5
end

return function (self)

	local connections = {}

	self.EquippedTool = Pen
	self.EraserSize = 0.05
	self.TriggerActiveConnection = nil
	self.ActiveStroke = false
	self.PenActiveDistance = 0.06

	table.insert(connections, UserInputService.InputBegan:Connect(function(input)
		if not VRService.VREnabled then return end
		if input.UserInputType ~= Enum.UserInputType.Gamepad1 then return end

		if input.KeyCode == Enum.KeyCode.ButtonL2 then
			self.EquippedTool = Eraser
		end

		if input.KeyCode == Enum.KeyCode.ButtonY then
			self.props.Board.Remotes.Undo:FireServer()
		end

		if input.KeyCode == Enum.KeyCode.ButtonX then
			self.props.Board.Remotes.Redo:FireServer()
		end

		if input.KeyCode == Enum.KeyCode.ButtonR2 then
			local boardTool = localPlayer.Character:FindFirstChild(Config.VR.PenToolName)
			if boardTool == nil then
				print("[metaboard] Cannot find VR tool")
				return
			end

			-- We connect to listen to VR pen movements as soon as the trigger is depressed
			-- even if it is too far from the board to draw.
			if inRange(self,boardTool.Handle.Attachment.WorldPosition) then
				self.ActiveStroke = true
				self:setState(function(state)
					return toolFunctions.ToolDown(self, state, toScalar(boardTool.Handle.Attachment.WorldPosition, self.props.Board.SurfaceCFrame, self.props.Board.SurfaceSize))
				end)
			end

			self.TriggerActiveConnection = RunService.RenderStepped:Connect(function()
				local penPos = boardTool.Handle.Attachment.WorldPosition

				if inRange(self,penPos) then
					if self.ActiveStroke then
						self:setState(function(state)
							return toolFunctions.ToolMoved(self, state, toScalar(penPos, self.props.Board.SurfaceCFrame, self.props.Board.SurfaceSize))
						end)
					else
					
						self.ActiveStroke = true
						self:setState(function(state)
							return toolFunctions.ToolDown(self, state, toScalar(penPos, self.props.Board.SurfaceCFrame, self.props.Board.SurfaceSize))
						end)
					end
				
					-- Rumble increases with distance *through* the board
					local distance = distanceToBoard(self,boardTool.Handle.Attachment.WorldPosition)
					if rightRumbleSupported then
						local motorStrength = 0
						if distance >= 0 then
							motorStrength = 0.1
						else
							motorStrength = 0.1 + 0.8 * math.tanh(-distance * 30)
						end
						HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.RightHand, motorStrength)
					end
				else
					if self.ActiveStroke then
						self:setState(function(state)
							return toolFunctions.ToolUp(self, state)
						end)

						self.ActiveStroke = false
						
						if rightRumbleSupported then
							HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.RightHand, 0)
						end
					end
				end
			end)
		end

	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if not VRService.VREnabled then return end
		if input.UserInputType ~= Enum.UserInputType.Gamepad1 then return end

		if input.KeyCode == Enum.KeyCode.ButtonL2 then
			self.EquippedTool = Pen
		end

		if input.KeyCode == Enum.KeyCode.ButtonR2 then
			if self.TriggerActiveConnection then self.TriggerActiveConnection:Disconnect() end
			self:setState(function(state)
				return toolFunctions.ToolUp(self, state)
			end)
			self.ActiveStroke = false

			if rightRumbleSupported then
				HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.RightHand, 0)
			end
		end

	end))

	return {

		Destroy = function ()

			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end

			if self.TriggerActiveConnection then self.TriggerActiveConnection:Disconnect() end
		end

	}

end