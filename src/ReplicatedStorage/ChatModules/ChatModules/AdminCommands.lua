local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local DataStore = game:GetService("DataStoreService")
local GroupService = game:GetService("GroupService")

local Settings = {
	Prefix = "/", -- Symbol that lets the script know the message is a command
	DebugMode = false, -- Set to true when making new commands so it's easier to identify errors
	DefaultPerm = 0,
	ScribePerm = 50, -- Can be overwritten by Roblox group settings
	AdminPerm = 254, -- Can be overwritten by Roblox group settings
	BanKickMessage = "You have been banned by an admin.",
	BanOnJoinMessage = "You are banned.",
    DataStoreTag = "v2.",
}

local permissions = {}
local scribeOnlyMode = true -- by default boards are off for guests
local robloxGroupId = 0

local remoteFunctions = {}
local remoteEvents = {}

local function isPrivateServer()
	return (game.PrivateServerId ~= "")
end

local function isPocket()
	return (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0)
end

--
-- DataStores
--

local dataStoreKey

if not isPrivateServer() then
	dataStoreKey = "permissionsDataStore"
else

	local Pocket = ReplicatedStorage:WaitForChild("Pocket")
	if Pocket and isPocket() then

		if Pocket:GetAttribute("PocketId") == nil then
			Pocket:GetAttributeChangedSignal("PocketId"):Wait()
		end

		local pocketId = Pocket:GetAttribute("PocketId")

		if pocketId then
			print("[MetaAdmin] Loading permissions for pocket")
			dataStoreKey = "metadmin." .. pocketId
		else
			print("[MetaAdmin] In a pocket but could not find PocketId, disabling admin commands.")
			return
		end

	else

		print("[MetaAdmin] Loading permissions for private server")
		dataStoreKey = "metadmin." .. game.PrivateServerOwnerId
	end
end

local permissionsDataStore = DataStore:GetDataStore(dataStoreKey)

-- Get permissions database
local success
success, permissions = pcall(function()
    return permissionsDataStore:GetAsync(Settings.DataStoreTag.."permissions") or {}
end)
if not success then
    print("[MetaAdmin] Failed to read permissions from DataStore")
    permissions = {}
end

-- NOTE: scribeOnlyMode is now fixed ON
-- Get scribeOnlyMode
--[[ success, scribeOnlyMode = pcall(function()
    return permissionsDataStore:GetAsync(Settings.DataStoreTag.."scribeOnlyMode") or false
end)
if not success then
    print("[MetaAdmin] Failed to read scribeOnlyMode from DataStore")
    scribeOnlyMode = false
end --]]

-- If scribeOnlyMode has not been set, we leave it with the default
if scribeOnlyMode == true then
    print("[MetaAdmin] Whiteboards deactivated for guests on startup")
elseif scribeOnlyMode == false then
    print("[MetaAdmin] Whiteboards activated for guests on startup")
end

-- Get robloxGroupId
success, robloxGroupId = pcall(function()
    return permissionsDataStore:GetAsync(Settings.DataStoreTag.."robloxGroupId") or 0
end)
if not success then
    print("[MetaAdmin] Failed to read robloxGroupId from DataStore")
    robloxGroupId = 0
end

local function PrintDebuggingInfo()
	local countAdmin = 0
	local countGuest = 0
	local countBanned = 0
	for userIdStr, level in pairs(permissions) do
		if level >= Settings.AdminPerm then
			countAdmin += 1
		elseif isBanned(userIdStr) then
			countBanned += 1
		else
			countGuest += 1
		end
	end

	print("Loaded permissions table with "..(countAdmin + countBanned + countGuest).." entries.")
	print("[MetaAdmin] "..countAdmin.." admins, "..countBanned.." banned, and "..countGuest.." others." )
    print("UserId | Permissions Level")
    print("-------------------")
    for userIdStr, level in pairs(permissions) do
        print(userIdStr, level)
    end
end

--Gets the permission level of the player from their player object
function GetPermLevel(userId)
	local permission = permissions[tostring(userId)]

	if permission then
		return permission
	else
		return Settings.DefaultPerm
	end
end

function GetPermLevelPlayer(player)
	return GetPermLevel(player.UserId)
end

function isBanned(userId)
	return GetPermLevel(userId) < Settings.DefaultPerm
end

function isAdmin(userId)
	return GetPermLevel(userId) >= Settings.AdminPerm
end

function isScribe(userId)
    return GetPermLevel(userId) >= Settings.ScribePerm
end

-- Everyone can write on whiteboards, unless
-- they are turned off in which case only scribes
-- or above can write
function canWriteOnWhiteboards(userId)
    local permLevel = GetPermLevel(userId)

    if scribeOnlyMode then
        return permLevel >= Settings.ScribePerm
    else
        return true
    end
end

--Sets the permission level of the speaker
function SetPermLevel(userId, level)
	permissions[tostring(userId)] = level
end

-- Tells the player to update their local knowledge of the permissions
function UpdatePerms(userId)
    local player = nil
	local success, response = pcall(function() player = Players:GetPlayerByUserId(tonumber(userId)) end)
	if player then
        if remoteEvents["PermissionsUpdate"] then remoteEvents["PermissionsUpdate"]:FireClient(player) end
		UpdateAttributes(player)
	end
end

function SetBanned(userId)
	SetPermLevel(userId, -1)
end

function SetDefault(userId)
	SetPermLevel(userId, Settings.DefaultPerm)
end

local function LoadPlayerPermissionsFromGroup(player, groupId)
    if not groupId or not player or groupId == 0 then return end

    local success, groups = pcall(function()
        return GroupService:GetGroupsAsync(player.UserId)
    end)
    if success then
        for _, group in ipairs(groups) do
            if group["Id"] == groupId then
                -- The player is a member of the group that owns this experience
                -- and so we just use their group rank here
                local playerRank = group["Rank"]
                SetPermLevel(player.UserId, playerRank)
                print("[MetaAdmin] Found player ".. player.Name.." in group, assigning rank "..tostring(playerRank))
            end
        end
    else
        print("[MetaAdmin] Failed to query player's groups")
    end
end

local function LoadPermissionsFromGroup(groupId)
    if not robloxGroupId or robloxGroupId == 0 then return end

    for _, player in pairs(Players:GetPlayers()) do
        LoadPlayerPermissionsFromGroup(player, robloxGroupId)
    end
end

local function LoadSettingsFromGroup(groupId)
    if groupId == 0 then
        Settings.ScribePerm = 50
        Settings.AdminPerm = 254
        return
    end

    local success, response = pcall(function()
        return GroupService:GetGroupInfoAsync(groupId)
    end)
    if success then
        if response and response.Roles then
            for _, role in ipairs(response.Roles) do
                if role.Name == "Scribe" then
                    -- Overwrite settings for scribes
                    Settings.ScribePerm = role.Rank
                end

                if role.Name == "Admin" then
                    -- Overwrite settings for admins
                    Settings.AdminPerm = role.Rank
                end
            end
        end
    else
        print("[MetaAdmin] Failed to get group info")
    end
end

game:BindToClose(function()
	local countAdmin = 0
	local countGuest = 0
	local countBanned = 0
	for userIdStr, level in pairs(permissions) do
		if level >= Settings.AdminPerm then
			countAdmin += 1
		elseif isBanned(userIdStr) then
			countBanned += 1
		else
			countGuest += 1
		end
	end

	--print("Writing "..(countAdmin + countBanned + countGuest).." permission entries to Data Store")
	--print(countAdmin.." admins, "..countBanned.." banned, and "..countGuest.." others." )
    local success, errormessage

    success, errormessage = pcall(function()
        return permissionsDataStore:SetAsync(Settings.DataStoreTag.."permissions", permissions)
    end)
    if not success then
        print("[MetaAdmin] Failed to store permissions")
        print(errormessage)
    end

	success, errormessage = pcall(function()
        return permissionsDataStore:SetAsync(Settings.DataStoreTag.."scribeOnlyMode", scribeOnlyMode)
    end)
    if not success then
        print("[MetaAdmin] Failed to store scribeOnlyMode")
        print(errormessage)
    end

    success, errormessage = pcall(function()
        return permissionsDataStore:SetAsync(Settings.DataStoreTag.."robloxGroupId", robloxGroupId)
    end)
    if not success then
        print("[MetaAdmin] Failed to store robloxGroupId")
        print(errormessage)
    end
end)

Players.PlayerAdded:Connect(function(player)
    -- Handle banning
	if isBanned(player.UserId) then
		print("[MetaAdmin] Kicked "..player.Name.." because they are banned. UserId: "..player.UserId..", Permission Level: "..GetPermLevel(player.UserId))
		player:Kick(Settings.BanOnJoinMessage)
		return
    end

    -- If a group is set, load permissions for this user
    if robloxGroupId ~=0 then
        LoadPlayerPermissionsFromGroup(player, robloxGroupId)
    end

    if Settings.DebugMode then
        PrintDebuggingInfo()
    end
end)

-- ##############################################################

function SendMessageToClient(data, speakerName)
	local ChatService = require(ServerScriptService.ChatServiceRunner.ChatService)
	-- The ChatService can also be found in the ServerScriptService
	local Speaker = ChatService:GetSpeaker(speakerName)
	-- The speaker is another module script in the ChatServiceRunner that has functions related to the speaker and some other things
	local extraData = {Color = data.ChatColor} -- Sets the color of the message
	Speaker:SendSystemMessage(data.Text, "All", extraData)
	-- Sends a private message to the speaker
end

-- Returns nil if user Id can't be found
-- Happens when GetUserIdFromNameAsync raises an error
function GetUserId(name)
	local player = Players:FindFirstChild(name)

	if player then
		return player.UserId
	else
		local userId = nil
		local success, reponse = pcall(function() userId = Players:GetUserIdFromNameAsync(name) end)
		if success then
			return userId
		else
			return nil
		end
	end
end

function UpdateAttributes(plr)
	if plr == nil then return end
	local userId = plr.UserId

	plr:SetAttribute("metaadmin_canwrite",canWriteOnWhiteboards(userId))
	plr:SetAttribute("metaadmin_isscribe",isScribe(userId))
	plr:SetAttribute("metaadmin_isadmin",isAdmin(userId))
end

function GetPermLevelName(name)
	local userId = GetUserId(name)

	if userId then
		return GetPermLevel(userId)
	else
		return Settings.DefaultPerm
	end
end

function GetTarget(player, msg)
	local msgl = msg:lower()
	local ts = {} -- Targets table

	if msgl == "all" then
		--// Loop through all players and add them to the targets table
		for i, v in pairs(Players:GetPlayers()) do
			table.insert(ts, v)
		end
	elseif msgl == "others" then
		--// Loops through all players and only adds them to the targets table if they aren't the player
		for i, v in pairs(Players:GetPlayers()) do
			if v.Name ~= player.Name then
				table.insert(ts, v)
			end
		end
	elseif msgl == "guests" then
		--// Loops through all players and only adds them to the targets table if they aren't the player
		for i, v in pairs(Players:GetPlayers()) do
			if GetPermLevel(v) < Settings.AdminPerm then
				table.insert(ts, v)
			end
		end
	elseif msgl == "me" then
		--// Loops through all players and only adds them to the targets table if they are the player
		for i, v in pairs(Players:GetPlayers()) do
			if v.Name == player.Name then
				table.insert(ts, v)
			end
		end
	else
		for i, v in pairs(Players:GetPlayers()) do
			if v.Name == msg then
				table.insert(ts, v)
			end
		end
	end
	return ts
end

local commands = {}

local function getHelpMessage()
	local message = "Admin Commands:\n--------------"
	for commandName, data in pairs(commands) do
		if data.usage then
			message = message.."\n"..data.usage
			if data.brief then
				message = message.."\n  "..data.brief
			end
		end
	end
	message = message.."\nUse /<command>? for more info about a command, e.g. /ban?"
	return message
end

local function sendCommandHelp(speakerName, commandName)
	local data = commands[commandName]
	if data then
		local message = ""
		if data.usage then
			message = data.usage
			if data.help then
				message = message.."\n  "..data.help
			elseif data.brief then
				message = message.."\n  "..data.brief
			end

			if data.examples then
				message = message.."\nExamples:"
				for _, example in ipairs(data.examples) do
					message = message.."\n  "..example
				end
			end

			SendMessageToClient({
				Text = message;
				ChatColor = Color3.new(0, 1, 0)
			}, speakerName)
		end
	end
end

-- Adds a new command to the commands table
function BindCommand(data)
	commands[data.name] = data
end

function BindCommands()

	BindCommand(
		{	name = "kick",
			usage = Settings.Prefix.."kick <name> [reason]",
			brief = "Kick a player, with an optional message",
			help = "Kick a player, with an optional message. This will instantly remove them from the game, but they can rejoin again immediately.",
			examples = {Settings.Prefix.."kick newton bye bye"},
			perm = Settings.AdminPerm,
			func = function(speaker, args)
				local commandTargets = GetTarget(speaker, args[1])

				if #commandTargets == 0 then
					-- No target was specified so we can't do anything
					SendMessageToClient({
						Text = "No targets specified";
						ChatColor = Color3.new(1, 0, 0)
					}, speaker.Name)
					return false
				end

				local kick_message = table.concat(args, " ")
				kick_message = kick_message:sub(#args[1]+2)

				for _, target in pairs(commandTargets) do
					-- Loop through targets table
					local targetPerm = GetPermLevelPlayer(target)
					local speakerPerm = GetPermLevelPlayer(speaker)
					if targetPerm < speakerPerm or speaker == target then
						target:Kick(kick_message)
						SendMessageToClient({
							Text = "Kicked "..target.Name;
							ChatColor = Color3.new(0, 1, 0)
						}, speaker.Name)
					else
						-- People of lower ranks can't use it on higher ranks or people of the same rank
						SendMessageToClient({
							Text = "You cannot use this command on "..target.Name..". They outrank you.";
							ChatColor = Color3.new(1, 0, 0)
						}, speaker.Name)
					end


				end
			end
		})

	BindCommand(
		{	name = "warn",
			usage = Settings.Prefix.."warn <name> [reason]",
			brief = "Warn a player, with an optional message",
			help = "Warn a player, with an optional message. This will move them to the spawn location and show them a warning message.",
			examples = {Settings.Prefix.."warn newton be less disruptive"},
			perm = Settings.AdminPerm,
			func = function(speaker, args)
				local commandTargets = GetTarget(speaker, args[1])

				if #commandTargets == 0 then
					-- No target was specified so we can't do anything
					SendMessageToClient({
						Text = "No targets specified";
						ChatColor = Color3.new(1, 0, 0)
					}, speaker.Name)
					return false
				end

				local kick_message = table.concat(args, " ")
				kick_message = kick_message:sub(#args[1]+2)

				for _, target in pairs(commandTargets) do
					-- Loop through targets table
					local targetPerm = GetPermLevelPlayer(target)
					local speakerPerm = GetPermLevelPlayer(speaker)
					if targetPerm < speakerPerm or speaker == target then
						if remoteEvents["WarnPlayer"] then
							remoteEvents["WarnPlayer"]:FireClient(target)
						end

						SendMessageToClient({
							Text = "Warned "..target.Name;
							ChatColor = Color3.new(0, 1, 0)
						}, speaker.Name)
					else
						-- People of lower ranks can't use it on higher ranks or people of the same rank
						SendMessageToClient({
							Text = "You cannot use this command on "..target.Name..". They outrank you.";
							ChatColor = Color3.new(1, 0, 0)
						}, speaker.Name)
					end
				end
			end
		})

	BindCommand({
		name = "banstatus",
		perm = Settings.AdminPerm,
		usage = Settings.Prefix.."banstatus <name>...",
		brief = "Check if a user is banned or not",
		help = "Check if a user is banned or not. Also shows permission level",
		func = function(speaker, args)
			if #args == 0 then
				SendMessageToClient({
					Text = "No arguments given.";
					ChatColor = Color3.new(1, 0, 0)
				}, speaker.Name)
				return false
			end

			for _, name in ipairs(args) do
				local userId = GetUserId(name)
				if userId then
					if isBanned(userId) then
						SendMessageToClient({
							Text = name.." is banned (User ID: "..userId.." ).";
							ChatColor = Color3.new(1, 0, 0)
						}, speaker.Name)
					else
						SendMessageToClient({
							Text = name.." is not banned (User ID: "..userId..", Permission level: "..GetPermLevel(userId)..").";
							ChatColor = Color3.new(0, 1, 0)
						}, speaker.Name)
					end
				else
					SendMessageToClient({
						Text = "Unable to get User Id of player with name: "..name;
						ChatColor = Color3.new(1, 0, 0)
					}, speaker.Name)
				end
			end
		end
	})

    BindCommand({
		name = "setrobloxgroup",
		perm = Settings.AdminPerm,
		usage = Settings.Prefix.."setrobloxgroup <groupId>",
		brief = "Set Roblox group",
		help = "Set Roblox group. If set, this group's ranks will be imported as permissions to this experience. Set to zero to disable.",
		examples = {Settings.Prefix.."setrobloxgroup 29199290"},
		func = function(speaker, args)

			if #args == 0 then
				SendMessageToClient({
					Text = "No arguments given.";
					ChatColor = Color3.new(1, 0, 0)
				}, speaker.Name)
				return false
			end

            local groupId = tonumber(args[1])

            if groupId == nil then
				SendMessageToClient({
					Text = "The second argument to this command must be an integer";
					ChatColor = Color3.new(1, 0, 0)
				}, speaker.Name)
				return false
			end

            -- groupId checks out, set the Roblox group and update settings
            robloxGroupId = groupId
            LoadSettingsFromGroup(groupId)
            LoadPermissionsFromGroup(groupId)

            SendMessageToClient({
                Text = "Roblox group set to "..groupId..".";
                ChatColor = Color3.new(0, 1, 0)
            }, speaker.Name)
		end
	})

	BindCommand({
		name = "ban",
		perm = Settings.AdminPerm,
		usage = Settings.Prefix.."ban <name>...",
		brief = "Ban 1 or more players",
		help = "Ban 1 or more players. Lowers their stored permission level below the ban threshold. They are instantly kicked and will be re-kicked every time they rejoin.",
		examples = {Settings.Prefix.."ban euler", Settings.Prefix.."ban leibniz gauss"},
		func = function(speaker, args)

			if #args == 0 then
				SendMessageToClient({
					Text = "No arguments given.";
					ChatColor = Color3.new(1, 0, 0)
				}, speaker.Name)
				return false
			end

			for _, name in ipairs(args) do
				local userId = GetUserId(name)
				if userId then
					if isAdmin(userId) then
						SendMessageToClient({
							Text = "You cannot ban an admin.";
							ChatColor = Color3.new(1, 0, 0)
						}, speaker.Name)
					else
						SetBanned(userId)
						local player = Players:GetPlayerByUserId(userId)
						if player then
							player:Kick(Settings.BanKickMessage)
							SendMessageToClient({
								Text = "User Id "..userId.." of "..name.." banned. They were kicked from this game.";
								ChatColor = Color3.new(0, 1, 0)
							}, speaker.Name)
						else
							SendMessageToClient({
								Text = name.." banned (UserId: "..userId.."). They were not found in this game, so have not been kicked.";
								ChatColor = Color3.new(0, 1, 0)
							}, speaker.Name)
						end
					end
				else
					SendMessageToClient({
						Text = "Unable to get User Id of player with name: "..name;
						ChatColor = Color3.new(1, 0, 0)
					}, speaker.Name)
				end
			end
		end
	})

	BindCommand({
		name = "unban",
		perm = Settings.AdminPerm,
		usage = Settings.Prefix.."unban <name>...",
		brief = "Unban 1 or more players",
		help = "Unban 1 or more players. Raises their permission level to the default/guest level if they are banned.",
		examples = {Settings.Prefix.."unban euler", Settings.Prefix.."unban leibniz gauss"},
		func = function(speaker, args)

			if #args == 0 then
				SendMessageToClient({
					Text = "No arguments given.";
					ChatColor = Color3.new(1, 0, 0)
				}, speaker.Name)
				return false
			end

			for _, name in ipairs(args) do
				local userId = GetUserId(name)

				if userId then
					if isBanned(userId) then
						SetDefault(userId)
						SendMessageToClient({
							Text = name.." unbanned (UserId: "..userId..", Permission level: "..tostring(GetPermLevel(userId))..").";
							ChatColor = Color3.new(0, 1, 0)
						}, speaker.Name)
					else
						SendMessageToClient({
							Text = name.." is already not banned (UserId: "..userId..", Permission level: "..tostring(GetPermLevel(userId))..")";
							ChatColor = Color3.new(1, 0, 0)
						}, speaker.Name)
					end
				else
					SendMessageToClient({
						Text = "Unable to get User Id of player with name: "..name;
						ChatColor = Color3.new(1, 0, 0)
					}, speaker.Name)
				end
			end
		end})

	BindCommand({
		name = "boards",
		perm = Settings.AdminPerm,
		usage = Settings.Prefix.."boards {on|off}",
		brief = "Turn the whiteboards on/off for guests (anyone below scribe level)",
		help = "'"..Settings.Prefix.."boards off' deactivates drawing on whiteboards for guests, and anyone with permission level below 'scribe'.\n'"..Settings.Prefix.."boards on' allows anyone to draw on whiteboards",
		examples = {Settings.Prefix.."boards off", Settings.Prefix.."boards on"},
		func = function(speaker, args)
			local activateMode = true

			if args[1] then
				if args[1]:lower() == "off" then
					activateMode = false
					scribeOnlyMode = true
				elseif args[1]:lower() == "on" then
					activateMode = true
					scribeOnlyMode = false
				else
					return false
				end
			else
				return false
			end

			for _, plr in ipairs(Players:GetPlayers()) do
                UpdatePerms(plr.UserId)
			end

			local actionWord = "???"
			if activateMode then
				actionWord = "activated"
			else
				actionWord = "deactivated"
			end

			SendMessageToClient({
				Text = "whiteboards "..actionWord.." for guests";
				ChatColor = Color3.new(0, 1, 0)
			}, speaker.Name)
		end
	})

	local function setLevel(level)
		return (function(speaker, args)
			if #args == 0 then
				return false
			end

			for _, name in ipairs(args) do
				local userId = GetUserId(name)

				if userId then
					SetPermLevel(userId, level)
                    UpdatePerms(userId)

					SendMessageToClient({
						Text = name.." given permission level "..tostring(level);
						ChatColor = Color3.new(0, 1, 0)
					}, speaker.Name)
				else
					SendMessageToClient({
						Text = "Unable to get User Id of player with name: "..name;
						ChatColor = Color3.new(1, 0, 0)
					}, speaker.Name)
				end
			end
		end)
	end

	BindCommand({
		name = "setadmin",
		perm = Settings.AdminPerm,
		usage = Settings.Prefix.."setadmin <name>...",
		brief = "Set the permission level of 1 or more players to admin",
		help = "Set the permission level of 1 or more players to admin. This will be overwritten on restart if their permission level is hardcoded.",
		examples = {Settings.Prefix.."setadmin euler", Settings.Prefix.."setadmin leibniz gauss"},
		func = setLevel(Settings.AdminPerm)})
	BindCommand({
		name = "setscribe",
		perm = Settings.AdminPerm,
		usage = Settings.Prefix.."setscribe <name>...",
		brief = "Set the permission level of 1 or more players to scribe",
		help = "Set the permission level of 1 or more players to scribe. This will be overwritten on restart if their permission level is hardcoded.",
		examples = {Settings.Prefix.."setscribe euler", Settings.Prefix.."setscribe leibniz gauss"},
		func = setLevel(Settings.ScribePerm)})
	BindCommand({
		name = "setscribeall",
		perm = Settings.AdminPerm,
		usage = Settings.Prefix.."setscribeall",
		brief = "Set the permission level all present players to scribe",
		help = "Set the permission level all present players to scribe",
		examples = {Settings.Prefix.."setscribeall"},
		func = function(speaker)
			SendMessageToClient({
				Text = "All present players given scribe permissions";
				ChatColor = Color3.new(0, 1, 0)
			}, speaker.Name)

			for _, plr in ipairs(Players:GetPlayers()) do
				SetPermLevel(plr.UserId, Settings.ScribePerm)
                UpdatePerms(plr.UserId)
			end
		end
	})
	BindCommand({
		name = "setguest",
		perm = Settings.AdminPerm,
		usage = Settings.Prefix.."setguest <name>...",
		brief = "Set the permission level of 1 or more players to guest",
		help = "Set the permission level of 1 or more players to guest. This will be overwritten on restart if their permission level is hardcoded.",
		examples = {Settings.Prefix.."setscribe euler", Settings.Prefix.."setscribe leibniz gauss"},
		func = setLevel(Settings.DefaultPerm)})
	BindCommand({
		name = "setperm",
		perm = Settings.AdminPerm,
		usage = Settings.Prefix.."setperm <name> <level>",
		brief = "Set a player's permission level",
		help = "Set a player's permission level. This will be overwritten on restart if their permission level is hardcoded.\nKey Permission Levels:\n<0 banned\n0 guest/default\n5 scribe\n10 admin",
		examples = {Settings.Prefix.."setperm gauss 5", Settings.Prefix.."setperm euler 57721"},
		func = function(speaker, args)
			if #args ~= 2 then
				SendMessageToClient({
					Text = "This command requires 2 arguments";
					ChatColor = Color3.new(1, 0, 0)
				}, speaker.Name)
				return false
			end

			local userName = args[1]
			local userId = GetUserId(userName)
			local level = tonumber(args[2])

			if level == nil then
				SendMessageToClient({
					Text = "The second argument to this command must be an integer";
					ChatColor = Color3.new(1, 0, 0)
				}, speaker.Name)
				return false
			end

			if userId then
				SetPermLevel(userId, level)
                UpdatePerms(userId)

				SendMessageToClient({
					Text = userName.." given permission level "..level;
					ChatColor = Color3.new(0, 1, 0)
				}, speaker.Name)
			else
				SendMessageToClient({
					Text = "Unable to get User Id of player with name: "..userName;
					ChatColor = Color3.new(1, 0, 0)
				}, speaker.Name)
			end
		end
	})

	BindCommand({
		name = "getperm",
		perm = Settings.AdminPerm,
		usage = Settings.Prefix.."getperm <name>",
		brief = "Get a player's permission level",
		help = "Get a player's permission level.\nKey Permission Levels:\n<0 banned\n0 guest/default\n5 scribe\n10 admin",
		examples = {Settings.Prefix.."setperm gauss", Settings.Prefix.."setperm euler leibniz"},
		func = function(speaker, args)

			if #args == 0 then
				SendMessageToClient({
					Text = "No arguments given";
					ChatColor = Color3.new(0, 1, 0)
				}, speaker.Name)
				return false
			end

			for _, name in ipairs(args) do

				local userId = GetUserId(name)

				if userId then

					local level = GetPermLevel(userId)

					SendMessageToClient({
						Text = name.." has permission level "..level;
						ChatColor = Color3.new(0, 1, 0)
					}, speaker.Name)
				else
					SendMessageToClient({
						Text = "Unable to get User Id of player with name: "..name;
						ChatColor = Color3.new(1, 0, 0)
					}, speaker.Name)
				end
			end
		end
	})

	local function sendHelp(speaker, args)
		SendMessageToClient({
			Text = getHelpMessage();
			ChatColor = Color3.new(1, 1, 1)
		}, speaker.Name)
	end

	BindCommand({
		name = "helpadmin",
		perm = Settings.AdminPerm,
		usage = Settings.Prefix.."help",
		brief = "Print this",
		help = getHelpMessage(),
		func = sendHelp})
end

-- These remote functions and events are invokved by client scripts
local function CreateRemotes()
    local adminCommonFolder = ReplicatedStorage:FindFirstChild("MetaAdmin")
    if not adminCommonFolder then
        adminCommonFolder = Instance.new("Folder")
        adminCommonFolder.Name = "MetaAdmin"
        adminCommonFolder.Parent = ReplicatedStorage
    end

    local remoteFunctionNames = {"GetPerm", "IsScribe", "IsAdmin", "IsBanned", "CanWrite"}

    for _, name in ipairs(remoteFunctionNames) do
        local newRF = Instance.new("RemoteFunction")
        newRF.Name = name
        newRF.Parent = adminCommonFolder
        remoteFunctions[name] = newRF
    end

    remoteFunctions["GetPerm"].OnServerInvoke = function(plr)
        return permissions[tostring(plr.UserId)]
    end

    remoteFunctions["IsScribe"].OnServerInvoke = function(plr)
        return isScribe(plr.UserId)
    end

    remoteFunctions["IsAdmin"].OnServerInvoke = function(plr)
        return isAdmin(plr.UserId)
    end

    remoteFunctions["IsBanned"].OnServerInvoke = function(plr)
        return isBanned(plr.UserId)
    end

    remoteFunctions["CanWrite"].OnServerInvoke = function(plr)
        return canWriteOnWhiteboards(plr.UserId)
    end

    local remoteEventNames = {"PermissionsUpdate", "WarnPlayer"}

    for _, name in ipairs(remoteEventNames) do
        local newRE = Instance.new("RemoteEvent")
        newRE.Name = name
        newRE.Parent = adminCommonFolder
        remoteEvents[name] = newRE
    end
end

-- Binds all commands at once
function Run(ChatService)
    -- The CREATOR of an experience is one who published it to Roblox. This can be an individual
    -- user or a group. The OWNER of an experience is the creator in the case of public servers,
    -- but for private servers it is the person who made the private server.
    --
    -- In the case of private servers we do not give the creator (or those in the group, if the
    -- creator is a group) special permissions in the server, as the owner of the private server
    -- does not expect this and may not be able to know what permissions have been set in that group.

    -- For a private server, the robloxGroupId is 0 by default (ununsed) and may be
    -- set by the owner to whatever they like

    -- For a public server, the robloxGroupId is 0 by default (unused), is automatically
    -- set to the group if the server is created by a group, and may be set by admins
    -- to whatever they like

    -- Note that by the time this runs, permissions, scribeOnlyMode and robloxGroupId
    -- have been read from the DataStore, so anything we do not now is overwriting
    -- those stored settings (and will be written on server shutdown to the DataStore)

    -- Give admin rights to owners of private servers and the creator of
    -- public servers if they are a user
    if isPrivateServer() then
		if not isPocket() then
			print("[MetaAdmin] Giving private server owner "..tostring(game.PrivateServerOwnerId).." admin")
			SetPermLevel(game.PrivateServerOwnerId, 255)
		else
			-- Try to find the creator in the pocket
			local creatorValue = workspace:WaitForChild("PocketCreatorId", 20)
			if not creatorValue then
				print("[MetaAdmin] Failed to find PocketCreatorId")
			else
				local creatorId = creatorValue.Value
				print("[MetaAdmin] Giving pocket owner " .. creatorId .. " admin")
				SetPermLevel(creatorId, 255)
			end
		end
    elseif game.CreatorType == Enum.CreatorType.User then
        print("[MetaAdmin] Giving game creator "..tostring(game.CreatorId).." admin")
        SetPermLevel(game.CreatorId, 255)
    end

    if not isPrivateServer() and robloxGroupId == 0 then
        -- If the game is created by a group, set this as the robloxGroupId
        if game.CreatorType == Enum.CreatorType.Group then
            robloxGroupId = game.CreatorId
        end
    end

    -- Look for Roblox group settings on Scribe and Admin rank cutoffs
    if robloxGroupId ~= 0 then
        print("[MetaAdmin] Loading settings from group "..tostring(robloxGroupId))
        LoadSettingsFromGroup(robloxGroupId)
    end

	-- Other code interacts with the permission system via remote functions and events
	CreateRemotes()

	-- Maintain attributes on players that reflect various permissions
	local function onPlayerAdded(player)
		UpdateAttributes(player)
	end

	for _p, plr in ipairs(Players:GetPlayers()) do
		onPlayerAdded(plr)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)

	-- Metaboard waits for this before opening up to clients
	script:SetAttribute("CanWritePermissionsSet", true)

    spawn(BindCommands) -- Bind all the commands

	local function ParseCommand(speakerName, message, channelName)
		local isCommand = message:match("^"..Settings.Prefix)
		-- Pattern that returns true if the prefix starts off the message
		if isCommand then
			local speaker = ChatService:GetSpeaker(speakerName) -- Requires the speaker module from the speaker module in the ChatServiceRunner
			local perms = GetPermLevelName(speakerName) -- Get speaker's permission level

			local messageWithoutPrefix = message:sub(#Settings.Prefix+1,#message) -- Get all characters after the prefix
			local command = nil -- The command the player is trying to execute (we haven't found that yet)
			local args = {} -- Table of arguments
			-- Arguments are words after the command
			-- So let's say the command was
			-- ;fly jerry
			-- jerry would be the 1st argument
			for word in messageWithoutPrefix:gmatch("[%w%p]+") do
				-- Loops through a table of words inside of the message
				if command ~= nil then
					table.insert(args, word)
				else
					command = word:lower()
				end
			end
			-- Identify the command and get the arguments
			local properCommand = command:sub(1,1):upper() .. command:sub(2,#command):lower()
			-- This converts something like "fLy" into "Fly"
			if commands[command] then
				SendMessageToClient({
					Text = "> "..message;
					ChatColor = Color3.new(1, 1, 1)
				}, speakerName)

				-- Command exists
				local commandPerm = commands[command].perm
				if commandPerm > perms then
					-- Player does not have permission to use this command
					SendMessageToClient({
						Text = "You do not have access to this command";
						ChatColor = Color3.new(1, .5, 0)
					}, speakerName)
					return true
				else
					if message:find("?") then
						-- Player is asking how to use this command
						sendCommandHelp(speakerName, command:gsub("?", ""))
						return true
					end
					-- Player has access to the command
					if Settings.DebugMode then
						-- Only shows output of command when DebugMode is on
						-- I'd turn it on if you're creating new commands and need to test them
						local executed, response = pcall(function()
							return commands[command].func(Players[speakerName], args)
						end)
						if executed then
							if response == false then
								SendMessageToClient({
									Text = "\"" .. command .. "\" failed";
									ChatColor = Color3.new(0, 1, 0)
								}, speakerName)
								sendCommandHelp(speakerName, command)
							else
								SendMessageToClient({
									Text = "\"" .. properCommand .. "\" ran without error";
									ChatColor = Color3.new(0, 1, 0)
								}, speakerName)
							end
							return true
						else
							SendMessageToClient({
								Text = "\"" .. command .. "\" failed";
								ChatColor = Color3.new(0, 1, 0)
							}, speakerName)
							sendCommandHelp(speakerName, command)
							return true
						end
					else
						-- DebugMode is disabled so we just execute the command
						local success, response = pcall(commands[command].func, Players[speakerName], args)
						if success and (response ~= false) then
							return true
						else
							SendMessageToClient({
								Text = "\"" .. command .. "\" failed";
								ChatColor = Color3.new(0, 1, 0)
							}, speakerName)
							sendCommandHelp(speakerName, command)
							return true
						end
					end
				end
			elseif commands[command:gsub("?", "")] then
				SendMessageToClient({
					Text = "> "..message;
					ChatColor = Color3.new(1, 1, 1)
				}, speakerName)
				-- Player is asking how to use this command
				sendCommandHelp(speakerName, command:gsub("?", ""))
				return true
			else
				-- Command doesn't exist
				--SendMessageToClient({
				--	Text = "\"" .. properCommand .. "\" doesn't exist!";
				--	ChatColor = Color3.new(1, 0, 0)
				--}, speakerName)
				return false
			end
		end
		return false
	end

	ChatService:RegisterProcessCommandsFunction("cmd", ParseCommand)

	spawn(function() ChatService.SpeakerAdded:Connect(function(speakerName)
			if GetPermLevelName(speakerName) >= Settings.AdminPerm then
				wait(2)
				local speaker = ChatService:GetSpeaker(speakerName)
				speaker:SendSystemMessage("Chat '"..Settings.Prefix.."helpadmin' for admin commands\nUse /<command>? for more info about an admin command, e.g. /ban?", "All")
			end
		end) end)

		local versionValue = script:FindFirstChild("version")
		local ver = versionValue and versionValue.Value or ""

	print("[MetaAdmin] "..ver.." initialised")
end

return Run