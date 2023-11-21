local ReplicatedStorage = game:GetService("ReplicatedStorage")

local metaboard = require(ReplicatedStorage.Packages.metaboard)
local Maid = require(ReplicatedStorage.Util.Maid)
local t = require(ReplicatedStorage.Packages.t)

local checkProps = t.strictInterface({
	Board = t.any,
	Origin = t.CFrame,
	Record = t.strictInterface {
		RecordType = t.literal("BoardRecord"),
		Timeline = t.table,
		BoardId = t.string,
		AspectRatio = t.numberPositive,

		InitialBoardState = t.optional(t.interface {
			AspectRatio = t.numberPositive,
			NextFigureZIndex = t.integer,
			ClearCount = t.optional(t.integer),
			Figures = t.table,
			DrawingTasks = t.table,
		}),
	}
})

export type BoardReplayProps = {
	Board: metaboard.BoardServer,
	Origin: CFrame,
	Record: {
		RecordType: "BoardRecord",
		Timeline: {any},
		BoardId: string,

		InitialBoardState: metaboard.BoardState?,
	},
}

local function BoardReplay(props: BoardReplayProps): BoardReplay
	assert(checkProps(props))
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap(), props = props }

	local timelineIndex = 1
	local finished = false

	function self.Init()
		timelineIndex = 1
		finished = false

		if props.Record.InitialBoardState then
			props.Board:SetState(props.Record.InitialBoardState)
		end
	end

	function self.IsFinished()
		return finished
	end
	
	function self.UpdatePlayhead(playhead: number)
	
		while timelineIndex <= #props.Record.Timeline do
	
			local event = props.Record.Timeline[timelineIndex]
	
			if event[1] <= playhead then
				local remoteName, authorId = table.unpack(event, 2, 3)
				local args = {"replay-"..authorId}
				table.move(event, 4, #event, 2, args)
				--[[
					e.g. if event is {"InitDrawingTask", "1234", drawingTask, canvasPos}
					then result is {"replay-1234", drawingTask, canvaPos}
				]]
				props.Board:HandleEvent(remoteName, table.unpack(args))
				timelineIndex += 1
				continue
			end
	
			break
		end
	
		if timelineIndex > #props.Record.Timeline then
	
			finished = true
		end
	end

	return self
end

export type BoardReplay = typeof(BoardReplay(nil :: any))

return BoardReplay
