local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local function CreateTopbarItems()
    if true then
        return false
    end

	
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
		end),
        Icon.new()
		:setLabel("Decal for Board...")
		:bindEvent("selected", function(self)
			self:deselect()
			icon:deselect()
			StartBoardSelectMode(StartDecalEntryDisplay)
		end)
	}) 

	icon:setTheme(Themes["BlueGradient"])
end

return {
	Start = CreateTopbarItems,
}