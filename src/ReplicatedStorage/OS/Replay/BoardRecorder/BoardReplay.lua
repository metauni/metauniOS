local ReplicatedStorage = game:GetService("ReplicatedStorage")

local metaboard = require(ReplicatedStorage.Packages.metaboard)
local Maid = require(ReplicatedStorage.Util.Maid)
local t = require(ReplicatedStorage.Packages.t)
local Blend = require(ReplicatedStorage.Util.Blend)

local checkProps = t.strictInterface({
	BoardParent = t.Instance,
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

		BoardInstanceRbx = t.strictInterface {
			SurfaceCFrame = t.CFrame,
			SurfaceSize = t.Vector2,
			BoardInstanceContainer = t.union(t.instanceIsA("BasePart"), t.instanceIsA("Model")),
		},
	}
})

export type BoardReplayProps = {
	BoardParent: Instance,
	Origin: CFrame,
	Record: {
		RecordType: "BoardRecord",
		Timeline: {any},
		BoardId: string,
		AspectRatio: number,

		InitialBoardState: metaboard.BoardState?,
		BoardInstanceRbx: {
			SurfaceCFrame: CFrame,
			SurfaceSize: Vector2,
			BoardInstanceContainer: BasePart | Model,
		},
	},
}

-- This mutates the board instance
local function initBoardInstance(boardContainer: BasePart | Model, parent: Instance): metaboard.BoardServer
	local boardPart = boardContainer:IsA("Model") and boardContainer.PrimaryPart or boardContainer
	assert(t.instanceIsA("BasePart")(boardPart))
	
	local function clean(instance: Instance)
		if instance.ClassName == "Folder" and instance.Name == "metaboardRemotes" then
			instance:Destroy()
			return
		end

		if instance.ClassName == "IntValue" and instance.Name == "PersistId" then
			instance:Destroy()
			return
		end

		for _, child in instance:GetChildren() do
			clean(child)
		end
	end

	clean(boardContainer)

	;(boardContainer :: any).Parent = parent
	boardPart:AddTag("metaboard")
	metaboard.Server.BoardServerBinder:Bind(boardPart)
	local boardServer = metaboard.Server.BoardServerBinder:Promise(boardPart):Wait()

	return boardServer
end

local function BoardReplay(props: BoardReplayProps): BoardReplay
	assert(checkProps(props))
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap(), props = props, ReplayType = "BoardReplay" }

	local timelineIndex = 1
	local finished = false

	-- Bad things happen if Init isn't called
	local boardServer

	local function initialiseBoardState()
		local initBoardState = table.clone(props.Record.InitialBoardState or metaboard.BoardState.emptyState(props.Record.AspectRatio))

		if boardServer.Loaded.Value == false then
			boardServer.State = initBoardState
			boardServer.Loaded.Value = true
		else
			boardServer:SetState(initBoardState)
		end
	end
	
	function self.Init()
		timelineIndex = 1
		finished = false

		local boardContainer = props.Record.BoardInstanceRbx.BoardInstanceContainer:Clone()
		boardServer = initBoardInstance(boardContainer, props.BoardParent)
		maid:GiveTask(boardContainer)

		initialiseBoardState()
	end

	function self.RewindTo(playhead: number)
		timelineIndex = 1
		finished = false
		initialiseBoardState()
		self.UpdatePlayhead(playhead)
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
				boardServer:HandleEvent(remoteName, table.unpack(args))
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
