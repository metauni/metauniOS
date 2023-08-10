local Plugin = plugin

local Packages = script.Parent.Packages
local PluginEssentials = require(Packages.PluginEssentials)

local Toolbar = PluginEssentials.Toolbar
local ToolbarButton = PluginEssentials.ToolbarButton

local Fusion = require(Packages.Fusion)

local App = require(script.App)

local pluginToolbar = Toolbar {
	Name = "metauni Tools",
}

local WidgetEnabled = Fusion.Value(false)
local toolbarButton = ToolbarButton {
	Toolbar = pluginToolbar,

	ClickableWhenViewportHidden = false,
	Name = "metauni Tools",
	ToolTip = "Toggle window",
	Image = "rbxassetid://14359367425",

	[Fusion.OnEvent "Click"] = function()
		WidgetEnabled:set(not WidgetEnabled:get())
	end,
}

Plugin.Unloading:Connect(Fusion.Observer(WidgetEnabled):onChange(function()
	toolbarButton:SetActive(WidgetEnabled:get(false))
end))

local app = App {
	WidgetEnabled = WidgetEnabled,
}
Plugin.Unloading:Connect(function()
	app:Destroy()
end)

