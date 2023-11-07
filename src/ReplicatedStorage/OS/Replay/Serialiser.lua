local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BitBuffer = require(ReplicatedStorage.Packages.BitBuffer)
local t = require(ReplicatedStorage.Packages.t)

local FORMAT_VERSION = "v0.01-alpha"

export type BitWidth1to32 = number
export type FloatPrecision = "Float32" | "Float64"

local CFRAME_SHAPE = {
	Type = "CFrame",
	PositionPrecision = "Float32",
	AngleBitWidth = 10, -- 2^10 many angles per axis
}

local checkFloatPrecision = t.union(t.literal("Float32"), t.literal("Float64"))
local checkBitWidth = t.every(t.integer, t.numberConstrained(1, 32))
local checkCFrameShape = t.strictInterface {
	Type = t.literal("CFrame"),
	PositionPrecision = checkFloatPrecision,
	AngleBitWidth = checkBitWidth,
}
local checkColorShape = t.strictInterface {
	Type = t.literal("Color3"),
}

assert(checkCFrameShape(CFRAME_SHAPE), "Bad literal CFrame shape")

local RSTK_BITBUFFER_LIBRARY = {
	PackageName = "rstk/bitbuffer@1.0.0",
	Link = "https://github.com/rstk/BitBuffer/blob/31c6d19a9d76e8055fd10aa06f6c5ac3f76608c9/src/init.lua",
}

local writeFloat = {
	Float32 = BitBuffer.WriteFloat32,
	Float64 = BitBuffer.WriteFloat64,
}
local readFloat: {[FloatPrecision]: (buffer: any) -> (number)} = {
	Float32 = BitBuffer.WriteFloat32,
	Float64 = BitBuffer.WriteFloat64,
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
		elseif typeof(dataShape) == "table" and dataShape.Type == "CFrame" then
			bits += dataShape.AngleBitWidth
			bits += calculateEventShapeBits({dataShape.PositionPrecision})
		else
			error(`Bad data shape {dataShape}`)
		end
	end
	assert(bits > 0, "Bad event shape")
	return bits
end

local checkCharacterData = t.strictInterface {
	_FormatVersion = t.literal(FORMAT_VERSION),
	TimelineBuffer = t.string,
	TimelineLength = t.integer,
	BitBufferLibrary = t.keyOf({"PackageName", "Link"}),
	EventShape = t.strictArray(checkFloatPrecision, checkCFrameShape),
}

local export = {}

function export.serialiseCharacterRecord(record)
	assert(t.strictInterface {
		Timeline = t.table,
	}(record))
	if #record.Timeline >= 1 then
		assert(t.strictArray(t.number, t.CFrame)(record.Timeline[1]))
	end

	local data = {
		_FormatVersion = FORMAT_VERSION,
		BitBufferLibrary = RSTK_BITBUFFER_LIBRARY,
		EventShape = { "Float32", CFRAME_SHAPE },
		TimelineLength = #record.Timeline,
	}

	local sizeInBits = #record.Timeline * calculateEventShapeBits(data.EventShape)
	local buffer = BitBuffer.new(sizeInBits)
	for _, event in ipairs(record.Timeline) do
		assert(typeof(event) == "table" and #event == #data.EventShape, "Bad event")
		writeEventShape(buffer, data.EventShape, event)
	end

	data.TimelineBuffer = buffer:ToBase91()

	-- Post check
	assert(checkCharacterData(data))
end

function export.deserialiseCharacterRecord(data)
	assert(checkCharacterData(data))

	local record = {
		Timeline = {},
	}

	local buffer = BitBuffer.FromBase91(data.TimelineBuffer)
	for _=1, data.TimelineLength do
		table.insert(record.Timeline, readEventShape(buffer, data.EventShape))
	end

	return record
end

return export