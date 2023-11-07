--[[
	For managing the recording, and editing of a replay recording.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseObject = require(ReplicatedStorage.Util.BaseObject)

local ReplayStudio = setmetatable({}, BaseObject)
ReplayStudio.__index = ReplayStudio

function ReplayStudio.new()
	local self = setmetatable(BaseObject.new(), ReplayStudio)

	self.Boards = {}
	self.CharacterIdToPlayerId = {}

	return self
end

function ReplayStudio:TrackBoard(boardId: string, board)
	assert(typeof(board) == "table", "Bad board")
	if self.Boards[boardId] then
		error(`[ReplayStudio] BoardId {boardId} already tracked`)
	end
end

function ReplayStudio:TrackPlayerCharacter(characterId: string, player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	local userId = player.UserId
	if self.CharacterIdToPlayerId[characterId] then
		error(`[ReplayStudio] Player with userId {player.UserId} already tracked`)
	end
	self.CharacterIdToPlayerId[userId] = player.UserId
end

function ReplayStudio:IsPlayerCharacterTracked(characterId: string)
	return self.CharacterIdToPlayerId[characterId] ~= nil
end



return ReplayStudio