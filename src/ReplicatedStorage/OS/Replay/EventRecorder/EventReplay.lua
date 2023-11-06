-- Services
local Replay = script.Parent.Parent

-- Imports
local t = require(Replay.Parent.t)

local EventReplay = {}
EventReplay.__index = EventReplay

local checkRecord = t.strictInterface({

	Timeline = t.table,
})

function EventReplay.new(record, callback: () -> ())

	assert(checkRecord(record))
	assert(t.callback(callback))

	return setmetatable({
		
		Record = record,
		Callback = callback,
	}, EventReplay)
end

function EventReplay:Init()

	self.TimelineIndex = 1
	self.Finished = false
end

function EventReplay:PlayUpTo(playhead: number)

	while self.TimelineIndex <= #self.Record.Timeline do

		local event = self.Record.Timeline[self.TimelineIndex]

		if event[1] <= playhead then

			self.Callback(unpack(event, 2))

			self.TimelineIndex += 1
			continue
		end

		break
	end

	if self.TimelineIndex > #self.Record.Timeline then

		self.Finished = true
	end
end

return EventReplay
