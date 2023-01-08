-- --[[
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- --]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Imports
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local Config = metaboard.Config
local FreeHand = metaboard.FreeHand

return {
	newDrawingTask = function(self)
		local taskId = Config.GenerateUUID()
		local stroke = {
			Width = 0.001,
			ShadedColor = {
				Color = Color3.new(1,1,1),
				BaseName = "White",
			}
		}
		local color = stroke.ShadedColor.Color

		return FreeHand.new(taskId, color, stroke.Width)
	end,
}