local HttpService = game:GetService("HttpService")
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

local writeFloat: {[FloatPrecision]: (buffer: BitBuffer.BitBuffer, number) -> ()} = {
	Float32 = BitBuffer.WriteFloat32,
	Float64 = BitBuffer.WriteFloat64,
}
local readFloat: {[FloatPrecision]: (buffer: BitBuffer.BitBuffer) -> (number)} = {
	Float32 = BitBuffer.ReadFloat32,
	Float64 = BitBuffer.ReadFloat64,
}

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
	local maxBitValue = bit32.lshift(1, bitWidth) - 1
	local range = max - min
	buffer:WriteUInt(bitWidth, math.clamp(math.round(maxBitValue * (value - min)/range), 0, maxBitValue))
end

local function readQuantized(buffer, bitWidth: number, min: number, max: number)
	local maxBitValue = bit32.lshift(1, bitWidth) - 1
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

local checkEnumShape = t.every(t.strictInterface {
	Type = t.literal("Enum"),
	BitWidth = checkBitWidth,
	EnumItems = t.array(function(item)
		if not table.find({"number", "string", "EnumItem"}, typeof(item)) then
			return false, `Bad enum item {item}`
		end
		return true
	end),
	ItemToToken = t.map(t.any, t.integer),
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

local function writeDataShape(buffer: BitBuffer.BitBuffer, dataShape: any, value: any)
	if dataShape == "Float32" then
		buffer:WriteFloat32(value)
	elseif dataShape == "Float64" then
		buffer:WriteFloat64(value)
	elseif dataShape == "Bool" then
		buffer:WriteBool(value)
	elseif dataShape == "Color3" then
		writeColor3(buffer, value)
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
		elseif typeof(dataShape) == "table" and dataShape.Type == "CFrame" then
			bits += 3 * dataShape.AngleBitWidth
			bits += 3 * calculateEventShapeBits({dataShape.PositionPrecision})
		elseif typeof(dataShape) == "table" and dataShape.Type == "Quantized" then
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

local checkEncodingBase = t.union(t.literal("64"), t.literal("91"))
local checkDataShape = function(dataShape)
	if typeof(dataShape) == "string" and table.find({"Float32", "Float64", "Bool", "Color3", "Variable"}, dataShape) then
		return true
	end
	if typeof(dataShape) == "table" then
		if dataShape.Type == "CFrame" then
			return checkCFrameShape(dataShape)
		elseif dataShape.Type == "Quantized" then
			return checkQuantizedShape(dataShape)
		elseif dataShape.Type == "Enum" then
			return checkEnumShape(dataShape)
		else
			return false, `Bad table data shape {dataShape}, .Type={dataShape.Type}`
		end
	end
	return false, `Unrecognised datashape {dataShape} with type {typeof(dataShape)}`
end
local checkEventShape = t.array(checkDataShape)

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
		_FormatVersion = FORMAT_VERSION,

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
		CharacterName = data.CharacterName,
	}

	record.HumanoidDescription = HumanoidDescriptionSerialiser.Deserialise(data.HumanoidDescription)
	record.HumanoidRigType = nameToHumanoidRigType[data.HumanoidRigType]

	record.Timeline = deserialiseTimeline(data.Timeline)
	record.VisibleTimeline = deserialiseTimeline(data.VisibleTimeline)

	return record
end

local checkBoardRecordData = t.strictInterface {
	_FormatVersion = t.string, -- Must already verify this is correct code for this format
	RecordType = t.literal("BoardRecord"),
	AspectRatio = t.numberPositive,
	BoardId = t.string,
	Timeline = t.strictInterface {
		EncodingBase = checkEncodingBase,
		EventPrefixShape = checkEventShape,
		RemoteToVariableShape = t.values(checkEventShape),
		TimelineLength = t.integer,
		TimelineBuffer = t.string,
	},
}

local function serialiseBoardRecord(record, force: true?)
	assert(t.strictInterface {
		RecordType = t.literal("BoardRecord"),
		BoardId = t.string,
		AspectRatio = t.every(t.numberPositive, checkRealNumber),
		Timeline = t.table,
	}(record))

	local data = {
		_FormatVersion = FORMAT_VERSION,

		RecordType = "BoardRecord",
		AspectRatio = record.AspectRatio,
		BoardId = record.BoardId
	}

	local timestampShape = "Float32"
	local xCanvasShape     = { Type = "Quantized", BitWidth = 12, Min = 0, Max = 1, }
	local yCanvasShape     = { Type = "Quantized", BitWidth = 12, Min = 0, Max = record.AspectRatio, }
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
			writeDataShape(buffer, variableShape[2], drawingTask.Curve.Width)
			-- Erase DrawingTask doesn't have a color, who cares ¯\_(ツ)_/¯
			-- we write a color to avoid another layer of variable bit width.
			local colorOrBlack = if drawingTask.Type ~= "Erase" then drawingTask.Curve.Color else Color3.new()
			writeDataShape(buffer, variableShape[3], colorOrBlack)
			writeDataShape(buffer, variableShape[4], canvasPos.X)
			writeDataShape(buffer, variableShape[5], canvasPos.Y)
		end
		-- Other's have no additional data
	end

	data.Timeline = {
		EncodingBase = "64",
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

local function deserialiseBoardRecord(data)
	assert(checkBoardRecordData(data))

	local record = {
		RecordType = "BoardRecord",
		BoardId = data.BoardId,
		AspectRatio = data.AspectRatio,
	}

	local timelineData = data.Timeline

	local buffer
	if timelineData.EncodingBase == "64" then
		buffer = BitBuffer.FromBase64(timelineData.TimelineBuffer)
	elseif timelineData.EncodingBase == "128" then
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
		elseif record.RecordType == "BoardRecord" then
			table.insert(data.Records, serialiseBoardRecord(record))
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
		elseif record.RecordType == "BoardRecord" then
			table.insert(segmentOfRecords.Records, deserialiseBoardRecord(record))
		else
			error(`RecordType not handled {record.RecordType}`)
		end
	end

	return segmentOfRecords
end

return export