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
	-- local contents = roblox.serializePlace(place) BAD DOESN'T WORK WITH CURRENT LUNE

	local contents = roblox.serializePlace(place, true)

	return net.request({
		url = `https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions`,
		headers = {
				["x-api-key"] = apiKey,
				["Content-Type"] = "application/xml",
				-- ["Content-Type"] = "applicsation/octet-stream", BAD DOESN'T WORK WITH CURRENT LUNE
		},
		query = {
				versionType = "Published",
		},
		method = "POST",
		body = contents,
	})
end


local function legacyUploadAssetId(contents: string, assetId: number): net.FetchResponse
	-- 1. Try to find the auth cookie for the current user
	local cookie = roblox.getAuthCookie()
 
	-- 2. Create request headers in advance, we might re-use them for CSRF challenges
	local headers = {
		["User-Agent"] = "Roblox/WinInet",
		["Content-Type"] = "application/xml",
		-- ["Content-Type"] = "application/octet-stream",
		Accept = "application/json",
		Cookie = cookie,
	}
 
	-- 3. Create and send a request to the upload url
	local uploadResponse = net.request({
		url = `https://data.roblox.com/Data/Upload.ashx?assetid={assetId}`,
		body = contents,
		method = "POST",
		headers = headers,
	})
 
	-- 4. Check if we got a valid response, we might have gotten a CSRF
	--    challenge and need to send the request with a token included
	if
		not uploadResponse.ok
		and uploadResponse.statusCode == 403
		and uploadResponse.headers["x-csrf-token"] ~= nil
	then
		headers["X-CSRF-Token"] = uploadResponse.headers["x-csrf-token"]
		uploadResponse = net.request({
			url = `https://data.roblox.com/Data/Upload.ashx?assetid={assetId}`,
			body = contents,
			method = "POST",
			headers = headers,
		})
	end

	return uploadResponse
end

function assetApi.downloadPlace(placeId: number)
	local contents = downloadAssetId(placeId)
	local place = roblox.deserializePlace(contents)
	return place
end

assetApi._downloadAssetId = downloadAssetId


function assetApi.publishExistingPlace(place: roblox.DataModel, placeId: number): net.FetchResponse
	local uploadResponse = uploadPlaceId(place, placeId)
	return uploadResponse
end

return assetApi