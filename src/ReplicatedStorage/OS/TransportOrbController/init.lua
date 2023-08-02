local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local VRService = game:GetService("VRService")

local Remotes = script.Remotes
local Config = require(script.Config)

local function getInstancePart(x)
	if x:IsA("BasePart") then return x end
	if x:IsA("Model") then return x.PrimaryPart end
	return nil
end

local TransportOrbController = {}

function TransportOrbController:Init()
	self.AttachedOrb = nil
	self.OrbSet = {}
	self.LuggageIcon = nil
end

function TransportOrbController:Start()
	self:CreateTopbarIcon()

	for _, orb in CollectionService:GetTagged(Config.TransportOrbTag) do
		self:SetupProximityPrompts(orb)
		self.OrbSet[orb] = true
	end
	
	CollectionService:GetInstanceAddedSignal(Config.TransportOrbTag):Connect(function(orb)
		self:SetupProximityPrompts(orb)
		self.OrbSet[orb] = true
	end)
	
	CollectionService:GetInstanceRemovedSignal(Config.TransportOrbTag):Connect(function(orb)
		self.OrbSet[orb] = nil
		-- TODO: destroy prompts behaviour was never implemented. is it necessary?
		-- because the prompts are parented to the orb
	end)
end

function TransportOrbController:SetupProximityPrompts(orb)
	local promptActivationDistance = 24
	if VRService.VREnabled then
		return
	end

	local orbPart = getInstancePart(orb)

	local prompt = orbPart:FindFirstChild("LuggagePrompt")
	if prompt ~= nil then
		prompt:Destroy()
	end

	prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LuggagePrompt"
	prompt.ActionText = "Attach as Luggage"
	prompt.MaxActivationDistance = promptActivationDistance
	prompt.HoldDuration = 1
	prompt.ObjectText = "Orb"
	prompt.RequiresLineOfSight = false
	prompt.Parent = orbPart

	prompt.Triggered:Connect(function(playerWhoTriggered)
		if playerWhoTriggered ~= Players.LocalPlayer then
			return
		end
		Remotes.TransportOrbAttach:FireServer(orb)
		
		if self.AttachedOrb then
			self:Detach()
		end
		self.AttachedOrb = orb
		self:RefreshAllPrompts()
    self:RefreshTopbarIcon()
	end)
end

function TransportOrbController:Detach()
	if not self.AttachedOrb then return end

	local orbPart = getInstancePart(self.AttachedOrb)
	local prompt = orbPart:FindFirstChild("LuggagePrompt")
	prompt.Enabled = true

	Remotes.TransportOrbDetach:FireServer(self.AttachedOrb)
	self.AttachedOrb = nil
end

function TransportOrbController:CreateTopbarIcon()
	-- luggage is https://fonts.google.com/icons?icon.query=luggage
	local luggageAssetId = "rbxassetid://9679458066"

	local Icon = require(game:GetService("ReplicatedStorage").Packages.Icon)
	local Themes =  require(game:GetService("ReplicatedStorage").Packages.Icon.Themes)
	
	self.LuggageIcon = Icon.new()
		:setImage(luggageAssetId)
		:setOrder(2)
		:setLabel("Luggage")
		:setTheme(Themes["BlueGradient"])
		:setEnabled(false)
		:bindEvent("deselected", function()
			self:Detach()
			self:RefreshTopbarIcon()
			self:RefreshAllPrompts()
		end)
	self.LuggageIcon.deselectWhenOtherIconSelected = false
end

function TransportOrbController:RefreshTopbarIcon()
	self.LuggageIcon:setEnabled(false)
	if self.AttachedOrb then
		self.LuggageIcon:setEnabled(true)
		self.LuggageIcon:select()
	else
		self.LuggageIcon:setEnabled(false)
	end
end

function TransportOrbController:RefreshAllPrompts()
	for orb in self.OrbSet do
		local orbPart = getInstancePart(orb)
	
		local luggagePrompt = orbPart:FindFirstChild("LuggagePrompt")
		if not luggagePrompt then
			return
		end
	
		if self.AttachedOrb == orb then
			luggagePrompt.Enabled = false
		else
			luggagePrompt.Enabled = true
		end
	end
end

return TransportOrbController