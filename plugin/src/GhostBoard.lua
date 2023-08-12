local Selection = game:GetService("Selection")
local BaseObject = require(script.Parent.BaseObject)
local Fusion = require(script.Parent.Parent.Packages.Fusion)

local GhostBoard = setmetatable({}, BaseObject)
GhostBoard.__index = GhostBoard

function GhostBoard.new(initalCurvature, initialApart)
	local self = setmetatable(BaseObject.new(), GhostBoard)

	self._selectedBoard = Fusion.Value(nil)
	self._ghost = Fusion.Value(nil)
	self._curvature = initalCurvature
	self._apart = initialApart

	return self
end

function GhostBoard:Start()
	self:_updateSelectedBoard()
	self._maid:Connect("SelectionChanged", Selection.SelectionChanged, function()
		self:_updateSelectedBoard()
	end)
end

function GhostBoard:Stop()
	self._maid:Clean("SelectionChanged")
	self._selectedBoard:set(nil)
	local ghost = self._ghost:get(false)
	self._ghost:set(nil)
	if ghost then
		ghost:Destroy()
	end
end

function GhostBoard:render(props)

	local CurrentCamera = Fusion.Value(workspace.CurrentCamera)

	return Fusion.New "ScreenGui" {
		Name = "metauniToolsGhostViewer",
		Parent = props.Parent,
		[Fusion.Children] = {
			Fusion.New "ViewportFrame" {
				AnchorPoint = Vector2.new(0,0),
				Position = UDim2.fromScale(0,0),
				Size = UDim2.fromScale(1,1),
				CurrentCamera = CurrentCamera,
				BackgroundTransparency = 1,
				ImageTransparency = Fusion.Computed(function()
					return if props.Show:get() then 0.5 else 1
				end),
			
				[Fusion.Cleanup] = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
					CurrentCamera:set(workspace.CurrentCamera)
				end),

				[Fusion.Children] = {
					self._ghost
				},
			}
		},
	}
end

function GhostBoard:_updateSelectedBoard()
	local selections = Selection:Get()
	if #selections ~= 1 then
		self._selectedBoard:set(nil)
		self:_setNewGhost()
		return
	end
	
	local object = selections[1]
	if not object:IsA("BasePart") and not object:IsA("Model") then
		self._selectedBoard:set(nil)
	elseif object:IsA("Model") and object.PrimaryPart == nil then
		-- selene:allow(if_same_then_else)
		self._selectedBoard:set(nil)
	else
		self._selectedBoard:set(object)
	end

	self:_setNewGhost()
end

function GhostBoard:_setNewGhost()
	local oldGhost = self._ghost:get()
	if oldGhost then
		oldGhost:Destroy()
	end

	local selectedBoard = self._selectedBoard:get(false)
	local ghost = selectedBoard and selectedBoard:Clone() or nil

	if ghost then
		ghost.Name = "ghost-"..ghost.Name
		-- This messes with the PersistId board binder
		ghost:RemoveTag("metaboard")
		if ghost:IsA("Model") and ghost.PrimaryPart then
			ghost.PrimaryPart:RemoveTag("metaboard")
		end
	end

	self._ghost:set(ghost)
	
	if selectedBoard then
		self:_setCFrame(ghost)
		local primaryPart = selectedBoard:IsA("Model") and selectedBoard.PrimaryPart or selectedBoard
		self._maid:Connect("WatchBoardCFrame", primaryPart:GetPropertyChangedSignal("CFrame"), function()
			self:_setCFrame(self._ghost:get(false))
		end)
	else
		self._maid:Clean("WatchBoardCFrame")
	end
end

function GhostBoard:_setCFrame(target: Model | BasePart)
	if target and self._apart and self._curvature and self._side then
		local board: Model | Part = self._selectedBoard:get()
		assert(board, "Board should exist if target does on update")

		local sign = self._side == "left" and 1 or -1
		local apart: number = self._apart
		local boardCFrame = board:GetPivot()

		if self._curvature == "flat" then
			target:PivotTo(boardCFrame * CFrame.new(sign * apart, 0, 0))
		else
			local radius = self._curvature
			local toPivot = CFrame.new(0, 0, -radius)
			local ry = sign * apart/radius
			target:PivotTo(boardCFrame * toPivot * CFrame.Angles(0, ry, 0) * toPivot:Inverse())
		end
	end
end

function GhostBoard:SetCurvature(curvature: "flat" | number)
	self._curvature = curvature
	self:_setCFrame(self._ghost:get(false))
end

function GhostBoard:SetApart(apart: number)
	self._apart = apart
	self:_setCFrame(self._ghost:get(false))
end

function GhostBoard:SetSide(side: "left" | "right")
	self._side = side
	self:_setCFrame(self._ghost:get(false))
end

function GhostBoard:CreateCopyAtGhost()
	local board = self._selectedBoard:get(false)
	if not board then
		return
	end

	local clone = board:Clone()
	self:_setCFrame(clone)
	clone.Parent = board.Parent

	return clone
end

function GhostBoard:State()
	return self._ghost
end

return GhostBoard