-- --[[
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- --]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Imports
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local PartCanvas = metaboard.PartCanvas
local Feather = require(ReplicatedStorage.Packages.Feather)
local Roact: Roact = require(ReplicatedStorage.Packages.Roact)
local e = Roact.createElement

--[[
	Wraps the feather-based PartCanvas in a Roact component
--]]
local WrapPartCanvas = Roact.Component:extend("WrapPartCanvas")

function WrapPartCanvas:init()
	
	self.ModelRef = Roact.createRef()
end

function WrapPartCanvas:render()
	
	return e("Model", {

		[Roact.Ref] = self.ModelRef,
	})
end

function WrapPartCanvas:didMount()
	
	self.Canvas = Feather.mount(Feather.createElement(PartCanvas, self.props), self.ModelRef:getValue(), "Feather Canvas")
end

function WrapPartCanvas:didUpdate(prevProps, prevState)

	Feather.update(self.Canvas, Feather.createElement(PartCanvas, self.props))
end

function WrapPartCanvas:willUnmount()

	Feather.unmount(self.Canvas)
end

return WrapPartCanvas