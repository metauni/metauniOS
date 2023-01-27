--
-- NPCService
--
-- Techniques for improving inference: https://github.com/openai/openai-cookbook/blob/main/techniques_to_improve_reliability.md

-- Roblox services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local ChatService = game:GetService("Chat")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")
local TextService = game:GetService("TextService")
local MessagingService = game:GetService("MessagingService")

local AIService = require(script.Parent.AIService)
local SecretService = require(ServerScriptService.SecretService)
local BoardService = require(script.Parent.BoardService)

local Sift = require(ReplicatedStorage.Packages.Sift)
local Array, Set, Dictionary = Sift.Array, Sift.Set, Sift.Dictionary

local NPCService = {}
NPCService.__index = NPCService
NPCService.NPCTag = "npcservice_npc"
NPCService.ObjectTag = "npcservice_object"
NPCService.TranscriptionTopic = "transcription"
NPCService.NPCs = {}

local REFERENCE_PROPER_NAMES = {
    ["euclid"] = "Euclid",
    ["brighter"] = "Adam Dorr's book Brighter",
    ["harbison"] = "Harbison's book 'Travels in the History of Architecture'",
    ["spinningworld"] = "the book 'The Spinning World'", -- cost $2.66 for embeddings
    ["scientist_as_rebel"] = "Freeman Dyson's book 'The Scientist As Rebel'",
    ["darwin_machines"] = "George Dyson's book 'Darwin among the Machines'",
    ["turings_cathedral"] = "George Dyson's book 'Turing's Cathedral'",
    ["how_buildings_learn"] = "Stewart Brand's book 'How Building's Learn'",
    ["human_use_human_beings"] = "Norbert W's book 'Human use of Human Beings'",
    ["analogia"] = "George Dyson's book 'Analogia'"
}

-- Utils
local function shuffle(t)
    local n = #t
    for i = 1, n do
        local j = math.random(i, n)
        t[i], t[j] = t[j], t[i]
    end
end

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

local function humanReadableTimeInterval(d)
    d = math.floor(d)
    if d < 60 then return "less than a minute" end

    local numMinutes = math.floor(d / 60)

    if numMinutes < 5 then return "less than five minutes" end
    if numMinutes < 10 then return "around ten minutes" end
    if numMinutes < 60 then return `around {tostring(math.floor(numMinutes / 10) * 10)} minutes` end

    local numHours = math.floor(numMinutes / 60)
    if numHours == 1 then return "around an hour" end
    if numHours < 24 then return `around {tostring(numHours)} hours` end
    
    local numDays = math.floor(numHours / 24)
    if numDays == 1 then return "around a day" end
    if numDays < 30 then return `around {tostring(numDays)} days` end

    local numMonths = math.floor(numDays / 30)
    if numMonths == 1 then return "around a month" end
    
    return `around {tostring(numMonths)} months`
end

local function updateWith(t, q)
    local s = {}
    for k, v in pairs(t) do s[k] = v end
    for k, v in pairs(q) do s[k] = v end
    return s
end

--
-- NPC class
--

local NPC = {}
NPC.__index = NPC

NPC.PersonalityProfile = {}
NPC.PersonalityProfile.Normal = {
    Name = "Normal",
    IntervalBetweenSummaries = 8,
    MaxRecentActions = 5,
    MaxThoughts = 8,
    MaxSummaries = 20,
    SearchShortTermMemoryProbability = 0.1,
    SearchLongTermMemoryProbability = 0.1,
    SearchReferencesProbability = 0.2,
    MaxConsecutivePlan = 2,
    TimestepDelayNormal = 12,
    TimestepDelayVoiceChat = 8,
    ReferenceRelevanceScoreCutoff = 0.8,
    MemoryRelevanceScoreCutoff = 0.7,
    HearingRadius = 40,
    GetsDetailedObservationsRadius = 40,
    PromptPrefix = SecretService.NPCSERVICE_PROMPT
}

NPC.PersonalityProfile.Seminar = updateWith(NPC.PersonalityProfile.Normal, {
    Name = "Seminar",
    SearchShortTermMemoryProbability = 0.2,
    SearchLongTermMemoryProbability = 0.2,
    SearchReferencesProbability = 0.3,
    TimestepDelayNormal = 30,
    TimestepDelayVoiceChat = 15,
    ReferenceRelevanceScoreCutoff = 0.81,
    MemoryRelevanceScoreCutoff = 0.8,
    HearingRadius = 60,
    GetsDetailedObservationsRadius = 40,
    PromptPrefix = SecretService.NPCSERVICE_PROMPT_SEMINAR
})

NPC.ActionType = {
	Unhandled = 0,
	Dance = 1,
	Laugh = 2,
	Wave = 3,
	Walk = 4,
	Say = 5,
	Plan = 6,
    Turn = 7,
    Point = 8
}

function NPC.new(instance: Model)
    assert(instance.PrimaryPart, "NPC Model must have PrimaryPart set: "..instance:GetFullName())

    local npc = {}
    setmetatable(npc, NPC)

    npc.Instance = instance
    npc.Thoughts = {}
    npc.RecentActions = {}
    npc.RecentReferences = {}
    npc.Summaries = {}
    npc.PlanningCounter = 0
    npc.PersonalityProfile = NPC.PersonalityProfile.Normal
    npc.TimestepDelay = npc.PersonalityProfile.TimestepDelayNormal
    npc.OrbOffset = nil
    
    npc.Animations = {}
    local animator = instance.Humanoid.Animator
    npc.Animations.WalkAnim = animator:LoadAnimation(instance.Animate.walk.WalkAnim)
    npc.Animations.WaveAnim = animator:LoadAnimation(instance.Animate.wave.WaveAnim)
    npc.Animations.LaughAnim = animator:LoadAnimation(instance.Animate.laugh.LaughAnim)
    npc.Animations.DanceAnim = animator:LoadAnimation(instance.Animate.dance.Animation1)
    npc.Animations.PointAnim = animator:LoadAnimation(instance.Animate.point.PointAnim)
    npc.Animations.IdleAnim = animator:LoadAnimation(instance.Animate.idle.Animation1)
    
    npc.Animations.IdleAnim:Play()

    return npc
end

function NPC:UpdatePersonalityProfile()
    -- Currently there are only two profiles: Normal and Seminar
    -- and the latter is only possible for NPCs with TargetOrb set
    local targetOrbValue = self.Instance:FindFirstChild("TargetOrb")
    if targetOrbValue == nil then return end
    if targetOrbValue.Value == nil then return end
    local orb = self.Instance.TargetOrb.Value
    if orb:FindFirstChild("Speaker") == nil then return end
    
    if orb.Speaker.Value ~= nil then
        self.PersonalityProfile = NPC.PersonalityProfile.Seminar
    else
        self.PersonalityProfile = NPC.PersonalityProfile.Normal
    end

    self.TimestepDelay = self.PersonalityProfile.TimestepDelayNormal
end

function NPC:Timestep(startup)
    self:UpdatePersonalityProfile()

    if math.random() < self.PersonalityProfile.SearchShortTermMemoryProbability then
        local memory = self:ShortTermMemory()
        if memory ~= nil then
            if not self:IsRepeatThought(memory) then
                self:AddThought(memory, "memory")
            end
        end
    end

    -- Always grab a long term memory on startup
    if startup or (math.random() < self.PersonalityProfile.SearchLongTermMemoryProbability) then
        local relevanceCutoff = if startup then 0.5 else self.PersonalityProfile.MemoryRelevanceScoreCutoff

        local memory = self:LongTermMemory(relevanceCutoff)
        if memory ~= nil then
            self:AddThought(memory, "memory")
        end
    end

    -- Search some references
    if math.random() < self.PersonalityProfile.SearchReferencesProbability then
        local ref = self:SearchReferences()
        if ref ~= nil then
            self:AddThought(ref, "reference")
        end
    end
    
    self:Prompt()
    
    -- Walk an NPC targetting an orb to maintain a fixed offset from the orb
    if self.PersonalityProfile.Name == "Seminar" then
        local targetOrb = self.Instance.TargetOrb.Value
        local orbPos = getInstancePosition(targetOrb)

        -- The first time we run this, we set the offset for later reference
        if self.OrbOffset == nil then    
            self.OrbOffset = self.Instance.PrimaryPart.Position - orbPos
        end

        local targetPos = getInstancePosition(targetOrb) + self.OrbOffset
        local distance = (targetPos - self.Instance.PrimaryPart.Position).Magnitude
        
        if (not self.Instance:GetAttribute("walking")) and distance > 5 then  
            self:WalkToPos(targetPos)
        end
    end
end

function NPC:IsRepeatAction(action)
    for _, entry in self.RecentActions do
        if entry.Action == action then return true end
	end

	return false
end

function NPC:IsRepeatThought(thought)
    for _, entry in self.Thoughts do
        if entry.Thought == thought then return true end
	end

	return false
end

function NPC:AddRecentAction(action)
	local entry = { Action = action, Timestamp = tick() }
	tableInsertWithMax(self.RecentActions, entry, self.PersonalityProfile.MaxRecentActions)
end

function NPC:AddThought(thought, type)
	local entry = { Thought = thought, Timestamp = tick() }
    if type ~= nil then entry.Type = type end

    -- Do not repeat memories or references
    if type == "memory" or type == "reference" then
        for _, entry in self.Thoughts do
            if entry.Type == type and entry.Thought == thought then return end
        end
    end

	tableInsertWithMax(self.Thoughts, entry, self.PersonalityProfile.MaxThoughts)
end

function NPC:AddSummary(text, type)
    -- Summaries are tables containing
    --      Timestamp
    --      Content
    --      Embedding (perhaps nil)

    local summaryDict = {}
    summaryDict.Timestamp = tick()
    summaryDict.Content = text

    local embedding = AIService.Embedding(text)
    if embedding ~= nil then summaryDict.Embedding = embedding end
    if type ~= nil then summaryDict.Type = type end

	tableInsertWithMax(self.Summaries, summaryDict, self.PersonalityProfile.MaxSummaries)

    -- Send this to the vector storage database for later query
    if embedding then
        local metadata = {
            ["name"] = self.Instance.Name,
            ["id"] = self.Instance.PersistId.Value,
            ["timestamp"] = summaryDict.Timestamp,
            ["content"] = summaryDict.Content,
            ["type"] = summaryDict.Type
        }
        AIService.StoreEmbedding("npc", embedding, metadata)
    end
end

function NPC:ShortTermMemory()
    -- Do not make use of summaries that are too recent, as they will
    -- always fit the current situation and thus get high scores
    local function filterForSummaries(x)
        if tick() - x.Timestamp < 5 * 60 then
            return false
        else
            return true
        end
    end

    -- Short term memory roughly covers this many seconds
    local timestepDelay = self.TimestepDelay
    local interval = self.PersonalityProfile.IntervalBetweenSummaries
    local max = self.PersonalityProfile.MaxSummaries

    local shortTermMemoryInterval = timestepDelay * interval * max
    
    local summary = self:GenerateSummary()
    if summary == nil then return end

    local relevantSummary = self:MostSimilarSummary(summary, filterForSummaries)
    if relevantSummary == nil then return end

    local timediff = tick() - relevantSummary.Timestamp
    local intervalText = humanReadableTimeInterval(timediff) .. " ago"
    local memoryText = `I remember that {intervalText}, {relevantSummary.Content}`
    return memoryText
end

function NPC:LongTermMemory(relevanceCutoff)
    local summary = self:GenerateSummary()
    if summary == nil then return end

    local embedding = AIService.Embedding(summary)
    if embedding == nil then
        warn("[NPCService] Got nil embedding for summary")
        return
    end

    -- Short term memory roughly covers this many seconds
    local timestepDelay = self.TimestepDelay
    local interval = self.PersonalityProfile.IntervalBetweenSummaries
    local max = self.PersonalityProfile.MaxSummaries

    local shortTermMemoryInterval = timestepDelay * interval * max
    
    local filter = {
        ["id"] = self.Instance.PersistId.Value,
        ["timestamp"] = { ["$lt"] = tick() - shortTermMemoryInterval }
    }
    local topk = 3
    local matches = AIService.QueryEmbeddings("npc", embedding, filter, topk)
    if matches == nil then return end
    if #matches == 0 then
        warn("[AIService] No matches for query of long term memory")
        return
    end

    local goodMatches = {}
    for _, match in matches do
        if match["score"] > relevanceCutoff then
            table.insert(goodMatches, match)
        end
    end

    if #goodMatches == 0 then return end

    local match = goodMatches[math.random(1,#goodMatches)]
    local metadata = match["metadata"]
    if metadata == nil then
        warn("[NPCService] Got malformed match for query embedding")
        return
    end

    local timediff = tick() - metadata["timestamp"]
    local intervalText = humanReadableTimeInterval(timediff) .. " ago"
    local memoryText = `I remember that {intervalText}, {metadata["content"]}`
    return memoryText
end

function NPC:SearchReferences()
    local summary = self:GenerateSummary("ideas")
    if summary == nil then return end

    local embedding = AIService.Embedding(summary)
    if embedding == nil then return end

    local refList = {}
    local referencesFolder = self.Instance:FindFirstChild("References")
    if referencesFolder == nil or #referencesFolder:GetChildren() == 0 then return end
    for _, ref in referencesFolder:GetChildren() do
        table.insert(refList, ref.Value)
    end

    local filter = {
        ["name"] = { ["$in"] = refList }
    }
    local topk = 3
    local matches = AIService.QueryEmbeddings("refs", embedding, filter, topk)
    if matches == nil then return end
    if #matches == 0 then return end

    local goodMatches = {}
    for _, match in matches do
        if match["score"] > self.PersonalityProfile.ReferenceRelevanceScoreCutoff and
            not tableContains(self.RecentReferences, match["id"]) then
            table.insert(goodMatches, match)
        end
    end

    if #goodMatches == 0 then return end

    local match = goodMatches[math.random(1,#goodMatches)]
    tableInsertWithMax(self.RecentReferences, match["id"], 6)

    local metadata = match["metadata"]
    if metadata == nil then
        warn("[NPC] Got malformed match for reference")
        return
    end

    local content = cleanstring(metadata["content"])
    local content = string.gsub(content, "\n", " ")
    local content = string.gsub(content, ":", " ") -- don't confuse the AI
    local content = string.gsub(content, "\"", "'") -- so we can wrap in " quotes

    local refName = REFERENCE_PROPER_NAMES[metadata["name"]]
    local refContent = `I remember that page {metadata["page"]} of {refName} has written on it \"{content}\"`
    if self.Instance:GetAttribute("debug") then
        print("----------")
        print("[NPC] Found content reference")
        print(string.sub(refContent,1,30) .. "...")
        print("score = " .. match["score"])
        print("----------")
    end
    return refContent
end

function NPC:Prompt()
	local prompt = self.PersonalityProfile.PromptPrefix .. "\n"
	prompt = prompt .. `Thought: My name is {self.Instance.Name}\n`
	
	-- Sample one of the other personality thoughts
	local personalityFolder = self.Instance:FindFirstChild("Personality")
	if personalityFolder then
		local personalityTexts = personalityFolder:GetChildren()
		if #personalityTexts > 0 then
			local pText = personalityTexts[math.random(1,#personalityTexts)].Value
			prompt = prompt .. `Thought: {pText}\n`
		end
	end
	
	local middle = self:PromptContent()
	prompt = prompt .. middle .. "Action:"
	
    -- If the agent has been talking to themself too much (i.e. planning)
    -- then force them to speak by giving Say as the prompt
    local forcedToAct = false
    local forcedActionText = ""
    if self.PlanningCounter >= self.PersonalityProfile.MaxConsecutivePlan then
        forcedToAct = true
        if math.random() < 0.7 then
            forcedActionText = " Say \""
        else
            forcedActionText = " Walk to"
        end
    end

    if forcedToAct then prompt = prompt .. forcedActionText end
    
	local temperature = 0.9 -- was 0.9
	local freqPenalty = 1.4 -- was 1.4
	local presPenalty = 1.6 -- was 1.6
	
    -- DEBUG
    if self.Instance:GetAttribute("debug") then
        print(prompt)
    end

	local responseText = AIService.GPTPrompt(prompt, 100, nil, temperature, freqPenalty, presPenalty)
	if responseText == nil then
		warn("[NPC] Got nil response from GPT3")
		return
	end
	
    if forcedToAct then
        responseText = "Action:" .. forcedActionText .. responseText
        self.PlanningCounter = 0
    else
	    responseText = "Action:" .. responseText
    end

    self.Instance:SetAttribute("gpt_prompt", prompt)
    self.Instance:SetAttribute("gpt_response", responseText)

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
                -- Remove the Action: or Thought: part
				table.remove(parts, 1)
                local s = cleanstring(table.concat(parts, " "))
                table.insert(lineType, s)

                -- Splitting into sentenes here is not a good idea,
                -- because of sentences like Say "This is good."
			end
		end
	end
	
	for _, thought in thoughts do
		self:AddThought(thought)
	end
	
	local hasSpoken = false -- only one speech act per timestep
    local hasMoved = false -- only one movement per timestep
	
	for _, action in actions do
        if self:IsRepeatAction(action) then continue end
		
		local parsedActionsList = NPCService.ParseActions(action)
        for _, parsedAction in parsedActionsList do
            if parsedAction.Type == NPC.ActionType.Unhandled then
                self.PlanningCounter += 1
                continue
            end
            
            if parsedAction.Type == NPC.ActionType.Say then
                if hasSpoken then
                    continue
                else
                    hasSpoken = true
                end
            end

            if parsedAction.Type == NPC.ActionType.Move then
                if hasMoved then
                    continue
                else
                    hasMoved = true
                end
            end

            -- The agents sometimes have too much internal monologue
            -- and we use this trick to force them to speak
            if parsedAction.Type ~= NPC.ActionType.Plan then
                self.PlanningCounter = 0
            else
                self.PlanningCounter += 1
            end
            
            -- Plans go into the agent's stream as thoughts, we
            -- don't need to also record them as recent actions
            if parsedAction.Type ~= NPC.ActionType.Plan then
                self:AddRecentAction(action)
            end

            self:TakeAction(parsedAction)
        end
	end
end

function NPC:PromptContent()
	local observations = self:Observe() or {}

	local middle = ""
	
	-- The order of events in the prompt is important: the most
	-- recent events are at the bottom. We keep observations at the
	-- top because it seems to work well.
	
	for _, obj in observations do
		middle = middle .. `Observation: {obj}\n`
	end
	
	local entries = {}
	
	for _, entry in self.RecentActions do
		table.insert(entries, { Type = "Action", Content = entry.Action, Timestamp = entry.Timestamp})	
	end
	
	for _, entry in self.Thoughts do
		table.insert(entries, { Type = "Thought", Content = entry.Thought, Timestamp = entry.Timestamp})	
	end
	
	local sortedEntries = Array.sort(entries, function(entry1, entry2)
		return entry1.Timestamp < entry2.Timestamp
	end)
	
	for _, entry in sortedEntries do
		middle = middle .. entry.Type .. `: {entry.Content}\n`
	end
	
	return middle
end

-- Filter is a function that takes a summary and returns true or false
function NPC:MostSimilarSummary(text, filter)
    local function alwaysTrue(x)
        return true
    end
    filter = filter or alwaysTrue

    local embedding = AIService.Embedding(text)
    if embedding == nil then
        warn("[NPC] Got nil embedding")
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
            warn("[NPC] Got zero vectors for cosine similarity")
            return nil
        end

        return dot / ( m1 * m2 )
    end

    local highestSimilarity = - math.huge
    local mostSimilarSummary = nil

    for _, summary in self.Summaries do
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

function NPC:GenerateSummary(type)
    local name = self.Instance.Name
	local prompt = `The following is a record of the history of Observations, Thoughts and Actions of agent named {name}.\n\n`
	local middle = self:PromptContent()
	prompt = prompt .. middle
	prompt = prompt .. "\n"
	prompt = prompt .. `A summary of this history of {name} in 40 words or less is given below, written in first person from {name}'s point of view\n`

    if type == "ideas" then
        prompt = prompt .. "The summary focuses on the ideas, concepts and topics that are being discussed, not on the people present or actions irrelevant to the ideas.\n"
    else
        prompt = prompt .. "The summary contains the details like names that will be useful for the agent to recall in future conversations.\n"
    end

	prompt = prompt .. "\n"
	prompt = prompt .. "Summary:"
	
	local temperature = 0.7
	local freqPenalty = 0
	local presPenalty = 0

	local responseText = AIService.GPTPrompt(prompt, 120, nil, temperature, freqPenalty, presPenalty)
	if responseText == nil then
		warn("[NPC] Got nil response from GPT3")
		return
	end
	
    return cleanstring(responseText)
end

function NPC:Observe()
    -- The constraint is that each observation uses tokens, and the prompt
    -- cannot use too many tokens, both because it is expensive and because
    -- it will distract the agent. We must therefore filter the observations
    -- and "pay attention" to things that are nearby and/or important.
    
    -- However, we can't *only* pay attention to nearby things, because
    -- then the agent will never switch activities

    -- Because there are many boards, and they usually don't have distinctive
    -- names, we treat them specially. The agent simply observes something like
    -- "There is a board nearby. Additionally there is a previous board and next board", 
    -- "There are several boards nearby", "There are more boards in the area"
    -- We handle actions such as "Move to the next board", "Walk to another board"
    -- "Walk to the boards far away"

	if self.Instance.PrimaryPart == nil then return end
	local pos = self.Instance.PrimaryPart.Position
	
	local potentialObservations = {}
	
	for _, x in CollectionService:GetTagged(NPCService.NPCTag) do
		if x == self.Instance then continue end
        if not x:IsDescendantOf(game.Workspace) then continue end
		if getInstancePosition(x) == nil then continue end
	
		table.insert(potentialObservations, {Object = x, 
											Name = x.Name,
											Description = "They are a person"})
	end
	
	for _, plr in Players:GetPlayers() do
		if plr.Character == nil or plr.Character.PrimaryPart == nil then continue end
        
		table.insert(potentialObservations, {Object = plr.Character,
											Name = plr.DisplayName,
											Description = "They are a person"})
	end

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
	
	local NextToMeRadius = 25
	local NearbyRadius = 80
	local WalkingDistanceRadius = 200
	local observedBoardPhrases = {}

    local nextToMeObservationsCount = 0
    local maxNextToMeObservations = 3

    local nearbyObservationsCount = 0
    local maxNearbyObservations = 3

    local walkingDistanceObservationsCount = 0
    local maxWalkingDistanceObservations = 1

    shuffle(potentialObservations)

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
            nextToMeObservationsCount += 1
            if nextToMeObservationsCount > maxNextToMeObservations then continue end
		elseif distance < NearbyRadius then
			phrase = "is nearby but too far away to hear me"
            boardPhrase = "There are boards nearby"
            nearbyObservationsCount += 1
            if nearbyObservationsCount > maxNearbyObservations then continue end
		elseif distance < WalkingDistanceRadius then
			phrase = "is within walking distance"
            boardPhrase = "There are boards within walking distance"
            walkingDistanceObservationsCount += 1
            if walkingDistanceObservationsCount > maxWalkingDistanceObservations then continue end
		end
		
		local phrase = obj.Name .. ` {phrase}. {obj.Description}.`

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
		
		if distance < self.PersonalityProfile.GetsDetailedObservationsRadius then
			if obj.Observations ~= nil then
				for _, objOb in obj.Observations do
					table.insert(observations, objOb)
				end
			end
		end
	end
	
	return observations
end

function NPC:WalkToPos(targetPos)
	local currentPos = getInstancePosition(self.Instance)
	
	local unitVector = (targetPos - currentPos).Unit
	local distance = (targetPos - currentPos).Magnitude
	local destPos = currentPos + (distance - 12) * unitVector
	destPos = NPCService.GetEmptySpotNearPos(destPos)
	local animationTrack = self.Animations.WalkAnim

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
			path:ComputeAsync(self.Instance.PrimaryPart.Position, destination)
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
				reachedConnection = self.Instance.Humanoid.MoveToFinished:Connect(function(reached)
					self.Instance:SetAttribute("walking", false)

					if reached and nextWaypointIndex < #waypoints then
						-- Increase waypoint index and move to next waypoint
						nextWaypointIndex += 1
						self.Instance.Humanoid:MoveTo(waypoints[nextWaypointIndex].Position)
						self.Instance:SetAttribute("walking", true)
                    elseif reached then
						animationTrack:Stop()
                        self.Animations.IdleAnim:Play()
						reachedConnection:Disconnect()
						blockedConnection:Disconnect()

                        task.wait(0.1)
                        self:RotateToFacePosition(targetPos)
					else
                        -- We failed to walk, teleport
                        animationTrack:Stop()
                        self.Animations.IdleAnim:Play()
                        self.Instance:PivotTo(CFrame.lookAt(destPos, targetPos))
                    end
				end)
			end

			-- Initially move to second waypoint (first waypoint is path start; skip it)
			nextWaypointIndex = 2
            self.Animations.IdleAnim:Stop()
			animationTrack:Play()
			self.Instance:SetAttribute("walking", true)
			self.Instance.Humanoid:MoveTo(waypoints[nextWaypointIndex].Position)
		else
			warn("[NPC] Path not computed!", errorMessage)
		end
	end

	followPath(destPos)
	return true
end

function NPC:RotateToFacePosition(targetPos)
	local npcPos = getInstancePosition(self.Instance)
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

	local tween = TweenService:Create(self.Instance.PrimaryPart, tweenInfo,
		{CFrame = CFrame.lookAt(npcPos, targetPosXZ)})

	tween:Play()
end

function NPC:TakeAction(parsedAction)

	if parsedAction.Type == NPC.ActionType.Dance then
        self.Animations.IdleAnim:Stop()
		self.Animations.DanceAnim:Play()

		task.delay(3, function()
			self.Animations.DanceAnim:Stop()
            self.Animations.IdleAnim:Play()
		end)
		return
	end
	
	if parsedAction.Type == NPC.ActionType.Laugh then
        local target = parsedAction.Target
		if target ~= nil then
			local targetPos = getInstancePosition(target)
			self:RotateToFacePosition(targetPos)
		end

        self.Animations.IdleAnim:Stop()
		self.Animations.LaughAnim:Play()

		task.delay(3, function()
			self.Animations.LaughAnim:Stop()
            self.Animations.IdleAnim:Play()
		end)
		return
	end
	
    if parsedAction.Type == NPC.ActionType.Point then
		local target = parsedAction.Target
		if target ~= nil then
			local targetPos = getInstancePosition(target)
			self:RotateToFacePosition(targetPos)
            task.wait(0.2)
		end
		
        self.Animations.IdleAnim:Stop()
		self.Animations.PointAnim:Play()

        task.delay(3, function()
			self.Animations.PointAnim:Stop()
            self.Animations.IdleAnim:Play()
		end)

		return
	end

	if parsedAction.Type == NPC.ActionType.Wave then
		local target = parsedAction.Target
		if target ~= nil then
			local targetPos = getInstancePosition(target)
			self:RotateToFacePosition(targetPos)
		end
		
        self.Animations.IdleAnim:Stop()
		self.Animations.WaveAnim:Play()

		task.delay(3, function()
			self.Animations.WaveAnim:Stop()
            self.Animations.IdleAnim:Play()
		end)
		return
	end
	
	if parsedAction.Type == NPC.ActionType.Walk then
		local target = parsedAction.Target
		if target ~= nil and target ~= self.Instance and not target:GetAttribute("walking") then
			local targetPos = getInstancePosition(target)
			if targetPos ~= nil then
				self:WalkToPos(targetPos)
			end
		end
		return
	end
	
	if parsedAction.Type == NPC.ActionType.Say then
        local target = parsedAction.Target
		if target ~= nil then
			local targetPos = getInstancePosition(target)
			self:RotateToFacePosition(targetPos)
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
            if self.Instance:IsDescendantOf(game.Workspace) then
			    ChatService:Chat(self.Instance.Head, filteredMessage)
            end
		end
		
		-- Note that agents see the unfiltered messages
		NPCService.HandleChat(self.Instance, message, target)
		return
	end
	
	if parsedAction.Type == NPC.ActionType.Plan then
		self:AddThought(parsedAction.Content, "plan")
		return -- don't let the agent think this has already been finished
	end
	
	warn("[NPC] Unhandled parsed action")
end

--
-- NPCService
--

function NPCService.Init()
    	
	local npcInstances = CollectionService:GetTagged(NPCService.NPCTag)
	for _, npcInstance in npcInstances do
        print("[NPCService] Found NPC " .. npcInstance.Name)
        local npc = NPC.new(npcInstance)
        table.insert(NPCService.NPCs, npc)
	end

    CollectionService:GetInstanceAddedSignal(NPCService.NPCTag):Connect(function(npcInstance)
        local npc = NPC.new(npcInstance)
        table.insert(NPCService.NPCs, npc)
    end)
	
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
    -- Subscribe to messages of voice transcriptions
    local subscribeSuccess, subscribeConnection = pcall(function()
        return MessagingService:SubscribeAsync(NPCService.TranscriptionTopic, function(message)
            local messageString = message.Data
            local sourcePlayerName, message = string.match(messageString, "(.+)::(.+)")
            if sourcePlayerName ~= nil and message ~= nil then
                local sourcePlayer = nil
                for _, plr in Players:GetPlayers() do
                    if plr.Name == sourcePlayerName then
                        sourcePlayer = plr
                        break
                    end
                end

                -- The transcription message was not meant for this server
                if sourcePlayer == nil then return end
                if sourcePlayer.Character == nil or sourcePlayer.Character.PrimaryPart == nil then return end
                
                NPCService.HandleTranscription(sourcePlayer, message)
            else
                warn("[NPCService] Failed to match MessagingService message to template")
                return
            end
        end)
    end)
    
    if not subscribeSuccess then
        warn("[NPCService] Failed to subscribe to transcription topic")
    end

    for _, npc in NPCService.NPCs do
        task.spawn(function()
            local startup = true
            local stepCount = 0

            while true do
                local timestepDelay = npc.TimestepDelay
                timestepDelay += math.random(0, 2)
                task.wait(timestepDelay)

                if not npc.Instance:IsDescendantOf(game.Workspace) then continue end
                if npc.Instance.PrimaryPart == nil then continue end
                
                npc:Timestep(startup)
                startup = false

                stepCount += 1
                if stepCount == npc.PersonalityProfile.IntervalBetweenSummaries then
                    local summary = npc:GenerateSummary()
                    if summary ~= nil then
                        npc:AddThought(summary, "summary")
                        npc:AddSummary(summary)
                    end
                
                    stepCount = 0
                end
            end
        end)
    end
                
    -- Keep updated observations of boards in a way that NPCs can read them
    -- In order to avoid frequently OCRing boards that are far away from any
    -- NPC, we only OCR boards within NPCService.GetsDetailedObservationsRadius

    task.spawn(function()    
        while task.wait(10) do
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
                local distToNPC, npc = NPCService.DistanceToNearestNPC(getInstancePosition(boardInstance))
                if npc == nil then continue end -- no NPCs

                if distToNPC > npc.PersonalityProfile.GetsDetailedObservationsRadius then continue end

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

function NPCService.HandleTranscription(sourcePlayer, message)
    -- The source player is *not* the one speaking, necessarily, but
    -- rather the player whose Roblox account is being used as a channel
    -- for voice chat
    local sourcePlayerPos = getInstancePosition(sourcePlayer.Character)

    for _, npc in NPCService.NPCs do
		local npcPos = getInstancePosition(npc.Instance)
		if npcPos == nil then continue end
		local distance = (npcPos - sourcePlayerPos).Magnitude
		
        -- This NPC heard the chat message
		if distance < npc.PersonalityProfile.HearingRadius then
			local ob = "Someone nearby said \"" .. cleanstring(message) .. "\""
			npc:AddThought(ob, "speech")

            -- We kick up the timestep frequency when voice chat is involved
            if npc.TimestepDelay ~= npc.PersonalityProfile.TimestepDelayVoiceChat then
                npc.TimestepDelay = npc.PersonalityProfile.TimestepDelayVoiceChat
                print("[NPCService] Shifting to faster NPC processing for voice chat")
            end
            -- TODO: throttle actively depending on interaction style
            -- Also we have no way of dropping out of this mode later
		end
	end
end

function NPCService.HandleChat(speaker, message, target)
	-- speaker is a player or npc Instance
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
	
	for _, npc in NPCService.NPCs do
		if npc.Instance == speaker then continue end
		local npcPos = getInstancePosition(npc.Instance)
		if npcPos == nil then continue end
		local distance = (npcPos - pos).Magnitude
		
        -- This NPC heard the chat message
		if distance < npc.PersonalityProfile.HearingRadius then
			local ob = ""
            if target == nil then
                ob = name .. " said \"" .. message .. "\""
            else
                local targetName = if target == npc then "me" else target.Name
                ob = name .. " said to " .. targetName .. " \"" .. message .. "\""
            end

			npc:AddThought(ob)
		end
	end
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
-- Turns towards Youtwice

-- TODO: currently we do not correctly parse things unless the capitalisation is correct

function NPCService.ParseActions(actionText:string)
	local function findMessage(text)
        -- Find the closing quote, if it exists, sometimes GPT
        -- forgets if there are a lot of punctuation chars
        local message = text
        local submsg = string.match(text, "([^\"]+)\".*")
        if submsg ~= nil then message = submsg end
        --print("============ findMessage =======")
        --print("Given: " .. text)
        --print()
        --print("Returning: " .. message)
        --print("=====================")
        return message
    end
    
    -- Walk and Say
    -- Example: Walk to starsonthars and say "Hi, I'm Shoal. Do you like talking about math and science?"
    local walkSayPrefixes = {"Walk to", "Go to", "Follow"}
    local walkSayRegexes = {}
    for _, p in walkSayPrefixes do
        table.insert(walkSayRegexes, "^" .. p .. " ([^,\" ]+) [^\"]*\"(.+)")
    end
    
    for _, r in walkSayRegexes do
		local dest, message = string.match(actionText, r)
		if dest ~= nil and message ~= nil then
            local actionList = {}

            local sayActionDict = {}
            local walkActionDict = {}

            message = findMessage(message)

			sayActionDict.Type = NPC.ActionType.Say
            sayActionDict.Content = message
            table.insert(actionList, sayActionDict)

			local destInstance = NPCService.InstanceByName(dest)
            if destInstance ~= nil then
                walkActionDict.Type = NPC.ActionType.Walk
				walkActionDict.Target = destInstance
                table.insert(actionList, walkActionDict)
			end

			return actionList
		end
	end

    -- Wave and Say
    -- Example: Wave and say to Youtwice "See you soon!"
    local waveSayPrefixes = {"Wave to", "Wave and say to", "Give a friendly farewell to", "Wave a hand in greeting to"}
    local waveSayRegexes = {}
    for _, p in waveSayPrefixes do
        table.insert(waveSayRegexes, "^" .. p .. " ([^, ]+) [^\"]*\"(.+)")
    end

    for _, r in waveSayRegexes do
		local target, message = string.match(actionText, r)
		if target ~= nil and message ~= nil then
            local actionList = {}

            local targetInstance = NPCService.InstanceByName(target)
            if targetInstance ~= nil then
                local waveActionDict = {}
			    waveActionDict.Type = NPC.ActionType.Wave
			    waveActionDict.Target = targetInstance
                table.insert(actionList, waveActionDict)
            end

            message = findMessage(message)

            local sayActionDict = {}
            sayActionDict.Type = NPC.ActionType.Say
            sayActionDict.Content = message
            table.insert(actionList, sayActionDict)

			return actionList
        end
    end

    -- Point and say
    -- Example: Point to the boards and say "This is where we're headed!"
    -- Currently only handles pointing to objects
	for _, obj in CollectionService:GetTagged(NPCService.ObjectTag) do
		local name = obj.Name
        local suffix = " .*\"(.+)"
        local regexes = {"^Point to the ","^Point to ", "^Point at the ","^Point at ",
                "^Point at the direction of the ","^Point at the direction of "}
		for _, r in regexes do
			local message = string.match(actionText, r .. name .. suffix)
			if message then
                local actionList = {}

                pointActionDict = {}
				pointActionDict.Type = NPC.ActionType.Point
				pointActionDict.Target = obj
                table.insert(actionList, pointActionDict)

                message = findMessage(message)

                local sayActionDict = {}
                sayActionDict.Type = NPC.ActionType.Say
                sayActionDict.Content = message
                table.insert(actionList, sayActionDict)

				return actionList
			end
		end

        local regexes = {"^Point to the " .. name,"^Point to " .. name,
                "^Point at the " .. name,"^Point at " .. name,
                "^Point at the direction of the " .. name,"^Point at the direction of " .. name}
        for _, r in regexes do
			local message = string.match(actionText, r)
			if message then
                pointActionDict = {}
				pointActionDict.Type = NPC.ActionType.Point
				pointActionDict.Target = obj

				return {pointActionDict}
			end
		end
	end

	local dancePrefixes = {"Dance"}
	for _, p in dancePrefixes do
		if string.match(actionText, "^" .. p) then
            local actionDict = {}
			actionDict.Type = NPC.ActionType.Dance
			return {actionDict}
		end
	end

    local laughSayRegexes = {"^Laugh .*\"(.+)"}
    for _, r in laughSayRegexes do
		local message = string.match(actionText, r)
		if message ~= nil then
            local actionList = {}

            local laughActionDict = {}
			laughActionDict.Type = NPC.ActionType.Laugh
			table.insert(actionList, laughActionDict)

            message = findMessage(message)

            local sayActionDict = {}
            sayActionDict.Type = NPC.ActionType.Say
            sayActionDict.Content = message
            table.insert(actionList, sayActionDict)

			return actionList
        end
    end

	local laughPrefixes = {"Laugh"}
	for _, p in laughPrefixes do
		if string.match(actionText, "^" .. p) then
            local actionDict = {}
			actionDict.Type = NPC.ActionType.Laugh
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
				actionDict.Type = NPC.ActionType.Walk
				actionDict.Target = obj
				return {actionDict}
			end
		end
	end
	
    local walkRegexes = {"^Walk .*to the ([^, ]+)", "^Walk .*to ([^, ]+)",
    "^Lead .*to the ([^, ]+)", "^Lead .*to ([^, ]+)",
    "^Start walking .*to the ([^, ]+)", "^Start walking .*to ([^, ]+)",
    "^Follow .*to the ([^, ]+)","^Follow .*to ([^, ]+)",
    "^Follow .*to go and see the ([^, ]+)","^Follow .*to go and see ([^, ]+)",
    "^Follow ([^, ]+)", -- important that this comes after more specific queries
    "^Go to the ([^, ]+)","^Go to ([^, ]+)",
    "^Start walking towards the ([^, ]+)","^Start walking towards ([^, ]+)"}
	for _, r in walkRegexes do
		local dest = string.match(actionText, r)
		if dest ~= nil then
            local destInstance = NPCService.InstanceByName(dest)
            if destInstance ~= nil then
                local actionDict = {}
			    actionDict.Type = NPC.ActionType.Walk
				actionDict.Target = destInstance
                return {actionDict}
			end
		end
	end
	
    -- Say to
    -- Example: Say to Youtwice "I was curious about this Redwood tree"
    local sayToPrefixes = {"Say to", "Ask", "Reply to", "Respond to", "Tell", "Thank", "Smile and say to", "Wave and say to", "Laugh and say to", "Explain to", "Nod in agreement and say to", "Turn to", "Agree", "Turn towards"}
    local sayToRegexes = {}
    for _, p in sayToPrefixes do
        table.insert(sayToRegexes, "^" .. p .. " ([^, ]+) [^\"]*\"(.+)")
    end
    
    for _, r in sayToRegexes do
		local target, message = string.match(actionText, r)
		if target ~= nil and message ~= nil then
            local sayActionDict = {}
            local targetInstance = NPCService.InstanceByName(target)
            if targetInstance ~= nil then
                sayActionDict.Target = targetInstance
			end
            
            message = findMessage(message)

			sayActionDict.Type = NPC.ActionType.Say
            sayActionDict.Content = message
            return {sayActionDict}
		end
	end

	local sayPrefixes = {"Say", "Ask", "Reply", "Respond", "Tell", "Smile", "Nod", "Answer", "Look", "Introduce", "Tell", "Invite", "Examine", "Read", "Suggest", "Greet", "Offer", "Extend", "Explain", "Nod", "Agree", "Think", "Conclusion", "Pause", "Wave"}
	for _, p in sayPrefixes do
		if string.match(actionText, "^" .. p) then
			local message = string.match(actionText, "^" .. p .. " [^\"]*\"(.+)")
			if message ~= nil then
                message = findMessage(message)

                local actionDict = {}
				actionDict.Type = NPC.ActionType.Say
				actionDict.Content = message
				return {actionDict}
			end
		end
	end
	
    local wavePrefixes = {"Wave at", "Wave to", "Wave", "Greet", "Shake hands", "Smile"}
	for _, p in wavePrefixes do
		if string.match(actionText, "^" .. p) then
            local actionDict = {}
			actionDict.Type = NPC.ActionType.Wave
			
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
			actionDict.Type = NPC.ActionType.Plan
			actionDict.Content = actionText
			return {actionDict}
		end
	end
	
    local actionDict = {}
	actionDict.Type = NPC.ActionType.Unhandled
	return {actionDict}
end

function NPCService.DistanceToNearestNPC(pos)
    local distance = math.huge
    local closestNPC = nil

    for _, npc in NPCService.NPCs do
        if not npc.Instance:IsDescendantOf(game.Workspace) then continue end
        if npc.Instance.PrimaryPart == nil then continue end
        local d = (getInstancePosition(npc.Instance) - pos).Magnitude
        if d < distance then
            distance = d
            closestNPC = npc
        end
    end

    return distance, closestNPC
end

return NPCService