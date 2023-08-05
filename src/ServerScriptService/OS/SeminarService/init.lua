local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local yaml = require(ReplicatedStorage.Packages.yaml)
local t = require(ReplicatedStorage.Packages.t)
local Promise = require(ReplicatedStorage.Packages.Promise)

local SeminarService = {}
SeminarService.__index = SeminarService

local DEBUG = false

function SeminarService:_fetchSchedule()
	local url = "https://raw.githubusercontent.com/metauni/metauni.github.io/main/schedule/schedule.yml"
	
	local response
	if DEBUG then
		response = script.example_schedule.Value
	else
		local TRIES = 3
		local DELAY = 3

		local promise = Promise.retryWithDelay(function()
			return Promise.new(function(resolve, reject)
				local success, msg = pcall(function()
					response = HttpService:GetAsync(url)
				end)
	
				if success then
					resolve(response)
				else
					reject(msg)
				end
			end)
		end, TRIES, DELAY)

		local success, result = promise:await()
		if success then
			response = result
		else
			error("Failed to fetch seminar schedule. "..result)
		end
	end

	return yaml.eval(response)
end

--[[
	data should be validated with SeminarService:_validateSchedule first
--]]
function SeminarService:_decodeTime(dateStr: string, utcOffsetStr: string, localTimeStr: string): DateTime
	
	local offsetMinutes do
		local sign, hours, minutes = utcOffsetStr:match("([%+%-])(%d+):(%d+)$")
		offsetMinutes = tonumber(hours) :: number * 60 + tonumber(minutes) :: number
	
		if sign == "-" then
			offsetMinutes = -offsetMinutes
		end
	end

	local localMinutes do
		local hours, minutes = localTimeStr:match("(%d+):(%d+)")
		localMinutes = tonumber(hours) :: number * 60 + tonumber(minutes) :: number
	end

	-- Assuming you have your date in year, month, day format
	local day, month, year = dateStr:match("^(%d+)/(%d+)/(%d+)$")
	day = tonumber(day)
	month = tonumber(month)
	year = tonumber(year)

	local universalMinutes = localMinutes - offsetMinutes
	return DateTime.fromUniversalTime(year, month, day, 0, universalMinutes)
end

function SeminarService:_validateSchedule(schedule: {[any]: any}): (boolean, string?)
	-- Example schedule.toml
	--[[
		metauni day: "27/07/2023" # dd/mm/yyyy
		timezone: "+10:00" # AEST is 10 hours and 00 minutes ahead of UTC

		whats on:
		- Euclid:
				time: 09:30-10:00
				organizer: Dan Murfet, Ken Chan
				desc: "Euclid's Elements Book 3."
				website: https://metauni.org/euclid
				location: https://www.roblox.com/games/start?placeId=8165217582&launchData=/
		- Singular Learning Theory:
				time: 16:00-17:30
				organizer: Dan Murfet, Edmund Lau
				desc: "Singularities are knowledge. A learning seminar on Watanabe’s Singular Learning Theory: algebraic geometry serves statistical learning theory."
				website: https://metauni.org/slt
	--]]

	local datePattern = "^(%d%d)/(%d%d)/(%d%d%d%d)$"
	local utcOffsetPattern = "^([+-])(%d%d):(%d%d)$"
	local timeslotPattern = "^(%d%d):(%d%d)-(%d%d):(%d%d)$"

	local seminarChecker = t.interface({
		["time"] = t.match(timeslotPattern)
		-- We use location for pocket name, but don't check it here
		-- because we default to TRS (or discord) if no match
	})

	local singletonMap = function(keyCheck, valueCheck)
		return function(value)
			local tableSuccess, tableErrMsg = t.table(value)
			if not tableSuccess then
				return false, tableErrMsg or "" -- pass error message for value not being a table
			end
			
			local onlyKey, _ = next(value)
			if not t.keys(t.literal(onlyKey))(value) then
				return false, "Bad table: not a singleton map"
			end

			return t.map(keyCheck, valueCheck)
		end
	end

	local checker = t.interface {
		["metauni day"] = t.match(datePattern),
		["timezone"] = t.match(utcOffsetPattern),
		-- This should be an array of singleton maps, with the seminar name as the only key
		["whats on"] = t.array(singletonMap(t.string, seminarChecker)),
	}

	return checker(schedule)
end

function SeminarService:GetCurrentSeminars()
	self = SeminarService

	local schedule = self:_fetchSchedule()
	assert(self:_validateSchedule(schedule))

	local dateStr = schedule["metauni day"]
	local utcOffsetStr = schedule["timezone"]

	local seminars = {}

	for _, seminarSingleton in schedule["whats on"] do

		local seminar = {}
		local title, data = next(seminarSingleton)
		seminar.Name = title

		local startTimeStr, endTimeStr = data.time:match("^(%d+:%d+)-(%d+:%d+)$")
		seminar.StartTime = self:_decodeTime(dateStr, utcOffsetStr, startTimeStr)
		seminar.EndTime = self:_decodeTime(dateStr, utcOffsetStr, endTimeStr)

		if data.location then
			local url: string = data.location:gsub("%%20", " "):gsub("%%3A", ":")
			local pocketMatch = url:match("pocket:(.+)$")
			if pocketMatch then
				seminar.PocketName = pocketMatch
			elseif url:match("launchData=/") then
				seminar.PocketName = "The Rising Sea"
			end
		end

		-- Note: It's possible there's no PocketName set
		table.insert(seminars, seminar)
	end

	return seminars
end

return SeminarService