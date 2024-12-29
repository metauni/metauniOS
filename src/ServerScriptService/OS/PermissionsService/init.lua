--!strict
-- Services
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Result = require(ReplicatedStorage.Util.Result)
local Remotes = ReplicatedStorage.OS.PermissionsController.Remotes
local Stream = require(ReplicatedStorage.Util.Stream)

type Result<T> = Result.Result<T>
type UserInfo = {
	UserId: number,
	UserName: string,
	Player: Player?,
	Perm: number,
	PermScope: string,
}

type CommandData = {
	Brief: string?,
	Help: string?,
	Usage: string?,
	Examples: { string }?,
}

-- Constants
local GlobalPermissionsDataStore = DataStoreService:GetDataStore("permissionsDataStore")
local PREFIX = "/"
local PERMISSION_ATTRIBUTE = "permission_level"
local GROUP_ID = tonumber(script.GroupId.Value)
local DEFAULT_PERM = 0
local ADMIN_PERM = 254
local SCRIBE_PERM = 50

-- State variables
local Commands: { [string]: TextChatCommand } = {}
local CommandData: { [string]: CommandData } = {}
local HelpOrder: { string } = {}
local PermCache: { [string]: { Perm: number, Scope: string } } = {}
local CurrentCommandThread: thread? = nil
local Exclusive: boolean? = nil

-- Helper functions
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

local function displayMsg(player: Player, msg: string, color: Color3?)
	Remotes.DisplaySystemMessage:FireClient(player, msg, color or Color3.fromHex("#808080"))
end

local function displayError(player: Player, msg: string)
	displayMsg(player, msg, Color3.new(1, 0, 0))
end

local function genHelp()
	local message = ""
	for _, name in HelpOrder do
		local data = CommandData[name]
		if data.Usage then
			message = message .. data.Usage .. "\n"
			if data.Brief then
				message = message .. "\n  " .. data.Brief
			end
		end
	end
	message = message .. "\nNAME is either a username starting with @ or the display-name of a player in game."
	message = message .. "\nUse /COMMAND? for more info about a command, e.g. /ban?"
	return message
end

local function waitForGetBudget()
	while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) <= 0 do
		task.wait(0.5)
	end
end

local function getPermissionsDataStore(): DataStore
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
			return DataStoreService:GetDataStore(POCKET_PATTERN:format(pocketId))
		else
			-- Private Server
			return DataStoreService:GetDataStore(PRIVATE_SERVER_PATTERN:format(game.PrivateServerOwnerId))
		end
	else
		-- TRS
		return DataStoreService:GetDataStore(TRS)
	end
end

local function syncPlayerAttributes(player: Player, perm: number)
	player:SetAttribute(PERMISSION_ATTRIBUTE, perm :: any)
	player:SetAttribute("metaadmin_isscribe", perm >= SCRIBE_PERM)
	player:SetAttribute("metaadmin_canwrite", perm >= SCRIBE_PERM)
	player:SetAttribute("metaadmin_isadmin", perm >= ADMIN_PERM)
end

local function setPermissionLevelAsync(userId: number, level: number): Result<number>
	return Result.pcall(function()
		local datastore = getPermissionsDataStore()

		while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync) <= 0 do
			task.wait(0.5)
		end

		datastore:SetAsync(tostring(userId), {
			Perm = level,
			Scope = "local",
		})

		PermCache[tostring(userId)] = {
			Perm = level,
			Scope = "local",
		}
		local player = Players:GetPlayerByUserId(userId)
		if player then
			syncPlayerAttributes(player, level)
		end
		return level
	end)
end

local function getPermissionInfoAsync(userId: number): Result<{
	Perm: number,
	Scope: string,
}>
	if PermCache[tostring(userId)] then
		local cached = PermCache[tostring(userId)]
		return Result.ok({ Perm = cached.Perm, Scope = cached.Scope })
	end

	local result = Result.pcall(function()
		local datastore = getPermissionsDataStore()
		waitForGetBudget()
		local localPerm = datastore:GetAsync(tostring(userId))
		if localPerm then
			return {
				Perm = localPerm,
				Scope = "local",
			}
		end

		if Exclusive == nil then
			waitForGetBudget()
			Exclusive = datastore:GetAsync("exclusive") or false
		end

		if Exclusive then
			return {
				Perm = DEFAULT_PERM,
				Scope = "exclusive-default",
			}
		end

		-- Default to global TRS Permissions datastore
		waitForGetBudget()
		local globalPerm = GlobalPermissionsDataStore:GetAsync(tostring(userId))
		if globalPerm then
			return {
				Perm = globalPerm,
				Scope = "global",
			}
		end

		-- Default to metauni group rank
		if not Exclusive then
			local groups = GroupService:GetGroupsAsync(userId)
			for _, group in groups do
				if group.Id == GROUP_ID then
					return {
						Perm = group.Rank,
						Scope = "group",
					}
				end
			end
		end

		return {
			Perm = DEFAULT_PERM,
			Scope = "default",
		}
	end)

	if result.success then
		PermCache[tostring(userId)] = result.data
	end
	return result
end

local function getUserInfoByIdAsync(userId: number, userName: string?): Result<UserInfo>
	return Result.pcall(function()
		local player = Players:GetPlayerByUserId(userId)
		userName = userName or if player then player.Name else nil
		userName = userName or Players:GetNameFromUserIdAsync(userId)

		if userName == nil then
			error(`Failed to resolve username of player with userId {userId}`)
		end

		local permInfo = Result.unwrap(getPermissionInfoAsync(userId))
		return {
			UserId = userId,
			UserName = userName,
			Player = Players:GetPlayerByUserId(userId),
			Perm = permInfo.Perm,
			PermScope = permInfo.Scope,
		}
	end)
end

local function getUserIdAndUserNameAsync(givenName: string): Result<{
	UserId: number,
	UserName: string,
}>
	-- Pattern: Starts with @, then one or more non-@ characters, which are captured
	local userName = givenName:match("^@([^@]+)")
	local players = Players:GetPlayers()

	if userName then
		for _, player in players do
			if player.Name == userName then
				return Result.ok({ UserId = player.UserId, UserName = player.Name })
			end
		end

		return Result.pcall(function()
			local userId = Players:GetUserIdFromNameAsync(userName)
			return { UserId = userId, UserName = userName }
		end)
	else
		local displayNameMatches = {}
		local userNameMatches = {}

		for _, player in players do
			if player.DisplayName == givenName then
				table.insert(displayNameMatches, player)
			end
			if player.Name == givenName then
				table.insert(userNameMatches, player)
			end
		end

		if #displayNameMatches == 0 then
			if #userNameMatches == 1 then
				return Result.err(
					`No in-game players with DisplayName={givenName}.\nDid you mean {userNameMatches[1].DisplayName} (@{userNameMatches[1].Name})?`
				)
			else
				return Result.err(`No in-game players with DisplayName={givenName}.\nSpecify @USERNAME`)
			end
		elseif #displayNameMatches > 1 then
			return Result.err(`Multiple in-game players with DisplayName={givenName}.\nSpecify @USERNAME`)
		else
			return Result.ok({ UserId = displayNameMatches[1].UserId, UserName = displayNameMatches[1].Name })
		end
	end
end

local function getUserInfoAsync(nameStr: string): Result<UserInfo>
	return Result.andThen(getUserIdAndUserNameAsync(nameStr), function(userInfo)
		return getUserInfoByIdAsync(userInfo.UserId, userInfo.UserName)
	end)
end

local function makeCommand(
	name: string,
	args: {
		Usage: string?,
		Brief: string?,
		Help: string?,
		Examples: { string }?,
		Perm: number,
		Alias: string?,
		Triggered: (speaker: Player, args: { string }) -> (),
	}
)
	local command = Instance.new("TextChatCommand")
	command.Name = name
	command.PrimaryAlias = "/" .. name
	if args.Alias then
		command.SecondaryAlias = "/" .. args.Alias
	end
	command.Triggered:Connect(function(originTextSource: TextSource, unfilteredText: string)
		if CurrentCommandThread then
			task.cancel(CurrentCommandThread)
			CurrentCommandThread = nil
		end
		CurrentCommandThread = task.spawn(function()
			local userId = originTextSource.UserId
			local player = Players:GetPlayerByUserId(userId)
			if not player then
				warn(`[PermissionsService] Couldn't find player who triggered command: {tostring(unfilteredText)}`)
				return
			end

			displayMsg(player, "> " .. unfilteredText, Color3.fromHex("#808080"))

			local speakerInfoResult = getUserInfoByIdAsync(userId)
			if not speakerInfoResult.success then
				warn(
					`[PermissionsService] Permission fetch failed (UserId: {userId})\n`
						.. tostring(speakerInfoResult.reason)
				)
				displayError(player, "Failed to get your permission level. Try again.")
				return
			end

			-- Allow commands in Studio, but restrict to args.Perm in live game
			if not RunService:IsStudio() and speakerInfoResult.data.Perm < args.Perm then
				displayError(
					player,
					`You ({speakerInfoResult.data.Perm}) must have permission level >={args.Perm} to use this command.`
				)
				return
			end

			local commandArgs = {}
			for arg in unfilteredText:sub(#command.PrimaryAlias + 2):gmatch("%s*(%S+)%s*") do
				table.insert(commandArgs, arg)
			end

			args.Triggered(player, commandArgs)
			if CurrentCommandThread == coroutine.running() then
				CurrentCommandThread = nil
			end
		end)
	end)

	Commands[name] = command
	table.insert(HelpOrder, name)

	CommandData[name] = {
		Brief = args.Brief,
		Help = args.Help,
		Usage = args.Usage,
		Examples = args.Examples,
	}

	command.Parent = TextChatService

	do
		local helpCommand = Instance.new("TextChatCommand")
		helpCommand.Name = name .. "?"
		helpCommand.PrimaryAlias = PREFIX .. name .. "?"
		helpCommand.Triggered:Connect(function(originTextSource, unfilteredText)
			task.spawn(function()
				local userId = originTextSource.UserId
				local player = Players:GetPlayerByUserId(userId)
				if not player then
					warn(
						`[PermissionsService] Couldn't find player with userId {userId} who triggered command: {tostring(
							unfilteredText
						)}`
					)
					return
				end

				displayMsg(player, "> " .. unfilteredText, Color3.fromHex("#808080"))

				local helpMessage = `{args.Help}\nUsage:{args.Usage}`
				if args.Examples and #args.Examples > 0 then
					helpMessage = helpMessage .. "\nExamples:\n  " .. table.concat(args.Examples, "\n  ")
				end

				displayMsg(player, helpMessage)
			end)
		end)
		helpCommand.Parent = TextChatService
	end
end

-- Exported Service
local Service = {
	ClassName = "PermissionsService",
}

function Service.GetPermissionLevelByIdAsync(userId: number): Result<number>
	return Result.map(getPermissionInfoAsync(userId), function(permInfo)
		return permInfo.Perm
	end)
end

function Service.Init()
	makeCommand("kick", {
		Usage = PREFIX .. "kick NAME [reason]",
		Brief = "Kick a player, with an optional message",
		Help = "Kick a player, with an optional message. This will instantly remove them from the game, but they can rejoin again immediately.",
		Examples = { PREFIX .. "kick newton bye bye" },
		Perm = ADMIN_PERM,
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No targets specified")
				return
			end

			local speakerPerm = speaker:GetAttribute(PERMISSION_ATTRIBUTE)
			local kick_message = table.concat(args, " ", 2)

			Result.match(getUserInfoAsync(args[1]), {
				ok = function(info)
					if not info.Player then
						displayError(speaker, `@{info.UserName} not found in game`)
						return
					end

					if info.Perm < speakerPerm or speaker.UserId == info.UserId then
						info.Player:Kick(kick_message)
						displayMsg(speaker, "Kicked " .. info.Player.Name)
					else
						displayError(speaker, `You cannot use this command on @{info.UserName}. They outrank you.`)
					end
				end,
				err = function(reason)
					displayError(speaker, reason)
				end,
			})
		end,
	})

	makeCommand("warn", {
		Usage = PREFIX .. "warn NAME [reason]",
		Brief = "Warn a player, with an optional message",
		Help = "Warn a player, with an optional message. This will move them to the spawn location and show them a warning message.",
		Examples = { PREFIX .. "warn newton be less disruptive" },
		Perm = ADMIN_PERM,
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No targets specified")
				return
			end

			local speakerPerm = speaker:GetAttribute(PERMISSION_ATTRIBUTE)
			local warn_message = table.concat(args, " ", 2)

			Result.match(getUserInfoAsync(args[1]), {
				ok = function(info)
					if not info.Player then
						displayError(speaker, `@{info.UserName} not found in game`)
						return
					end

					if info.Perm < speakerPerm or speaker.UserId == info.UserId then
						displayMsg(info.Player, warn_message, Color3.new(1, 0, 0))
						displayMsg(speaker, `Warned @{info.UserName}`)
					else
						displayError(
							speaker,
							`You cannot use this command on @{info.UserName}={info.Perm}. They outrank you={speakerPerm}.`
						)
					end
				end,
				err = function(reason)
					displayError(speaker, reason)
				end,
			})
		end,
	})

	makeCommand("perm", {
		Perm = ADMIN_PERM,
		Usage = PREFIX .. "perm NAME...",
		Brief = "Check a players permission level",
		Help = "Check a players permission level",
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No names given")
				return
			end

			for _, name in args do
				Result.match(getUserInfoAsync(name), {
					ok = function(info)
						displayMsg(speaker, `@{info.UserName}: {info.Perm} ({toRoleName(info.Perm)})`)
					end,
					err = function(reason)
						displayError(speaker, reason)
					end,
				})
			end
		end,
	})

	makeCommand("allperms", {
		Perm = ADMIN_PERM,
		Usage = PREFIX .. "allperms",
		Brief = "Print the permissions of every player in-game",
		Help = "Print the permissions of every player in-game",
		Triggered = function(speaker)
			local players = Players:GetPlayers()

			for _, player in players do
				Result.match(getUserInfoAsync("@" .. player.Name), {
					ok = function(info)
						displayMsg(speaker, `@{info.UserName}: {info.Perm} ({toRoleName(info.Perm)})`)
					end,
					err = function(reason)
						warn(`[PermissionsService] Permission level fetch for @{player.Name} failed.`, reason)
						displayError(speaker, `Failed to get permission level of @{player.Name}. Try again.`)
					end,
				})
			end
		end,
	})

	makeCommand("ban", {
		Perm = ADMIN_PERM,
		Usage = PREFIX .. "ban NAME...",
		Brief = "Ban 1 or more players",
		Help = "Ban 1 or more players. They are instantly kicked and will be re-kicked every time they rejoin.",
		Examples = { PREFIX .. "ban euler", PREFIX .. "ban leibniz gauss" },
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No names given")
				return
			end

			for _, givenName in args do
				Result.match(getUserInfoAsync(givenName), {
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
								displayMsg(
									speaker,
									`@{info.UserName} is already banned. They were kicked from this game.`
								)
							else
								displayMsg(speaker, `@{info.UserName} is already banned.`)
							end
							return
						end

						Result.match(setPermissionLevelAsync(info.UserId, DEFAULT_PERM - 1), {
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
							end,
						})
					end,
					err = function(reason)
						displayError(speaker, reason)
					end,
				})
			end
		end,
	})

	makeCommand("unban", {
		Perm = ADMIN_PERM,
		Usage = PREFIX .. "unban NAME...",
		Brief = "Unban 1 or more players",
		Help = "Unban 1 or more players. Raises their permission level to the default/guest level if they are banned.",
		Examples = { PREFIX .. "unban euler", PREFIX .. "unban leibniz gauss" },
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No names given")
				return
			end

			for _, givenName in args do
				Result.match(getUserInfoAsync(givenName), {
					ok = function(info)
						if info.Perm >= ADMIN_PERM then
							displayError(speaker, "You cannot ban/unban an admin.")
							return
						end

						if info.Perm >= DEFAULT_PERM then
							displayMsg(
								speaker,
								`@{info.UserName} is already not-banned (Permission Level {info.Perm}).`
							)
							return
						end

						Result.match(setPermissionLevelAsync(info.UserId, DEFAULT_PERM), {
							ok = function()
								displayMsg(speaker, `@{info.UserName} was unbanned.`)
							end,
							err = function(reason)
								warn(`[PermissionsService] Permission level set for @{info.UserName} failed.`, reason)
								displayError(speaker, `Failed to set permission level of @{info.UserName}. Try again.`)
							end,
						})
					end,
					err = function(reason)
						displayError(speaker, reason)
					end,
				})
			end
		end,
	})

	makeCommand("setscribe", {
		Perm = ADMIN_PERM,
		Usage = PREFIX .. "setscribe NAME..",
		Brief = "Give scribe permissions to 1 or more players",
		Help = "Give scribe permissions to 1 or more players.",
		Examples = { PREFIX .. "setscribe euler", PREFIX .. "setscribe euler gauss" },
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No names given")
				return
			end

			for _, name in args do
				Result.match(getUserInfoAsync(name), {
					ok = function(info)
						if info.Perm >= SCRIBE_PERM then
							displayMsg(speaker, `@{info.UserName} already >=scribe.`)
							return
						elseif info.Perm < DEFAULT_PERM then
							displayMsg(speaker, `@{info.UserName} is banned. Unban before /setscribe.`)
							return
						end

						Result.match(setPermissionLevelAsync(info.UserId, SCRIBE_PERM), {
							ok = function()
								displayMsg(speaker, `@{info.UserName} was set to scribe.`)
							end,
							err = function(reason)
								warn(`[PermissionsService] Permission level set for @{info.UserName} failed.`, reason)
								displayError(speaker, `Failed to set permission level of @{info.UserName}. Try again.`)
							end,
						})
					end,
					err = function(reason)
						displayError(speaker, reason)
					end,
				})
			end
		end,
	})

	makeCommand("setscribeall", {
		Perm = ADMIN_PERM,
		Usage = PREFIX .. "setscribeall",
		Brief = "Give scribe permissions to every in-game player",
		Help = "Give scribe permissions to every in-game player. Does not lower permissions of scribes, admins.",
		Examples = { PREFIX .. "setscribeall" },
		Triggered = function(speaker)
			local players = Players:GetPlayers()

			for _, player in players do
				Result.match(getUserInfoAsync("@" .. player.Name), {
					ok = function(info)
						if info.Perm >= SCRIBE_PERM then
							displayMsg(speaker, `@{info.UserName} already >=scribe.`)
							return
						elseif info.Perm < DEFAULT_PERM then
							displayMsg(speaker, `@{info.UserName} is banned. Unban before /setscribe.`)
							return
						end

						Result.match(setPermissionLevelAsync(info.UserId, SCRIBE_PERM), {
							ok = function()
								displayMsg(speaker, `@{info.UserName} was set to scribe.`)
							end,
							err = function(reason)
								warn(`[PermissionsService] Permission level set for @{info.UserName} failed.`, reason)
								displayError(speaker, `Failed to set permission level of @{info.UserName}. Try again.`)
							end,
						})
					end,
					err = function(reason)
						displayError(speaker, reason)
					end,
				})
			end
		end,
	})

	makeCommand("setguest", {
		Perm = ADMIN_PERM,
		Usage = PREFIX .. "setguest NAME..",
		Brief = "Set 1 or more players to default permissions.",
		Help = "Set 1 or more players to default permissions. Will lower permissions of scribes, admins.",
		Examples = { PREFIX .. "setguest euler", PREFIX .. "setguest euler gauss" },
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No names given")
				return
			end

			for _, name in args do
				Result.match(getUserInfoAsync(name), {
					ok = function(info)
						if info.Perm < DEFAULT_PERM then
							displayMsg(speaker, `@{info.UserName} is banned. Unban before /setguest.`)
							return
						elseif info.Perm >= 255 then
							displayMsg(speaker, `@{info.UserName} is game owner. Cannot lower permissions.`)
							return
						end

						Result.match(setPermissionLevelAsync(info.UserId, DEFAULT_PERM), {
							ok = function()
								local oldRole = toRoleName(info.Perm)
								displayMsg(
									speaker,
									`@{info.UserName} {info.Perm} ({oldRole}) -> {DEFAULT_PERM} (guest).`
								)
							end,
							err = function(reason)
								warn(`[PermissionsService] Permission level set for @{info.UserName} failed.`, reason)
								displayError(speaker, `Failed to set permission level of @{info.UserName}. Try again.`)
							end,
						})
					end,
					err = function(reason)
						displayError(speaker, reason)
					end,
				})
			end
		end,
	})

	makeCommand("setadmin", {
		Perm = ADMIN_PERM,
		Usage = PREFIX .. "setadmin NAME..",
		Brief = "Set 1 or more players to admin permissions.",
		Help = "Set 1 or more players to admin permissions.",
		Examples = { PREFIX .. "setadmin euler", PREFIX .. "setadmin euler gauss" },
		Triggered = function(speaker, args)
			if #args == 0 then
				displayError(speaker, "No names given")
				return
			end

			for _, name in args do
				Result.match(getUserInfoAsync(name), {
					ok = function(info)
						if info.Perm < DEFAULT_PERM then
							displayMsg(speaker, `@{info.UserName} is banned. Unban before /setadmin.`)
							return
						end

						Result.match(setPermissionLevelAsync(info.UserId, ADMIN_PERM), {
							ok = function()
								local oldRole = toRoleName(info.Perm)
								displayMsg(speaker, `@{info.UserName} {info.Perm} ({oldRole}) -> {ADMIN_PERM} (admin).`)

								if info.Player then
									displayMsg(info.Player, "You are an admin. Say /admin for command help.")
								end
							end,
							err = function(reason)
								warn(`[PermissionsService] Permission level set for @{info.UserName} failed.`, reason)
								displayError(speaker, `Failed to set permission level of @{info.UserName}. Try again.`)
							end,
						})
					end,
					err = function(reason)
						displayError(speaker, reason)
					end,
				})
			end
		end,
	})

	makeCommand("admin", {
		Alias = "?",
		Perm = ADMIN_PERM,
		Usage = PREFIX .. "admin",
		Brief = "Print admin help.",
		Help = "Print admin help.",
		Triggered = function(speaker)
			local message = genHelp()
			displayMsg(speaker, message)
		end,
	})
end

function Service.Start()
	-- Set Permission level attribute of present and incoming players, and kick
	-- the banned
	Stream.eachPlayer(function(player, alive)
		if not alive then
			return
		end

		local TRIES = 3
		local DELAY = 5

		for i = 1, TRIES do
			local result = getPermissionInfoAsync(player.UserId)
			if result.success then
				local perm = result.data.Perm
				if isBanned(perm) then
					player:Kick("You are banned")
				else
					syncPlayerAttributes(player, perm)
					-- Send help message to admins
					if perm >= ADMIN_PERM then
						displayMsg(player, "You are an admin. Say /admin for command help.")
					end
				end
				return
			end

			if i < TRIES then
				task.wait(DELAY)
			else
				warn(
					`[PermissionsService] Failed to initialise permissions of @{player.Name} after {TRIES} tries.`,
					result.reason
				)
			end
		end
	end)
end

return Service
