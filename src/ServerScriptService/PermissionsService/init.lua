local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Promise = require(ReplicatedStorage.Packages.Promise)
local Sift = require(ReplicatedStorage.Packages.Sift)

local PermissionsService = {}

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

local Remotes = ReplicatedStorage.PermissionsController.Remotes
local GlobalPermissionsDataStore = DataStoreService:GetDataStore("permissionsDataStore")

function PermissionsService:_makeCommand(name: string, args: table)
	
	local command = Instance.new("TextChatCommand")

	command.Name = name
	command.PrimaryAlias = "/"..name
	if args.Alias then
		command.SecondaryAlias = "/"..args.Alias
	end
	command.Triggered:Connect(function(originTextSource: TextSource, unfilteredText: string)
		
		local userId = originTextSource.UserId
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			warn(`[PermissionsService] Couldn't find player who triggered command: {tostring(unfilteredText)}`)
			return
		end

		Remotes.DisplaySystemMessage:FireClient(player, "> "..unfilteredText, Color3.fromHex("#808080"))

		self:promisePermissionLevel(userId)
			:andThen(function(permission_level)
				
				-- Allow commands in Studio, but restrict to args.Perm in live game
				if not RunService:IsStudio() and permission_level < args.Perm then
					Remotes.DisplaySystemMessage:FireClient(player, `You ({permission_level}) must have permission level >={args.Perm} to use this command.`,Color3.new(1, 0, 0))
					return
				end
				
				local commandArgs = {}
				for arg in unfilteredText:sub(#command.PrimaryAlias+2):gmatch("%s*(%S+)%s*") do
					table.insert(commandArgs, arg)
				end
				
				if self._lastCommandPromise and Promise.is(self._lastCommandPromise) then
					self._lastCommandPromise:cancel()
				end
				self._lastCommandPromise = args.Triggered(player, commandArgs)
			end)
			:catch(function(msg)
				warn(`[PermissionsService] Permission level fetch failed (UserId: {userId})\n`..tostring(msg))
				Remotes.DisplaySystemMessage:FireClient(player, `Failed to get your permission level. Try again.`, Color3.new(1,0,0))
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
			
			local userId = originTextSource.UserId
			local player = Players:GetPlayerByUserId(userId)
			if not player then
				warn(`[PermissionsService] Couldn't find player with userId {userId} who triggered command: {tostring(unfilteredText)}`)
				return
			end
			
			Remotes.DisplaySystemMessage:FireClient(player, "> "..unfilteredText, Color3.fromHex("#808080"))

			local helpMessage = `{args.Help}\nUsage:{args.Usage}`
			if args.Examples and #args.Examples > 0 then
				helpMessage = helpMessage.."\nExamples:\n  "..table.concat(args.Examples, "\n  ")
			end
			
			Remotes.DisplaySystemMessage:FireClient(player, helpMessage)
		end)
		helpCommand.Parent = TextChatService
	end
end

function PermissionsService:promisePermissionsDataStore()

	local Pocket = ReplicatedStorage.Pocket
	local POCKET_PATTERN = "metadmin.%s"
	local PRIVATE_SERVER_PATTERN = "metadmin.%s"
	local TRS = "permissionsDataStore"

	if game.PrivateServerId ~= ""then
		if game.PrivateServerOwnerId == 0 then
			-- Pocket (Reserved Server)
			return Promise.new(function()
				if Pocket:GetAttribute("PocketId") == nil then
					Pocket:GetAttributeChangedSignal("PocketId"):Wait()
				end
				local pocketId = Pocket:GetAttribute("PocketId")
				DataStoreService:GetDataStore(POCKET_PATTERN:format(pocketId))
			end)
		else
			-- Private Server
			return Promise.resolve(DataStoreService:GetDataStore(PRIVATE_SERVER_PATTERN:format(game.PrivateServerOwnerId)))
		end
	else
		-- TRS
		return Promise.resolve(DataStoreService:GetDataStore(TRS))
	end
end

function PermissionsService:promisePermissionLevel(userId: number)

	local function waitForGetBudget()
		while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) <= 0 do
			task.wait(0.5)
		end
	end

	if self._permCache[tostring(userId)] then
		return Promise.resolve(unpack(self._permCache[tostring(userId)]))
	else
		return self:promisePermissionsDataStore()
			:andThen(function(datastore: DataStore)

				local success, result, source = pcall(function()
					
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
					self._permCache[tostring(userId)] = {result, source}
					return result, source
				else
					return Promise.reject(result)
				end
			end)
	end
end

function PermissionsService:_syncPlayerAttributes(player: Player, perm: number)
	player:SetAttribute(PERMISSION_ATTRIBUTE, perm)
	player:SetAttribute("metaadmin_isscribe", perm >= SCRIBE_PERM)
	player:SetAttribute("metaadmin_canwrite", perm >= SCRIBE_PERM)
	player:SetAttribute("metaadmin_isadmin", perm >= ADMIN_PERM)
end

function PermissionsService:promiseSetPermissionLevel(userId: number, level: number)
	return self:promisePermissionsDataStore()
		:andThen(function(datastore: DataStore)

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
				return level
			else
				return Promise.reject(result)
			end
		end)
end

function PermissionsService:Init()

	self.Commands = {}
	self._commandData = {}
	self._helpOrder = {}
	self._permCache = {}

	local function promiseUserIdAndUserName(givenName: string)
		return Promise.new(function(resolve, reject)
			
			-- Pattern: Starts with @, then one or more non-@ characters, which are captured
			local userName = givenName:match("^@([^@]+)")
			local players = Players:GetPlayers()

			if userName then
				
				for _, player in players do
					if player.Name == userName then
						resolve(player.UserId, player.Name)
						return
					end
				end
	
				local success, result = pcall(function()
					return Players:GetUserIdFromNameAsync(userName)
				end)
				if success then
					resolve(result, userName)
				else
					reject(result)
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
						reject(`No in-game players with DisplayName={givenName}.\nDid you mean {userNameMatches[1].DisplayName} (@{userNameMatches[1].Name})?`)
					else
						reject(`No in-game players with DisplayName={givenName}.\nSpecify @USERNAME`)
					end
				elseif #displayNameMatches > 1 then
					reject(`Multiple in-game players with DisplayName={givenName}.\nSpecify @USERNAME`)
				else
					resolve(displayNameMatches[1].UserId, displayNameMatches[1].Name)
				end
			end
		end)
	end

	local function onGetPermFail(speaker: Player, username: string)
		return function(...)
			warn(`[PermissionsService] Permission level fetch for @{username} failed.`, ...)
			Remotes.DisplaySystemMessage:FireClient(speaker, `Failed to get permission level of @{username}. Try again.`, Color3.new(1,0,0))
		end
	end

	local function onSetPermFail(speaker: Player, username: string)
		return function(...)
			warn(`[PermissionsService] Permission level set for @{username} failed.`, ...)
			Remotes.DisplaySystemMessage:FireClient(speaker, `Failed to set permission level of @{username}. Try again.`, Color3.new(1,0,0))
		end
	end

	local function respondWithError(speaker: Player)
		return function (...)
			Remotes.DisplaySystemMessage:FireClient(speaker, ..., Color3.new(1,0,0))
		end
	end

	self:_makeCommand("kick", {
		Usage = PREFIX.."kick NAME [reason]",
		Brief = "Kick a player, with an optional message",
		Help = "Kick a player, with an optional message. This will instantly remove them from the game, but they can rejoin again immediately.",
		Examples = {PREFIX.."kick newton bye bye"},
		Perm = ADMIN_PERM,
		Triggered = function(speaker, args)

			if #args == 0 then
				Remotes.DisplaySystemMessage:FireClient(speaker, "No targets specified", Color3.new(1, 0, 0))
				return
			end

			local speakerPerm = speaker:GetAttribute(PERMISSION_ATTRIBUTE)
			local kick_message = table.concat(args, " ", 2)

			return promiseUserIdAndUserName(args[1])
				:andThen(function(userId: number, username: string)
		
					local target = Players:GetPlayerByUserId(userId)
					if not target then
						Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} not found in game`, Color3.new(1,0,0))
						return
					end
					
					return self:promisePermissionLevel(userId)
						:andThen(function(targetPerm)
							
							if targetPerm < speakerPerm or speaker.UserId == userId then
								target:Kick(kick_message)
								Remotes.DisplaySystemMessage:FireClient(speaker, "Kicked "..target.Name)
							else
								Remotes.DisplaySystemMessage:FireClient(speaker, `You cannot use this command on @{username}. They outrank you.`, Color3.new(1,0,0))
							end
						end)
						:catch(onGetPermFail(speaker, username))
				end)
				:catch(respondWithError(speaker))
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
				Remotes.DisplaySystemMessage:FireClient(speaker, "No targets specified", Color3.new(1, 0, 0))
				return
			end

			local speakerPerm = speaker:GetAttribute(PERMISSION_ATTRIBUTE)
			local givenName = args[1]
			local warn_message = table.concat(args, " ", 2)

			return promiseUserIdAndUserName(givenName)
				:andThen(function(userId: number, username: string)
		
					local target = Players:GetPlayerByUserId(userId)
					if not target then
						Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} not found in game`, Color3.new(1,0,0))
						return
					end
					
					return self:promisePermissionLevel(userId)
						:andThen(function(perm)
							
							if perm < speakerPerm or speaker.UserId == userId then
								Remotes.DisplaySystemMessage:FireClient(target, warn_message, Color3.new(1,0,0))
								Remotes.DisplaySystemMessage:FireClient(speaker, `Warned @{username}`)
							else
								Remotes.DisplaySystemMessage:FireClient(speaker, `You cannot use this command on @{username}={perm}. They outrank you={speakerPerm}.`, Color3.new(1,0,0))
							end
						end)
						:catch(onGetPermFail(speaker))
				end)
				:catch(respondWithError(speaker))
		end
	})

	self:_makeCommand("perm", {
		Perm = ADMIN_PERM,
		Usage = PREFIX.."perm NAME...",
		Brief = "Check a players permission level",
		Help = "Check a players permission level",
		Triggered = function(speaker, args)
			if #args == 0 then
				Remotes.DisplaySystemMessage:FireClient(speaker, "No names given", Color3.new(1, 0, 0))
				return
			end

			local promises = table.create(#args)

			for _, name in args do

				promises[#promises+1] =
					promiseUserIdAndUserName(name)
						:andThen(function(userId: number, username: string)
							return self:promisePermissionLevel(userId)
								:andThen(function(perm, source)
									Remotes.DisplaySystemMessage:FireClient(speaker, `@{username}: {perm} ({toRoleName(perm)}, {source})`)
								end)
								:catch(onGetPermFail(speaker, username))
						end)
						:catch(respondWithError(speaker))
			end

			return Promise.allSettled(promises)
		end
	})

	self:_makeCommand("allperms", {
		Perm = ADMIN_PERM,
		Usage = PREFIX.."allperms",
		Brief = "Print the permissions of every player in-game",
		Help = "Print the permissions of every player in-game",
		Triggered = function(speaker, _args)

			local players = Players:GetPlayers()
			local promises = table.create(#players)
			
			for _, player in players do
				promises[#promises+1] = 
					self:promisePermissionLevel(player.UserId)
						:andThen(function(perm)
							Remotes.DisplaySystemMessage:FireClient(speaker, `@{player.Name}: {perm} ({toRoleName(perm)})`)
						end)
						:catch(onGetPermFail(speaker, player.Name))
			end

			return Promise.allSettled(promises)
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
				Remotes.DisplaySystemMessage:FireClient(speaker, "No names given", Color3.new(1, 0, 0))
				return
			end

			local promises = table.create(#args)

			for _, givenName in args do

				promises[#promises+1] =
					promiseUserIdAndUserName(givenName)
						:andThen(function(userId: number, username: string)

							return self:promisePermissionLevel(userId)
								:andThen(function(perm)

									if perm >= ADMIN_PERM then
										Remotes.DisplaySystemMessage:FireClient(speaker, "You cannot ban an admin.", Color3.new(1,0,0))
										return
									end
									
									local player = Players:GetPlayerByUserId(userId)
									if player then
										player:Kick("You have been banned by an admin")
									end

									if perm < DEFAULT_PERM then
										if player then
											Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} is already banned. They were kicked from this game."`)
										else
											Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} is already banned.`)
										end
									else
										return self:promiseSetPermissionLevel(userId, DEFAULT_PERM-1)
											:andThen(function()
												if player then
													Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} was banned and kicked from this game."`)
												else
													Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} was banned`)
												end
											end)
											:catch(onSetPermFail(speaker, username))
									end
								end)
								:catch(onGetPermFail(speaker, username))
						end)
						:catch(respondWithError(speaker))
			end

			return Promise.allSettled(promises)
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
				Remotes.DisplaySystemMessage:FireClient(speaker, "No names given", Color3.new(1, 0, 0))
				return
			end

			local promises = table.create(#args)

			for _, givenName in args do

				promises[#promises+1] =
					promiseUserIdAndUserName(givenName)
						:andThen(function(userId: number, username: string)

							return self:promisePermissionLevel(userId)
								:andThen(function(perm)

									if perm >= ADMIN_PERM then
										Remotes.DisplaySystemMessage:FireClient(speaker, "You cannot ban/unban an admin.", Color3.new(1,0,0))
										return
									end

									if perm >= DEFAULT_PERM then
										Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} is already not-banned (Permission Level {perm}).`)
									else
										return self:promiseSetPermissionLevel(userId, DEFAULT_PERM)
											:andThen(function()
												Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} was unbanned.`)
											end)
											:catch(onSetPermFail(speaker, username))
									end
								end)
								:catch(onGetPermFail(speaker, username))
						end)
						:catch(respondWithError(speaker))
			end

			return Promise.allSettled(promises)
		end})

	self:_makeCommand("setscribe", {
		Perm = ADMIN_PERM,
		Usage = PREFIX.."setscribe NAME..",
		Brief = "Give scribe permissions to 1 or more players",
		Help = "Give scribe permissions to 1 or more players.",
		Examples = {PREFIX.."setscribe euler", PREFIX.."setscribe euler gauss"},
		Triggered = function(speaker, args)

			if #args == 0 then
				Remotes.DisplaySystemMessage:FireClient(speaker, "No names given", Color3.new(1, 0, 0))
				return
			end

			local promises = table.create(#args)

			for _, name in args do

				promises[#promises+1] =
					promiseUserIdAndUserName(name)
						:andThen(function(userId: number, username: string)
			
							return self:promisePermissionLevel(userId)
								:andThen(function(currentPerm)
			
									if currentPerm >= SCRIBE_PERM then
										Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} already >=scribe.`)
										return
									elseif currentPerm < DEFAULT_PERM then
										Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} is banned. Unban before /setscribe.`)
									else
										return self:promiseSetPermissionLevel(userId, SCRIBE_PERM)
											:andThen(function()
												Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} was set to scribe.`)
											end)
											:catch(onSetPermFail(speaker, username))
									end
								end)
								:catch(onGetPermFail(speaker, username))
						end)
						:catch(respondWithError(speaker))
			end

			return Promise.allSettled(promises)
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
			local promises = table.create(#players)

			for _, player in players do

				promises[#promises+1] =
					self:promisePermissionLevel(player.UserId)
						:andThen(function(currentPerm)

							if currentPerm >= SCRIBE_PERM then
								Remotes.DisplaySystemMessage:FireClient(speaker, `@{player.Name} already >=scribe.`)
								return
							elseif currentPerm < DEFAULT_PERM then
								Remotes.DisplaySystemMessage:FireClient(speaker, `@{player.Name} is banned. Unban before /setscribe.`)
							else
								return self:promiseSetPermissionLevel(player.UserId, SCRIBE_PERM)
									:andThen(function()
										Remotes.DisplaySystemMessage:FireClient(speaker, `@{player.Name} was set to scribe.`)
									end)
									:catch(onSetPermFail(speaker, player.Name))
							end
						end)
						:catch(onGetPermFail(speaker, player.Name))
			end

			return Promise.allSettled(promises)
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
				Remotes.DisplaySystemMessage:FireClient(speaker, "No names given", Color3.new(1, 0, 0))
				return
			end

			local promises = table.create(#args)

			for _, name in args do

				promises[#promises+1] =
					promiseUserIdAndUserName(name)
						:andThen(function(userId: number, username: string)
			
							return self:promisePermissionLevel(userId)
								:andThen(function(currentPerm)
			
									if currentPerm < DEFAULT_PERM then
										Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} is banned. Unban before /setguest.`)
									elseif currentPerm >= 255 then
										Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} is game owner. Cannot lower permissions.`)
									else
										return self:promiseSetPermissionLevel(userId, DEFAULT_PERM)
											:andThen(function()
												local oldRole = toRoleName(currentPerm)
												Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} {currentPerm} ({oldRole}) -> {DEFAULT_PERM} (guest).`)
											end)
											:catch(onSetPermFail(speaker, username))
									end
								end)
								:catch(onGetPermFail(speaker, username))
						end)
						:catch(respondWithError(speaker))
			end

			return Promise.allSettled(promises)
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
				Remotes.DisplaySystemMessage:FireClient(speaker, "No names given", Color3.new(1, 0, 0))
				return
			end

			local promises = table.create(#args)

			for _, name in args do

				promises[#promises+1] =
					promiseUserIdAndUserName(name)
						:andThen(function(userId: number, username: string)
			
							return self:promisePermissionLevel(userId)
								:andThen(function(currentPerm)
			
									if currentPerm < DEFAULT_PERM then
										Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} is banned. Unban before /setadmin.`)
									else
										return self:promiseSetPermissionLevel(userId, ADMIN_PERM)
											:andThen(function()
												local oldRole = toRoleName(currentPerm)
												Remotes.DisplaySystemMessage:FireClient(speaker, `@{username} {currentPerm} ({oldRole}) -> {ADMIN_PERM} (admin).`)

												local newAdminPlayer = Players:GetPlayerByUserId(userId)
												if newAdminPlayer then
													self:_onAdmin(newAdminPlayer)
												end
											end)
											:catch(onSetPermFail(speaker, username))
									end
								end)
								:catch(onGetPermFail(speaker, username))
						end)
						:catch(respondWithError(speaker))
			end

			return Promise.allSettled(promises)
		end
	})

	self:_makeCommand("admin", {
		Alias = "?",
		Perm = ADMIN_PERM,
		Usage = PREFIX.."admin",
		Brief = "Print admin help.",
		Help = "Print admin help.",
		Triggered = function(speaker, _args)
			local message = self:_genHelp()
			Remotes.DisplaySystemMessage:FireClient(speaker, message)
		end})
end

function PermissionsService:_genHelp()
	local message = ""
		for _, name in self._helpOrder do

			local data = self._commandData[name]
			if data.Usage then
				message = message..data.Usage.."\n"
				if data.Brief then
					message = message.."\n  "..data.brief
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
	local onPlayer = function(player)
		local TRIES = 3
		local DELAY = 5

		Promise.retryWithDelay(function()
				return self:promisePermissionLevel(player.UserId)
			end, TRIES, DELAY)
			:andThen(function(perm)
				if isBanned(perm) then
					player:Kick("You are banned")
				else
					self:_syncPlayerAttributes(player, perm)
					-- Send help message to admins
					if perm >= ADMIN_PERM then
						self:_onAdmin(player)
					end
				end
			end)
			:catch(function(msg)
				warn(`[PermissionsService] Failed to initialise permissions of @{player.Name} after {TRIES} tries.`, msg)
			end)
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return PermissionsService



