local Selection = game:GetService("Selection")
local BaseObject = require(script.Parent.Parent.BaseObject)
local Rx = require(script.Parent.Parent.Rx)
local Rxi = require(script.Parent.Parent.Rxi)
local Fusion = require(script.Parent.Parent.Parent.Packages.Fusion)

local PersistIdBoard = setmetatable({}, BaseObject)
PersistIdBoard.__index = PersistIdBoard

function PersistIdBoard.new(board: BasePart, guiContainer: Instance, manager)
	local self = setmetatable(BaseObject.new(board), PersistIdBoard)
	
	self._guiContainer = guiContainer
	self:_onAncestry()
	self._maid:Connect("ancestry", self._obj.AncestryChanged, function()
		self:_onAncestry()
	end)

	return self
end

function PersistIdBoard:_onAncestry()
	self._maid._gui = nil -- Destroy old gui
	if self._obj:IsDescendantOf(workspace) then
		self._maid._gui = self:_render()
	end
end

function PersistIdBoard:_basePart()
	return if self._obj:IsA("Model") then self._obj.PrimaryPart else self._obj
end

function PersistIdBoard:_observePersistId()
	return Rx.of(self:_basePart()):Pipe {
		Rxi.findFirstChild("PersistId"),
		Rxi.property("Value"),
	}
end

function PersistIdBoard:_setPersistId(persistId: number)
	local persistIdValue = self:_basePart():FindFirstChild("PersistId")
	if not persistIdValue then
		persistIdValue = Fusion.New "IntValue" {
			Name = "PersistId",
			Value = 0,
			Parent = self:_basePart(),
		}
	end

	persistIdValue.Value = persistId
end

function PersistIdBoard:_render()

	local PersistId = Fusion.Value(nil)
	local cleanup = {
		self:_observePersistId():Subscribe(function(persistId)
			PersistId:set(persistId)
		end),
	}

	local TextBox = Fusion.Value(nil)

	return Fusion.New "SurfaceGui" {
		Name = self._obj:GetFullName(),
		Parent = self._guiContainer,
		Adornee = self:_basePart(),
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 20,

		[Fusion.Children] = {

			Fusion.New "TextBox" {
				AnchorPoint = Vector2.new(0.5,0.5),
				Position = UDim2.fromScale(0.5,0.5),
				Size = UDim2.fromScale(0.5,0.5),
				BackgroundTransparency = 0.8,

				TextScaled = true,
				Text = Fusion.Computed(function()
					local persistId = PersistId:get()
					return persistId or ""
				end),
				TextColor3 = Color3.fromHex("F3F3F4"),
				TextStrokeTransparency = 0,

				[Fusion.Ref] = TextBox,

				[Fusion.OnEvent "FocusLost"] = function(enterPressed: boolean)
					if enterPressed then
						local text = TextBox:get().Text
						local persistId = tonumber(text)
						if persistId and math.floor(persistId) == persistId and persistId > 0 then
							self:_setPersistId(persistId)
							local persistIdValue = self:_basePart():FindFirstChild("PersistId")
							if persistIdValue then
								Selection:Set({persistIdValue})
							end
							return -- Success!
						end
					end
					-- This is reached only on the failure path
					TextBox:get().Text = PersistId:get(false)
				end

			}
		},

		[Fusion.Cleanup] = cleanup,
	}
end

return PersistIdBoard