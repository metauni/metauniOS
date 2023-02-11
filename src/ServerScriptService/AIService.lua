--
-- AIService
--

-- Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local SecretService = require(ServerScriptService.SecretService)

local metaboard = require(ReplicatedStorage.Packages.metaboard)
local Figure = metaboard.Figure
local Sift = require(ReplicatedStorage.Packages.Sift)
local Dictionary = Sift.Dictionary

local PINECONE_UPSERT_URL = "https://metauni-d08c033.svc.us-west1-gcp.pinecone.io/vectors/upsert"
local PINECONE_QUERY_URL = "https://metauni-d08c033.svc.us-west1-gcp.pinecone.io/query"
local VISION_API_URL = "https://www.metauniservice.com"
local GPT_API_URL = "https://api.openai.com/v1/completions"
local EMBEDDINGS_API_URL = "https://api.openai.com/v1/embeddings"

-- Utils
local function serialiseBoard(board)
    -- Commit all of the drawing task changes (like masks) to the figures
	local figures = board:CommitAllDrawingTasks()
	local removals = {}

	-- Remove the figures that have been completely erased
	for figureId, figure in pairs(figures) do
		if Figure.FullyMasked(figure) then
			removals[figureId] = Sift.None
		end
	end

	figures = Dictionary.merge(figures, removals)
	local lines = {}

	for figureId, figure in pairs(figures) do
        if figure.Type == "Curve" and figure.Color == nil then
            figure.Color = Color3.new(1,1,1)
        end
        
		local serialisedFigure = Figure.Serialise(figure)
		table.insert(lines, { figureId, serialisedFigure })
	end
	
	return lines
end

-- authString is optional
local function safePostAsync(apiUrl, encodedRequest, authDict)
    local success, response

    if authDict ~= nil then
        success, response = pcall(function()
            return HttpService:PostAsync(
                apiUrl,
                encodedRequest,
                Enum.HttpContentType.ApplicationJson,
                false,
                authDict)
        end)
    else
        success, response = pcall(function()
            return HttpService:PostAsync(
                apiUrl,
                encodedRequest,
                Enum.HttpContentType.ApplicationJson,
                false)
        end)
    end

    if not success then
        warn("[AIService] PostAsync failed: " .. response)
        return
    end	

    if response == nil then
        warn("[AIService] Got a bad response from PostAsync")
        return
    end

    if response == "" or response == " " then
        warn("[AIService] Got blank response from PostAsync")
        return
    end

    local decodeSuccess, responseData = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if not decodeSuccess then
        warn("[AIService] JSONDecode in safePostAsync: " .. responseData)
        warn("[AIService] Invalid JSON was: " .. response)
        return
    end

    if responseData == nil then
        warn("[AIService] JSONDecode returned nil")
        return
    end
	
    return responseData
end

--
-- AIService
--

local AIService = {}
AIService.__index = AIService

function AIService.Init()
end

function AIService.Start()
end

function AIService.CleanGPTResponse(text, extraPrefixes)
	local matched
	
	local prefixes = {" ", "\n", "%."}
	if extraPrefixes ~= nil then
		for _, p in extraPrefixes do
			table.insert(prefixes, p)
		end
	end
	
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
	
	-- Break words that are too long
	local words = string.split(text, " ")
	local newText = ""
	
	for _, w in words do
		if string.len(w) > 20 then
			
			newText = newText .. string.sub(w,1,10) .. " " .. string.sub(w,11,-1) .. " "
		else
			newText = newText .. w .. " "
		end
	end
	
	return text
end

function AIService.Embedding(text, plr)
    if text == nil or text == "" then
        warn("[AIService] Asked for embedding of empty string")
        return
    end

    local request = { ["model"] = "text-embedding-ada-002",
		["input"] = text}
	
	if plr ~= nil then
		request["user"] = tostring(plr.UserId)
	end

    local encodedRequest = HttpService:JSONEncode(request)

    local responseData = safePostAsync(EMBEDDINGS_API_URL, encodedRequest, 
        {["Authorization"] = "Bearer " .. SecretService.GPT_API_KEY})

    if responseData == nil then return end

	local responseVector = responseData["data"][1]["embedding"]
    if responseVector == nil then
        warn("[AIService] Embedding got malformed response:")
        print(responseVector)
        return
	end

    return responseVector
end

function AIService.StoreEmbedding(vectorId, vector, metadata, namespace)
    assert(vector ~= nil, "[AIService] nil vector")
    assert(metadata ~= nil, "[AIService] nil metadata")
    assert(namespace ~= nil, "[AIService] nil namespace")

    local request = { ["namespace"] = namespace,
        ["vectors"] = {
        {
          ["id"] = vectorId,
          ["metadata"] = metadata,
          ["values"] = vector
        }} }

    local encodedRequest = HttpService:JSONEncode(request)
    local responseData = safePostAsync(PINECONE_UPSERT_URL, encodedRequest, 
        {["Api-Key"] = SecretService.PINECONE_API_KEY})

    if responseData == nil then
        warn("[AIService] Failed to send embedding to pinecone")
    end
end

function AIService.QueryEmbeddings(vector, filter, topk, namespace)
    namespace = namespace or ""
    local request = { ["vector"] = vector,
                      ["filter"] = filter,
                      ["topK"] = topk,
                      ["includeMetadata"] = true,
                      ["namespace"] = namespace }
        
    local encodedRequest = HttpService:JSONEncode(request)
    local responseData = safePostAsync(PINECONE_QUERY_URL, encodedRequest, 
        {["Api-Key"] = SecretService.PINECONE_API_KEY})

    if responseData == nil then
        warn("[AIService] Failed to query embeddings")
        return {}
    end

    local matches = responseData["matches"]
    return matches
end

function AIService.GPTPrompt(promptText, maxTokens, plr, temperature, freqPenalty, presPenalty, model)
    temperature = temperature or 0
    freqPenalty = freqPenalty or 0.0
    presPenalty = presPenalty or 0.0
    model = model or "text-davinci-003"

	local request = { ["model"] = model,
		["prompt"] = promptText,
		["temperature"] = temperature,
		["max_tokens"] = maxTokens,
		["top_p"] = 1.0,
		["frequency_penalty"] = freqPenalty,
		["presence_penalty"] = presPenalty}
	
	if plr ~= nil then
		request["user"] = tostring(plr.UserId)
	end

    local encodedRequest = HttpService:JSONEncode(request)
    local responseData = safePostAsync(GPT_API_URL, encodedRequest, 
        {["Authorization"] = "Bearer " .. SecretService.GPT_API_KEY})

    if responseData == nil then return end

    local tokenCount = responseData["usage"]["total_tokens"]

	local responseText = responseData["choices"][1]["text"]
    if responseText == nil then
        warn("[AIService] GPTPrompt got malformed response:")
        print(responseData)
        return
    end

	return responseText, tokenCount
end

function AIService.ObjectLocalizationForBoard(board)

    local serialisedBoardData = serialiseBoard(board)
	local encodedRequest = HttpService:JSONEncode({RequestType = "ObjectLocalization", 
			Content = serialisedBoardData})
	
    local responseData = safePostAsync(VISION_API_URL, encodedRequest)
    if responseData == nil then return end

    local responseDict = responseData["objects"]
    if responseDict == nil then
        warn("[AIService] ObjectLocalizationForBoard got malformed response:")
        print(responseData)
    end
	
    return responseDict
end

function AIService.OCRBoard(board)

	local serialisedBoardData = serialiseBoard(board)
	local encodedRequest = HttpService:JSONEncode({RequestType = "OCR", 
			Content = serialisedBoardData})
	
    local responseData = safePostAsync(VISION_API_URL, encodedRequest)
    if responseData == nil then return end

    local responseText = responseData["text"]
    if responseText == nil then
        warn("[AIService] OCRBoard got malformed response:")
        print(responseData)
        return
    end

    return responseText
end

return AIService
