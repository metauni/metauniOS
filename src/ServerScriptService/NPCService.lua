--
-- NPCService
--

-- Roblox services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local ChatService = game:GetService("Chat")
local TweenService = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")
local TextService = game:GetService("TextService")

local AIService = require(script.Parent.AIService)
local SecretService = require(ServerScriptService.SecretService)
local BoardService = require(script.Parent.BoardService)

local Sift = require(ReplicatedStorage.Packages.Sift)
local Array, Set, Dictionary = Sift.Array, Sift.Set, Sift.Dictionary

-- Utils
local function tableContains(t, x)
	for _, y in t do
		if x == y then return true end
	end
		
	return false	
end

local function tableInsertWithMax(t, x, n)
	table.insert(t, x)
	if #t > n then
		table.remove(t, 1)
	end	
end

local function getInstancePosition(x)
	if x:IsA("Part") then return x.Position end
	if x:IsA("Model") and x.PrimaryPart ~= nil then
		return x.PrimaryPart.Position
	end
	
	return nil
end

local function getPlayerPosition(x)
	if x.Character == nil then return end
	if x.Character.PrimaryPart == nil then return end
	return x.Character.PrimaryPart.Position
end

local function cleanstring(text)
	local matched

	local prefixes = {" "}
	
	-- Remove starting spaces, newlines or fullstops
	while true do
		if text == "" then break end
		matched = false

		for _, x in prefixes do
			if string.match(text, "^" .. x) then
				matched = true
				text = string.sub(text, string.len(x)+1,-1)
			end	
		end

		if not matched then break end
	end
	
	-- Replace “ with "
	-- Replace ” with "
	text = string.gsub(text, "“", "\"")
	text = string.gsub(text, "”", "\"")
	
	return text
end

local NPCService = {}
NPCService.__index = NPCService

NPCService.ActionType = {
	Unhandled = 0,
	Dance = 1,
	Laugh = 2,
	Wave = 3,
	Walk = 4,
	Say = 5,
	Plan = 6
}

function NPCService.Init()
    NPCService.IntervalBetweenSummaries = 8 -- default 10
    NPCService.MaxObservations = 6 -- default 6
    NPCService.MaxRecentActions = 4 -- default 4
    NPCService.MaxThoughts = 10 -- default 8
    NPCService.MaxSummaries = 30 -- default 20
    NPCService.MemorySearchProbability = 0.3
    NPCService.MaxConsecutivePlan = 2
    NPCService.NPCTag = "npcservice_npc"
    NPCService.ObjectTag = "npcservice_object"
    NPCService.HearingRadius = 15
    NPCService.GetsDetailedObservationsRadius = 20
    NPCService.PromptPrefix = SecretService.NPCSERVICE_PROMPT

	NPCService.thoughtsForNPC = {}
	NPCService.recentActionsForNPC = {}
	NPCService.animationsForNPC = {}
	NPCService.summariesForNPC = {}
    NPCService.planningCounter = {}
	
	local npcs = CollectionService:GetTagged(NPCService.NPCTag)
	for _, npc in npcs do
		NPCService.thoughtsForNPC[npc] = {}
		NPCService.recentActionsForNPC[npc] = {}
		NPCService.summariesForNPC[npc] = {}
        NPCService.planningCounter[npc] = 0
		
		NPCService.animationsForNPC[npc] = {}
		local animator = npc.Humanoid:WaitForChild("Animator")
		NPCService.animationsForNPC[npc].WalkAnim = animator:LoadAnimation(npc.Animate.walk.WalkAnim)
		NPCService.animationsForNPC[npc].WaveAnim = animator:LoadAnimation(npc.Animate.wave.WaveAnim)
		NPCService.animationsForNPC[npc].LaughAnim = animator:LoadAnimation(npc.Animate.laugh.LaughAnim)
		NPCService.animationsForNPC[npc].DanceAnim = animator:LoadAnimation(npc.Animate.dance.Animation1)
	end
	
	Players.PlayerAdded:Connect(function(plr)
		plr.Chatted:Connect(function(msg)
			NPCService.HandleChat(plr, msg)
		end)
	end)
	
	for _, plr in Players:GetPlayers() do
		plr.Chatted:Connect(function(msg)
			NPCService.HandleChat(plr, msg)
		end)
	end
end

function NPCService.Start()
    task.spawn(function()
        local stepCount = 0
        
        while task.wait(5) do
            local npcs = CollectionService:GetTagged(NPCService.NPCTag)
            for _, npc in npcs do
                if npc.PrimaryPart == nil then continue end
                
                --print("-- " .. npc.Name .. " -----")
                NPCService.TimestepNPC(npc)	
                task.wait(1)
            end
            
            stepCount += 1
            if stepCount == NPCService.IntervalBetweenSummaries then
                
                for _, npc in npcs do
                    if npc.PrimaryPart == nil then continue end
                    
                    --print("-- summary for " .. npc.Name .. " ----")
                    NPCService.GenerateSummaryThoughtForNPC(npc)
                end
                stepCount = 0
            end
        end
    end)

    -- Keep updated observations of boards in a way that NPCs can read them
    -- In order to avoid frequently OCRing boards that are far away from any
    -- NPC, we only OCR boards within NPCService.GetsDetailedObservationsRadius
    -- of an agent

    task.spawn(function()    
        while task.wait(10) do
            local npcs = CollectionService:GetTagged(NPCService.NPCTag)
            local function distanceToNearestNPC(pos)
                local distance = math.huge
                for _, npc in npcs do
                    if not npc:IsDescendantOf(game.Workspace) then continue end
                    if npc.PrimaryPart == nil then continue end
                    local d = (getInstancePosition(npc) - pos).Magnitude
                    if d < distance then
                        distance = d
                    end
                end

                return distance
            end

            local function observationFolder(board)
                local obPart = board:FindFirstChild("NPCObservationPart")
                if obPart then return obPart.Observations end
                
                local boardPart = if board:IsA("Model") then board.PrimaryPart else board
                
                -- TODO these can obscure clicking on boards
                local obPart = Instance.new("Part")
                obPart.Name = "NPCObservationPart"
                obPart.CFrame = boardPart.CFrame + boardPart.CFrame.LookVector * 10
                obPart.Position += Vector3.new(0,-boardPart.Size.Y/2 + 1,0)
                obPart.Color = Color3.new(0.3,0.2,0.7)
                obPart.Transparency = 1
                obPart.Size = Vector3.new(4, 1, 2)
                obPart.CanCollide = false
                obPart.CastShadow = false
                obPart.Anchored = true
                obPart.Parent = board

                CollectionService:AddTag(obPart, NPCService.ObjectTag)
                CollectionService:AddTag(obPart, "_hidden")

                local obFolder = Instance.new("Folder")
                obFolder.Name = "Observations"
                obFolder.Parent = obPart

                return obFolder
            end

            local boards = CollectionService:GetTagged("metaboard")
            for _, boardInstance in boards do
                if not boardInstance:IsDescendantOf(game.Workspace) then continue end
                local distToNPC = distanceToNearestNPC(getInstancePosition(boardInstance))
                if distToNPC > NPCService.GetsDetailedObservationsRadius then continue end

                local board = BoardService.Boards[boardInstance]

                local boardText = AIService.OCRBoard(board)
                if boardText then
                    boardText = cleanstring(boardText)
                    boardText = string.gsub(boardText, "\n", " ")

                    local obFolder = observationFolder(boardInstance)
                    obFolder:ClearAllChildren()

                    --print("OCR board ====")
                    --print(boardText)
                    --print("====")

                    local stringValue = Instance.new("StringValue")
                    stringValue.Value = "The board has written on it \"" .. boardText .."\""
                    stringValue.Parent = obFolder
                end
            end
        end
    end)

    print("[NPCService] Started")
end

function NPCService.RotateNPCToFacePosition(npc, targetPos)
	local npcPos = getInstancePosition(npc)
	if (npcPos - targetPos).Magnitude < 0.1 then
		return
	end
	
	local targetPosXZ = Vector3.new(targetPos.X,npcPos.Y,targetPos.Z)

	local tweenInfo = TweenInfo.new(
		0.5, -- Time
		Enum.EasingStyle.Linear, -- EasingStyle
		Enum.EasingDirection.Out, -- EasingDirection
		0, -- RepeatCount (when less than zero the tween will loop indefinitely)
		false, -- Reverses (tween will reverse once reaching it's goal)
		0 -- DelayTime
	)

	local tween = TweenService:Create(npc.PrimaryPart, tweenInfo,
		{CFrame = CFrame.lookAt(npcPos, targetPosXZ)})

	tween:Play()
end

function NPCService.PromptContentForNPC(npc)
	local observations = NPCService.ObserveForNPC(npc) or {}

	local middle = ""
	
	-- The order of events in the prompt is important: the most
	-- recent events are at the bottom. We keep observations at the
	-- top because it seems to work well.
	
	for _, obj in observations do
		middle = middle .. "Observation: " .. obj .. "\n"
	end
	
	local entries = {}
	
	for _, entry in NPCService.recentActionsForNPC[npc] do
		table.insert(entries, { Type = "Action", Content = entry.Action, Timestamp = entry.Timestamp})	
	end
	
	for _, entry in NPCService.thoughtsForNPC[npc] do
		table.insert(entries, { Type = "Thought", Content = entry.Thought, Timestamp = entry.Timestamp})	
	end
	
	local sortedEntries = Array.sort(entries, function(entry1, entry2)
		return entry1.Timestamp < entry2.Timestamp
	end)
	
	for _, entry in sortedEntries do
		middle = middle .. entry.Type .. ": " .. entry.Content .. "\n"	
	end
	
	return middle
end

function NPCService.RecentActions(npc)
	local actions = {}
	for _, entry in NPCService.recentActionsForNPC[npc] do
		table.insert(actions, entry.Action)
	end
	return actions
end

function NPCService.Thoughts(npc)
	local thoughts = {}
	for _, entry in NPCService.thoughtsForNPC[npc] do
		table.insert(thoughts, entry.Thought)
	end
	return thoughts
end

function NPCService.AddRecentAction(npc, action)
	local entry = { Action = action, Timestamp = tick() }
	tableInsertWithMax(NPCService.recentActionsForNPC[npc], entry, NPCService.MaxRecentActions)
end

function NPCService.AddThought(npc, thought)
	local entry = { Thought = thought, Timestamp = tick() }
	tableInsertWithMax(NPCService.thoughtsForNPC[npc], entry, NPCService.MaxThoughts)
end

function NPCService.AddSummary(npc, text)
    -- Summaries are tables containing
    --      Timestamp
    --      Content
    --      Embedding (perhaps nil)

    local summaryDict = {}
    summaryDict.Timestamp = tick()
    summaryDict.Content = text

    local embedding = AIService.Embedding(text)
    if embedding ~= nil then
        summaryDict.Embedding = embedding
    end

	tableInsertWithMax(NPCService.summariesForNPC[npc], summaryDict, NPCService.MaxSummaries)
end

-- Filter is a function that takes a summary and returns true or false
function NPCService.MostSimilarSummary(npc, text, filter)
    local function alwaysTrue(x)
        return true
    end
    filter = filter or alwaysTrue

    local embedding = AIService.Embedding(text)
    if embedding == nil then
        warn("[NPCService] Got nil embedding")
        return
    end

    local function dotproduct(v,w)
        local d = 0

        for i, _ in ipairs(v) do
            d += v[i] * w[i]
        end

        return d
    end

    local function magnitude(e)
        return math.sqrt(dotproduct(e,e))
    end

    local function cosine_similarity(v,w)
        local dot = dotproduct(v,w)
        local m1 = magnitude(v)
        local m2 = magnitude(w)
        if m1 == 0 or m2 == 0 then
            warn("[NPCService] Got zero vectors for cosine similarity")
            return nil
        end

        return dot / ( m1 * m2 )
    end

    local highestSimilarity = - math.huge
    local mostSimilarSummary = nil

    for _, summary in NPCService.summariesForNPC[npc] do
        if not filter(summary) then continue end
        if summary.Embedding == nil then continue end

        local similarity_score = cosine_similarity(summary.Embedding, embedding)
        if similarity_score > highestSimilarity then
            highestSimilarity = similarity_score
            mostSimilarSummary = summary
        end
    end

    return mostSimilarSummary
end

function NPCService.GenerateSummaryThoughtForNPC(npc:instance)
	local prompt = "The following is a record of the history of Observations, Thoughts and Actions of agent named " .. npc.Name .. ".\n\n"
	local middle = NPCService.PromptContentForNPC(npc)
	prompt = prompt .. middle
	prompt = prompt .. "\n"
	prompt = prompt .. "A summary of this history of " .. npc.Name .. " in 50 words or less is given below, written in first person from " .. npc.Name .. "'s point of view\n"
	prompt = prompt .. "\n"
	prompt = prompt .. "Summary:"
	
	local temperature = 0.7
	local freqPenalty = 0
	local presPenalty = 0

	local responseText = AIService.GPTPrompt(prompt, 200, nil, temperature, freqPenalty, presPenalty)
	if responseText == nil then
		warn("[NPCService] Got nil response from GPT3")
		return
	end
	
	NPCService.AddThought(npc, responseText)
	
    local function humanReadableTimeInterval(d)
        if d < 60 then return "less than a minute ago" end
        if d < 60 * 5 then return "less than five minutes ago" end
        if d < 60 * 10 then return "around ten minutes ago" end
        return "around " .. tostring((d % 600) * 10) .. " minutes ago"
    end

    local function filterForSummaries(x)
        if ( tick() - x.Timestamp ) % 60 < 5 then -- default 5
            return false
        else
            return true
        end
    end

    if math.random() < NPCService.MemorySearchProbability then
        local relevantSummary = NPCService.MostSimilarSummary(npc, responseText, filterForSummaries)
        if relevantSummary ~= nil then
            local timediff = tick() - relevantSummary.Timestamp
            local intervalText = humanReadableTimeInterval(timediff)
            local memoryText = "I remember that " .. intervalText .. ", " .. relevantSummary.Content
            NPCService.AddThought(npc, memoryText)
        end
    end

    NPCService.AddSummary(npc, responseText)
end

function NPCService.TimestepNPC(npc:instance)
	local prompt = NPCService.PromptPrefix .. "\n"
	prompt = prompt .. "Thought: My name is " .. npc.Name .. "\n"
	
	-- Sample one of the other personality thoughts
	local personalityFolder = npc:FindFirstChild("Personality")
	if personalityFolder then
		local personalityTexts = personalityFolder:GetChildren()
		if #personalityTexts > 0 then
			local pText = personalityTexts[math.random(1,#personalityTexts)].Value
			prompt = prompt .. "Thought: " .. pText .. "\n"
		end
	end
	
	local middle = NPCService.PromptContentForNPC(npc)
	
	prompt = prompt .. middle .. "Action:"
	
    -- If the agent has been talking to themself too much (i.e. planning)
    -- then force them to speak by giving Say as the prompt
    local forcedToAct = false
    local forcedActionText = ""
    if NPCService.planningCounter[npc] >= NPCService.MaxConsecutivePlan then
        forcedToAct = true
        if math.random() < 0.7 then
            forcedActionText = " Say \""
        else
            forcedActionText = " Walk to"
        end
    end

    if forcedToAct then prompt = prompt .. forcedActionText end
    
	--if npc.Name == "Shoal" then print(prompt) end
	
	local temperature = 0.8
	local freqPenalty = 1.0
	local presPenalty = 1.4
	
	local responseText = AIService.GPTPrompt(prompt, 100, nil, temperature, freqPenalty, presPenalty)
	if responseText == nil then
		warn("[NPCService] Got nil response from GPT3")
		return
	end
	
    if forcedToAct then
        responseText = "Action:" .. forcedActionText .. responseText
        NPCService.planningCounter[npc] = 0
    else
	    responseText = "Action:" .. responseText
    end

    if npc.Name == "Shoal" then
        print("=== response ===")
        print(responseText)
        print("==============")
    end
	
	local actions = {}
	local thoughts = {}
	local itemType = ""
	
	for _, l in string.split(responseText, "\n") do
		local lineType = nil
		if string.match(l, "^Action:") then
			itemType = "Action"
			lineType = actions
		elseif string.match(l, "^Thought:") then
			itemType = "Thought"
			lineType = thoughts
		end
		
		if lineType ~= nil then
			local parts = string.split(l, " ")
			if #parts > 1 then
				table.remove(parts, 1)
				local s = cleanstring(table.concat(parts, " "))
				table.insert(lineType, s)
			end
		end
	end
	
	-- Note that the only thoughts at the next step
	-- are ones returned by GPT, or that we infer from Actions
	for _, thought in thoughts do
		NPCService.AddThought(npc, thought)
	end
	
	local hasSpoken = false -- only one speech act per timestep
    local hasMoved = false -- only one movement per timestep
	
	for _, action in actions do
		-- Do not repeat recent actions (e.g. repeating lines of text)
		if tableContains(NPCService.RecentActions(npc),action) then continue end
		
		local parsedActionsList = NPCService.ParseActions(action)
        for _, parsedAction in parsedActionsList do
            if parsedAction.Type == NPCService.ActionType.Unhandled then continue end
            
            if parsedAction.Type == NPCService.ActionType.Say then
                if hasSpoken then
                    continue
                else
                    hasSpoken = true
                end
            end

            if parsedAction.Type == NPCService.ActionType.Move then
                if hasMoved then
                    continue
                else
                    hasMoved = true
                end
            end

            -- The agents sometimes have too much internal monologue
            -- and we use this trick to force them to speak
            if parsedAction.Type ~= NPCService.ActionType.Plan then
                NPCService.planningCounter[npc] = 0
            else
                NPCService.planningCounter[npc] += 1
            end
            
            NPCService.AddRecentAction(npc, action)
            NPCService.TakeAction(npc, parsedAction)
        end
	end
end

function NPCService.HandleChat(speaker, message)
	-- speaker is a player or npc
	local name
	local pos
	
	if CollectionService:HasTag(speaker, NPCService.NPCTag) then
		name = speaker.Name
		if speaker.PrimaryPart == nil then return end
		pos = speaker.PrimaryPart.Position
	else
		name = speaker.DisplayName
		if speaker.Character == nil or speaker.Character.PrimaryPart == nil then return end
		pos = speaker.Character.PrimaryPart.Position
	end
	
	for _, npc in CollectionService:GetTagged(NPCService.NPCTag) do
		if npc == speaker then continue end
		local npcPos = getInstancePosition(npc)
		if npcPos == nil then continue end
		local distance = (npcPos - pos).Magnitude
		
		if distance < NPCService.HearingRadius then
			-- This NPC heard the chat message
			local ob = name .. " said \"" .. message .. "\""
			NPCService.AddThought(npc, ob)
		end
	end
end

-- Look in the environment for observations
function NPCService.ObserveForNPC(npc:instance)
	if npc.PrimaryPart == nil then return end
	local pos = npc.PrimaryPart.Position
	
	local potentialObservations = {}
	
	-- Look at other NPCS
	for _, x in CollectionService:GetTagged(NPCService.NPCTag) do
		if x == npc then continue end
        if not x:IsDescendantOf(game.Workspace) then return end
		if getInstancePosition(x) == nil then continue end
		
		table.insert(potentialObservations, {Object = x, 
											Name = x.Name,
											Description = "They are a person"})
	end
	
	-- Look at players
	for _, plr in Players:GetPlayers() do
		if plr.Character == nil or plr.Character.PrimaryPart == nil then continue end
		table.insert(potentialObservations, {Object = plr.Character,
											Name = plr.DisplayName,
											Description = "They are a person"})
	end
	
    -- Look at boards
    -- TODO

	-- Look at objects
	for _, x in CollectionService:GetTagged(NPCService.ObjectTag) do
		if getInstancePosition(x) == nil then continue end
		local t = {Object = x, Name = x.Name, Description = "It is an object, not a person"}
		if x:FindFirstChild("Observations") then
			local objObservations = {}
			for _, strVal in x.Observations:GetChildren() do
				if strVal:IsA("StringValue") then
					table.insert(objObservations, strVal.Value)
				end
			end
			t.Observations = objObservations
		end
		
		table.insert(potentialObservations, t)
	end
	
	local observations = {}
	
	local NextToMeRadius = 15
	local NearbyRadius = 80
	local WalkingDistanceRadius = 200
	local observedBoardPhrases = {}

	for _, obj in potentialObservations do
		local objPos = getInstancePosition(obj.Object)
		local distance = (objPos - pos).Magnitude
		
		-- To far away to observe
		if distance > WalkingDistanceRadius then continue end
		
		local phrase = ""
        local boardPhrase = ""
		
		if distance < NextToMeRadius then
			phrase = "is next to me"
            boardPhrase = "There is a board next to me"
		elseif distance < NearbyRadius then
			phrase = "is nearby"
            boardPhrase = "There are boards nearby"
		elseif distance < WalkingDistanceRadius then
			phrase = "is within walking distance"
            boardPhrase = "There are boards within walking distance"
		end
		
		local phrase = obj.Name .. " " .. phrase .. ". " .. obj.Description .. "."

        -- We have special sentences for boards (because there are lots of them)
        local objectIsBoard = CollectionService:HasTag(obj.Object, "metaboard")

        -- Objects tagged with _hidden contribute Observations from their
        -- Observations folder, but NPCs do not hear about them directly
        if not CollectionService:HasTag(obj.Object, "_hidden") then
            if objectIsBoard and not tableContains(observedBoardPhrases, boardPhrase) then
                table.insert(observations, boardPhrase)
                table.insert(observedBoardPhrases, boardPhrase)
            else
		        table.insert(observations, phrase)
            end
        end
		
		if distance < NPCService.GetsDetailedObservationsRadius then
			if obj.Observations ~= nil then
				for _, objOb in obj.Observations do
					table.insert(observations, objOb)
				end
			end
		end
	end
	
	return observations
end

function NPCService.InstanceByName(name)
	for _, npc in CollectionService:GetTagged(NPCService.NPCTag) do
        if not npc:IsDescendantOf(game.Workspace) then continue end

		if string.lower(npc.Name) == string.lower(name) then
			return npc
		end	
	end

	for _, plr in Players:GetPlayers() do
        if plr.Character == nil or plr.Character.PrimaryPart == nil then continue end

		if string.lower(plr.DisplayName) == string.lower(name) then
			return plr.Character
		end
	end
	
	for _, x in CollectionService:GetTagged(NPCService.ObjectTag) do
        if not x:IsDescendantOf(game.Workspace) then continue end

		if string.lower(x.Name) == string.lower(name) then
			return x
		end
		
		if "the " .. string.lower(x.Name) == string.lower(name) then
			return x
		end
	end
	
	return nil
end

function NPCService.GetEmptySpotNearPos(pos)
	local npcs = CollectionService:GetTagged(NPCService.NPCTag)
	for _, npc in npcs do
        if not npc:IsDescendantOf(game.Workspace) then continue end
		if npc.PrimaryPart == nil then continue end
		if (getInstancePosition(npc) - pos).Magnitude < 4 then
			return pos + Vector3.new(math.random(-4,4),0,math.random(-4,4))
		end
	end
	
	return pos
end

-- Walk with starsonthars
-- Handle turning to ask or say at someone
-- Wave goodbye
-- Ask Percy "..."
-- Walk towards Percy
-- Invite them to ...
-- Offer to show them around the area
-- Ask X, Y, Z if they would like to E
-- Say goodbye to X, Y, Z
-- Start walking with
-- Speak in Chinese and say "Let's go"
-- Speak in Chinese to ...
-- Introduce Sneetch to Percy
-- Smile at
-- Shake Percy's hand
-- Start walking to the camping spot
-- Agree with X and Y and say ""
-- Lead the way to the camping spot
-- Follow Pecy and starsonthars
-- Lead Percy and Sneetch on the walk
-- Start walking with Percy and Sneetch
-- Ask Percy and Sneetch what they are doing today 
-- Ask Percy and Sneetch if they would like to join you for a walk 
-- Show Percy and Sneetch pictures of your pet cat
-- Smile and say to Percy and starsonthars "Thank you!"
-- Introduce yourself to Starsonthars and explain why your favourite pet is a dragon
-- Shake hands with Sneetch
-- Ask starsonthars if they would like to dance
-- Ask Percy and Sneetch what their names are
-- Invite starsonthars to explore more mysteries together
-- Walk with Percy and Sneetch while talking about the possibilities of the universe
-- Listen to starsonthars response and ask follow-up questions if necessary
-- Follow starsonthars by walking to him
-- Follow starsonthars while walking and say "Lead the way!"
-- Invite Youtwice and Ginger to join in the star dance
-- Join Youtwice and Nous in the star dance
-- Join starsonthars and the others in the star dance by saying "/e dances"
-- Point to the knot and say, "See that? It’s really interesting. Do you know any stories related to it?"
-- Respond to starsonthars with “Yes, it's near the knot. Let's go explore together!”
-- Ask the board writer, "Could you please explain a bit more about Euclid's Elements? I would really appreciate it!"
-- Examine the boards closely and say "There's text written on them. It looks like it contains information about seminars, university services, infrastructure, personal journeys, classes and replays."
-- Point to the boards and say "This is where we're headed!"

function NPCService.ParseActions(actionText:string)
	
    -- Walk and Say
    -- Example: Walk to starsonthars and say "Hi, I'm Shoal. Do you like talking about math and science?"
    local walkSayPrefixes = {"Walk to", "Go to", "Follow"}
    local walkSayRegexes = {}
    for _, p in walkSayPrefixes do
        table.insert(walkSayRegexes, "^" .. p .. " ([^, ]+) .+\"(.+)\"")
    end
    
    for _, r in walkSayRegexes do
		local dest, message = string.match(actionText, r)
		if dest ~= nil and message ~= nil then
            local actionList = {}

            local sayActionDict = {}
            local walkActionDict = {}

			sayActionDict.Type = NPCService.ActionType.Say
            sayActionDict.Content = message
            table.insert(actionList, sayActionDict)

			local destInstance = NPCService.InstanceByName(dest)
            if destInstance ~= nil then
                walkActionDict.Type = NPCService.ActionType.Walk
				walkActionDict.Target = destInstance
                table.insert(actionList, walkActionDict)
			end

			return actionList
		end
	end

    -- Wave and Say
    -- Example: Wave and say to Youtwice "See you soon!"
    local waveSayPrefixes = {"Wave to", "Wave and say to", "Give a friendly farewell to"}
    local waveSayRegexes = {}
    for _, p in waveSayPrefixes do
        table.insert(waveSayRegexes, "^" .. p .. " ([^, ]+) .+\"(.+)\"")
    end

    for _, r in waveSayRegexes do
		local target, message = string.match(actionText, r)
		if target ~= nil and message ~= nil then
            local actionList = {}

            local targetInstance = NPCService.InstanceByName(target)
            if targetInstance ~= nil then
                local waveActionDict = {}
			    waveActionDict.Type = NPCService.ActionType.Wave
			    waveActionDict.Target = targetInstance
                table.insert(actionList, waveActionDict)
            end

            local sayActionDict = {}
            sayActionDict.Type = NPCService.ActionType.Say
            sayActionDict.Content = message
            table.insert(actionList, sayActionDict)

			return actionList
        end
    end

	local dancePrefixes = {"Dance"}
	for _, p in dancePrefixes do
		if string.match(actionText, "^" .. p) then
            local actionDict = {}
			actionDict.Type = NPCService.ActionType.Dance
			return {actionDict}
		end
	end

    local laughSayRegexes = {"^Laugh .+ \"(.+)\""}
    for _, r in laughSayRegexes do
		local message = string.match(actionText, r)
		if message ~= nil then
            local actionList = {}

            local laughActionDict = {}
			laughActionDict.Type = NPCService.ActionType.Laugh
			table.insert(actionList, laughActionDict)

            local sayActionDict = {}
            sayActionDict.Type = NPCService.ActionType.Say
            sayActionDict.Content = message
            table.insert(actionList, sayActionDict)

			return actionList
        end
    end

	local laughPrefixes = {"Laugh"}
	for _, p in laughPrefixes do
		if string.match(actionText, "^" .. p) then
            local actionDict = {}
			actionDict.Type = NPCService.ActionType.Laugh
			return {actionDict}
		end
	end
	
    -- This handles objects that have compound names (with spaces)
    -- that are awkward to handle using regexes, but will not catch
    -- for example players or NPCs
	for _, obj in CollectionService:GetTagged(NPCService.ObjectTag) do
		local name = obj.Name
		local regexes = {"^Walk to the " .. name,"^Walk to " .. name,
			"^Walk .+ to the " .. name, "^Walk .+ to " .. name,
			"^Lead .+ to the " .. name, "^Lead .+ to " .. name,
            "^Lead .+ to explore the " .. name, "^Lead .+ to explore " .. name,
			"^Start walking .+ to the " .. name, "^Start walking .+ to " .. name,
            "^Begin walking .+ to the " .. name, "^Begin walking .+ to " .. name,
			"^Follow .+ to the " .. name,"^Follow .+ to " .. name,
			"^Go to the " .. name,"^Go to " .. name,
            "^Check out .+ the " .. name,"^Check out .+ " .. name,
			"^Start walking towards the " .. name,"^Start walking towards " .. name,
            "^Start exploring the " .. name,"^Start exploring " .. name,
            "^Begin exploring the " .. name,"^Begin exploring " .. name,
            "^Show .+ inside " .. name, "^Show .+ inside the " .. name,
            "^Arrange a meeting with " .. name,
            "^Lead .+ towards " .. name,
            "^Lead .+ to explore " .. name}
		for _, r in regexes do
			local dest = string.match(actionText, r)
			if dest then
                local actionDict = {}
				actionDict.Type = NPCService.ActionType.Walk
				actionDict.Target = obj
				return {actionDict}
			end
		end
	end
	
    local walkRegexes = {"^Walk to the ([^, ]+)","^Walk to ([^, ]+)",
    "^Walk .+ to the ([^, ]+)", "^Walk .+ to ([^, ]+)",
    "^Lead .+ to the ([^, ]+)", "^Lead .+ to ([^, ]+)",
    "^Start walking .+ to the ([^, ]+)", "^Start walking .+ to ([^, ]+)",
    "^Follow .+ to the ([^, ]+)","^Follow .+ to ([^, ]+)",
    "^Follow .+ to go and see the ([^, ]+)","^Follow .+ to go and see ([^, ]+)",
    "^Follow ([^, ]+)", -- important that this comes after more specific queries
    "^Go to the ([^, ]+)","^Go to ([^, ]+)",
    "^Start walking towards the ([^, ]+)","^Start walking towards ([^, ]+)"}
	for _, r in walkRegexes do
		local dest = string.match(actionText, r)
		if dest ~= nil then
            local destInstance = NPCService.InstanceByName(dest)
            if destInstance ~= nil then
                local actionDict = {}
			    actionDict.Type = NPCService.ActionType.Walk
				actionDict.Target = destInstance
                return {actionDict}
			end
		end
	end
	
    -- Say to
    -- Example: Say to Youtwice "I was curious about this Redwood tree"
    local sayToPrefixes = {"Say to", "Ask", "Reply to", "Respond to", "Tell", "Thank", "Smile and say to", "Wave and say to", "Laugh and say to", "Explain to", "Nod in agreement and say to", "Turn to"}
    local sayToRegexes = {}
    for _, p in sayToPrefixes do
        table.insert(sayToRegexes, "^" .. p .. " ([^, ]+) .+\"(.+)\"")
    end
    
    for _, r in sayToRegexes do
		local target, message = string.match(actionText, r)
		if target ~= nil and message ~= nil then
            local sayActionDict = {}
            local targetInstance = NPCService.InstanceByName(target)
            if targetInstance ~= nil then
                sayActionDict.Target = targetInstance
			end
            
			sayActionDict.Type = NPCService.ActionType.Say
            sayActionDict.Content = message
            return {sayActionDict}
		end
	end

	local sayPrefixes = {"Say", "Ask", "Reply", "Respond", "Tell", "Smile", "Nod", "Answer", "Look", "Point", "Introduce", "Tell", "Invite", "Examine", "Read", "Suggest", "Greet", "Offer", "Extend", "Explain", "Nod", "Agree"}
	for _, p in sayPrefixes do
		if string.match(actionText, "^" .. p) then
			local message = string.match(actionText, "^" .. p .. ".+\"(.+)\"")
			if message ~= nil then
                local actionDict = {}
				actionDict.Type = NPCService.ActionType.Say
				actionDict.Content = message
				return {actionDict}
			end
		end
	end
	
    local wavePrefixes = {"Wave at", "Wave to", "Wave", "Greet", "Shake hands", "Smile"}
	for _, p in wavePrefixes do
		if string.match(actionText, "^" .. p) then
            local actionDict = {}
			actionDict.Type = NPCService.ActionType.Wave
			
			local target = string.match(actionText, "^" .. p .. " ([^, ]+)")
            if target ~= nil then
                local targetInstance = NPCService.InstanceByName(target)
                if targetInstance ~= nil then
                    actionDict.Target = targetInstance
                end
            end

			return {actionDict}
		end
	end

	-- Unhandled speech actions that "look like" speech become thoughts
	for _, p in sayPrefixes do
		if string.match(actionText, "^" .. p) then
            local actionDict = {}
			actionDict.Type = NPCService.ActionType.Plan
			actionDict.Content = actionText
			return {actionDict}
		end
	end
	
    local actionDict = {}
	actionDict.Type = NPCService.ActionType.Unhandled
	return {actionDict}
end

function NPCService.WalkNPCToPos(npc, targetPos)
	local currentPos = getInstancePosition(npc)
	
	local unitVector = (targetPos - currentPos).Unit
	local distance = (targetPos - currentPos).Magnitude
	local destPos = currentPos + (distance - 12) * unitVector
	destPos = NPCService.GetEmptySpotNearPos(destPos)
	local animationTrack = NPCService.animationsForNPC[npc].WalkAnim

	local path = PathfindingService:CreatePath({
		Costs = {
			Water = 20,
			Grass = 5,
			Mud = 2
		}
	})

	local waypoints
	local nextWaypointIndex
	local reachedConnection
	local blockedConnection

	local function followPath(destination)
		-- Compute the path
		local success, errorMessage = pcall(function()
			path:ComputeAsync(npc.PrimaryPart.Position, destination)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			waypoints = path:GetWaypoints()

			blockedConnection = path.Blocked:Connect(function(blockedWaypointIndex)
				if blockedWaypointIndex >= nextWaypointIndex then
					blockedConnection:Disconnect()
					followPath(destination)
				end
			end)

			-- Detect when movement to next waypoint is complete
			if not reachedConnection then
				reachedConnection = npc.Humanoid.MoveToFinished:Connect(function(reached)
					npc:SetAttribute("walking", false)

					if reached and nextWaypointIndex < #waypoints then
						-- Increase waypoint index and move to next waypoint
						nextWaypointIndex += 1
						npc.Humanoid:MoveTo(waypoints[nextWaypointIndex].Position)
						npc:SetAttribute("walking", true)
					else
						animationTrack:Stop()
						reachedConnection:Disconnect()
						blockedConnection:Disconnect()
					end
				end)
			end

			-- Initially move to second waypoint (first waypoint is path start; skip it)
			nextWaypointIndex = 2
			animationTrack:Play()
			npc:SetAttribute("walking", true)
			npc.Humanoid:MoveTo(waypoints[nextWaypointIndex].Position)
		else
			warn("[NPCService] Path not computed!", errorMessage)
		end
	end

	followPath(destPos)
	return true
end
function NPCService.TakeAction(npc:instance, parsedAction)
	if parsedAction.Type == NPCService.ActionType.Dance then
		local animationTrack = NPCService.animationsForNPC[npc].DanceAnim
		animationTrack:Play()

		task.delay(3, function()
			animationTrack:Stop()
		end)
		return
	end
	
	if parsedAction.Type == NPCService.ActionType.Laugh then
        local target = parsedAction.Target
		if target ~= nil then
			local targetPos = getInstancePosition(target)
			NPCService.RotateNPCToFacePosition(npc, targetPos)
		end

		local animationTrack = NPCService.animationsForNPC[npc].LaughAnim
		animationTrack:Play()

		task.delay(3, function()
			animationTrack:Stop()
		end)
		return
	end
	
	if parsedAction.Type == NPCService.ActionType.Wave then
		local target = parsedAction.Target
		if target ~= nil then
			local targetPos = getInstancePosition(target)
			NPCService.RotateNPCToFacePosition(npc, targetPos)
		end
		
		local animationTrack = NPCService.animationsForNPC[npc].WaveAnim
		animationTrack:Play()

		task.delay(3, function()
			animationTrack:Stop()
		end)
		return
	end
	
	if parsedAction.Type == NPCService.ActionType.Walk then
		local target = parsedAction.Target
		if target ~= nil and target ~= npc and not target:GetAttribute("walking") then
			local targetPos = getInstancePosition(target)
			if targetPos ~= nil then
				NPCService.WalkNPCToPos(npc, targetPos)
			end
		end
		return
	end
	
	if parsedAction.Type == NPCService.ActionType.Say then
        local target = parsedAction.Target
		if target ~= nil then
			local targetPos = getInstancePosition(target)
			NPCService.RotateNPCToFacePosition(npc, targetPos)
		end

		local message = parsedAction.Content
		
		local playerList = Players:GetPlayers()
        if #playerList == 0 then return end
		local randomPlr = playerList[math.random(1,#playerList)]
		
		local success, filteredText = pcall(function()
			return TextService:FilterStringAsync(message, randomPlr.UserId)
		end)
		if not success then
			warn("[NPCService] Error filtering text:", message, ":", filteredText)
		else
			local filteredMessage = filteredText:GetNonChatStringForBroadcastAsync()
			ChatService:Chat(npc.Head, filteredMessage)
		end
		
		-- Note that agents see the unfiltered messages
		NPCService.HandleChat(npc, message)
		return
	end
	
	if parsedAction.Type == NPCService.ActionType.Plan then
		NPCService.AddThought(npc, parsedAction.Content)
		return -- don't let the agent think this has already been finished
	end
	
	warn("[NPCService] Unhandled parsed action")
end

return NPCService