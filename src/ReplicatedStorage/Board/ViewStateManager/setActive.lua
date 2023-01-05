-- --[[
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- --]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Imports
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local Roact: Roact = require(ReplicatedStorage.Packages.Roact)
local e = Roact.createElement
local DrawingUI = metaboard.DrawingUI

local SurfaceCanvas = require(script.Parent.SurfaceCanvas)

return function(self, board, viewData)
	local oldViewData = viewData or {}

	local makeElement = function(whenLoaded, budgetThisFrame)

		return e(SurfaceCanvas, {

			Figures = board.Figures,
			DrawingTasks = board.DrawingTasks,
			BudgetThisFrame = budgetThisFrame,
			LineLoadFinishedCallback = whenLoaded,
			Board = board,

			WorkspaceTarget = self.CanvasesFolder,
			StorageTarget = self.CanvasStorage,

			--[[
				Make the surface clickable only if no other board is open.
			--]]
			OnSurfaceClick = self.OpenedBoard == nil and function()
				
				self.OpenedBoard = board
				
				DrawingUI(board, "Gui", function()
					-- This function is called when the Drawing UI is closed
					self.OpenedBoard = nil
					self:RefreshViewStates()
				end)
				
				self:RefreshViewStates()
			end,
		})
	end

	if oldViewData.Status == "Active" then
		Roact.update(oldViewData.Tree, makeElement(oldViewData.WhenLoaded, nil))
	else

		local newViewData = {}

		newViewData.WhenLoaded = function()
			if oldViewData.Destroy then
				oldViewData.Destroy()
			end
			newViewData.WhenLoaded = nil
		end

		newViewData.Tree = Roact.mount(makeElement(newViewData.WhenLoaded, nil), self.CanvasesFolder, board:FullName())

		local updateConnection = board.DataChangedSignal:Connect(function()
			if not newViewData.Paused then
				Roact.update(newViewData.Tree, makeElement(newViewData.WhenLoaded, nil))
			end
		end)

		newViewData.Status = "Active"
		newViewData.Destroy = function()
			updateConnection:Disconnect()
			Roact.unmount(newViewData.Tree)
			newViewData.Status = nil
			newViewData.Tree = nil
			newViewData.Destroy = nil
		end
		newViewData.LoadMore = function(budgetThisFrame)
			Roact.update(newViewData.Tree, makeElement(newViewData.WhenLoaded, budgetThisFrame))
		end

		return newViewData
	end

	return viewData
end