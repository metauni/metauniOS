local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Remotes = script.Parent.Remotes
local Config = require(script.Parent.Config)

local OrbAttachRemoteEvent = Remotes.OrbAttach
local OrbDetachRemoteEvent = Remotes.OrbDetach
local OrbListenOnRemoteEvent = Remotes.OrbListenOn
local OrbListenOffRemoteEvent = Remotes.OrbListenOff
local OrbcamOnRemoteEvent = Remotes.OrbcamOn
local OrbcamOffRemoteEvent = Remotes.OrbcamOff
local GetOrbcamStatusRemoteFunction = Remotes.GetOrbcamStatus
local GetListeningStatusRemoteFunction = Remotes.GetListeningStatus
local GetAttachmentsRemoteFunction = Remotes.GetAttachments
local OrbAttachSpeakerRemoteEvent = Remotes.OrbAttachSpeaker

local Attachments, ListeningStatus, OrbCamStatus

local Halos = {}
Halos.__index = Halos

function Halos.Init()
    -- Fired whenever someone attaches to an orb as listener or luggage
    -- Note that these halos are created on the client for every player (not
    -- just the local player)

    Attachments = GetAttachmentsRemoteFunction:InvokeServer()
    ListeningStatus = GetListeningStatusRemoteFunction:InvokeServer()
    OrbCamStatus = GetOrbcamStatusRemoteFunction:InvokeServer()

    local function attachHalo(plr, orb)
        if not plr.Character then return end
        if not orb then return end -- NOTE: may mean in game streaming you don't get halos

        -- Copy the rings from the orb
        local earRing = orb:FindFirstChild("EarRing")
        local eyeRing = orb:FindFirstChild("EyeRing")

        if earRing ~= nil then
            local whiteHalo = earRing:Clone()
            whiteHalo.Name = Config.WhiteHaloName
            whiteHalo.Transparency = 1
            whiteHalo.Parent = plr.Character

            -- Check to see if they are listening
            if ListeningStatus[tostring(plr.UserId)] then
                whiteHalo.Transparency = 0
            end
        end

        if eyeRing ~= nil then
            local blackHalo = eyeRing:Clone()
            blackHalo.Name = Config.BlackHaloName
            blackHalo.Transparency = 1
            blackHalo.Parent = plr.Character
            
            -- Check to see if they are watching
            if OrbCamStatus[tostring(plr.UserId)] then
                blackHalo.Transparency = 0
            end
        end
    end

    -- Create halos for players who attached before this client joined
    for _, plr in ipairs(Players:GetPlayers()) do
        local character = plr.Character
        if character then
            local orb = Attachments[tostring(plr.UserId)]
            if orb ~= nil then
                if not CollectionService:HasTag(orb, Config.TransportTag) then
                    attachHalo(plr, orb)
                end
            end
        end
    end

    OrbAttachSpeakerRemoteEvent.OnClientEvent:Connect(function(plr,orb)
        Attachments[tostring(plr.UserId)] = orb
    end)

    OrbAttachRemoteEvent.OnClientEvent:Connect(function(plr,orb)
        Attachments[tostring(plr.UserId)] = orb

        if CollectionService:HasTag(orb, Config.TransportTag) then return end

        attachHalo(plr, orb)
    end)

    -- Fired whenever someone detaches from an orb
    OrbDetachRemoteEvent.OnClientEvent:Connect(function(plr,orb)
        Attachments[tostring(plr.UserId)] = nil

        if CollectionService:HasTag(orb, Config.TransportTag) then return end

        local whiteHalo = plr.Character:FindFirstChild(Config.WhiteHaloName)
        local blackHalo = plr.Character:FindFirstChild(Config.BlackHaloName)
        if whiteHalo then
            whiteHalo:Destroy()
        end

        if blackHalo then
            blackHalo:Destroy()
        end
    end)

    OrbListenOnRemoteEvent.OnClientEvent:Connect(function(plr)
        if not plr then return end

        ListeningStatus[tostring(plr.UserId)] = true

        if not plr.Character then return end

        local whiteHalo = plr.Character:FindFirstChild(Config.WhiteHaloName)
        if whiteHalo then
            whiteHalo.Transparency = 0
        end
    end)

    OrbListenOffRemoteEvent.OnClientEvent:Connect(function(plr)
        if not plr then return end

        ListeningStatus[tostring(plr.UserId)] = false

        if not plr.Character then return end
        
        local whiteHalo = plr.Character:FindFirstChild(Config.WhiteHaloName)
        if whiteHalo then
            whiteHalo.Transparency = 1
        end
    end)

    OrbcamOnRemoteEvent.OnClientEvent:Connect(function(plr)
        if not plr then return end

        OrbCamStatus[tostring(plr.UserId)] = true

        if not plr.Character then return end

        local blackHalo = plr.Character:FindFirstChild(Config.BlackHaloName)
        if blackHalo then
            blackHalo.Transparency = 0
        end
    end)

    OrbcamOffRemoteEvent.OnClientEvent:Connect(function(plr)
        if not plr then return end

        OrbCamStatus[tostring(plr.UserId)] = false

        if not plr.Character then return end
        
        local blackHalo = plr.Character:FindFirstChild(Config.BlackHaloName)
        if blackHalo then
            blackHalo.Transparency = 1
        end
    end)

    -- Update the halo positions
	RunService.RenderStepped:Connect(function(delta)
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if character then
				local head = character:FindFirstChild("Head")
				local whiteHalo = character:FindFirstChild(Config.WhiteHaloName)
				local blackHalo = character:FindFirstChild(Config.BlackHaloName)

				if head and whiteHalo and blackHalo then
					whiteHalo.CFrame = head.CFrame * CFrame.new(0,Config.HaloOffset,0) * CFrame.Angles(0,0,math.pi/2) 
					blackHalo.CFrame = head.CFrame * CFrame.new(0,Config.HaloOffset,0) * CFrame.Angles(0,0,math.pi/2)
				end
			end
		end
	end)
end

return Halos