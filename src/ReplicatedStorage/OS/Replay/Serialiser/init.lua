local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HumanoidDescriptionSerialiser = require(script.Parent.HumanoidDescriptionSerialiser)
local BitBuffer = require(ReplicatedStorage.Packages.BitBuffer)
local t = require(ReplicatedStorage.Packages.t)

--[[
	v0 serialisation library.

	Dependencies: 
		rstk/bitbuffer@1.0.0 (https://github.com/rstk/BitBuffer/blob/31c6d19a9d76e8055fd10aa06f6c5ac3f76608c9/src/init.lua)
]]

local FORMAT_VERSION = "v0.0.1-alpha"
-- vMAJOR.MINOR.PATCH-ADDITIONAL
local function getsemver(semverStr: string)
	local major, minor, patch = string.match(semverStr, "^v(%d+)%.(%d+)%.(%d+)")
	local additional = string.match(semverStr, "^v%d+%.%d+%.%d+%-(.*)")
	return {
		Major = major,
		Minor = minor,
		Patch = patch,
		Additional = additional,
	}
end

export type BitWidth1to32 = number
export type FloatPrecision = "Float32" | "Float64"

local checkPositiveInteger = t.every(t.integer, t.numberPositive)
local checkFloatPrecision = t.union(t.literal("Float32"), t.literal("Float64"))
local checkBoolShape = t.literal("Bool")
local checkBitWidth = t.every(t.integer, t.numberConstrained(1, 32))
local checkCFrameShape = t.strictInterface {
	Type = t.literal("CFrame"),
	PositionPrecision = checkFloatPrecision,
	AngleBitWidth = checkBitWidth,
}
local checkColorShape = t.strictInterface {
	Type = t.literal("Color3"),
}

local writeFloat = {
	Float32 = BitBuffer.WriteFloat32,
	Float64 = BitBuffer.WriteFloat64,
}
local readFloat: {[FloatPrecision]: (buffer: any) -> (number)} = {
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

local function writeCFrame(buffer, value: CFrame, positionPrecision: "Float32" | "Float64", angleBitWidth: BitWidth1to32)
	assert(typeof(value) == "CFrame", "Bad CFrame")
	writeVector3(buffer, value.Position, positionPrecision)
	local rx, ry, rz = value:ToEulerAnglesXYZ()
	local range = bit32.lshift(1, angleBitWidth) - 1
	-- Transform each from [-pi, pi] -> [0,1]
	-- Clamp to [0,1]
	-- Transform to [0,2^bits-1]
	-- Round to nearest integer
	buffer:WriteUInt(angleBitWidth, math.round(range * math.clamp((rx/math.pi + 1) / 2, 0, 1)))
	buffer:WriteUInt(angleBitWidth, math.round(range * math.clamp((ry/math.pi + 1) / 2, 0, 1)))
	buffer:WriteUInt(angleBitWidth, math.round(range * math.clamp((rz/math.pi + 1) / 2, 0, 1)))
end

local function readCFrame(buffer, positionPrecision: "Float32" | "Float64", angleBitWidth: BitWidth1to32)
	local range = bit32.lshift(1, angleBitWidth) - 1
	local position = readVector3(buffer, positionPrecision)
	local rx = (buffer:ReadUInt(angleBitWidth) / range * 2 - 1) * math.pi
	local ry = (buffer:ReadUInt(angleBitWidth) / range * 2 - 1) * math.pi
	local rz = (buffer:ReadUInt(angleBitWidth) / range * 2 - 1) * math.pi
	return CFrame.new(position) * CFrame.fromEulerAnglesXYZ(rx, ry, rz)
end

local function writeColor3(buffer, color: Color3)
	assert(typeof(color) == "Color3", "Bad color")
	local r = math.round(color.R * 255)
	local g = math.round(color.G * 255)
	local b = math.round(color.B * 255)
	buffer:WriteUInt(8, r)
	buffer:WriteUInt(8, g)
	buffer:WriteUInt(8, b)
end

local function readColor3(buffer): Color3
	return Color3.fromRGB(
		buffer:ReadUInt(8) / 255,
		buffer:ReadUInt(8) / 255,
		buffer:ReadUInt(8) / 255)
end

local function writeEventShape(buffer, eventShape, event)
	for i=1, #eventShape do
		local dataShape = eventShape[i]
		local value = event[i]
		if dataShape == "Float32" then
			buffer:WriteFloat32(value)
		elseif dataShape == "Float64" then
			buffer:WriteFloat64(value)
		elseif dataShape == "Bool" then
			buffer:WriteBool(value)
		elseif typeof(dataShape) == "table" and dataShape.Type == "CFrame" then
			writeCFrame(buffer, value, dataShape.PositionPrecision, dataShape.AngleBitWidth)
		else
			error("Bad dataShape")
		end
	end
end

local function readEventShape(buffer, eventShape): number | CFrame
	local event = table.create(#eventShape)
	for i=1, #eventShape do
		local dataShape = eventShape[i]
		if dataShape == "Float32" then
			table.insert(event, buffer:ReadFloat32())
		elseif dataShape == "Float64" then
			table.insert(event, buffer:ReadFloat64())
		elseif dataShape == "Bool" then
			table.insert(event, buffer:ReadBool())
		elseif typeof(dataShape) == "table" and dataShape.Type == "CFrame" then
			table.insert(event, readCFrame(buffer, dataShape.PositionPrecision, dataShape.AngleBitWidth))
		else
			error("Bad dataShape")
		end
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
		elseif typeof(dataShape) == "table" and dataShape.Type == "CFrame" then
			bits += 3 * dataShape.AngleBitWidth
			bits += 3 * calculateEventShapeBits({dataShape.PositionPrecision})
		else
			error(`Bad data shape {dataShape}`)
		end
	end
	assert(bits > 0, "Bad event shape")
	return bits
end

local checkEncodingBase = t.union(t.literal("64"), t.literal("91"))
local checkEventShape = t.array(t.union(
	checkFloatPrecision,
	checkBoolShape,
	checkCFrameShape,
	checkColorShape
))

local checkTimelineConfig = t.strictInterface {
	EncodingBase = checkEncodingBase,
	EventShape = checkEventShape,
}

local checkTimelineData = t.strictInterface {
	EncodingBase = checkEncodingBase,
	EventShape = checkEventShape,
	TimelineBuffer = t.string,
	EventShapeBits = checkPositiveInteger,
	TimelineLength = t.integer,
}

local function serialiseTimeline(timeline, config)
	assert(t.table(timeline))
	assert(checkTimelineConfig(config))

	local data = {
		EncodingBase = config.EncodingBase,
		EventShape = config.EventShape,
		EventShapeBits = calculateEventShapeBits(config.EventShape),
		TimelineLength = #timeline,
	}

	local sizeInBits = #timeline * data.EventShapeBits
	local buffer = BitBuffer.new(sizeInBits)
	for _, event in ipairs(timeline) do
		assert(typeof(event) == "table" and #event == #data.EventShape, "Bad event")
		writeEventShape(buffer, data.EventShape, event)
	end

	if config.EncodingBase == "64" then
		data.TimelineBuffer = buffer:ToBase64()
	elseif config.EncodingBase == "91" then
		data.TimelineBuffer = buffer:ToBase91()
	end

	return data
end

local function deserialiseTimeline(data)
	assert(checkTimelineData(data))

	local timeline = table.create(data.TimelineLength)

	local buffer
	if data.EncodingBase == "64" then
		buffer = BitBuffer.FromBase64(data.TimelineBuffer)
	elseif data.EncodingBase == "91" then
		buffer = BitBuffer.FromBase91(data.TimelineBuffer)
	end

	for _=1, data.TimelineLength do
		table.insert(timeline, readEventShape(buffer, data.EventShape))
	end

	return timeline
end

local checkCharacterRecordData = t.strictInterface {
	_FormatVersion = t.string, -- Must already verify this is correct code for this format
	RecordType = t.literal("CharacterRecord"),
	PlayerUserId = t.integer,
	CharacterId = t.string,
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
		HumanoidDescription = t.instanceOf("HumanoidDescription"),
		HumanoidRigType = t.enum(Enum.HumanoidRigType),
		Timeline = t.table,
		VisibleTimeline = t.table,
	})

	local data = {
		_FormatVersion = FORMAT_VERSION,

		RecordType = "CharacterRecord",
		PlayerUserId = record.PlayerUserId,
		CharacterId = record.CharacterId,
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
		EncodingBase = "64",
		EventShape = { timestampShape, cframeShape },
	})

	data.VisibleTimeline = serialiseTimeline(record.VisibleTimeline, {
		EncodingBase = "64",
		EventShape = { timestampShape, "Bool" },
	})

	if not force then
		assert(checkCharacterRecordData(data))
	end

	return data
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
	}

	record.HumanoidDescription = HumanoidDescriptionSerialiser.Deserialise(data.HumanoidDescription)
	record.HumanoidRigType = nameToHumanoidRigType[data.HumanoidRigType]

	record.Timeline = deserialiseTimeline(data.Timeline)
	record.VisibleTimeline = deserialiseTimeline(data.VisibleTimeline)

	return record
end

local export = {}

function export.serialiseSegmentOfRecords(segmentOfRecords, segmentIndex: number)
	local data = {
		_FormatVersion = FORMAT_VERSION,

		Records = {},
		Index = segmentIndex,
		-- InitialState = segmentOfRecords.InitialState,
	}
	for _, record in segmentOfRecords.Records do
		if record.RecordType == "CharacterRecord" then
			table.insert(data.Records, serialiseCharacterRecord(record))
		else
			error(`RecordType not handled {record.RecordType}`)
		end
	end

	return data
end

function export.deserialiseSegmentOfRecords(data)
	local segmentOfRecords = {
		Records = {},
		Index = data.Index,
		-- InitialState = {}
	}
	for _, record in data.Records do
		if record.RecordType == "CharacterRecord" then
			table.insert(segmentOfRecords.Records, deserialiseCharacterRecord(record))
		else
			error(`RecordType not handled {record.RecordType}`)
		end
	end

	return segmentOfRecords
end

return export