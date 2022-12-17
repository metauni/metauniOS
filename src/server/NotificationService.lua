--
-- NotificationService
--
-- Interfaces with the metauniService webserver, allowing
-- web and email notifications of in-world events

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

metauniServiceAddress = "http://34.116.106.66:8080"
	
local NotificationService = {}
NotificationService.__index = NotificationService

function NotificationService.GetNumberOfSubscribers(pocketId)
	if not pocketId then
		pocketId = ""
	end
	
	local json = HttpService:JSONEncode({RequestType = "GetBoardNotificationSubscriberNumbers", 
		Content = pocketId})

	local success, response = pcall(function()
		return HttpService:PostAsync(
			metauniServiceAddress,
			json,
			Enum.HttpContentType.ApplicationJson,
			false)
	end)	
	
	if success then
		if response == nil then
			print("[NotificationService] Got a bad response from PostAsync")
			return nil
		end

		local successJson, responseData = pcall(function()
			return HttpService:JSONDecode(response)
		end)

		if successJson then
			if responseData == nil then
				print("[NotificationService] JSONDecode on response failed")
				return nil
			end
		else
			print("[NotificationService] Can't parse JSON")
			return
		end

		return responseData
	else
		print("[NotificationService] HTTPService PostAsync failed ".. response)
		return nil
	end
end

function NotificationService.SendNotification(note)
	local json = HttpService:JSONEncode({RequestType = "Notification", 
		Content = note})

	local success, response = pcall(function()
		return HttpService:PostAsync(
			metauniServiceAddress,
			json,
			Enum.HttpContentType.ApplicationJson,
			false)
	end)

	if success then
		if response == nil then
			print("[NotificationService] Got a bad response from PostAsync")
			return nil
		end
		
		local successJson, responseData = pcall(function()
			return HttpService:JSONDecode(response)
		end)
		
		if successJson then
			if responseData == nil then
				print("[NotificationService] JSONDecode on response failed")
				return nil
			end
		else
			print("[NotificationService] Can't parse JSON")
			return
		end

		local responseText = responseData["text"]
		return responseText
	else
		print("[NotificationService] HTTPService PostAsync failed ".. response)
		return nil
	end
end

return NotificationService
