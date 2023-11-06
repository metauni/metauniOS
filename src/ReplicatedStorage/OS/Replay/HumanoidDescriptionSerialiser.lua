-- From from AvatarEditor.AvatarEditorSerialize by https://github.com/phoebethewitch

local AvatarEditorSerialize = {}

local propertiesToSerialize = {
	"BackAccessory",
	"BodyTypeScale",
	"ClimbAnimation",
	"DepthScale",
	"Face",
	"FaceAccessory",
	"FallAnimation",
	"FrontAccessory",
	"GraphicTShirt",
	"HairAccessory",
	"HatAccessory",
	"Head",
	"HeadColor",
	"HeadScale",
	"HeightScale",
	"IdleAnimation",
	"JumpAnimation",
	"LeftArm",
	"LeftArmColor",
	"LeftLeg",
	"LeftLegColor",
	"NeckAccessory",
	"Pants",
	"ProportionScale",
	"RightArm",
	"RightArmColor",
	"RightLeg",
	"RightLegColor",
	"RunAnimation",
	"Shirt",
	"ShouldersAccessory",
	"SwimAnimation",
	"Torso",
	"TorsoColor",
	"WaistAccessory",
	"WalkAnimation",
	"WidthScale",
}

local AcessoryTypeToEnum = {}

for _, enum in ipairs(Enum.AccessoryType:GetEnumItems()) do
	AcessoryTypeToEnum[enum.Name] = enum
end

function AvatarEditorSerialize.Serialize(description: HumanoidDescription)
	local serialized = {
		properties = {},
		emotes = {},
		equippedEmotes = {},
		layeredClothing = {},
	}
	
	-- properties
	for _, property in ipairs(propertiesToSerialize) do
		local value = description[property]
		if typeof(value) == "Color3" then
			serialized.properties[property] = {
				"Color3",
				value.R,
				value.G,
				value.B
			}
		else
			serialized.properties[property] = description[property]
		end
	end
	
	-- emotes
	serialized.emotes = description:GetEmotes()
	
	-- equipped emotes
	serialized.equippedEmotes = description:GetEquippedEmotes()
	
	-- layered clothing
	serialized.layeredClothing = description:GetAccessories(false)
	
	for i, accessory in ipairs(serialized.layeredClothing) do
		serialized.layeredClothing[i].AccessoryType = accessory.AccessoryType.Name
	end
	
	return serialized
end

function AvatarEditorSerialize.Deserialize(serialized: { properties: {}, emotes: {}, equippedEmotes: {}, layeredClothing: {} })	
	local description = Instance.new("HumanoidDescription")
	
	for _, property in ipairs(propertiesToSerialize) do
		local value = serialized.properties[property]
		if value then
			if typeof(value) == "table" then
				if value[1] == "Color3" then
					description[property] = Color3.new(value[2], value[3], value[4])
				end
			else
				description[property] = value
			end
		end
	end
	
	description:SetEmotes(serialized.emotes)
	
	description:SetEquippedEmotes(serialized.equippedEmotes)
	
	local layeredClothing = {}
	if serialized.layeredClothing then
		layeredClothing = table.clone(serialized.layeredClothing)
		
		for i, accessory in ipairs(layeredClothing) do
			accessory = table.clone(accessory)
			layeredClothing[i] = accessory
			accessory.AccessoryType = AcessoryTypeToEnum[accessory.AccessoryType]
		end
	end
	
	description:SetAccessories(layeredClothing, false)
	
	return description
end

return {
	
	Serialise = AvatarEditorSerialize.Serialize,
	Deserialise = AvatarEditorSerialize.Deserialize,
}
