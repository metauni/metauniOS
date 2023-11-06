-- Services
local Replay = script.Parent.Parent

-- Imports
local t = require(Replay.Parent.t)

local BoardReplay = {}
BoardReplay.__index = BoardReplay

export type ReplayArgs = {

	Board: any,
	Origin: CFrame,
}

local checkReplayArgs = t.strictInterface({

	Board = t.any,
	Origin = t.CFrame,
})

function BoardReplay.new(record: {Timeline: {any}}, replayArgs: ReplayArgs)

	assert(checkReplayArgs(replayArgs))

	local tokenToAuthorId = {}

	for authorId, token in record.AuthorIdTokens do

		if tokenToAuthorId[token] then
			
			error("[BoardReplay] Non-distinct authorId tokens")
		end
		
		tokenToAuthorId[token] = authorId
	end

	local tokenToRemoteName = {}

	for remoteName, token in record.RemoteNameTokens do

		if tokenToRemoteName[token] then
			
			error("[BoardReplay] Non-distinct remote name tokens")
		end
		
		tokenToRemoteName[token] = remoteName
	end

	return setmetatable({
		Record = record,
		__tokenToAuthorId = tokenToAuthorId,
		__tokenToRemoteName = tokenToRemoteName,
		Board = replayArgs.Board,
		Origin = replayArgs.Origin,
	}, BoardReplay)
end

function BoardReplay:Init()

	self.TimelineIndex = 1
	self.Finished = false
end

function BoardReplay:PlayUpTo(playhead: number)

	while self.TimelineIndex <= #self.Record.Timeline do

		local event = self.Record.Timeline[self.TimelineIndex]

		if event[1] <= playhead then

			local remoteName = self.__tokenToRemoteName[event[2]]
			local authorId = self.__tokenToAuthorId[event[3]]
			local args = {}

			if remoteName == "InitDrawingTask" then
				
				local taskId, taskType, width, r, g, b, x, y = unpack(event, 4)

				local drawingTask = {
					Id = taskId,
					Type = taskType,
					Curve = {
						Type = "Curve",
						Points = nil,
						Width = width,
						Color = Color3.new(r,g,b)
					},
					Verified = true,
				}

				args = {drawingTask, Vector2.new(x, y)}
			elseif remoteName == "UpdateDrawingTask" then

				local x, y = unpack(event, 4)

				args = {Vector2.new(x, y)}
			end

			for watcher in pairs(self.Board.Watchers) do
				self.Board.Remotes[remoteName]:FireClient(watcher, "replay-"..authorId, unpack(args))
			end

			self.Board["Process"..remoteName](self.Board, "replay-"..authorId, unpack(args))

			self.TimelineIndex += 1
			continue
		end

		break
	end

	if self.TimelineIndex > #self.Record.Timeline then

		self.Finished = true
	end
end

return BoardReplay
