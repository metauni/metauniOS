-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Chunker = require(ReplicatedStorage.Packages.Chunker)
local BoardRecorder = require(script.Parent.BoardRecorder)
local BoardSerialiser = require(script.Parent.BoardSerialiser)
local EventRecorder = require(script.Parent.EventRecorder)
local HumanoidDescriptionSerialiser = require(script.Parent.HumanoidDescriptionSerialiser)
local VRCharacterRecorder = require(script.Parent.VRCharacterRecorder)

local TalkRecorder = {}
TalkRecorder.__index = TalkRecorder

--[[
	NOTE: The keys of the boards table are used as identifiers for each board
	and are used in the datastore keys for each board (so keep them short)
	The boards table can be a dictionary or an array (which will result in numeric keys).

	If it's an array. Ensure to keep the order consistent (don't use :GetChildren() anywhere).
--]]
function TalkRecorder.new(args)

	local self = setmetatable({
		
		Origin = args.Origin,
		Boards = args.Boards,
		Players = args.Players,
		
		DataStore = args.DataStore,
		ReplayId = args.ReplayId
	}, TalkRecorder)

	self.BoardRecorders = {}
	self.VRCharacterRecorders = {}
	self.ChalkRecorders = {}

	self.InitBoardStates = {}
	self.InitChalkStates = {}

	for boardId, board in self.Boards do

		self.BoardRecorders[boardId] = BoardRecorder.new({

			Board = board,
			Origin = self.Origin
		})
	end

	for _, player in ipairs(self.Players) do

		local userId = tostring(player.UserId)

		self.VRCharacterRecorders[userId] = VRCharacterRecorder.new({

			Player = player,
			Origin = self.Origin,
		})

		local character = player.Character or player.CharacterAdded:Wait()

		local chalk = character:FindFirstChild("MetaChalk")
			or player.Backpack:FindFirstChild("MetaChalk")
			or error("[Replay] "..player.DisplayName.." has no chalk")

		self.ChalkRecorders[userId] = EventRecorder.new({

			Signal = chalk.AncestryChanged,
			ProcessArgs = function()
				
				return chalk.Parent == player.Character
			end,
		})
	end
	
	self.RecordCount = 0

	return self
end

function TalkRecorder:__allRecorders()

	local recorders = {}

	for _, recorderGroup in ipairs({self.BoardRecorders, self.VRCharacterRecorders, self.ChalkRecorders}) do

		for _, recorder in recorderGroup do

			table.insert(recorders, recorder)
		end
	end

	return recorders
end

local function storeRecord(self)

	self.RecordCount += 1
	local recordIndex = self.RecordCount

	local getRecords = function(recorders)

		local records = {}

		for id, recorder in recorders do

			records[id] = recorder:FlushTimelineToRecord()
		end

		return records
	end

	local record = {
		BoardRecords = getRecords(self.BoardRecorders),
		VRCharacterRecords = getRecords(self.VRCharacterRecorders),
		ChalkRecords = getRecords(self.ChalkRecorders),
	}

	while true do

		local success, errormsg = pcall(function()

			while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync) <= 0 do

				task.wait()
			end

			self.DataStore:SetAsync("Records/"..self.ReplayId.."/"..recordIndex, record)
		end)

		if success then

			break
		else

			warn("[Replay] "..errormsg)
			task.wait(2)
		end
	end
	
	while true do

		local success, errormsg = pcall(function()

			while math.min(DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync), DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync)) <= 0 do

				task.wait()
			end
			
			self.DataStore:UpdateAsync("ReplayIndex/"..self.ReplayId, function(data)
				
				data.RecordCount = data.RecordCount + 1
				
				return data
			end)
		end)

		if success then

			break
		else

			warn("[Replay] "..errormsg)
			task.wait(2)
		end
	end

end

function TalkRecorder:Start()

	for boardId, board in self.Boards do

		local figures = board:CommitAllDrawingTasks()
		local nextFigureZIndex = board.NextFigureZIndex
		local surfaceCFrame = self.Origin:Inverse() * board.SurfaceCFrame
		local surfaceSize = board.SurfaceSize
		
		self.InitBoardStates[boardId] = BoardSerialiser.Serialise(figures, nextFigureZIndex, surfaceCFrame, surfaceSize)
	end

	for _, player in ipairs(self.Players) do

		local userId = tostring(player.UserId)

		if self.VRCharacterRecorders[userId] then

			self.InitChalkStates[userId] = player.Character:FindFirstChild("MetaChalk") ~= nil
		end
	end

	local vrCharacters = {}

	for _, player in ipairs(self.Players) do

		local userId = tostring(player.UserId)

		if self.VRCharacterRecorders[userId] then

			local serialisedHumanoidDescription = HumanoidDescriptionSerialiser.Serialise(player.Character.Humanoid.HumanoidDescription) -- TODO: assumes Character is there

			vrCharacters[userId] = {

				HumanoidDescription = serialisedHumanoidDescription,
				RigType = player.Character.Humanoid.RigType.Name
			}
		end
	end
	
	-- Globally agreed start time across recorders
	self.StartTime = os.clock()

	for _, recorder in self:__allRecorders() do

		recorder:Start(self.StartTime)
	end
	
	self._recorderStoreThread = task.spawn(function()
		
		while true do
			
			task.wait(1)
			
			local totalSizeEstimate = 0
			
			for _, recorder in self:__allRecorders() do

				totalSizeEstimate += recorder:GetRecordSizeEstimate()
			end
			
			if totalSizeEstimate > 3900000 then
				
				print("[TalkRecorder] Storing Record with an estimate of", totalSizeEstimate, "bytes")
				storeRecord(self)
			end
		end
	end)

	local data = {

		_FormatVersion = "Talk-v1",
		RecordCount = 0,
		VRCharacters = vrCharacters,
	}

	while true do

		local success, errormsg = pcall(function()

			self.DataStore:SetAsync("ReplayIndex/"..self.ReplayId, data)
		end)

		if success then

			break
		else

			warn("[Replay] "..errormsg)
			task.wait(2)
		end
	end
	
	local initState = {
		
		InitBoardStates = self.InitBoardStates,
		InitChalkStates = self.InitChalkStates,
	}

	while true do

		local success, errormsg = pcall(function()

			Chunker.SetChunkedAsync(self.DataStore, "Records/"..self.ReplayId.."/InitState", initState)
		end)

		if success then

			break
		else

			warn("[Replay] "..errormsg)
			task.wait(2)
		end
	end
	
	print("[Replay] Recording replay "..tostring(self.ReplayId).." to datastore", self.DataStore.Name)
end

function TalkRecorder:Stop()

	for _, recorder in self:__allRecorders() do

		recorder:Stop()
	end
	
	coroutine.close(self._recorderStoreThread)
	
	local totalSizeEstimate = 0

	for _, recorder in self:__allRecorders() do

		totalSizeEstimate += recorder:GetRecordSizeEstimate()
	end
	
	print("[TalkRecorder] Storing Record with an estimate of", totalSizeEstimate, "bytes")
	storeRecord(self)
end

return TalkRecorder