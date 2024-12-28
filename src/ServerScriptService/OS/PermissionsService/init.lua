local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Result = require(ReplicatedStorage.Util.Result)
local Sift = require(ReplicatedStorage.Packages.Sift)
local Remotes = ReplicatedStorage.OS.PermissionsController.Remotes

type Result<T> = Result.Result<T>
type UserPermInfo = {
	UserId: number,
	UserName: string,
	Player: Player?,
	Perm: number,
	PermScope: string,
}

local GlobalPermissionsDataStore = DataStoreService:GetDataStore("permissionsDataStore")
local PREFIX = "/"
local PERMISSION_ATTRIBUTE = "permission_level"
local GROUP_ID = tonumber(script.GroupId.Value)
local DEFAULT_PERM = 0
local ADMIN_PERM = 254
local SCRIBE_PERM = 50

local function isBanned(perm)
	return perm < 0
end

local function toRoleName(level: number)
	if level >= ADMIN_PERM then
		return "admin"
	elseif level >= SCRIBE_PERM then
		return "scribe"
	elseif level >= DEFAULT_PERM then
		return "guest"
	else
		return "banned"
	end
end

local function displayMsg(player, msg, color)
	Remotes.DisplaySystemMessage:FireClient(player, msg, color or Color3.fromHex("#808080"))
end

local function displayError(player, msg)
	displayMsg(player, msg, Color3.new(1,0,0))
end

function getUserIdAndUserName(givenName: string): Result<{
		UserId: number,
		UserName: string,
	}>
	-- Pattern: Starts with @, then one or more non-@ characters, which are captured
	local userName = givenName:match("^@([^@]+)")
	local players = Players:GetPlayers()

	if userName then
		for _, player in players do
			if player.Name == userName then
				return Result.ok({UserId = player.UserId, UserName = player.Name})
			end
		end

		local success, result = pcall(function()
			return Players:GetUserIdFromNameAsync(userName)
		end)
		if success then
			return Result.ok({UserId = result, UserName = userName})
		else
			return Result.err(result)
		end

	else
		local displayNameMatches = Sift.Array.filter(players, function(player: Player)
			return player.DisplayName == givenName
		end)
		local userNameMatches = Sift.Array.filter(players, function(player: Player)
			return player.Name == givenName
		end)

		if #displayNameMatches == 0 then
			if #userNameMatches == 1 then
				return Result.err(`No in-game players with DisplayName={givenName}.\nDid you mean {userNameMatches[1].DisplayName} (@{userNameMatches[1].Name})?`)
			else
				return Result.err(`No in-game players with DisplayName={givenName}.\nSpecify @USERNAME`)
			end
		elseif #displayNameMatches > 1 then
			return Result.err(`Multiple in-game players with DisplayName={givenName}.\nSpecify @USERNAME`)
		else
			return Result.ok({UserId = displayNameMatches[1].UserId, UserName = displayNameMatches[1].Name})
		end
	end
end

local PermissionsService = {}

function PermissionsService:getUserPermInfoById(userId: number, userName: string?): Result<UserPermInfo>
	return Result.call(function()
		local player = Players:GetPlayerByUserId(userId)
		userName = userName or if player then player.Name else nil
		userName = userName or Players:GetNameFromUserIdAsync(userId)

		local permInfo = Result.unwrap(self:getPermissionInfo(userId))
		return {
			UserId = userId,
			UserName = userName,
			Player = Players:GetPlayerByUserId(userId),
			Perm = permInfo.Perm,
			PermScope = permInfo.Scope,
		}
	end)
end

function PermissionsService:getUserPermInfo(nameStr: string): Result<UserPermInfo>
	local userInfoResult = getUserIdAndUserName(nameStr)
	return Result.andThen(userInfoResult, function(userInfo)
		return self:getUserPermInfoById(userInfo.UserId, userInfo.UserName)
	end)
end

function PermissionsService:getPermissionsDataStore(): Result<DataStore>
	local Pocket = ReplicatedStorage.OS.Pocket
	local POCKET_PATTERN = "metadmin.%s"
	local PRIVATE_SERVER_PATTERN = "metadmin.%s"
	local TRS = "permissionsDataStore"

	if game.PrivateServerId ~= "" then
		if game.PrivateServerOwnerId == 0 then
			-- Pocket (Reserved Server)
			if Pocket:GetAttribute("PocketId") == nil then
				Pocket:GetAttributeChangedSignal("PocketId"):Wait()
			end
			local pocketId = Pocket:GetAttribute("PocketId")
			return Result.ok(DataStoreService:GetDataStore(POCKET_PATTERN:format(pocketId)))
		else
			-- Private Server
			return Result.ok(DataStoreService:GetDataStore(PRIVATE_SERVER_PATTERN:format(game.PrivateServerOwnerId)))
		end
	else
		-- TRS
		return Result.ok(DataStoreService:GetDataStore(TRS))
	end
end

function PermissionsService:getPermissionInfo(userId: number): Result<{
		Perm: number,
		Scope: string,
	}>
	local function waitForGetBudget()
		while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) <= 0 do
			task.wait(0.5)
		end
	end

	if self._permCache[tostring(userId)] then
		local cached = self._permCache[tostring(userId)]
		return Result.ok({Perm = cached[1], Scope = cached[2]})
	end

	local datastoreResult = self:getPermissionsDataStore()
	if not datastoreResult.success then
		return Result.err(datastoreResult.reason)
	end

	local datastore = datastoreResult.data
	local success, result, scope = pcall(function()
		local perm
		waitForGetBudget()
		perm = datastore:GetAsync(userId)
		if perm then
			return perm, "local"
		end

		if self._exclusive == nil then
			waitForGetBudget()
			self._exclusive = datastore:GetAsync("exclusive") or false
		end

		if self._exclusive then
			return DEFAULT_PERM, "exclusive-default"
		end

		-- Default to global TRS Permissions datastore
		waitForGetBudget()
		perm = GlobalPermissionsDataStore:GetAsync(userId)
		if perm then
			return perm, "global"
		end

		-- Default to metauni group rank
		if not perm and not self._exclusive then
			local groups = GroupService:GetGroupsAsync(userId)
			for _, group in groups do
				if group.Id == GROUP_ID then
					return group.Rank, "group"
				end
			end
		end

		return DEFAULT_PERM, "default"
	end)

	if success then
		self._permCache[tostring(userId)] = {result, scope}
		return Result.ok({Perm = result, Scope = scope})
	else
		return Result.err(result)
	end
end

function PermissionsService:getPermissionLevelById(userId: number): Result<number>
	return Result.map(self:getPermissionInfo(userId), function(info)
		return info.Perm
	end)
end

function PermissionsService:_syncPlayerAttributes(player: Player, perm: number)
	player:SetAttribute(PERMISSION_ATTRIBUTE, perm)
	player:SetAttribute("metaadmin_isscribe", perm >= SCRIBE_PERM)
	player:SetAttribute("metaadmin_canwrite", perm >= SCRIBE_PERM)
	player:SetAttribute("metaadmin_isadmin", perm >= ADMIN_PERM)
end

function PermissionsService:setPermissionLevel(userId: number, level: number): Result<number>
	local datastoreResult = self:getPermissionsDataStore()
	if not datastoreResult.success then
		return Result.err(datastoreResult.reason)
	end

	local datastore = datastoreResult.data
	while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync) <= 0 do
		task.wait(0.5)
	end

	local success, result = pcall(function()
		datastore:SetAsync(userId, level)
	end)

	if success then
		self._permCache[tostring(userId)] = {level, "local"}
		local player = Players:GetPlayerByUserId(userId)
		if player then
			self:_syncPlayerAttributes(player, level)
		end
		return Result.ok(level)
	else
		return Result.err(result)
	end
end

function PermissionsService:_makeCommand(name: string, args: {
		Usage: string?,
		Brief: string?,
		Help: string?,
		Examples: {string}?,
		Perm: number,
		Alias: string?,
		Triggered: (speaker: Player, args: {string}) -> ()
	})
	local command = Instance.new("TextChatCommand")
	command.Name = name
	command.PrimaryAlias = "/"..name
	if args.Alias then
		command.SecondaryAlias = "/"..args.Alias
	end
	command.Triggered:Connect(function(originTextSource: TextSource, unfilteredText: string)
		if self._currentCommandThread then
			task.cancel(self._currentCommandThread)
			self._currentCommandThread = nil
		end
		self._currentCommandThread = task.spawn(function()
			local userId = originTextSource.UserId
			local player = Players:GetPlayerByUserId(userId)
			if not player then
				warn(`[PermissionsService] Couldn't find player who triggered command: {tostring(unfilteredText)}`)
				return
			end

			displayMsg(player, "> "..unfilteredText, Color3.fromHex("#808080"))

			local speakerInfoResult = self:getUserPermInfoById(userId)
			if not speakerInfoResult.success then
				warn(`[PermissionsService] Permission fetch failed (UserId: {userId})\n`..tostring(speakerInfoResult.reason))
				displayError(player, "Failed to get your permission level. Try again.")
				return
			end

			-- Allow commands in Studio, but restrict to args.Perm in live game
			if not RunService:IsStudio() and speakerInfoResult.data.Perm < args.Perm then
				displayError(player, `You ({speakerInfoResult.data.Perm}) must have permission level >={args.Perm} to use this command.`)
				return
			end

			local commandArgs = {}
			for arg in unfilteredText:sub(#command.PrimaryAlias+2):gmatch("%s*(%S+)%s*") do
				table.insert(commandArgs, arg)
			end

			args.Triggered(player, commandArgs)
			if self._currentCommandThread == coroutine.running() then
				self._currentCommandThread = nil
			end
		end)
	end)

	self.Commands[name] = command
	table.insert(self._helpOrder, name)

	self._commandData[name] = {
		Briefs = args.Brief,
		Help = args.Help,
		Usage = args.Usage,
		Examples = args.Examples,
	}

	command.Parent = TextChatService

	do
		local helpCommand = Instance.new("TextChatCommand")
		helpCommand.Name = name.."?"
		helpCommand.PrimaryAlias = PREFIX..name.."?"
		helpCommand.Triggered:Connect(function(originTextSource, unfilteredText)
			task.spawn(function()
				local userId = originTextSource.UserId
				local player = Players:GetPlayerByUserId(userId)
				if not player then
					warn(`[PermissionsService] Couldn't find player with userId {userId} who triggered command: {tostring(unfilteredText)}`)
					return
				end

				displayMsg(player, "> "..unfilteredText, Color3.fromHex("#808080"))

				local helpMessage = `{args.Help}\nUsage:{args.Usage}`
				if args.Examples and #args.Examples > 0 then
					helpMessage = helpMessage.."\nExamples:\n  "..table.concat(args.Examples, "\n  ")
				end

				displayMsg(player, helpMessage)
			end)
		end)
		helpCommand.Parent = TextChatService
	end
end

function PermissionsService:Init()
	self.Commands = {}
	self._commandData = {}
	self._helpOrder = {}
	self._permCache = {}

	self:_makeCommand("kick", {
		Usage = PREFIX.."kick NAME [reason]",
		Brief = "Kick a player, with an optional message",
		Help = "Kick a player, with an optional message. This will instantly remove them from the game, but they can rejoin again immediately.",
		Examples = {PREFIX.."kick newton bye bye"},
		Perm = ADMIN_PERM,
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No targets specified")
				return
			end

			local speakerPerm = speaker:GetAttribute(PERMISSION_ATTRIBUTE)
			local kick_message = table.concat(args, " ", 2)

			Result.match(self:getUserPermInfo(args[1]), {
				ok = function(info)
					if not info.Player then
						displayError(speaker, `@{info.UserName} not found in game`)
						return
					end

					if info.Perm < speakerPerm or speaker.UserId == info.UserId then
						info.Player:Kick(kick_message)
						displayMsg(speaker, "Kicked "..info.Player.Name)
					else
						displayError(speaker, `You cannot use this command on @{info.UserName}. They outrank you.`)
					end
				end,
				err = function(reason)
					displayError(speaker, reason)
				end
			})
		end
	})

	self:_makeCommand("warn", {
		Usage = PREFIX.."warn NAME [reason]",
		Brief = "Warn a player, with an optional message",
		Help = "Warn a player, with an optional message. This will move them to the spawn location and show them a warning message.",
		Examples = {PREFIX.."warn newton be less disruptive"},
		Perm = ADMIN_PERM,
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No targets specified")
				return
			end

			local speakerPerm = speaker:GetAttribute(PERMISSION_ATTRIBUTE)
			local warn_message = table.concat(args, " ", 2)

			Result.match(self:getUserPermInfo(args[1]), {
				ok = function(info)
					if not info.Player then
						displayError(speaker, `@{info.UserName} not found in game`)
						return
					end

					if info.Perm < speakerPerm or speaker.UserId == info.UserId then
						displayMsg(info.Player, warn_message, Color3.new(1,0,0))
						displayMsg(speaker, `Warned @{info.UserName}`)
					else
						displayError(speaker, `You cannot use this command on @{info.UserName}={info.Perm}. They outrank you={speakerPerm}.`)
					end
				end,
				err = function(reason)
					displayError(speaker, reason)
				end
			})
		end
	})

	self:_makeCommand("perm", {
		Perm = ADMIN_PERM,
		Usage = PREFIX.."perm NAME...",
		Brief = "Check a players permission level",
		Help = "Check a players permission level",
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No names given")
				return
			end

			for _, name in args do
				Result.match(self:getUserPermInfo(name), {
					ok = function(info)
						displayMsg(speaker, `@{info.UserName}: {info.Perm} ({toRoleName(info.Perm)})`)
					end,
					err = function(reason)
						displayError(speaker, reason)
					end
				})
			end
		end
	})

	self:_makeCommand("allperms", {
		Perm = ADMIN_PERM,
		Usage = PREFIX.."allperms",
		Brief = "Print the permissions of every player in-game",
		Help = "Print the permissions of every player in-game",
		Triggered = function(speaker)
			local players = Players:GetPlayers()

			for _, player in players do
				Result.match(self:getUserPermInfo("@"..player.Name), {
					ok = function(info)
						displayMsg(speaker, `@{info.UserName}: {info.Perm} ({toRoleName(info.Perm)})`)
					end,
					err = function(reason)
						warn(`[PermissionsService] Permission level fetch for @{player.Name} failed.`, reason)
						displayError(speaker, `Failed to get permission level of @{player.Name}. Try again.`)
					end
				})
			end
		end
	})

	self:_makeCommand("ban", {
		Perm = ADMIN_PERM,
		Usage = PREFIX.."ban NAME...",
		Brief = "Ban 1 or more players",
		Help = "Ban 1 or more players. They are instantly kicked and will be re-kicked every time they rejoin.",
		Examples = {PREFIX.."ban euler", PREFIX.."ban leibniz gauss"},
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No names given")
				return
			end

			for _, givenName in args do
				Result.match(self:getUserPermInfo(givenName), {
					ok = function(info)
						if info.Perm >= ADMIN_PERM then
							displayError(speaker, "You cannot ban an admin.")
							return
						end

						if info.Player then
							info.Player:Kick("You have been banned by an admin")
						end

						if info.Perm < DEFAULT_PERM then
							if info.Player then
								displayMsg(speaker, `@{info.UserName} is already banned. They were kicked from this game.`)
							else
								displayMsg(speaker, `@{info.UserName} is already banned.`)
							end
							return
						end

						Result.match(self:setPermissionLevel(info.UserId, DEFAULT_PERM-1), {
							ok = function()
								if info.Player then
									displayMsg(speaker, `@{info.UserName} was banned and kicked from this game.`)
								else
									displayMsg(speaker, `@{info.UserName} was banned`)
								end
							end,
							err = function(reason)
								warn(`[PermissionsService] Permission level set for @{info.UserName} failed.`, reason)
								displayError(speaker, `Failed to set permission level of @{info.UserName}. Try again.`)
							end
						})
					end,
					err = function(reason)
						displayError(speaker, reason)
					end
				})
			end
		end
	})

	self:_makeCommand("unban", {
		Perm = ADMIN_PERM,
		Usage = PREFIX.."unban NAME...",
		Brief = "Unban 1 or more players",
		Help = "Unban 1 or more players. Raises their permission level to the default/guest level if they are banned.",
		Examples = {PREFIX.."unban euler", PREFIX.."unban leibniz gauss"},
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No names given")
				return
			end

			for _, givenName in args do
				Result.match(self:getUserPermInfo(givenName), {
					ok = function(info)
						if info.Perm >= ADMIN_PERM then
							displayError(speaker, "You cannot ban/unban an admin.")
							return
						end

						if info.Perm >= DEFAULT_PERM then
							displayMsg(speaker, `@{info.UserName} is already not-banned (Permission Level {info.Perm}).`)
							return
						end

						Result.match(self:setPermissionLevel(info.UserId, DEFAULT_PERM), {
							ok = function()
								displayMsg(speaker, `@{info.UserName} was unbanned.`)
							end,
							err = function(reason)
								warn(`[PermissionsService] Permission level set for @{info.UserName} failed.`, reason)
								displayError(speaker, `Failed to set permission level of @{info.UserName}. Try again.`)
							end
						})
					end,
					err = function(reason)
						displayError(speaker, reason)
					end
				})
			end
		end
	})

	self:_makeCommand("setscribe", {
		Perm = ADMIN_PERM,
		Usage = PREFIX.."setscribe NAME..",
		Brief = "Give scribe permissions to 1 or more players",
		Help = "Give scribe permissions to 1 or more players.",
		Examples = {PREFIX.."setscribe euler", PREFIX.."setscribe euler gauss"},
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No names given")
				return
			end

			for _, name in args do
				Result.match(self:getUserPermInfo(name), {
					ok = function(info)
						if info.Perm >= SCRIBE_PERM then
							displayMsg(speaker, `@{info.UserName} already >=scribe.`)
							return
						elseif info.Perm < DEFAULT_PERM then
							displayMsg(speaker, `@{info.UserName} is banned. Unban before /setscribe.`)
							return
						end

						Result.match(self:setPermissionLevel(info.UserId, SCRIBE_PERM), {
							ok = function()
								displayMsg(speaker, `@{info.UserName} was set to scribe.`)
							end,
							err = function(reason)
								warn(`[PermissionsService] Permission level set for @{info.UserName} failed.`, reason)
								displayError(speaker, `Failed to set permission level of @{info.UserName}. Try again.`)
							end
						})
					end,
					err = function(reason)
						displayError(speaker, reason)
					end
				})
			end
		end
	})

	self:_makeCommand("setscribeall", {
		Perm = ADMIN_PERM,
		Usage = PREFIX.."setscribeall",
		Brief = "Give scribe permissions to every in-game player",
		Help = "Give scribe permissions to every in-game player. Does not lower permissions of scribes, admins.",
		Examples = {PREFIX.."setscribeall"},
		Triggered = function(speaker)
			local players = Players:GetPlayers()

			for _, player in players do
				Result.match(self:getUserPermInfo("@"..player.Name), {
					ok = function(info)
						if info.Perm >= SCRIBE_PERM then
							displayMsg(speaker, `@{info.UserName} already >=scribe.`)
							return
						elseif info.Perm < DEFAULT_PERM then
							displayMsg(speaker, `@{info.UserName} is banned. Unban before /setscribe.`)
							return
						end

						Result.match(self:setPermissionLevel(info.UserId, SCRIBE_PERM), {
							ok = function()
								displayMsg(speaker, `@{info.UserName} was set to scribe.`)
							end,
							err = function(reason)
								warn(`[PermissionsService] Permission level set for @{info.UserName} failed.`, reason)
								displayError(speaker, `Failed to set permission level of @{info.UserName}. Try again.`)
							end
						})
					end,
					err = function(reason)
						displayError(speaker, reason)
					end
				})
			end
		end
	})

	self:_makeCommand("setguest", {
		Perm = ADMIN_PERM,
		Usage = PREFIX.."setguest NAME..",
		Brief = "Set 1 or more players to default permissions.",
		Help = "Set 1 or more players to default permissions. Will lower permissions of scribes, admins.",
		Examples = {PREFIX.."setguest euler", PREFIX.."setguest euler gauss"},
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No names given")
				return
			end

			for _, name in args do
				Result.match(self:getUserPermInfo(name), {
					ok = function(info)
						if info.Perm < DEFAULT_PERM then
							displayMsg(speaker, `@{info.UserName} is banned. Unban before /setguest.`)
							return
						elseif info.Perm >= 255 then
							displayMsg(speaker, `@{info.UserName} is game owner. Cannot lower permissions.`)
							return
						end

						Result.match(self:setPermissionLevel(info.UserId, DEFAULT_PERM), {
							ok = function()
								local oldRole = toRoleName(info.Perm)
								displayMsg(speaker, `@{info.UserName} {info.Perm} ({oldRole}) -> {DEFAULT_PERM} (guest).`)
							end,
							err = function(reason)
								warn(`[PermissionsService] Permission level set for @{info.UserName} failed.`, reason)
								displayError(speaker, `Failed to set permission level of @{info.UserName}. Try again.`)
							end
						})
					end,
					err = function(reason)
						displayError(speaker, reason)
					end
				})
			end
		end
	})

	self:_makeCommand("setadmin", {
		Perm = ADMIN_PERM,
		Usage = PREFIX.."setadmin NAME..",
		Brief = "Set 1 or more players to admin permissions.",
		Help = "Set 1 or more players to admin permissions.",
		Examples = {PREFIX.."setadmin euler", PREFIX.."setadmin euler gauss"},
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No names given")
				return
			end

			for _, name in args do
				Result.match(self:getUserPermInfo(name), {
					ok = function(info)
						if info.Perm < DEFAULT_PERM then
							displayMsg(speaker, `@{info.UserName} is banned. Unban before /setadmin.`)
							return
						end

						Result.match(self:setPermissionLevel(info.UserId, ADMIN_PERM), {
							ok = function()
								local oldRole = toRoleName(info.Perm)
								displayMsg(speaker, `@{info.UserName} {info.Perm} ({oldRole}) -> {ADMIN_PERM} (admin).`)

								if info.Player then
									self:_onAdmin(info.Player)
								end
							end,
							err = function(reason)
								warn(`[PermissionsService] Permission level set for @{info.UserName} failed.`, reason)
								displayError(speaker, `Failed to set permission level of @{info.UserName}. Try again.`)
							end
						})
					end,
					err = function(reason)
						displayError(speaker, reason)
					end
				})
			end
		end
	})

	self:_makeCommand("admin", {
		Alias = "?",
		Perm = ADMIN_PERM,
		Usage = PREFIX.."admin",
		Brief = "Print admin help.",
		Help = "Print admin help.",
		Triggered = function(speaker)
			local message = self:_genHelp()
			Remotes.DisplaySystemMessage:FireClient(speaker, message)
		end
	})
end

function PermissionsService:_genHelp()
	local message = ""
	for _, name in self._helpOrder do
		local data = self._commandData[name]
		if data.Usage then
			message = message..data.Usage.."\n"
			if data.Brief then
				message = message.."\n  "..data.Brief
			end
		end
	end
	message = message.."\nNAME is either a username starting with @ or the diplay-name of a player in game."
	message = message.."\nUse /COMMAND? for more info about a command, e.g. /ban?"
	return message
end

function PermissionsService:_onAdmin(player: Player)
	Remotes.DisplaySystemMessage:FireClient(player, "You are an admin. Say /admin for command help.", Color3.fromHex("#808080"))
end

function PermissionsService:Start()
	-- Set Permission level attribute of present and incoming players, and kick
	-- the banned
	local function onPlayer(player)
		local TRIES = 3
		local DELAY = 5

		for i = 1, TRIES do
			local result = self:getPermissionInfo(player.UserId)
			if result.success then
				local perm = result.data.Perm
				if isBanned(perm) then
					player:Kick("You are banned")
				else
					self:_syncPlayerAttributes(player, perm)
					-- Send help message to admins
					if perm >= ADMIN_PERM then
						self:_onAdmin(player)
					end
				end
				return
			end

			if i < TRIES then
				task.wait(DELAY)
			else
				warn(`[PermissionsService] Failed to initialise permissions of @{player.Name} after {TRIES} tries.`, result.reason)
			end
		end
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return PermissionsService
