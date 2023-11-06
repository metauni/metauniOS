-- Services
local Replay = script.Parent

-- Imports
local t = require(Replay.Parent.t)

local EventRecorder = {}
EventRecorder.__index = EventRecorder

local check = t.strictInterface({

	Signal = t.union(t.typeof("RBXScriptSignal"), t.interface({ Connect = t.callback })),
	ProcessArgs = t.optional(t.callback),
})

function EventRecorder.new(args)

	assert(check(args))
	
	return setmetatable(args, EventRecorder)
end

function EventRecorder:Start(startTime)
	
	-- Start time is passed as argument for consistency between recorders
	self.StartTime = startTime
	self.Timeline = {}
	self._sizeAcc = 0
	
	self.Connection = self.Signal:Connect(function(...)
		
		local now = os.clock() - self.StartTime

		local processedArgs do
			
			if self.ProcessArgs then
				
				processedArgs = {self.ProcessArgs(...)}

			else

				processedArgs = {...}

			end
		end

		for i, arg in ipairs(processedArgs) do

			if i~= #processedArgs then
				
				-- Comma
				self._sizeAcc += 1
			end

			local argType = typeof(arg)

			if argType == "number" then
				
				self._sizeAcc += #tostring(arg)
			elseif argType == "boolean" then

				self._sizeAcc += arg and 4 or 5 -- #"true" == 4, #"false" = 5
			elseif argType == "string" then

				self._sizeAcc += #arg + 2 -- inc quotes
			elseif argType == "nil" then

				self._sizeAcc += 4 -- #"null" = 0
			else

				error(("[Replay] EventRecorder: Processed arg[%d] = %s is not a number | boolean | string | nil"):format(i, tostring(arg))) 
			end
		end
		
		table.insert(self.Timeline, {now, unpack(processedArgs)})
	end)
end

function EventRecorder:Stop()
	
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
end

function EventRecorder:FlushTimelineToRecord()
	
	local record = {
		
		Timeline = self.Timeline,
	}

	self.Timeline = {}
	self._sizeAcc = 0

	return record
end

local SCAFFOLD = #[[{"Timeline":{}}]]

function EventRecorder:GetRecordSizeEstimate()
	
	return SCAFFOLD + self._sizeAcc
end


return EventRecorder
