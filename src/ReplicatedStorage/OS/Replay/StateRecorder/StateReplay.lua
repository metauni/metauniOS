local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateRecorder = require(script.Parent)
local Maid = require(ReplicatedStorage.Util.Maid)
local t = require(ReplicatedStorage.Packages.t)

local checkProps = t.strictInterface {
	Record = t.strictInterface {
		RecordType = t.literal("StateRecord"),
		StateType = t.string,
		StateInfo = t.table,
		Timeline = t.table,
	},
	Handler = t.callback,
}

type State = any

--[[
	Replays a timeline of states with a handler.
	Only calls the handler on the most recent state after the playhead,
	possibly skipping intermediate states
]]
local function StateReplay(props: {
		Record: StateRecorder.StateRecord,
		Handler: (State) -> (),
	}): StateReplay
	assert(checkProps(props))
	local maid = Maid.new()
	local self = { Destroy = maid:Wrap(), props = props, ReplayType = "StateReplay" }

	local finished = false
	local timelineIndex = 1

	function self.Init()
		finished = false
		timelineIndex = 1
	end

	function self.RewindTo(playhead: number)
		self.Init()
		self.UpdatePlayhead(playhead)
	end

	function self.IsFinished()
		return finished
	end
	
	function self.UpdatePlayhead(playhead: number)
	
		while timelineIndex <= #props.Record.Timeline do
			local event = props.Record.Timeline[timelineIndex]
			local nextEvent = props.Record.Timeline[timelineIndex+1]
			if event[1] <= playhead then
				-- Skip this one if the next is also after playhead
				if nextEvent and nextEvent[1] <= playhead then
					timelineIndex += 1
					continue
				end

				local state = event[2]
				props.Handler(state)

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

export type StateReplay = typeof(StateReplay(nil :: any))

return StateReplay
