-- local fs = require("@lune/fs")
local net = require("@lune/net")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")
local metauni = require("metauni")

local assetApi = {}

local function downloadAssetId(assetId: number)
	-- 1. Try to find the auth cookie for the current user
	local cookie = roblox.getAuthCookie()
	
	assert(cookie ~= nil, "Failed to get roblox auth cookie")
 
	-- 2. Send a request to the asset delivery API,
	--    which will respond with cdn download link(s)
	local assetApiResponse = net.request({
		url = `https://assetdelivery.roblox.com/v2/assetId/{assetId}`,
		headers = {
			Accept = "application/json",
			Cookie = cookie,
		},
	})
	if not assetApiResponse.ok then
		error(
			string.format(
				"Failed to fetch asset download link for asset id %s!\n%s (%s)\n%s",
				tostring(assetId),
				tostring(assetApiResponse.statusCode),
				tostring(assetApiResponse.statusMessage),
				tostring(assetApiResponse.body)
			)
		)
	end
 
	-- 3. Make sure we got a valid response body
	local assetApiBody = serde.decode("json", assetApiResponse.body)
	if type(assetApiBody) ~= "table" then
		error(
			string.format(
				"Asset delivery API returned an invalid response body!\n%s",
				assetApiResponse.body
			)
		)
	elseif type(assetApiBody.locations) ~= "table" then
		--selene:allow(if_same_then_else)
		error(
			string.format(
				"Asset delivery API returned an invalid response body!\n%s",
				assetApiResponse.body
			)
		)
	end
 
	-- 4. Grab the first asset download location - we only
	--    requested one in our query, so this will be correct
	local firstLocation = assetApiBody.locations[1]
	if type(firstLocation) ~= "table" then
		error(
			string.format(
				"Asset delivery API returned no download locations!\n%s",
				assetApiResponse.body
			)
		)
	elseif type(firstLocation.location) ~= "string" then
		error(
			string.format(
				"Asset delivery API returned no valid download locations!\n%s",
				assetApiResponse.body
			)
		)
	end
 
	-- 5. Fetch the place contents from the cdn
	local cdnResponse = net.request({
		url = firstLocation.location,
		headers = {
			Cookie = cookie,
		},
	})
	if not cdnResponse.ok then
		error(
			string.format(
				"Failed to download asset with id %s from the Roblox cdn!\n%s (%s)\n%s",
				tostring(assetId),
				tostring(cdnResponse.statusCode),
				tostring(cdnResponse.statusMessage),
				tostring(cdnResponse.body)
			)
		)
	end
 
	-- 6. The response body should now be the contents of the asset file
	return cdnResponse.body
end

local function uploadPlaceId(place: roblox.DataModel, placeId: number): net.FetchResponse
	
	local apiKey = process.env["METAUNIOS_PUBLISH_KEY"]
	local universeId = metauni.UniverseId
	local contents = roblox.serializePlace(place)

	return net.request({
		url = `https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions`,
		headers = {
				["x-api-key"] = apiKey,
				["Content-Type"] = "applicsation/octet-stream",
		},
		query = {
				versionType = "Published",
		},
		method = "POST",
		body = contents,
	})
end

function assetApi.downloadPlace(placeId: number)
	local contents = downloadAssetId(placeId)
	local place = roblox.deserializePlace(contents)
	return place
end

function assetApi.publishExistingPlace(place: roblox.DataModel, placeId: number): net.FetchResponse
	local uploadResponse = uploadPlaceId(place, placeId)
	return uploadResponse
end

return assetApi