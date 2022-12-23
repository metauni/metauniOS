--
-- AIService
--
-- Interfaces with OpenAI APIs and other AI services
-- via HttpService

-- Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local SecretService = require(ServerScriptService.SecretService)

local Common = ReplicatedStorage:WaitForChild("metaboardCommon")
local Figure = require(Common.Figure)
local Sift = require(Common.Packages.Sift)
local Config = require(Common.Config)
local Array, Set, Dictionary = Sift.Array, Sift.Set, Sift.Dictionary
local BoardService = require(Common.BoardService)

local VISION_API_URL = "http://34.116.106.66:8080"
local GPT_API_URL = "https://api.openai.com/v1/completions"

local function serialiseBoard(board)
	local clearCount = board.ClearCount
	local nextFigureZIndex = board.NextFigureZIndex
	local aspectRatio = board:AspectRatio()

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

	-- Serialise and encode every figureId-figure pair as a length 2 json array
	local chunks = {}
	local lines = {}

	for figureId, figure in pairs(figures) do
		local serialisedFigure = Figure.Serialise(figure)
		table.insert(lines, { figureId, serialisedFigure })
	end
	
	return lines
end


local AIService = {}
AIService.__index = AIService

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

function AIService.GPTPrompt(promptText, maxTokens, plr)
	local request = { ["model"] = "text-davinci-003",
		["prompt"] = promptText,
		["temperature"] = 0,
		["max_tokens"] = maxTokens,
		["top_p"] = 1.0,
		["frequency_penalty"] = 0.0,
		["presence_penalty"] = 0.0}
	
	if plr ~= nil then
		request["user"] = tostring(plr.UserId)
	end

	local success, response = pcall(function()
		return HttpService:PostAsync(
			GPT_API_URL,
			HttpService:JSONEncode(request),
			Enum.HttpContentType.ApplicationJson,
			false,
			{["Authorization"] = "Bearer " .. SecretService.GPT_API_KEY})
	end)

	if success then
		if response == nil then
			print("[AIService] Got a bad response from PostAsync")
			return nil
		end

		local responseData = HttpService:JSONDecode(response)
		if responseData == nil then
			print("[AIService] JSONDecode on response failed")
			return nil
		end
		
		local responseText = responseData["choices"][1]["text"]
		return responseText
	else
		return nil
	end
end

function AIService.ObjectLocalizationForBoard(boardInstance)
    local board = BoardService.Boards[boardInstance]
    if board == nil then
        print("[AIService] Failed to fetch board data from BoardService")
        return nil
    end

    local serialisedBoardData = serialiseBoard(board)
	local json = HttpService:JSONEncode({RequestType = "ObjectLocalization", 
			Content = serialisedBoardData})
	
	local success, response = pcall(function()
		return HttpService:PostAsync(
			VISION_API_URL,
			json,
			Enum.HttpContentType.ApplicationJson,
			false)
	end)

	if success then
		if response == nil then
			print("[AIService] Got a bad response from ObjectLocalization PostAsync")
			return nil
		end

		local responseData = HttpService:JSONDecode(response)
		if responseData == nil then
			print("[AIService] ObjectLocalization JSONDecode on response failed")
			return nil
		end

		local responseDict = responseData["objects"]
		return responseDict
	else
		print("[AIService] ObjectLocalization HTTPService PostAsync failed ".. response)
		return nil
	end
end

function AIService.OCRBoard(boardInstance)
	local board = BoardService.Boards[boardInstance]
    if board == nil then
        print("[AIService] Failed to fetch board data from BoardService")
        return nil
    end

    local serialisedBoardData = serialiseBoard(board)
	local json = HttpService:JSONEncode({RequestType = "OCR", 
			Content = serialisedBoardData})
	
	local success, response = pcall(function()
		return HttpService:PostAsync(
			VISION_API_URL,
			json,
			Enum.HttpContentType.ApplicationJson,
			false)
	end)

	if success then
		if response == nil then
			print("[AIService] Got a bad response from OCR PostAsync")
			return nil
		end

		local responseData = HttpService:JSONDecode(response)
		if responseData == nil then
			print("[AIService] OCR JSONDecode on response failed")
			return nil
		end

		local responseText = responseData["text"]
		return responseText
	else
		print("[AIService] OCR HTTPService PostAsync failed ".. response)
		return nil
	end
end

return AIService
