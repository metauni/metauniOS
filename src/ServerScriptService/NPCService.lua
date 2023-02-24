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
local TweenService = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")
local TextService = game:GetService("TextService")
local MessagingService = game:GetService("MessagingService")
local DataStoreService = game:GetService("DataStoreService")

-- Services
local AIService = require(script.Parent.AIService)
local SecretService = require(ServerScriptService.SecretService)
local BoardService = require(script.Parent.BoardService)

local Sift = require(ReplicatedStorage.Packages.Sift)
local Array = Sift.Array

local NPCService = {}
NPCService.__index = NPCService
NPCService.NPCTag = "npcservice_npc"
NPCService.ObjectTag = "npcservice_object"
NPCService.TranscriptionTopic = "transcription"
NPCService.NPCs = {}
NPCService.NPCFromInstance = {}

local npcStorageFolder = ReplicatedStorage:FindFirstChild("NPCs")
assert(npcStorageFolder, "[NPCService] Missing NPC storage folder")

local npcWorkspaceFolder = game.Workspace:FindFirstChild("NPCs")
assert(npcWorkspaceFolder, "[NPCService] Missing NPC workspace folder")

local REFERENCE_PROPER_NAMES = {
    ["euclid"] = "Euclid's Elements",
    ["heath_greek_history"] = "Heath's 'History of Greek Mathematics'",
    ["brighter"] = "Adam Dorr's book 'Brighter'",
    ["darwin_machines"] = "George Dyson's book 'Darwin among the Machines'",
    ["harbison"] = "Harbison's book 'Travels in the History of Architecture'",
    ["scientist_as_rebel"] = "Freeman Dyson's book 'The Scientist As Rebel'",
    ["turings_cathedral"] = "George Dyson's book 'Turing's Cathedral'",
    ["how_buildings_learn"] = "Stewart Brand's book 'How Building's Learn'",
    ["diamond_age"] = "Neal Stephenson's 'Diamond Age'",
    ["star_trek_philosophy"] = "the book 'Star Trek and Philosophy'",
    ["music_harmony_china"] = "Erica Brindley's 'Music, Cosmology and the Politics of Harmony in China'",
    --["sacred_geometry"] = "Hidetoshi and Rothman's 'Sacred Geometry'",
    ["lanier_owns_future"] = "Jaron Lanier's 'Who Owns the Future'",
    ["innovators_dilemma"] = "Clayton Christensen's 'Innovator's Dilemma'",
    ["great_stagnation"] = "Tyler Cowen's 'Great Stagnation'",
    ["brief_history_university"] = "John Moore's 'A Brief History of Universities'",
    ["russell_western_philosophy"] = "Bertrand Russell's 'History of Western Philosophy'",
    ["russell_basic_writings"] = "Bertrand Russell's 'Basic Writings'",
    ["russell_autobiography"] = "Bertrand Russell's autobiography",
    ["utopian_universities"] = "Taylor and Pellew's 'Utopian Universities'",
    ["haiku_anthology"] = "the book 'Haiku - An Anthology of Japanese Poems'",
    ["haiku_mountain_tasting"] = "the collection 'Mountain Tasting' of haiku by Taneda",
    ["bashos_haiku"] = "the book 'Bashos Haiku'"
}

-- Utils
local function newRemoteFunction(name)
    if ReplicatedStorage:FindFirstChild(name) then
        warn(`[NPCService] Remote function {name} already exists`)
        return
    end
    
    local r = Instance.new("RemoteFunction")
    r.Name = name
    r.Parent = ReplicatedStorage
    return r
end

local function newRemoteEvent(name)
    if ReplicatedStorage:FindFirstChild(name) then
        warn(`[NPCService] Remote event {name} already exists`)
        return
    end

    local r = Instance.new("RemoteEvent")
    r.Name = name
    r.Parent = ReplicatedStorage
    return r
end

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	while DataStoreService:GetRequestBudgetForRequestType(requestType) <= 0 do
		task.wait()
	end
end

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

function NPC.DefaultPlayerPerm()
    local perm = {["Read"] = true, ["Remember"] = false}
    return perm
end

function NPC.DefaultPersonalityProfiles()
    -- Note, many highly relevant references have scores of ~ 0.83, 0.84
    local personalityProfiles = {}
    personalityProfiles.Normal = {
        Name = "Normal",
        IntervalBetweenSummaries = 8,
        MaxRecentActions = 5,
        MaxThoughts = 8,
        MaxSummaries = 20,
        SearchShortTermMemoryProbability = 0.1,
        SearchLongTermMemoryProbability = 0.1,
        SearchReferencesProbability = 0.07,
        SearchTranscriptsProbability = 0.05,
        SomethingDifferentProbability = 0.05,
        MaxConsecutivePlan = 2,
        TimestepDelayNormal = 15,
        TimestepDelayVoiceChat = 8,
        ReferenceRelevanceScoreCutoff = 0.83,
        TranscriptRelevanceScoreCutoff = 0.83,
        MemoryRelevanceScoreCutoff = 0.7,
        ModelTemperature = 0.9, -- was 0.85
	    ModelFrequencyPenalty = 1.8, -- was 1.6
	    ModelPresencePenalty = 1.6,
        ModelName = "text-davinci-003",
        HearingRadius = 40,
        GetsDetailedObservationsRadius = 60,
        SecondsWithoutInteractionBeforeSleep = 2 * 60,
        WalkingDistanceRadius = 200,
        PromptPrefix = SecretService.NPCSERVICE_PROMPT,
        PersonalityLines = {}, -- configured per NPC
        Seminars = {}, -- configured per NPC
        References = {}, -- configured per NPC
    }

    personalityProfiles.Seminar = updateWith(personalityProfiles.Normal, {
        Name = "Seminar",
        SearchShortTermMemoryProbability = 0.2,
        SearchLongTermMemoryProbability = 0.2,
        SearchReferencesProbability = 0.25,
        SearchTranscriptsProbability = 0.2,
        TimestepDelayNormal = 30,
        TimestepDelayVoiceChat = 15,
        ReferenceRelevanceScoreCutoff = 0.8,
        TranscriptRelevanceScoreCutoff = 0.8,
        MemoryRelevanceScoreCutoff = 0.8,
        HearingRadius = 60,
        GetsDetailedObservationsRadius = 60,
        PromptPrefix = SecretService.NPCSERVICE_PROMPT_SEMINAR
    })

    personalityProfiles.Storm = updateWith(personalityProfiles.Normal, {
        Name = "Storm",
        SearchReferencesProbability = 0.15,
        SearchTranscriptsProbability = 0.08,
        SearchShortTermMemoryProbability = 0.08,
        SearchLongTermMemoryProbability = 0.08,
        TimestepDelayNormal = 8,
        TimestepDelayVoiceChat = 5,
        ReferenceRelevanceScoreCutoff = 0.8,
        TranscriptRelevanceScoreCutoff = 0.8,
        MemoryRelevanceScoreCutoff = 0.71,
        ModelTemperature = 0.9,
	    ModelFrequencyPenalty = 1.8,
	    ModelPresencePenalty = 1.6,
    })

    return personalityProfiles
end

function NPC.new(instance: Model)
    assert(instance.PrimaryPart, "NPC Model must have PrimaryPart set: "..instance:GetFullName())
    assert(instance.PersistId, "NPC must have a PersistId")

    local npc = {}
    setmetatable(npc, NPC)

    npc.Instance = instance
    npc.PersistId = instance.PersistId.Value
    npc.Thoughts = {}
    npc.RecentActions = {}
    npc.RecentReferences = {}
    npc.RecentTranscripts = {}
    npc.Summaries = {}
    npc.PlanningCounter = 0
    npc.PersonalityProfiles = NPC.DefaultPersonalityProfiles()
    npc.CurrentProfile = "Normal"
    npc.LastInteractionTimestamp = -math.huge -- last time the agent saw a chat or voice message from a player
    npc.OrbOffset = nil
    npc.TokenCount = 0
    
    -- Personalisation
    local configScript = npc.Instance:FindFirstChild("NPCConfig")

    if configScript then
        local Config = require(configScript)
        assert(typeof(Config) == "function", "Bad NPCConfig, should be function that modifies PersonalityProfiles")
        
        Config(npc.PersonalityProfiles)
    end

    npc.TimestepDelay = npc:GetPersonality("TimestepDelayNormal")

    -- Animations
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

function NPC:SetCurrentProfile(name)
    self.CurrentProfile = name
    self.TimestepDelay = self:GetPersonality("TimestepDelayNormal")
end

function NPC:UpdatePersonalityProfile()
    -- This automated change is only for Seminar/Normal
    if self.CurrentProfile ~= "Seminar" and self.CurrentProfile ~= "Normal" then return end

    local targetOrbValue = self.Instance:FindFirstChild("TargetOrb")
    if targetOrbValue == nil then return end
    if targetOrbValue.Value == nil then return end
    local orb = self.Instance.TargetOrb.Value
    if orb:FindFirstChild("Speaker") == nil then return end
    
    if orb.Speaker.Value ~= nil then
        self:SetCurrentProfile("Seminar")
    else
        self:SetCurrentProfile("Normal")
    end
end

function NPC:GetPersonality(attribute)
    return self.PersonalityProfiles[self.CurrentProfile][attribute]
end

function NPC:Timestep(forceSearch)
    self:UpdatePersonalityProfile()

    if math.random() < self:GetPersonality("SearchShortTermMemoryProbability") then
        local memory = self:ShortTermMemory()
        if memory ~= nil then
            if not self:IsRepeatThought(memory) then
                self:AddThought(memory, "memory")
            end
        end
    end

    if forceSearch or math.random() < self:GetPersonality("SearchLongTermMemoryProbability") then
        local relevanceCutoff = if forceSearch then 0.5 else self:GetPersonality("MemoryRelevanceScoreCutoff")

        local memory = self:LongTermMemory(relevanceCutoff)
        if memory ~= nil then
            self:AddThought(memory, "memory")
        end
    end

    -- Search references
    if forceSearch or math.random() < self:GetPersonality("SearchReferencesProbability") then
        local ref = self:SearchReferences()
        if ref ~= nil then
            self:AddThought(ref, "reference")
        end
    end

    -- Search transcripts
    if math.random() < self:GetPersonality("SearchTranscriptsProbability") then
        local ref = self:SearchTranscripts()
        if ref ~= nil then
            self:AddThought(ref, "transcript")
        end
    end
    
    self:Prompt()
    
    -- Walk an NPC targetting an orb to maintain a fixed offset from the orb
    if self.CurrentProfile == "Seminar" then
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
	tableInsertWithMax(self.RecentActions, entry, self:GetPersonality("MaxRecentActions"))
end

function NPC:AddThought(thought, type)
	local entry = { Thought = thought, Timestamp = tick() }
    if type ~= nil then entry.Type = type end

    if type == "memory" or type == "reference" or type == "transcript" then
        for _, entry in self.Thoughts do
            if entry.Type == type and entry.Thought == thought then return end
        end
    end

	tableInsertWithMax(self.Thoughts, entry, self:GetPersonality("MaxThoughts"))
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

	tableInsertWithMax(self.Summaries, summaryDict, self:GetPersonality("MaxSummaries"))

    if embedding then
        local metadata = {
            ["name"] = self.Instance.Name,
            ["id"] = self.PersistId,
            ["timestamp"] = summaryDict.Timestamp,
            ["content"] = summaryDict.Content,
            ["type"] = summaryDict.Type
        }
        local vectorId = HttpService:GenerateGUID(false)
        AIService.StoreEmbedding(vectorId, embedding, metadata, "npc")
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
    local interval = self:GetPersonality("IntervalBetweenSummaries")
    local max = self:GetPersonality("MaxSummaries")

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
    local interval = self:GetPersonality("IntervalBetweenSummaries")
    local max = self:GetPersonality("MaxSummaries")

    local shortTermMemoryInterval = timestepDelay * interval * max
    
    local filter = {
        ["id"] = self.PersistId,
        ["timestamp"] = { ["$lt"] = tick() - shortTermMemoryInterval }
    }
    local topk = 3
    local matches = AIService.QueryEmbeddings(embedding, filter, topk, "npc")
    if matches == nil then return end
    if #matches == 0 then return end

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

function NPC:SearchTranscripts()
    local summary = self:GenerateSummary("ideas")
    if summary == nil then return end

    local embedding = AIService.Embedding(summary)
    if embedding == nil then return end

    local semList = self:GetPersonality("Seminars")
    if #semList == 0 then return end
    local filter = {
        ["seminar"] = { ["$in"] = semList }
    }
    
    local topk = 3
    local matches = AIService.QueryEmbeddings(embedding, filter, topk, "transcripts")
    if matches == nil then return end
    if #matches == 0 then return end

    local goodMatches = {}
    for _, match in matches do
        if match["score"] > self:GetPersonality("TranscriptRelevanceScoreCutoff") and
            not tableContains(self.RecentTranscripts, match["id"]) then
            table.insert(goodMatches, match)
        end
    end

    if #goodMatches == 0 then return end

    local match = goodMatches[math.random(1,#goodMatches)]
    tableInsertWithMax(self.RecentTranscripts, match["id"], 6)

    local metadata = match["metadata"]
    if metadata == nil then
        warn("[NPC] Got malformed match for transcript")
        return
    end

    local content = cleanstring(metadata["content"])
    local content = string.gsub(content, "\n", " ")
    local content = string.gsub(content, ":", " ") -- don't confuse the AI
    local content = string.gsub(content, "\"", "'") -- so we can wrap in " quotes

    local timediff = tick() - metadata["timestamp"]
    local intervalText = humanReadableTimeInterval(timediff) .. " ago"

    local refContent = `I remember that {intervalText} in the {metadata["seminar"]} seminar it was discussed that \"{content}\"`
    if self.Instance:GetAttribute("debug") then
        print("----------")
        print("[NPC] Found transcript reference")
        print(string.sub(refContent,1,30) .. "...")
        print("score = " .. match["score"])
        print("----------")
    end
    return refContent
end

function NPC:SearchReferences()
    local summary = self:GenerateSummary("ideas")
    if summary == nil then return end

    local embedding = AIService.Embedding(summary)
    if embedding == nil then return end

    local refList = self:GetPersonality("References")
    if #refList == 0 then return end
    local filter = {
        ["name"] = { ["$in"] = refList }
    }

    local topk = 3
    local matches = AIService.QueryEmbeddings(embedding, filter, topk, "refs")
    if matches == nil then return end
    if #matches == 0 then return end

    local goodMatches = {}
    for _, match in matches do
        if match["score"] > self:GetPersonality("ReferenceRelevanceScoreCutoff") and
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

function NPC:RespondToMessage(message)
    self:Timestep(true)
end

function NPC:Prompt()
	local prompt = self:GetPersonality("PromptPrefix") .. "\n"
    prompt = prompt .. `{self.Instance.Name} is an Agent\n`
	prompt = prompt .. `Thought: My name is {self.Instance.Name}, I live in a virtual world called metauni which is an institution of higher learning.\n`
	
	-- Sample one of the other personality thoughts
	local personalityLines = self:GetPersonality("PersonalityLines")
    if #personalityLines > 0 then
        local pText = personalityLines[math.random(1,#personalityLines)]
        prompt = prompt .. `Thought: {pText}\n`
    end
	
	local middle = self:PromptContent()
	prompt = prompt .. middle .. "Action:"
	
    -- If the agent has been talking to themself too much (i.e. planning)
    -- then force them to speak by giving Say as the prompt
    local forcedToAct = false
    local forcedActionText = ""
    if self.PlanningCounter >= self:GetPersonality("MaxConsecutivePlan") then
        forcedToAct = true
        forcedActionText = " Say \""
    end

    if forcedToAct then prompt = prompt .. forcedActionText end
    
	local temperature = self:GetPersonality("ModelTemperature")
	local freqPenalty = self:GetPersonality("ModelFrequencyPenalty")
	local presPenalty = self:GetPersonality("ModelPresencePenalty")

    local model = self:GetPersonality("ModelName")
    
    local responseText, tokenCount = AIService.GPTPrompt(prompt, 100, nil, temperature, freqPenalty, presPenalty, model)

	if responseText == nil then
		warn("[NPC] Got nil response from GPT3")
		return
	end

    self.TokenCount += tokenCount
    self.Instance:SetAttribute("npcservice_tokencount", self.TokenCount)
	
    if forcedToAct then
        responseText = "Action:" .. forcedActionText .. responseText
        self.PlanningCounter = 0
    else
	    responseText = "Action:" .. responseText
    end

    if self.Instance:GetAttribute("debug") then
        self.Instance:SetAttribute("gpt_prompt", prompt)
        self.Instance:SetAttribute("gpt_response", responseText)
        print(middle)
    end

	local actions = {}
	local thoughts = {}
	
	for _, l in string.split(responseText, "\n") do
		local lineType = nil
		if string.match(l, "^Action:") then
			lineType = actions
		elseif string.match(l, "^Thought:") then
			lineType = thoughts
		end
		
		if lineType ~= nil then
			local parts = string.split(l, " ")
			if #parts > 1 then
                -- Remove the Action: or Thought: part
				table.remove(parts, 1)
                local s = cleanstring(table.concat(parts, " "))
                table.insert(lineType, s)
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

function NPC:PromptContent(filter)
    filter = filter or function(text) return true end

	local observations = self:Observe() or {}

	local middle = ""
	
	-- The order of events in the prompt is important: the most
	-- recent events are at the bottom. We keep observations at the
	-- top because it seems to work well.
	for _, obj in observations do
        if filter(obj) then
		    middle = middle .. `Observation: {obj}\n`
        end
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

    -- If we are forming a memory, then do not include messages
    -- from players that have declined permission for this NPC
    local function filter(text)
        for _, plr in Players:GetPlayers() do
            if string.match(text, "^" .. plr.DisplayName .. " said.*") then
                return NPCService.PlayerPerms[plr][tostring(self.PersistId)]["Remember"]
            end
        end
        
        return true
    end

	local prompt = `The following is a record of the history of Observations, Thoughts and Actions of agent named {name}.\n\n`
	local middle = if type == "memory" then self:PromptContent(filter) else self:PromptContent()
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
	
	local temperature = 0.5
	local freqPenalty = 0
	local presPenalty = 0

	local responseText, tokenCount = AIService.GPTPrompt(prompt, 120, nil, temperature, freqPenalty, presPenalty)
	if responseText == nil then
		warn("[NPC] Got nil response from GPT3")
		return
	end

    --local responseTextCurie, _ = AIService.GPTPrompt(prompt, 120, nil, temperature, freqPenalty, presPenalty, "text-curie-001")
    --print("Davinci summary ----")
    --print(responseText)
    --print("Curie summary-----")
    --print(responseTextCurie)

    self.TokenCount += tokenCount
    self.Instance:SetAttribute("npcservice_tokencount", self.TokenCount)
	
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
	
	local NextToMeRadius = self:GetPersonality("HearingRadius")
	local NearbyRadius = 80
	local WalkingDistanceRadius = self:GetPersonality("WalkingDistanceRadius")
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
		
		if distance < self:GetPersonality("GetsDetailedObservationsRadius") then
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
    NPCService.PlayerPerms = {} -- plr to permissions for each NPC

	local npcInstances = CollectionService:GetTagged(NPCService.NPCTag)
	for _, npcInstance in npcInstances do
        local npc = NPC.new(npcInstance)
        table.insert(NPCService.NPCs, npc)
        NPCService.NPCFromInstance[npcInstance] = npc
	end

    CollectionService:GetInstanceAddedSignal(NPCService.NPCTag):Connect(function(npcInstance)
        local npc = NPC.new(npcInstance)
        table.insert(NPCService.NPCs, npc)
    end)
	
    local function playerInit(plr)
        -- Enable NPCs to perceive text chat
        plr.Chatted:Connect(function(msg)
			NPCService.HandleChat(plr, msg)
		end)

        NPCService.FetchPlayerPerms(plr)
    end

	Players.PlayerAdded:Connect(function(plr)
        playerInit(plr)
	end)

    Players.PlayerRemoving:Connect(function(plr)
        NPCService.StorePlayerPerms(plr)
    end)
	
	for _, plr in Players:GetPlayers() do
		playerInit(plr)
	end

    newRemoteFunction("GetNPCPrivacySettings").OnServerInvoke = function(plr)
        return NPCService.PlayerPerms[plr]
    end

    newRemoteEvent("SetNPCPrivacySettings").OnServerEvent:Connect(function(plr : Instance, npcPersistId : number, permType : string, value : boolean)
        -- The NPC perms are a dictionary that maps the PersistId of an NPC to
        -- a dictionary of the form { "Read" = true, "Remember" = false }
        NPCService.PlayerPerms[plr] = NPCService.PlayerPerms[plr] or {}
        NPCService.PlayerPerms[plr][tostring(npcPersistId)] = NPCService.PlayerPerms[plr][tostring(npcPersistId)] or {}
        NPCService.PlayerPerms[plr][tostring(npcPersistId)][permType] = value
    end)
end

local function inTimePeriods(periodList)
    local function minutesSinceBeginningOfWeek()
        local dayOfWeek = tonumber(os.date("!%w"))
        local secondsSinceMidnight = os.date("!%H") * 3600 + os.date("!%M") * 60 + os.date("!%S")
        local secondsToLastSunday = dayOfWeek * 24 * 3600
        return (secondsSinceMidnight + secondsToLastSunday) / 60
    end

    local minutesNow = minutesSinceBeginningOfWeek()
    for _, hours in periodList do
        if minutesNow >= hours.StartTime and minutesNow <= hours.StartTime + hours.Duration then
            return true
        end
    end

    return false
end

function NPCService.NPCByPersistId(persistId)
    for _, npc in NPCService.NPCs do
        if npc.PersistId == persistId then return npc end
    end
end

local sceneProps = {}

function NPCService.StartScene(scene)
    local Config = require(scene.Config)

    if Config.Name then
        print(`[NPCService] Starting scene {Config.Name}`)
    else
        print("[NPCService] Starting scene")
    end

    -- Move NPCs into position
    for _, npcData in Config.NPCs do
        local npc = NPCService.NPCByPersistId(npcData.PersistId)
        if npc == nil then continue end

        if npc.Instance.Parent == npcStorageFolder then
            npc.Instance.Parent = npcWorkspaceFolder
        end
        
        npc.Instance:PivotTo(CFrame.new(npcData.Position))
        npc.Instance:SetAttribute("npcservice_inactivescene", true)
    end

    -- Move props into position
    if scene:FindFirstChild("Props") then
        local sceneFolder = scene.Props:Clone()
        sceneFolder.Parent = npcWorkspaceFolder
        sceneProps[scene] = sceneFolder
    end

    if Config.Start then task.spawn(Config.Start) end
end

function NPCService.EndScene(scene)
    local Config = require(scene.Config)

    if Config.Name then
        print(`[NPCService] Ending scene {Config.Name}`)
    else
        print("[NPCService] Ending scene")
    end

    -- Move NPCs into storage
    for _, npcData in Config.NPCs do
        local npc = NPCService.NPCByPersistId(npcData.PersistId)
        if npc == nil then continue end

        if npc.Instance.Parent == npcWorkspaceFolder then
            npc.Instance.Parent = npcStorageFolder
        end

        npc.Instance:SetAttribute("npcservice_inactivescene", false)
    end

    if sceneProps[scene] then
        sceneProps[scene]:Destroy()
        sceneProps[scene] = nil
    end

    if Config.Stop then task.spawn(Config.Stop) end
end

function NPCService.CheckScenes()
    local DELAY = 10
    local sceneStatus = {} -- active or inactive

    while true do
        task.wait(DELAY)

        for _, scene in CollectionService:GetTagged("npcservice_scene") do
            if sceneStatus[scene] == nil then sceneStatus[scene] = "inactive" end

            if not scene:FindFirstChild("Config") then continue end
            local Config = require(scene.Config)
            local active = inTimePeriods(Config.Times) or scene:GetAttribute("npcservice_scene_debugon")
            
            if active and sceneStatus[scene] == "inactive" then
                NPCService.StartScene(scene)
                sceneStatus[scene] = "active"
            elseif not active and sceneStatus[scene] == "active" then
                NPCService.EndScene(scene)
                sceneStatus[scene] = "inactive"
            end
        end
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

                -- Check to see if we are in office hours
                local inActiveScene = npc.Instance:GetAttribute("npcservice_inactivescene")
                local inWorkspace = npc.Instance:IsDescendantOf(game.Workspace)

                -- If the agent has not been interacted with recently, and is not
                -- in office hours, and has not been summoned, move it to storage
                if not inActiveScene and npc.LastInteractionTimestamp < tick() - 5 * 60 and 
                    not npc.Instance:GetAttribute("npcservice_summoned") then
                    
                    if npcStorageFolder then
                        npc.Instance.Parent = npcStorageFolder
                        inWorkspace = false
                    end
                end

                if not inWorkspace then continue end
                if npc.Instance.PrimaryPart == nil then continue end
                
                -- Don't sit around thinking too much without human input
                if npc.LastInteractionTimestamp < tick() - npc:GetPersonality("SecondsWithoutInteractionBeforeSleep") then
                    continue
                end

                ----- take the step ----
                npc:Timestep(startup)
                ------------------------

                startup = false

                stepCount += 1
                if stepCount == npc:GetPersonality("IntervalBetweenSummaries") then
                    local summary = npc:GenerateSummary("memory")
                    if summary ~= nil then
                        npc:AddThought(summary, "summary")
                        npc:AddSummary(summary)
                    end
                
                    stepCount = 0
                end
            end
        end)
    end

    task.spawn(NPCService.CheckScenes)
                
    -- Keep updated observations of boards in a way that NPCs can read them
    -- In order to avoid frequently OCRing boards that are far away from any
    -- NPC, we only OCR boards within GetsDetailedObservationsRadius
    
    task.spawn(function() 
        while true do
            task.wait(10)

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

                if distToNPC > npc:GetPersonality("GetsDetailedObservationsRadius") then continue end

                local board = BoardService.Boards[boardInstance]

                local boardText = AIService.OCRBoard(board)
                if boardText and boardText ~= "" then
                    boardText = cleanstring(boardText)
                    boardText = string.gsub(boardText, "\n", " ")
                    boardText = string.gsub(boardText, "\"", "'")

                    local obFolder = observationFolder(boardInstance)
                    obFolder:ClearAllChildren()

                    local stringValue = Instance.new("StringValue")
                    stringValue.Value = "The board has written on it \"" .. boardText .."\""
                    stringValue.Parent = obFolder
                end
            end
        end
    end)
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
		if distance < npc:GetPersonality("HearingRadius") then
			local ob = "Someone nearby said \"" .. cleanstring(message) .. "\""
			npc:AddThought(ob, "speech")

            npc.Instance:SetAttribute("npcservice_hearing", true)
            npc.TimestepDelay = npc:GetPersonality("TimestepDelayVoiceChat")

            npc.LastInteractionTimestamp = tick()
		else
            npc.Instance:SetAttribute("npcservice_hearing", false)
            npc.TimestepDelay = npc:GetPersonality("TimestepDelayNormal")
        end
	end
end

function NPCService.FetchPlayerPerms(plr)
    local DataStore = DataStoreService:GetDataStore("npcservice")
    local permKey = "perms/" .. plr.UserId

    local success, permDict = pcall(function()
        waitForBudget(Enum.DataStoreRequestType.GetAsync)
        return DataStore:GetAsync(permKey)
    end)
    if not success then
        warn(`[NPCService] Failed to get permissions for {plr.Name}: ` .. permDict)
        return
    end
    
    NPCService.PlayerPerms[plr] = permDict or {}
    for _, npc in NPCService.NPCs do
        if not NPCService.PlayerPerms[plr][tostring(npc.PersistId)] then
            NPCService.PlayerPerms[plr][tostring(npc.PersistId)] = NPC.DefaultPlayerPerm()
        end
    end
end

function NPCService.StorePlayerPerms(plr)
    if not NPCService.PlayerPerms[plr] then
        warn(`[NPCService] Perms for player {plr.Name} not loaded, declining to store`)
        return
    end

    local DataStore = DataStoreService:GetDataStore("npcservice")
    local permKey = "perms/" .. plr.UserId

    local success, result = pcall(function()
        waitForBudget(Enum.DataStoreRequestType.SetIncrementAsync)
        DataStore:SetAsync(permKey, NPCService.PlayerPerms[plr])
    end)

    if not success then
        warn(`[NPCService] Failed to store perms for player {plr.Name} :` .. result)
    end
end

function NPCService.HandleChat(speaker, message, target)
	local name
	local pos

	if CollectionService:HasTag(speaker, NPCService.NPCTag) then
        -- Speaker is a NPC
        speakerIsPlayer = false
		name = speaker.Name
		if speaker.PrimaryPart == nil then return end
		pos = speaker.PrimaryPart.Position
	else
        -- Speaker is a player
        speakerIsPlayer = true
		name = speaker.DisplayName
		if speaker.Character == nil or speaker.Character.PrimaryPart == nil then return end
		pos = speaker.Character.PrimaryPart.Position
	end
	
    local function getReadPerm(plr, npc)
        return NPCService.PlayerPerms[plr][tostring(npc.PersistId)]["Read"]
    end

	for _, npc in NPCService.NPCs do
        if not npc.Instance then continue end
        if not npc.Instance:IsDescendantOf(game.Workspace) then continue end
		if npc.Instance == speaker then continue end

        if speakerIsPlayer and not getReadPerm(speaker, npc) then continue end

		local npcPos = getInstancePosition(npc.Instance)
		local distance = (npcPos - pos).Magnitude
		
		if distance < npc:GetPersonality("HearingRadius") then
            -- This NPC heard the chat message
			local ob = ""
            if target == nil then
                -- WARNING: The format of this text is used to filter player messages
                -- from NPC memories, so change with care
                ob = name .. " said \"" .. message .. "\""
            else
                local targetName = if target == npc then "me" else target.Name
                ob = name .. " said to " .. targetName .. " \"" .. message .. "\""
            end

			npc:AddThought(ob)

            -- If the message contains the name of this NPC, then we have
            -- some special behaviour to prepare the agent to respond
            if string.match(message, npc.Instance.Name) then
                npc:RespondToMessage(message)
            end

            if speakerIsPlayer then
                npc.LastInteractionTimestamp = tick()
            end
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