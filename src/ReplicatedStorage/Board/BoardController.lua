-- --[[
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- --]]

-- Services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")

-- Imports
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local Config = metaboard.Config
local BoardClient = require(script.Parent.BoardClient)
local Sift = require(ReplicatedStorage.Packages.Sift)
local SurfaceCanvas = require(script.Parent.SurfaceCanvas)
local BoardButton = require(script.Parent.BoardButton)
local VRInput = require(script.Parent.VRInput)

-- Constants
local LINE_LOAD_FRAME_BUDGET = 128

local BoardController = {}
BoardController.__index = BoardController

function BoardController:Init()
	
	self.Boards = {}
	self.SurfaceCanvases = {}
	self.BoardButtons = {}
	self.OpenedBoard = nil
	self.VRInputs = {}
end

function BoardController:Start()
	
	-- VR Chalk

	if VRService.VREnabled then
		task.spawn(function()
			local chalk = ReplicatedStorage.Chalk:Clone()
			chalk.Parent = Players.LocalPlayer:WaitForChild("Backpack")
		end)
	end

	-- Sort all the boards by proximity to the character every 0.5 seconds
	-- TODO: Holy smokes batman is this not optimised. We need a voronoi diagram and/or a heap.
	-- Must not assume that boards don't move around.
	
	task.spawn(function()
		
		while true do

			local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
			
			if character then
				
				local loading = Sift.Dictionary.filter(self.SurfaceCanvases, function(surfaceCanvas, instance)
					
					local surfacePart = instance:IsA("Model") and instance.PrimaryPart or instance

					local isLoading = surfacePart and surfacePart:IsDescendantOf(workspace) and surfaceCanvas.Loading

					return isLoading
				end)
			
				local characterPos = character:GetPivot().Position
				self._canvasLoadingQueue = {}

				-- Sort the loading canvases by distance and store them in self._canvasLoadingQueue
				do
					local nearestSet = {}

					while true do
						local minSoFar = math.huge
						local nearestCanvas = nil
						for _, surfaceCanvas in loading do
							if nearestSet[surfaceCanvas] then
								continue
							end

							local board = surfaceCanvas.Board
	
							local distance = (board.SurfaceCFrame.Position - characterPos).Magnitude
							if distance < minSoFar then
								nearestCanvas = surfaceCanvas
								minSoFar = distance
							end
						end
	
						if nearestCanvas then
							table.insert(self._canvasLoadingQueue, nearestCanvas)
							nearestSet[nearestCanvas] = true
						else
							break
						end
					end
				end
			end

			task.wait(0.5)
		end
	end)

	-- Constantly connect VRInput objects to whatever boards are "inRange"

	if VRService.VREnabled then

		local function inRange(board)

			if not board or not board._instance:IsDescendantOf(workspace) then
				return false
			end

			local boardLookVector = board.SurfaceCFrame.LookVector
			local boardRightVector = board.SurfaceCFrame.RightVector

			local character = Players.LocalPlayer.Character
			if character then
				local characterVector = character:GetPivot().Position - board.SurfaceCFrame.Position
				local normalDistance = boardLookVector:Dot(characterVector)

				local strafeDistance = boardRightVector:Dot(characterVector)
				return (0 <= normalDistance and normalDistance <= 20) and math.abs(strafeDistance) <= board.SurfaceSize.X/2 + 5
			end
		end
			

		task.spawn(function()
			
			while true do

				-- Destroy VRInputs out of range of board or for dead boards

				self.VRInputs = Sift.Dictionary.filter(self.VRInputs, function(vrInput, instance)
					
					local surfaceCanvas = self.SurfaceCanvases[instance]

					if not surfaceCanvas or not inRange(self.Boards[instance]) then
						vrInput:Destroy()

						if surfaceCanvas then
							surfaceCanvas:render()
						end
						return false
					end
					return true
				end)

				-- Add new VRInputs that are in range

				for instance, surfaceCanvas in self.SurfaceCanvases do

					if self.VRInputs[instance] then
						continue
					end

					local isInRange = inRange(surfaceCanvas.Board)
		
					if isInRange then
						self.VRInputs[instance] = VRInput.new(surfaceCanvas.Board, surfaceCanvas)
					end
				end
	
				task.wait(1)
			end
		end)
	end

	-- Load Surface Canvases gradually, prioritised by proximity and visibility

	RunService.Heartbeat:Connect(function()

		local closestLoading
		local closestInFOV
		local closestVisible
		
		for _, surfaceCanvas in ipairs(self._canvasLoadingQueue) do

			local board = surfaceCanvas.Board
			
			if surfaceCanvas.Loading then
				closestLoading = closestLoading or surfaceCanvas

				local boardPos = board.SurfaceCFrame.Position
				local _, inFOV = workspace.CurrentCamera:WorldToViewportPoint(boardPos)
				
				if inFOV then
					closestInFOV = closestInFOV or surfaceCanvas

					if board.SurfaceCFrame.LookVector:Dot(workspace.CurrentCamera.CFrame.LookVector) < 0 then
						closestVisible = closestVisible or surfaceCanvas
						break
					end
				end
			end
		end

		local canvasToLoad = closestVisible or closestInFOV or closestLoading
		if canvasToLoad then
			canvasToLoad:LoadMore(LINE_LOAD_FRAME_BUDGET)
		end
	end)

	--------------------------------------------------------------------------------
	
	local function bindInstanceAsync(instance)
	
		-- Ignore if already seen this board or it's in the PlayerGui
		if self.Boards[instance] or instance:IsDescendantOf(Players.LocalPlayer.PlayerGui) then
			return
		end
	
		if not instance:GetAttribute("BoardServerInitialised") then
			
			instance:GetAttributeChangedSignal("BoardServerInitialised"):Wait()
		end
	
		local board = BoardClient.new(instance)
		
		local data = board.Remotes.GetBoardData:InvokeServer()
		
		board:LoadData(data)
		
		board:ConnectRemotes()
	
		self.Boards[instance] = board
		self.SurfaceCanvases[instance] = SurfaceCanvas.new(board)
		self.BoardButtons[instance] = BoardButton.new(board, self.OpenedBoard == nil, function()
			
			-- This is the default function called when the boardButton is clicked.
			-- Can be temporarily overwritten by setting boardButton.OnClick

			for _, boardButton in self.BoardButtons do
				boardButton:SetActive(false)
			end
			
			metaboard.DrawingUI(board, "Gui", function()
				-- This function is called when the Drawing UI is closed
				self.OpenedBoard = nil
				for _, boardButton in self.BoardButtons do
					boardButton:SetActive(true)
				end
			end)

			self.OpenedBoard = board
		end)
	end
	
	-- Bind regular metaboards
	
	for _, instance in ipairs(CollectionService:GetTagged(Config.BoardTag)) do
		
		task.spawn(bindInstanceAsync, instance)
	end
	
	CollectionService:GetInstanceAddedSignal(Config.BoardTag):Connect(bindInstanceAsync)
	
	-- TODO: Think about GetInstanceRemovedSignal (destroying metaboards)
	
	-- Bind personal boards
	
	for _, instance in ipairs(CollectionService:GetTagged("metaboard_personal_board")) do
		
		task.spawn(bindInstanceAsync, instance)
	end
	
	CollectionService:GetInstanceAddedSignal("metaboard_personal_board"):Connect(function(instance)
			
		bindInstanceAsync(instance)
	end)

	local function onRemoved(instance)
		
		local boardButton = self.BoardButtons[instance]
		local surfaceCanvas = self.SurfaceCanvases[instance]
		local board = self.Boards[instance]
		
		if boardButton then
			boardButton:Destroy()
		end
		if surfaceCanvas then
			surfaceCanvas:Destroy()
		end
		if board then
			board:Destroy()
		end

		self.BoardButtons[instance] = nil
		self.SurfaceCanvases[instance] = nil
		self.Boards[instance] = nil
	end

	CollectionService:GetInstanceRemovedSignal(Config.BoardTag):Connect(onRemoved)
	CollectionService:GetInstanceRemovedSignal("metaboard_personal_board"):Connect(onRemoved)
end

return BoardController
