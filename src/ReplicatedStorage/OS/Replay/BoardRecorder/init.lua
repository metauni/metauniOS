-- Services
local Replay = script.Parent

-- Imports
local t = require(Replay.Parent.t)
local remoteTokens = require(script.remoteTokens)

local BoardRecorder = {}
BoardRecorder.__index = BoardRecorder

local check = t.strictInterface({

	Board = t.any,
	Origin = t.CFrame,
})

function BoardRecorder.new(args)

	assert(check(args))
	
	return setmetatable(args, BoardRecorder)
end

local NUM_LENGTH_EST = 20 -- Average is about 19.26

function BoardRecorder:Start(startTime)
	
	-- Start time is passed as argument for consistency between recorders
	self.StartTime = startTime
	self.Timeline = {}
	self._sizeAcc = 0
	
	self.RemoteNameTokens = remoteTokens
	self.AuthorIdTokens = {}
	
	local newAuthorIdToken = function()
		
		local maxToken = 0
		for _, token in self.AuthorIdTokens do
			
			maxToken = math.max(maxToken, token)
		end

		return maxToken + 1
	end
	
	local connections = {}


	for remoteName, remoteToken in self.RemoteNameTokens do
		
		if remoteName == "InitDrawingTask" then

			table.insert(connections, self.Board.Remotes[remoteName].OnServerEvent:Connect(function(player, drawingTask, canvasPos)

				local now = os.clock() - self.StartTime
				
				local authorId = tostring(player.UserId)
				local authorIdToken = self.AuthorIdTokens[authorId] or newAuthorIdToken()
				self.AuthorIdTokens[authorId] = authorIdToken

				local taskId = drawingTask.Id
				local taskType = drawingTask.Type
				local width = drawingTask.Curve.Width
				local color = drawingTask.Curve.Color

				self._sizeAcc +=
					NUM_LENGTH_EST -- now
					+ 1 -- remoteToken
					+ #tostring(authorIdToken) -- authorIdToken
					+ #taskId + 2
					+ #taskType + 2
					+ 6 * NUM_LENGTH_EST -- rest of the numbers
					+ 12 -- braces and commas

				table.insert(self.Timeline, {now, remoteToken, authorIdToken, taskId, taskType, width, color.R, color.G, color.B, canvasPos.X, canvasPos.Y})
			end))
		elseif remoteName == "UpdateDrawingTask" then
			
			table.insert(connections, self.Board.Remotes[remoteName].OnServerEvent:Connect(function(player, canvasPos)
	
				local now = os.clock() - self.StartTime
				
				local authorId = tostring(player.UserId)
				local authorIdToken = self.AuthorIdTokens[authorId] or newAuthorIdToken()
				self.AuthorIdTokens[authorId] = authorIdToken

				self._sizeAcc += 3 * NUM_LENGTH_EST + #tostring(authorIdToken) + 9 -- inc braces, commas, quotes, remoteToken

				table.insert(self.Timeline, {now, remoteToken, authorIdToken, canvasPos.X, canvasPos.Y})
			end))

		else

			table.insert(connections, self.Board.Remotes[remoteName].OnServerEvent:Connect(function(player)
	
				local now = os.clock() - self.StartTime
				
				local authorId = tostring(player.UserId)
				local authorIdToken = self.AuthorIdTokens[authorId] or newAuthorIdToken()
				self.AuthorIdTokens[authorId] = authorIdToken

				self._sizeAcc += NUM_LENGTH_EST + #tostring(authorIdToken) + 7 -- inc braces, commas, quotes, remoteToken

				table.insert(self.Timeline, {now, remoteToken, authorIdToken})
			end))
		end
	end
	
	self.Connections = connections
end

function BoardRecorder:Stop()
	
	for _, con in ipairs(self.Connections or {}) do
		con:Disconnect()
	end

	self.Connections = nil
end

function BoardRecorder:FlushTimelineToRecord()
	
	local record = {
		
		Timeline = self.Timeline,
		AuthorIdTokens = self.AuthorIdTokens,
		RemoteNameTokens = self.RemoteNameTokens,
	}

	self.Timeline = {}
	self._sizeAcc = 0

	return record
end

local SCAFFOLD = #[[{"Timeline":{},"AuthorIdTokes":{},"RemoteNameTokens":{}}]]

function BoardRecorder:GetRecordSizeEstimate()

	local size = self._sizeAcc

	for authorId, token in self.AuthorIdTokens do
		
		size += #authorId + #tostring(token) + 3 -- quotes and comma
	end

	for remoteName, token in self.RemoteNameTokens do
		
		size += #remoteName + #tostring(token) + 3 -- quotes and comma
	end
	
	return size + SCAFFOLD
end


return BoardRecorder
