local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local OrbServer = require(script.OrbServer)
local OrbPlayer = require(script.OrbPlayer)
local Ring = require(script.Ring)
local Stream = require(ReplicatedStorage.Util.Stream)

local Service = {
	Orbs = {} :: { [Part]: OrbServer.OrbServer },
}

local function makeHaloTemplates()
	local earHalo: UnionOperation = Ring {
		Name = "EarHalo",
		Parent = script,
		Material = Enum.Material.Neon,
		Color = Color3.new(1, 1, 1),
		CastShadow = false,
		CanCollide = false,

		InnerDiameter = 1.5 + 0.1,
		OuterDiameter = 1.5 + 0.5,
	}

	local eyeHalo: UnionOperation = Ring {
		Name = "EyeHalo",
		Parent = script,
		Material = Enum.Material.Neon,
		Color = Color3.new(0, 0, 0),
		CastShadow = false,
		CanCollide = false,

		InnerDiameter = 1.5 + 0.5,
		OuterDiameter = 1.5 + 1,
	}

	local earWeld = Instance.new("WeldConstraint")
	earWeld.Part0 = earHalo
	earWeld.Parent = earHalo

	local eyeWeld = Instance.new("WeldConstraint")
	eyeWeld.Part0 = eyeHalo
	eyeWeld.Parent = eyeHalo
end

local function connectEvents()
	local Remotes = ReplicatedStorage.OS.OrbController.Remotes

	local function expectOrbServer(orbPart: Part, remote: string): OrbServer.OrbServer
		local orb = Service.Orbs[orbPart]
		if not orb then
			print(`[Service] {remote} called with orb {orbPart:GetFullName()}`)
			error(`[Service] Could not find orb server for part {orbPart:GetFullName()}`)
		end
		return orb
	end

	Remotes.SetSpeaker.OnServerEvent:Connect(function(player, orb)
		for otherOrb, orbServer in Service.Orbs do
			if otherOrb ~= orb then
				orbServer.DetachPlayer(player)
			end
		end
		expectOrbServer(orb, "SetSpeaker").SetSpeaker(player)
	end)

	Remotes.SetListener.OnServerEvent:Connect(function(player, orb)
		for otherOrb, orbServer in Service.Orbs do
			if otherOrb ~= orb then
				orbServer.DetachPlayer(player)
			end
		end
		expectOrbServer(orb, "SetListener").SetListener(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		for _, orbServer in Service.Orbs do
			orbServer.DetachPlayer(player)
		end
	end)

	local PlayerToOrb: Folder = ReplicatedStorage.OS.OrbController.PlayerToOrb

	Remotes.DetachPlayer.OnServerEvent:Connect(function(player, orb)
		local AttachedOrb: ObjectValue? = PlayerToOrb:FindFirstChild(tostring(player.UserId)) :: any
		if AttachedOrb then
			AttachedOrb.Value = nil
		end
		expectOrbServer(orb, "DetachPlayer").DetachPlayer(player)
	end)

	Remotes.SetViewMode.OnServerEvent:Connect(function(player, orb, viewMode)
		local orbServer = expectOrbServer(orb, "SetViewMode")
		if orbServer.Speaker.Value == player then
			orbServer.ViewMode.Value = viewMode
		end
	end)

	Remotes.SetShowAudience.OnServerEvent:Connect(function(player, orb, showAudience)
		local orbServer = expectOrbServer(orb, "SetShowAudience")
		if orbServer.Speaker.Value == player then
			orbServer.ShowAudience.Value = showAudience
		end
	end)

	Remotes.SendEmoji.OnServerEvent:Connect(function(player, orb, emoji)
		for _, orbValue in PlayerToOrb:GetChildren() do
			local userId = tonumber(orbValue.Name)
			local attachedPlayer = Players:GetPlayerByUserId(userId)
			if userId ~= player.UserId and attachedPlayer and orbValue.Value == orb then
				Remotes.SendEmoji:FireClient(attachedPlayer, emoji)
			end
		end
	end)

	Remotes.OrbcamStatus.OnServerEvent:Connect(function(player, orb)
		if game.Workspace.StreamingEnabled then
			player:RequestStreamAroundAsync(orb.Position)
		end
	end)

	Remotes.SetWaypointOnly.OnServerEvent:Connect(function(player, orb, waypointOnly)
		local orbServer = expectOrbServer(orb, "SetWaypointOnly")
		if orbServer.Speaker.Value == player then
			orbServer.WaypointOnly.Value = waypointOnly
		end
	end)
end

function Service.Start()
	makeHaloTemplates()

	-- We don't use waypoints anymore, but we must still hide them if they are there.
	for _, waypoint in CollectionService:GetTagged("metaorb_waypoint") do
		waypoint.Transparency = 1
		waypoint.Anchored = true
		waypoint.CanCollide = false
		waypoint.CastShadow = false
	end

	Stream.listenTidyEach(Stream.eachTagged("metaorb"), function(instance: Instance)
		if CollectionService:HasTag(instance, "metaorb_transport") then
			return nil
		end

		if not instance:IsA("BasePart") then
			error(`[Service] {instance:GetFullName()} is a Model. Must tag PrimaryPart with "metaorb".`)
		end

		local orb = OrbServer.new(instance :: any)
		Service.Orbs[instance] = orb
		return function()
			Service.Orbs[instance] = nil
			orb:Destroy()
		end
	end)

	Stream.listenTidyEach(Stream.eachPlayer, function(player: Player)
		return OrbPlayer(player)
	end)

	connectEvents()
end

return Service
