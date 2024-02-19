local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HumanoidDescriptionSerialiser = require(script.Parent.HumanoidDescriptionSerialiser)
local BitBuffer = require(ReplicatedStorage.Packages.BitBuffer)
local Rose = require(ReplicatedStorage.Packages.Rose)
local Sift = require(ReplicatedStorage.Packages.Sift)
local metaboard = require(ReplicatedStorage.Packages.metaboard)
local t = require(ReplicatedStorage.Packages.t)

--[[
	v0 serialisation library.

	Dependencies: 
		rstk/bitbuffer@1.0.0 (https://github.com/rstk/BitBuffer/blob/31c6d19a9d76e8055fd10aa06f6c5ac3f76608c9/src/init.lua)
]]
local export = {}

local FORMAT_VERSION = "v0.1.0"
-- vMAJOR.MINOR.PATCH-ADDITIONAL
local function parseSemver(semverStr: string)
	assert(t.string(semverStr))
	local major, minor, patch = string.match(semverStr, "^v(%d+)%.(%d+)%.(%d+)")
	local additional = string.match(semverStr, "^v%d+%.%d+%.%d+%-(.*)")
	return {
		Major = tonumber(major),
		Minor = tonumber(minor),
		Patch = tonumber(patch),
		Additional = additional,
	}
end

local checkSemVer = t.strictInterface {
	Major = t.number,
	Minor = t.number,
	Patch = t.number,
	Additional = t.optional(t.any),
}

local CURRENT_SEMVER = parseSemver(FORMAT_VERSION)
assert(checkSemVer(CURRENT_SEMVER))

local function checkSemVerOrWarnOrError(semverStr: string)
	local semver = parseSemver(semverStr)
	do
		local ok, msg = checkSemVer(semver)
		if not ok then
			error(`Bad semver formatting {semverStr}: {msg}`)
		end
	end

	if typeof(semver.Additional) == "string" and string.match(semver.Additional, "alpha") then
		warn(`Replay recording is alpha version ({semverStr})`)
		return
	end

	if semver.Major < CURRENT_SEMVER.Major then
		error(`Replay recording is on outdated major version {semver.Major} (semver: {semverStr}, current: {FORMAT_VERSION})`)
	end

	if semver.Major > CURRENT_SEMVER.Major then
		error(`Unable to parse record with later major version {semver.Major} (semver: {semverStr}, current: {FORMAT_VERSION})`)
	end

	if semver.Minor > CURRENT_SEMVER.Minor then
		warn(`Replay recording is newer minor version than current {semver.Minor} (semver: {semverStr}, current: {FORMAT_VERSION})`)
	end
end

export type BitWidth1to32 = number
export type FloatPrecision = "Float32" | "Float64"

local checkNonNegativeInteger = t.every(t.integer, t.numberMin(0))
local checkPositiveInteger = t.every(t.integer, t.numberPositive)
local checkFloatPrecision = t.union(t.literal("Float32"), t.literal("Float64"))
local checkEncoding = t.union(t.literal("Base64"), t.literal("Base91"))
local checkBoolShape = t.literal("Bool")
local checkBitWidth = t.every(t.integer, t.numberConstrained(1, 32))
local checkVector2Shape = t.strictInterface {
	Type = t.literal("Vector2"),
	Precision = checkFloatPrecision,
}
local checkVector3Shape = t.strictInterface {
	Type = t.literal("Vector3"),
	Precision = checkFloatPrecision,
}
local checkUIntShape = t.strictInterface {
	Type = t.literal("UInt"),
	BitWidth = checkBitWidth,
}
local checkBytesShape = t.strictInterface {
	Type = t.literal("Bytes"),
	NumBytes = checkPositiveInteger,
}
local checkCFrameShape = t.strictInterface {
	Type = t.literal("CFrame"),
	PositionPrecision = checkFloatPrecision,
	AngleBitWidth = checkBitWidth,
}
local checkRealNumber = function(number)
	if number == math.huge then
		return false, "Expected real number, got math.huge"
	elseif number == -math.huge then
		return false, "Expected real number, got -math.huge"
	elseif number ~= number then
		return false, "Expected real number, got nan"
	end
	return true
end
local checkColorShape = t.literal("Color3")
local checkQuantizedShape = t.every(t.strictInterface {
	Type = t.literal("Quantized"),
	BitWidth = checkBitWidth,
	Min = checkRealNumber,
	Max = checkRealNumber,
}, function(value)
	if value.Max - value.Min <= 0 then
		return false, `Bad min/max values [{value.Min}, {value.Max}]`
	end
	return true
end)

local checkEnumShape = t.every(t.strictInterface {
	Type = t.literal("Enum"),
	BitWidth = checkBitWidth,
	EnumItems = t.array(function(item)
		if not table.find({"number", "string", "EnumItem"}, typeof(item)) then
			return false, `Bad enum item {item}`
		end
		return true
	end),
	ItemToToken = t.map(t.any, checkNonNegativeInteger),
	Expandable = t.boolean,
}, function(enumShape)

	if not enumShape.Expandable and #enumShape.EnumItems <= 0 then
		return false, "Expected > 0 enumItems for non-expandable enumShape"
	end
	if #enumShape.EnumItems > bit32.lshift(1, enumShape.BitWidth) then
		return false, `Too many enums {enumShape.EnumItems} for BitWidth`
	end
	for item, token in enumShape.ItemToToken do
		if enumShape.EnumItems[token+1] ~= item then
			return false, `Bad mapping {item} -> {token}`
		end
	end
	for i, item in enumShape.EnumItems do
		if enumShape.ItemToToken[item] ~= i-1 then
			return false, `Bad mapping {item} -> {enumShape.ItemToToken[item]} (should be {i-1})`
		end
	end
	return true
end)

local function checkDataShape(dataShape)
	if typeof(dataShape) == "string" and table.find({"Float32", "Float64", "Bool", "Color3", "Variable"}, dataShape) then
		return true
	end
	if typeof(dataShape) == "table" then
		if dataShape.Type == "CFrame" then
			return checkCFrameShape(dataShape)
		elseif dataShape.Type == "Vector2" then
			return checkVector2Shape(dataShape)
		elseif dataShape.Type == "Vector3" then
			return checkVector3Shape(dataShape)
		elseif dataShape.Type == "UInt" then
			return checkUIntShape(dataShape)
		elseif dataShape.Type == "Bytes" then
			return checkBytesShape(dataShape)
		elseif dataShape.Type == "Quantized" then
			return checkQuantizedShape(dataShape)
		elseif dataShape.Type == "Enum" then
			return checkEnumShape(dataShape)
		elseif dataShape.Type == "Array" then
			return t.strictInterface {
				Type = t.literal("Array"),
				LengthShape = checkUIntShape,
				ItemShapes = t.array(checkDataShape),
			}(dataShape)
		else
			return false, `Bad table data shape {dataShape}, .Type={dataShape.Type}`
		end
	end
	return false, `Unrecognised datashape {dataShape} with type {typeof(dataShape)}`
end

local function checkStrictArrayShape(...)
	local itemShapeCheckers = {...}
	assert(t.array(t.callback)(itemShapeCheckers))

	return function(value)
		return t.every(t.strictInterface {
			Type = t.literal("Array"),
			LengthShape = checkUIntShape,
			ItemShapes = t.strictArray(table.unpack(itemShapeCheckers)),
		})(value)
	end
end

local writeFloat: {[FloatPrecision]: (buffer: BitBuffer.BitBuffer, number) -> ()} = {
	Float32 = BitBuffer.WriteFloat32,
	Float64 = BitBuffer.WriteFloat64,
}
local readFloat: {[FloatPrecision]: (buffer: BitBuffer.BitBuffer) -> (number)} = {
	Float32 = BitBuffer.ReadFloat32,
	Float64 = BitBuffer.ReadFloat64,
}

local function writeVector2(buffer, value: Vector2, precision: "Float32" | "Float64")
	assert(typeof(value) == "Vector2", "Bad Vector2")
	writeFloat[precision](buffer, value.X)
	writeFloat[precision](buffer, value.Y)
end

local function readVector2(buffer, precision: "Float32" | "Float64"): Vector2
	return Vector2.new(
		readFloat[precision](buffer),
		readFloat[precision](buffer))
end

local function writeVector3(buffer, value: Vector3, precision: "Float32" | "Float64")
	assert(typeof(value) == "Vector3", "Bad Vector3")
	writeFloat[precision](buffer, value.X)
	writeFloat[precision](buffer, value.Y)
	writeFloat[precision](buffer, value.Z)
end

local function readVector3(buffer, precision: "Float32" | "Float64"): Vector3
	return Vector3.new(
		readFloat[precision](buffer),
		readFloat[precision](buffer),
		readFloat[precision](buffer))
end

local function writeQuantized(buffer, value: number, bitWidth: number, min: number, max: number)
	assert(typeof(value) == "number" and value == value, "Bad number")
	local maxBitValue = 2^bitWidth - 1
	local range = max - min
	buffer:WriteUInt(bitWidth, math.clamp(math.round(maxBitValue * (value - min)/range), 0, maxBitValue))
end

local function readQuantized(buffer, bitWidth: number, min: number, max: number)
	local maxBitValue = 2^bitWidth - 1
	local range = max - min
	return min + buffer:ReadUInt(bitWidth) / maxBitValue * range
end

local function writeCFrame(buffer, value: CFrame, positionPrecision: "Float32" | "Float64", angleBitWidth: BitWidth1to32)
	assert(typeof(value) == "CFrame", "Bad CFrame")
	writeVector3(buffer, value.Position, positionPrecision)
	local rx, ry, rz = value:ToEulerAnglesXYZ()
	writeQuantized(buffer, rx, angleBitWidth, -math.pi, math.pi)
	writeQuantized(buffer, ry, angleBitWidth, -math.pi, math.pi)
	writeQuantized(buffer, rz, angleBitWidth, -math.pi, math.pi)
end

local function readCFrame(buffer, positionPrecision: "Float32" | "Float64", angleBitWidth: BitWidth1to32)
	local position = readVector3(buffer, positionPrecision)
	local rx = readQuantized(buffer, angleBitWidth, -math.pi, math.pi)
	local ry = readQuantized(buffer, angleBitWidth, -math.pi, math.pi)
	local rz = readQuantized(buffer, angleBitWidth, -math.pi, math.pi)
	return CFrame.new(position) * CFrame.fromEulerAnglesXYZ(rx, ry, rz)
end

local function writeColor3(buffer, color: Color3)
	assert(typeof(color) == "Color3", "Bad color")
	local r = math.clamp(math.round(color.R * 255), 0, 255)
	local g = math.clamp(math.round(color.G * 255), 0, 255)
	local b = math.clamp(math.round(color.B * 255), 0, 255)
	buffer:WriteUInt(8, r)
	buffer:WriteUInt(8, g)
	buffer:WriteUInt(8, b)
end

local function readColor3(buffer): Color3
	return Color3.new(
		buffer:ReadUInt(8) / 255,
		buffer:ReadUInt(8) / 255,
		buffer:ReadUInt(8) / 255)
end

-- enumItems can be any numeric-table of non-table, json-serialisable items
local function makeEnumShape(enumItems: {any}, bitWidth: number, expandable: boolean)
	local enumShape = {
		Type = "Enum",
		EnumItems = enumItems,
		BitWidth = bitWidth,
		ItemToToken = {},
		Expandable = expandable,
	}
	for i, item in enumItems do
		-- Tokens start from 0
		enumShape.ItemToToken[item] = i-1
	end
	checkEnumShape(enumShape)
	return enumShape
end

local function getEnumItem(enumShape, token)
	-- Tokens start from 0
	return enumShape.EnumItems[token + 1]
end

local function getItemTokenAndMaybeExpand(enumShape, item)
	assert(typeof(item) ~= "table", "Bad enum item")
	local token = enumShape.ItemToToken[item]
	if not token then
		if not enumShape.Expandable then
			error(`item {item} missing in non-expandable enumShape {enumShape}`)
		end
		if #enumShape.EnumItems >= bit32.lshift(1, enumShape.BitWidth) then
			local newBitWidth = enumShape.BitWidth + 1
			if newBitWidth > 32 then
				error("Tried to store more than 2^32 different enum values. There's no way this was intended.")
			end
			enumShape.BitWidth = newBitWidth
		end
		table.insert(enumShape.EnumItems, item)
		-- Tokens start from 0
		token = #enumShape.EnumItems - 1
		enumShape.ItemToToken[item] = token
		-- This O(n) check only happens log(n) times (n == number of enum items)
		checkEnumShape(enumShape)
	end

	return token
end

local function writeEnum(buffer: BitBuffer.BitBuffer, enumShape, item)
	assert(item, "Bad enum item")
	assert(typeof(item) ~= "table", "Bad enum item")
	local token = getItemTokenAndMaybeExpand(enumShape, item)
	buffer:WriteUInt(enumShape.BitWidth, token)
end

local function readEnum(buffer: BitBuffer.BitBuffer, enumShape)
	local token = buffer:ReadUInt(enumShape.BitWidth)
	local item = getEnumItem(enumShape, token)
	if not item then
		error(`Read bad token {token} for enumShape (example enum item={enumShape.EnumItems[1]})`)
	end
	return item
end

local function makeArrayShape(dataShapes, bitWidth: number?)
	bitWidth = bitWidth or 32
	assert(checkBitWidth(bitWidth))
	assert(t.array(checkDataShape)(dataShapes))
	return {
		Type = "Array",
		LengthShape = { Type = "UInt", BitWidth = bitWidth},
		ItemShapes = dataShapes,
	}
end

local function writeDataShape(buffer: BitBuffer.BitBuffer, dataShape: any, value: any)
	if dataShape == "Float32" then
		buffer:WriteFloat32(value)
	elseif dataShape == "Float64" then
		buffer:WriteFloat64(value)
	elseif dataShape == "Bool" then
		buffer:WriteBool(value)
	elseif dataShape == "Color3" then
		writeColor3(buffer, value)
	elseif typeof(dataShape) == "table" and dataShape.Type == "Vector2" then
		writeVector2(buffer, value, dataShape.Precision)
	elseif typeof(dataShape) == "table" and dataShape.Type == "Vector3" then
		writeVector3(buffer, value, dataShape.Precision)
	elseif typeof(dataShape) == "table" and dataShape.Type == "UInt" then
		buffer:WriteUInt(dataShape.BitWidth, value)
	elseif typeof(dataShape) == "table" and dataShape.Type == "Bytes" then
		assert(#value == dataShape.NumBytes, "Bad bytes value")
		buffer:WriteBytes(value)
	elseif typeof(dataShape) == "table" and dataShape.Type == "CFrame" then
		writeCFrame(buffer, value, dataShape.PositionPrecision, dataShape.AngleBitWidth)
	elseif typeof(dataShape) == "table" and dataShape.Type == "Quantized" then
		writeQuantized(buffer, value, dataShape.BitWidth, dataShape.Min, dataShape.Max)
	elseif typeof(dataShape) == "table" and dataShape.Type == "Enum" then
		writeEnum(buffer, dataShape, value)
	else
		error("Bad dataShape")
	end
end

-- eventShape should be checked once before calling this function many times
local function writeEventShape(buffer: BitBuffer.BitBuffer, eventShape, event)
	for i, dataShape in ipairs(eventShape) do
		writeDataShape(buffer, dataShape, event[i])
	end
end

local function readDataShape(buffer: BitBuffer.BitBuffer, dataShape)
	if dataShape == "Float32" then
		return buffer:ReadFloat32()
	elseif dataShape == "Float64" then
		return buffer:ReadFloat64()
	elseif dataShape == "Bool" then
		return buffer:ReadBool()
	elseif dataShape == "Color3" then
		return readColor3(buffer)
	elseif typeof(dataShape) == "table" and dataShape.Type == "Vector2" then
		return readVector2(buffer, dataShape.Precision)
	elseif typeof(dataShape) == "table" and dataShape.Type == "Vector3" then
		return readVector3(buffer, dataShape.Precision)
	elseif typeof(dataShape) == "table" and dataShape.Type == "UInt" then
		return buffer:ReadUInt(dataShape.BitWidth)
	elseif typeof(dataShape) == "table" and dataShape.Type == "Bytes" then
		return buffer:ReadBytes(dataShape.NumBytes)
	elseif typeof(dataShape) == "table" and dataShape.Type == "CFrame" then
		return readCFrame(buffer, dataShape.PositionPrecision, dataShape.AngleBitWidth)
	elseif typeof(dataShape) == "table" and dataShape.Type == "Quantized" then
		return readQuantized(buffer, dataShape.BitWidth, dataShape.Min, dataShape.Max)
	elseif typeof(dataShape) == "table" and dataShape.Type == "Enum" then
		return readEnum(buffer, dataShape)
	else
		error("Bad dataShape")
	end
end

-- eventShape should be checked once before calling this function many times
local function readEventShape(buffer: BitBuffer.BitBuffer, eventShape)
	local event = table.create(#eventShape)
	for _, dataShape in ipairs(eventShape) do
		table.insert(event, readDataShape(buffer, dataShape))
	end
	return event
end

local function calculateEventShapeBits(eventShape: {any})
	local bits = 0
	for _, dataShape in eventShape do
		if dataShape == "Float32" then
			bits += 32
		elseif dataShape == "Float64" then
			bits += 64
		elseif dataShape == "Bool" then
			bits += 1
		elseif dataShape == "Color3" then
			bits += 3 * 8
		elseif typeof(dataShape) == "table" and dataShape.Type == "Vector2" then
			bits += 2 * calculateEventShapeBits({dataShape.Precision})
		elseif typeof(dataShape) == "table" and dataShape.Type == "Vector3" then
			bits += 3 * calculateEventShapeBits({dataShape.Precision})
		elseif typeof(dataShape) == "table" and dataShape.Type == "UInt" then
			bits += dataShape.BitWidth
		elseif typeof(dataShape) == "table" and dataShape.Type == "Bytes" then
			bits += 8 * dataShape.NumBytes
		elseif typeof(dataShape) == "table" and dataShape.Type == "CFrame" then
			bits += 3 * dataShape.AngleBitWidth
			bits += 3 * calculateEventShapeBits({dataShape.PositionPrecision})
		elseif typeof(dataShape) == "table" and dataShape.Type == "Quantized" then
			-- selene:allow(if_same_then_else)
			bits += dataShape.BitWidth
		elseif typeof(dataShape) == "table" and dataShape.Type == "Enum" then
			-- selene:allow(if_same_then_else)
			bits += dataShape.BitWidth
		else
			error(`Bad data shape {dataShape}`)
		end
	end
	assert(bits > 0, "Bad event shape")
	return bits
end

local function estimateEncodingLength(numBits: number, encoding: "Base64" | "Base91")
	assert(checkEncoding(encoding))

	local bytes = math.ceil(numBits/32)
	if encoding == "Base64" then
		return 4 * math.ceil(32*bytes/24)
	else
		-- Not super accurate, could be improved with better understanding of Base91
		return 2 * math.ceil(32*bytes/13)
	end
end

type RbxStruct = {
	__FormatVersion: string,
	Type: "RbxStruct",
	DataShapeMap: {[string]: any?},
	InstancePackets: {[string]: any?},
	BufferKeys: {string},
	Buffer: string,
	Encoding: "Base64" | "Base91",
}

local checkRbxStructDataShapeMap = t.map(t.string, t.union(checkDataShape, t.literal("Instance")))

local checkRbxStruct = t.every(t.strictInterface {
	__FormatVersion = t.optional(t.string),
	_FormatVersion = t.optional(t.string),
	Type = t.literal("RbxStruct"),
	DataShapeMap = checkRbxStructDataShapeMap,
	InstancePackets = t.keys(t.string),
	BufferKeys = t.array(t.string),
	Buffer = t.string,
	Encoding = t.union(t.literal("Base64"), t.literal("Base91")),
}, function(rbxStruct: RbxStruct)
	for _, key in rbxStruct.BufferKeys do
		if rbxStruct.DataShapeMap[key] == nil then
			return false, `BufferKey {key} not in DataShapeMap`
		end
	end
	return true
end)

local function makeRbxStruct(data, dataShapeMap): RbxStruct
	assert(t.keys(t.string)(data))
	assert(checkRbxStructDataShapeMap(dataShapeMap))

	local buffer = BitBuffer.new()
	local bufferKeys: {string} = {}
	local instancePackets: {[string]: any?} = {}

	for key, value in data do
		local dataShape = dataShapeMap[key]
		if not dataShape then
			error(`Bad dataShapeMap for RbxStruct with value of type {typeof(value)}`)
		end

		if dataShape == "Instance" then
			assert(typeof(value) == "Instance", `Expected instance at key {key} of RbxStruct`)
			local packet = Rose.serialize(value)
			instancePackets[key] = packet
		else
			-- Will error if dataShape not recognised
			writeDataShape(buffer, dataShape, value)
			table.insert(bufferKeys, key)
		end
	end

	local rbxStruct = {
		__FormatVersion = FORMAT_VERSION,
		Type = "RbxStruct",
		DataShapeMap = dataShapeMap,
		InstancePackets = instancePackets,
		BufferKeys = bufferKeys,
		Buffer = buffer:ToBase64(),
		Encoding = "Base64",
	}
	
	assert(checkRbxStruct(rbxStruct))

	return rbxStruct
end

local function fromRbxStruct(data: RbxStruct)
	assert(checkRbxStruct(data))

	local decoded = {}
	local buffer = if data.Encoding == "Base91" then BitBuffer.FromBase91(data.Buffer) else BitBuffer.FromBase64(data.Buffer)

	for _, key in data.BufferKeys do
		local dataShape = data.DataShapeMap[key]
		local value = readDataShape(buffer, dataShape)
		decoded[key] = value
	end

	for key, instancePacket in data.InstancePackets do
		local instance = Rose.deserialize(instancePacket)
		decoded[key] = instance
	end

	return decoded
end

local checkEventShape = t.array(checkDataShape)

local checkTimelineConfig = t.strictInterface {
	Encoding = checkEncoding,
	EventShape = checkEventShape,
}

local checkTimelineData = t.strictInterface {
	Encoding = checkEncoding,
	EventShape = checkEventShape,
	TimelineBuffer = t.string,
	TimelineLength = checkNonNegativeInteger,
}

local function serialiseTimeline(timeline, config)
	assert(t.table(timeline))
	assert(checkTimelineConfig(config))

	local data = {
		Encoding = config.Encoding,
		EventShape = config.EventShape,
		TimelineLength = #timeline,
	}

	local sizeInBits = #timeline * calculateEventShapeBits(data.EventShape)
	local buffer = BitBuffer.new(sizeInBits)
	for _, event in ipairs(timeline) do
		assert(typeof(event) == "table" and #event == #data.EventShape, "Bad event")
		writeEventShape(buffer, data.EventShape, event)
	end

	if config.Encoding == "Base64" then
		data.TimelineBuffer = buffer:ToBase64()
	elseif config.Encoding == "Base91" then
		data.TimelineBuffer = buffer:ToBase91()
	end

	return data
end

local function deserialiseTimeline(data)
	assert(checkTimelineData(data))

	local timeline = table.create(data.TimelineLength)

	local buffer
	if data.Encoding == "Base64" then
		buffer = BitBuffer.FromBase64(data.TimelineBuffer)
	elseif data.Encoding == "Base91" then
		buffer = BitBuffer.FromBase91(data.TimelineBuffer)
	end

	for _=1, data.TimelineLength do
		table.insert(timeline, readEventShape(buffer, data.EventShape))
	end

	return timeline
end

local checkCharacterRecordData = t.strictInterface {
	__FormatVersion = t.optional(t.string), -- Must already verify this is correct code for this format
	_FormatVersion = t.optional(t.string),
	RecordType = t.literal("CharacterRecord"),
	PlayerUserId = t.integer,
	CharacterId = t.string,
	CharacterName = t.string,
	HumanoidDescription = t.any, -- This is up to the HumanoidDescriptionSerialiser
	HumanoidRigType = t.string,
	Timeline = checkTimelineData,
	VisibleTimeline = checkTimelineData,
}

local function serialiseCharacterRecord(record, force: true?)
	assert(t.strictInterface {
		RecordType = t.literal("CharacterRecord"),
		PlayerUserId = t.integer,
		CharacterId = t.string,
		CharacterName = t.string,
		HumanoidDescription = t.instanceOf("HumanoidDescription"),
		HumanoidRigType = t.enum(Enum.HumanoidRigType),
		Timeline = t.table,
		VisibleTimeline = t.table,
	})

	local data = {
		__FormatVersion = FORMAT_VERSION,

		RecordType = "CharacterRecord",
		PlayerUserId = record.PlayerUserId,
		CharacterId = record.CharacterId,
		CharacterName = record.CharacterName,
	}

	data.HumanoidDescription = HumanoidDescriptionSerialiser.Serialise(record.HumanoidDescription)
	data.HumanoidRigType = record.HumanoidRigType.Name

	local timestampShape = "Float32"
	local cframeShape = {
		Type = "CFrame",
		PositionPrecision = "Float32",
		AngleBitWidth = 10, -- 2^10 many angles per axis
	}

	data.Timeline = serialiseTimeline(record.Timeline, {
		Encoding = "Base64",
		EventShape = { timestampShape, cframeShape },
	})

	data.VisibleTimeline = serialiseTimeline(record.VisibleTimeline, {
		Encoding = "Base64",
		EventShape = { timestampShape, "Bool" },
	})

	if not force then
		assert(checkCharacterRecordData(data))
	end

	return data
end

--[[
	Byte Estimation for CharacterRecord
	WARNING: Keep this in sync with serialiseCharacterRecord
]]
do 
	local timestampShape = "Float32"
	local cframeShape = {
		Type = "CFrame",
		PositionPrecision = "Float32",
		AngleBitWidth = 10, -- 2^10 many angles per axis
	}

	local PER_TIMELINE_EVENT = estimateEncodingLength(calculateEventShapeBits({ timestampShape, cframeShape }), "Base64")
	local PER_VISIBLE_EVENT = estimateEncodingLength(calculateEventShapeBits({ timestampShape, "Bool" }), "Base64")
	-- Manually estimated by taking the json of a CharacterRecord and removing the encoded timelines
	local JSON_ESTIMATE = 2300

	function export.estimateCharacterRecordBytes(timeline: {any}, visibleTimeline: {any}): number
		return JSON_ESTIMATE + PER_TIMELINE_EVENT * #timeline
			+ PER_VISIBLE_EVENT * #visibleTimeline
	end
end

local nameToHumanoidRigType = {}
for _, enum in Enum.HumanoidRigType:GetEnumItems() do
	nameToHumanoidRigType[enum.Name] = enum
end

local function deserialiseCharacterRecord(data)
	assert(checkCharacterRecordData(data))

	local record = {
		RecordType = "CharacterRecord",
		PlayerUserId = data.PlayerUserId,
		CharacterId = data.CharacterId,
		CharacterName = data.CharacterName,
	}

	record.HumanoidDescription = HumanoidDescriptionSerialiser.Deserialise(data.HumanoidDescription)
	record.HumanoidRigType = nameToHumanoidRigType[data.HumanoidRigType]

	record.Timeline = deserialiseTimeline(data.Timeline)
	record.VisibleTimeline = deserialiseTimeline(data.VisibleTimeline)

	return record
end


local checkVRCharacterRecordData = t.strictInterface {
	__FormatVersion = t.optional(t.string), -- Must already verify this is correct code for this format
	_FormatVersion = t.optional(t.string),
	RecordType = t.literal("VRCharacterRecord"),
	PlayerUserId = t.integer,
	CharacterId = t.string,
	CharacterName = t.string,
	HumanoidDescription = t.any, -- This is up to the HumanoidDescriptionSerialiser
	HumanoidRigType = t.string,
	Timeline = checkTimelineData,
	VisibleTimeline = checkTimelineData,
	ChalkTimeline = checkTimelineData,
}

local function serialiseVRCharacterRecord(record, force: true?)
	assert(t.strictInterface {
		RecordType = t.literal("CharacterRecord"),
		PlayerUserId = t.integer,
		CharacterId = t.string,
		CharacterName = t.string,
		HumanoidDescription = t.instanceOf("HumanoidDescription"),
		HumanoidRigType = t.enum(Enum.HumanoidRigType),
		Timeline = t.table,
		VisibleTimeline = t.table,
		ChalkTimeline = t.table,
	})

	local data = {
		__FormatVersion = FORMAT_VERSION,

		RecordType = "VRCharacterRecord",
		PlayerUserId = record.PlayerUserId,
		CharacterId = record.CharacterId,
		CharacterName = record.CharacterName,
	}

	data.HumanoidDescription = HumanoidDescriptionSerialiser.Serialise(record.HumanoidDescription)
	data.HumanoidRigType = record.HumanoidRigType.Name

	local timestampShape = "Float32"
	local cframeShape = {
		Type = "CFrame",
		PositionPrecision = "Float32",
		AngleBitWidth = 10, -- 2^10 many angles per axis
	}

	data.Timeline = serialiseTimeline(record.Timeline, {
		Encoding = "Base64",
		-- Three cframes: head, lefthand, righthand
		EventShape = { timestampShape, cframeShape, cframeShape, cframeShape },
	})

	data.VisibleTimeline = serialiseTimeline(record.VisibleTimeline, {
		Encoding = "Base64",
		EventShape = { timestampShape, "Bool" },
	})

	data.ChalkTimeline = serialiseTimeline(record.ChalkTimeline, {
		Encoding = "Base64",
		EventShape = { timestampShape, "Bool" },
	})

	if not force then
		assert(checkVRCharacterRecordData(data))
	end

	return data
end

--[[
	Byte Estimation for VRCharacterRecord
	WARNING: Keep this in sync with serialiseVRCharacterRecord
]]
do 
	local timestampShape = "Float32"
	local cframeShape = {
		Type = "CFrame",
		PositionPrecision = "Float32",
		AngleBitWidth = 10, -- 2^10 many angles per axis
	}

	-- Byte length estimates
	local TIMELINE_EVENT= estimateEncodingLength(calculateEventShapeBits({ timestampShape, cframeShape, cframeShape, cframeShape }), "Base64")
	local VISIBLE_EVENT = estimateEncodingLength(calculateEventShapeBits({ timestampShape, "Bool" }), "Base64")
	local CHALK_EVENT = estimateEncodingLength(calculateEventShapeBits({ timestampShape, "Bool" }), "Base64")
	-- Manually estimated by taking the json of a CharacterRecord and removing the encoded timelines
	local JSON_ESTIMATE = 2300

	function export.estimateVRCharacterRecordBytes(timeline: {any}, visibleTimeline: {any}, chalkTimeline: {any}): number
		return JSON_ESTIMATE + TIMELINE_EVENT * #timeline
			+ VISIBLE_EVENT * #visibleTimeline
			+ CHALK_EVENT * #chalkTimeline
	end
end

local function deserialiseVRCharacterRecord(data)
	assert(checkVRCharacterRecordData(data))

	local record = {
		RecordType = "VRCharacterRecord",
		PlayerUserId = data.PlayerUserId,
		CharacterId = data.CharacterId,
		CharacterName = data.CharacterName,
	}

	record.HumanoidDescription = HumanoidDescriptionSerialiser.Deserialise(data.HumanoidDescription)
	record.HumanoidRigType = nameToHumanoidRigType[data.HumanoidRigType]

	record.Timeline = deserialiseTimeline(data.Timeline)
	record.VisibleTimeline = deserialiseTimeline(data.VisibleTimeline)
	record.ChalkTimeline = deserialiseTimeline(data.ChalkTimeline)

	return record
end

local checkBoardStateData = t.strictInterface {
	__FormatVersion = t.optional(t.string),
	_FormatVersion = t.optional(t.string),
	AspectRatio = t.numberPositive,
	NextFigureZIndex = checkNonNegativeInteger,
	ClearCount = t.optional(checkNonNegativeInteger),
	Figures = t.strictInterface {
		Encoding = checkEncoding,
		NumCurves = checkNonNegativeInteger,
		CurvesBuffer = t.string,
		CurveShape = t.strictArray(
			checkBytesShape,
			checkUIntShape,
			checkQuantizedShape,
			checkColorShape,
			checkStrictArrayShape(checkUIntShape),
			checkStrictArrayShape(checkQuantizedShape, checkQuantizedShape)
		)
	}
}

local function serialiseBoardState(boardState: metaboard.BoardState)
	local clearCount = boardState.ClearCount
	local nextFigureZIndex = boardState.NextFigureZIndex
	local aspectRatio = boardState.AspectRatio
	-- Commit all of the drawing task changes (like masks) to the figures
	local figures = metaboard.BoardState.commitAllDrawingTasks(boardState.DrawingTasks, boardState.Figures)

	-- Remove the figures that have been completely erased
	local removals = {}
	for figureId, figure in pairs(figures) do
		if metaboard.Figure.FullyMasked(figure) then
			removals[figureId] = Sift.None
		end
	end
	figures = Sift.Dictionary.merge(figures, removals)

	local buffer = BitBuffer.new()
	
	local figureIdShape     = { Type = "Bytes", NumBytes = 36, }
	local zIndexShape       = { Type = "UInt", BitWidth = 32, }
	local strokeWidthShape  = { Type = "Quantized", BitWidth = 16, Min = 0, Max = 1, }

	local bitMaskShape      = { Type = "UInt", BitWidth = 32}
	local bitmaskArrayShape = makeArrayShape({bitMaskShape})

	local xCanvasShape      = { Type = "Quantized", BitWidth = 12, Min = 0, Max = aspectRatio, }
	local yCanvasShape      = { Type = "Quantized", BitWidth = 12, Min = 0, Max = 1, }
	local pointsArrayShape  = makeArrayShape({xCanvasShape, yCanvasShape})

	local data = {
		__FormatVersion = FORMAT_VERSION,
		AspectRatio = aspectRatio,
		NextFigureZIndex = nextFigureZIndex,
		ClearCount = clearCount,
		Figures = {
			Encoding = "Base64",
			NumCurves = Sift.Dictionary.count(figures),
			CurvesBuffer = nil, -- will be set later
			CurveShape = {
				figureIdShape,
				zIndexShape,
				strokeWidthShape,
				"Color3",
				bitmaskArrayShape,
				pointsArrayShape,
			}
		}
	}

	for figureId, figure in pairs(figures) do

		if figure.Type ~= "Curve" then
			error(`Figure type {figure.Type} not handled`)
		end

		writeDataShape(buffer, figureIdShape, figureId)
		writeDataShape(buffer, zIndexShape, figure.ZIndex)
		writeDataShape(buffer, strokeWidthShape, figure.Width)
		writeDataShape(buffer, "Color3", figure.Color)
		
		local numPoints = #figure.Points

		--[[
			Write how many (size 32) bitmasks will be written as a 32-bit UInt (0 if none),
			then write all of the bitmasks
		]]
		do
			if figure.Mask and next(figure.Mask) and numPoints > 0 then
				-- Number of 2^5=32-bit masks needed
				local numBitMasks = bit32.rshift(numPoints-1, 5)+1
				buffer:WriteUInt(32, numBitMasks)
	
				local bitMaskIndex = 0
				while bitMaskIndex < numBitMasks do
					local bitMask = 0
					for i=1, 32 do
						local pointKey = tostring(32 * bitMaskIndex + i)
						if figure.Mask[pointKey] then
							bitMask = bit32.bor(bitMask, bit32.lshift(1, i-1))
						end
					end
					buffer:WriteUInt(32, bitMask)
					bitMaskIndex += 1
				end
			else
				local numBitMasks = 0
				buffer:WriteInt(32, numBitMasks)
			end
		end

		buffer:WriteUInt(32, numPoints)
		for _, point in figure.Points do
			writeDataShape(buffer, xCanvasShape, point.X)
			writeDataShape(buffer, yCanvasShape, point.Y)
		end
	end

	data.Figures.CurvesBuffer = buffer:ToBase64()

	return data
end

local function deserialiseBoardState(data): metaboard.BoardState
	assert(checkBoardStateData(data))

	local boardState: metaboard.BoardState = {
		AspectRatio = data.AspectRatio,
		DrawingTasks = {},
		Figures = {},
		NextFigureZIndex = data.NextFigureZIndex,
		PlayerHistories = {},
	}

	local figureIdShape     = data.Figures.CurveShape[1]
	local zIndexShape       = data.Figures.CurveShape[2]
	local strokeWidthShape  = data.Figures.CurveShape[3]
	local colorShape        = data.Figures.CurveShape[4]
	local bitmaskArrayShape = data.Figures.CurveShape[5]
	local pointsArrayShape  = data.Figures.CurveShape[6]

	local buffer
	if data.Figures.Encoding == "Base64" then
		buffer = BitBuffer.FromBase64(data.Figures.CurvesBuffer)
	elseif data.Figures.Encoding == "Base128" then
		buffer = BitBuffer.FromBase128(data.Figures.CurvesBuffer)
	end

	for _=1, data.Figures.NumCurves do

		local figureId = readDataShape(buffer, figureIdShape)
		local zIndex = readDataShape(buffer, zIndexShape)
		local width = readDataShape(buffer, strokeWidthShape)
		local color = readDataShape(buffer, colorShape)
		
		local mask = {}
		local numBitMasks = readDataShape(buffer, bitmaskArrayShape.LengthShape)
		for maskIndex=1, numBitMasks do
			local bitMask = readDataShape(buffer, bitmaskArrayShape.ItemShapes[1])
			for i=1, 32 do
				if bit32.btest(bitMask, bit32.lshift(1, i-1)) then
					local pointKey = tostring(32 * maskIndex + i)
					mask[pointKey] = true
				end
			end
		end

		local points = {}
		local numPoints = readDataShape(buffer, pointsArrayShape.LengthShape)
		local xCanvasShape = pointsArrayShape.ItemShapes[1]
		local yCanvasShape = pointsArrayShape.ItemShapes[2]
		for _=1, numPoints do
			local x = readDataShape(buffer, xCanvasShape)
			local y = readDataShape(buffer, yCanvasShape)
			table.insert(points, Vector2.new(x,y))
		end

		local curve: metaboard.Curve = {
			Type = "Curve",
			Color = color,
			Points = points,
			Width = width,
			ZIndex = zIndex,
		}

		boardState.Figures[figureId] = curve
	end

	return metaboard.BoardState.deserialise(boardState)
end

local checkBoardRecordData = t.strictInterface {
	__FormatVersion = t.optional(t.string), -- Must already verify this is correct code for this format
	_FormatVersion = t.optional(t.string),
	RecordType = t.literal("BoardRecord"),
	AspectRatio = t.every(t.numberPositive, checkRealNumber),
	BoardId = t.string,
	Timeline = t.strictInterface {
		Encoding = checkEncoding,
		EventPrefixShape = checkEventShape,
		RemoteToVariableShape = t.values(checkEventShape),
		TimelineLength = checkNonNegativeInteger,
		TimelineBuffer = t.string,
	},
	InitialBoardState = t.optional(checkBoardStateData),
	BoardInstanceRbx = checkRbxStruct,
}

local checkBoardInstanceContainer = function(value)
	do
		local ok, msg = t.Instance(value)
		if not ok then
			return false, msg
		end
	end
	if value:IsA("BasePart") then
		return true
	end
	if value:IsA("Model") then
		if not value.PrimaryPart
			or not value.PrimaryPart:IsA("BasePart")
			or not value.PrimaryPart:HasTag("metaboard")
		then
			return false, "Bad primary part (should be metaboard)"
		end
	end
	return true
end

local function serialiseBoardRecord(record, force: true?)
	assert(t.strictInterface {
		RecordType = t.literal("BoardRecord"),
		BoardId = t.string,
		AspectRatio = t.every(t.numberPositive, checkRealNumber),
		Timeline = t.table,
		InitialBoardState = t.optional(t.interface {
			AspectRatio = t.numberPositive,
			NextFigureZIndex = checkNonNegativeInteger,
			ClearCount = t.optional(checkNonNegativeInteger),
			Figures = t.table,
		}),
		BoardInstanceRbx = t.strictInterface {
			SurfaceCFrame = t.CFrame,
			SurfaceSize = t.Vector2,
			BoardInstanceContainer = checkBoardInstanceContainer,
		},
	}(record))

	local data = {
		__FormatVersion = FORMAT_VERSION,

		RecordType = "BoardRecord",
		AspectRatio = record.AspectRatio,
		BoardId = record.BoardId
	}

	if record.InitialBoardState then
		data.InitialBoardState = serialiseBoardState(record.InitialBoardState)
	end

	data.BoardInstanceRbx = makeRbxStruct(record.BoardInstanceRbx, {
		SurfaceCFrame = {
			Type = "CFrame",
			PositionPrecision = "Float32",
			AngleBitWidth = 32,
		},
		SurfaceSize = {
			Type = "Vector2",
			Precision = "Float32",
		},
		BoardInstanceContainer = "Instance",
	})

	local timestampShape = "Float32"
	local xCanvasShape     = { Type = "Quantized", BitWidth = 12, Min = 0, Max = record.AspectRatio, }
	local yCanvasShape     = { Type = "Quantized", BitWidth = 12, Min = 0, Max = 1, }
	local strokeWidthShape = { Type = "Quantized", BitWidth = 16, Min = 0, Max = 1, }

	local authorIdEnumShape = makeEnumShape({}, 1, true)

	local remoteNameEnumShape = makeEnumShape({
		"InitDrawingTask",
		"UpdateDrawingTask",
		"FinishDrawingTask",
		"Undo",
		"Redo",
		"Clear",
	}, 3, false)

	local taskTypeEnumShape = makeEnumShape({
		"FreeHand",
		"StraightLine",
		"Erase",
	}, 2, false)

	local eventPrefixShape = { timestampShape, remoteNameEnumShape, authorIdEnumShape, "Variable" }
	local remoteToVariableShape = {
		InitDrawingTask = { taskTypeEnumShape, strokeWidthShape, "Color3",  xCanvasShape, yCanvasShape},
		UpdateDrawingTask = { xCanvasShape, yCanvasShape },
		FinishDrawingTask = nil,
		Undo = nil,
		Redo = nil,
		Clear = nil,
	}

	local buffer = BitBuffer.new()
	
	for _, event in record.Timeline do
		local timestamp: number = event[1]
		local remoteName: string = event[2]
		local authorId: string = event[3]

		if remoteNameEnumShape.ItemToToken[remoteName] == nil then
			if force then
				warn(`Bad remote name {remoteName}`)
			else
				error(`Bad remote name {remoteName}`)
			end
		end

		--[[
			THESE SHOULD MATCH THE CORRESPONDING VARIABLE SHAPE
		]]
		
		writeDataShape(buffer, eventPrefixShape[1], timestamp)
		writeDataShape(buffer, eventPrefixShape[2], remoteName)
		writeDataShape(buffer, eventPrefixShape[3], authorId)

		local variableShape = remoteToVariableShape[remoteName]

		--[[
			THESE SHOULD MATCH THE CORRESPONDING VARIABLE SHAPE
		]]

		if remoteName == "UpdateDrawingTask" then
			local canvasPos = event[4]
			writeDataShape(buffer, variableShape[1], canvasPos.X)
			writeDataShape(buffer, variableShape[2], canvasPos.Y)
		elseif remoteName == "InitDrawingTask" then
			-- No need to store task id, just synthesise another one later.
			local drawingTask = event[4]
			local canvasPos = event[5]
			writeDataShape(buffer, variableShape[1], drawingTask.Type)
			if drawingTask.Type == "Erase" then
				-- Erase DrawingTask doesn't have a color, who cares ¯\_(ツ)_/¯
				-- we write a color to avoid another layer of variable bit width.
				writeDataShape(buffer, variableShape[2], drawingTask.ThicknessYScale)
				writeDataShape(buffer, variableShape[3], Color3.new())
			else
				writeDataShape(buffer, variableShape[2], drawingTask.Curve.Width)
				writeDataShape(buffer, variableShape[3], drawingTask.Curve.Color)
			end
			writeDataShape(buffer, variableShape[4], canvasPos.X)
			writeDataShape(buffer, variableShape[5], canvasPos.Y)
		end
		-- Other's have no additional data
	end

	data.Timeline = {
		Encoding = "Base64",
		EventPrefixShape = eventPrefixShape,
		RemoteToVariableShape = remoteToVariableShape,
		TimelineLength = #record.Timeline,
		TimelineBuffer = buffer:ToBase64(),
	}

	if not force then
		assert(checkBoardRecordData(data))
	end

	return data
end

do
	-- Average taken from an example timeline buffer, it's about 10.1
	local AVERAGE_TIMELINE_EVENT = 22280/2206
	-- An entire example json (including BoardInstanceRbx encoding)
	-- minus the timeline buffer and the InitialBoardState
	local JSON_ESTIMATE = 2900

	function export.estimateBoardRecordBytesMinusInitialState(timeline: {any})
		return JSON_ESTIMATE + AVERAGE_TIMELINE_EVENT * #timeline
	end

	function export.slowCalculateBoardStateBytes(boardState): number
		return #HttpService:JSONEncode(serialiseBoardState(boardState))
	end
end

local function deserialiseBoardRecord(data)
	assert(checkBoardRecordData(data))

	local record = {
		RecordType = "BoardRecord",
		BoardId = data.BoardId,
		AspectRatio = data.AspectRatio,
	}

	if data.InitialBoardState then
		record.InitialBoardState = deserialiseBoardState(data.InitialBoardState)
	end

	record.BoardInstanceRbx = fromRbxStruct(data.BoardInstanceRbx)

	local timelineData = data.Timeline

	local buffer
	if timelineData.Encoding == "Base64" then
		buffer = BitBuffer.FromBase64(timelineData.TimelineBuffer)
	elseif timelineData.Encoding == "Base128" then
		buffer = BitBuffer.FromBase128(timelineData.TimelineBuffer)
	end

	local timeline = table.create(timelineData.TimelineLength)
	
	for _=1, timelineData.TimelineLength do
	
		local timestamp = readDataShape(buffer, timelineData.EventPrefixShape[1])
		local remoteName = readDataShape(buffer, timelineData.EventPrefixShape[2])
		local authorId = readDataShape(buffer, timelineData.EventPrefixShape[3])

		local event = {timestamp, remoteName, authorId}

		local variableShape = timelineData.RemoteToVariableShape[remoteName]

		--[[
			THESE SHOULD MATCH THE CORRESPONDING VARIABLE SHAPE
		]]

		if remoteName == "UpdateDrawingTask" then
			local x = readDataShape(buffer, variableShape[1])
			local y = readDataShape(buffer, variableShape[2])
			table.insert(event, Vector2.new(x,y))
		elseif remoteName == "InitDrawingTask" then
			-- No need to store task id, just synthesise another one later.
			
			local taskType = readDataShape(buffer, variableShape[1])
			local width = readDataShape(buffer, variableShape[2])
			-- Erase DrawingTask doesn't have a color, who cares ¯\_(ツ)_/¯
			local color = readDataShape(buffer, variableShape[3])
			local x = readDataShape(buffer, variableShape[4])
			local y = readDataShape(buffer, variableShape[5])
			
			local drawingTask = {
				Type = taskType,
				Id = HttpService:GenerateGUID(false),
			}
			if drawingTask.Type == "FreeHand" or drawingTask.Type == "StraightLine" then
				drawingTask.Curve = {
					Type = "Curve",
					Width = width,
					Color = color,
				}
			elseif drawingTask.Type == "Erase" then
				drawingTask.ThicknessYScale = width
				drawingTask.FigureIdToMask = {}
			end

			local canvasPos = Vector2.new(x, y)
			table.insert(event, drawingTask)
			table.insert(event, canvasPos)
		end
		-- Other's have no additional data

		table.insert(timeline, event)
	end

	record.Timeline = timeline

	return record
end

local checkSegmentOfRecordsData = t.strictInterface {
	__FormatVersion = t.optional(t.string),
	-- The legacy of an oopsie
	_FormatVersion = t.optional(t.string),
	ReplayName = t.optional(t.string),
	Origin = t.strictArray(
		-- 12 cframe matrix components
		t.number, t.number, t.number,
		t.number, t.number, t.number,
		t.number, t.number, t.number,
		t.number, t.number, t.number
	),
	Records = t.array(t.interface {
		RecordType = t.union(
			t.literal("CharacterRecord"),
			t.literal("VRCharacterRecord"),
			t.literal("BoardRecord"),
			t.literal("SoundRecord"),
			t.literal("StateRecord")
		)
	}),
	EndTimestamp = t.number,
	Index = checkPositiveInteger,
}

function export.serialiseSegmentOfRecords(segmentOfRecords, segmentIndex: number)
	local data = {
		__FormatVersion = FORMAT_VERSION,

		ReplayName = segmentOfRecords.ReplayName,
		Origin = {segmentOfRecords.Origin:GetComponents()},
		Records = {},
		EndTimestamp = segmentOfRecords.EndTimestamp,
		Index = segmentIndex,
	}
	for _, record in segmentOfRecords.Records do
		if record.RecordType == "CharacterRecord" then
			table.insert(data.Records, serialiseCharacterRecord(record))
		elseif record.RecordType == "VRCharacterRecord" then
			table.insert(data.Records, serialiseVRCharacterRecord(record))
		elseif record.RecordType == "BoardRecord" then
			table.insert(data.Records, serialiseBoardRecord(record))
		elseif record.RecordType == "StateRecord" then
			-- Assumed JSONable
			table.insert(data.Records, record)
		else
			error(`RecordType not handled {record.RecordType}`)
		end
	end

	assert(checkSegmentOfRecordsData(data))

	return data
end

local checkSoundRecordData = t.strictInterface {
	RecordType = t.literal("SoundRecord"),
	CharacterId = t.string,
	CharacterName = t.string,
	Clips = t.array(t.strictInterface {
		AssetId = t.string,
		StartTimestamp = t.number,
		StartOffset = t.number,
		EndOffset = t.number,
	}),
}

function export.deserialiseSegmentOfRecords(data)
	assert(checkSegmentOfRecordsData(data))

	checkSemVerOrWarnOrError(data.__FormatVersion or data._FormatVersion)

	local segmentOfRecords = {
		ReplayName = data.ReplayName,
		Records = {},
		Origin = CFrame.new(table.unpack(data.Origin)),
		EndTimestamp = data.EndTimestamp,
		Index = data.Index,
	}
	for _, record in data.Records do
		if record.RecordType == "CharacterRecord" then
			table.insert(segmentOfRecords.Records, deserialiseCharacterRecord(record))
		elseif record.RecordType == "VRCharacterRecord" then
			table.insert(segmentOfRecords.Records, deserialiseVRCharacterRecord(record))
		elseif record.RecordType == "BoardRecord" then
			table.insert(segmentOfRecords.Records, deserialiseBoardRecord(record))
		elseif record.RecordType == "StateRecord" then
			table.insert(segmentOfRecords.Records, record)
		elseif record.RecordType == "SoundRecord" then
			-- Nothing to deserialise. Just tables, numbers, strings etc
			assert(checkSoundRecordData(record))
			table.insert(segmentOfRecords.Records, record)
		else
			error(`RecordType not handled {record.RecordType}`)
		end
	end

	return segmentOfRecords
end

return export