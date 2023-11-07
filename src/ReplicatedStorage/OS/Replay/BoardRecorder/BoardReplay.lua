local ReplicatedStorage = game:GetService("ReplicatedStorage")

local t = require(ReplicatedStorage.Packages.t)

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

export type BoardRecord = {
	Timeline: {any},
}

function BoardReplay.new(record: BoardRecord, replayArgs: ReplayArgs)

	assert(checkReplayArgs(replayArgs))

	return setmetatable({
		Record = record,
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
			local remoteName, authorId = table.unpack(event, 2, 3)
			local args = {"replay-"..authorId}
			table.move(event, 4, #event, 2, args)
			--[[
				e.g. if event is {"InitDrawingTask", "1234", drawingTask, canvasPos}
				then result is {"replay-1234", drawingTask, canvaPos}
			]]
			self.Board:HandleEvent(remoteName, table.unpack(args))
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
