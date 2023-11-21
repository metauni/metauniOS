local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Imports
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local t = require(ReplicatedStorage.Packages.t)
local Maid = require(ReplicatedStorage.Util.Maid)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)

local function listen(board, Timeline: ValueObject.ValueObject<{}>, startTime: number)

	local cleanup = {}

	local remoteNames = {
		"InitDrawingTask",
		"UpdateDrawingTask",
		"FinishDrawingTask",
		"Undo",
		"Redo",
		"Clear",
	}

	for _, remoteName in remoteNames do
		local remote = board.Remotes[remoteName]

		table.insert(cleanup, remote.OnServerEvent:Connect(function(player: Player, ...)
		
			local now = os.clock() - startTime
			local authorId = tostring(player.UserId)
			-- TODO accumulate size estimation
			table.insert(Timeline.Value, {now, remote.Name, authorId, ...})
		end))
	end

	return cleanup
end

export type BoardRecorderProps = {
	Origin: CFrame,
	BoardId: string,
	Board: metaboard.BoardServer,
}

local checkProps = t.strictInterface {
	Origin = t.CFrame,
	BoardId = t.string,
	Board = t.any,
}

local function BoardRecorder(props: BoardRecorderProps): BoardRecorder
	assert(checkProps(props))
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap() , props = props, RecorderType = "BoardRecorder" }

	local Timeline = ValueObject.new({})
	-- This goes from nil to a boardState on Start, and back to nil on FlushToRecord
	local InitialBoardState = ValueObject.new(nil :: metaboard.BoardState?)

	function self.Start(startTime: number)
		Timeline.Value = {}
		-- TODO: This has an immutable Figures and DrawingTasks,
		-- but other tables are mutable (which aren't used). Probably doesn't matter
		-- but not ideal.
		InitialBoardState.Value = table.clone(props.Board.State)
		maid._listening = listen(props.Board, Timeline, startTime)
	end

	function self.Stop()
		maid._listening = nil
	end

	function self.FlushToRecord()
		local record = {
			RecordType = "BoardRecord",
			BoardId = props.BoardId,
			Timeline = Timeline.Value,
			AspectRatio = props.Board:GetAspectRatio(),

			InitialBoardState = InitialBoardState.Value
		}
		Timeline.Value = {}
		InitialBoardState.Value = nil
		return record
	end

	return self
end

export type BoardRecorder = typeof(BoardRecorder(nil :: any))

return BoardRecorder
