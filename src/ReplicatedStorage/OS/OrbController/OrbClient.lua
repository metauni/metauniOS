local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local New = Fusion.New
local Value = Fusion.Value
local OnEvent = Fusion.OnEvent

local Destructor = require(ReplicatedStorage.OS.Destructor)
local Rx = require(ReplicatedStorage.OS.Rx)
local Rxi = require(ReplicatedStorage.OS.Rxi)

local Remotes = script.Parent.Remotes

local OrbClient = {}
OrbClient.__index = OrbClient

function OrbClient.new(orbPart: Part, observeAttached: Observable<boolean>): OrbClient

	local destructor = Destructor.new()

	-- Wrap Fusion.New in a destructor
	local NewTracked = function(className: string)
		return function (props)
			return destructor:Add(New(className)(props))
		end
	end

	-- Transform an observable into a Fusion StateObject that
	-- holds the latest observed value
	local function observedValue(observable: Rx.Observable<T>): Value<T>
		local value = Value()
		destructor:Add(observable:Subscribe(function(newValue)
			value:set(newValue)
		end))
		return value 
	end

	NewTracked "ProximityPrompt" {

		Name = "AttachAsListenerPrompt",
		ActionText = "Attach as Listener",
		KeyboardKeyCode = Enum.KeyCode.E,
		GamepadKeyCode = Enum.KeyCode.ButtonX,
		Enabled = observedValue(observeAttached:Pipe{
			Rx.map(function(attached)
				return not attached
			end)
		}),
		[OnEvent "Triggered"] = function()
			Remotes.SetListener:FireServer(orbPart)
		end,
		
		MaxActivationDistance = 24,
		ObjectText = "Orb",
		RequiresLineOfSight = false,
		Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow,
		HoldDuration = 1,
		Parent = orbPart,
	}

	NewTracked "ProximityPrompt" {

		Name = "AttachAsSpeakerPrompt",
		
		ActionText = "Attach as Speaker",
		KeyboardKeyCode = Enum.KeyCode.F,
		GamepadKeyCode = Enum.KeyCode.ButtonY,
		UIOffset = Vector2.new(0,75),
		Enabled = observedValue(
			Rx.combineLatest({
				observeAttached,
				Rx.of(orbPart):Pipe {
					Rxi.findFirstChildWithClass("ObjectValue", "Speaker"),
					Rxi.property("Value"),
				},
				Rx.of(Players.LocalPlayer):Pipe({
					Rxi.attribute("metaadmin_isscribe")
				}),
			})
			:Pipe {
				Rx.unpacked,
				Rx.map(function(attached: boolean, speaker: Player?, isScribe: boolean?)
					return (not attached) and (isScribe or RunService:IsStudio()) and speaker == nil
				end)
			}
		),
		[OnEvent "Triggered"] = function()
			Remotes.SetSpeaker:FireServer(orbPart)
		end,

		MaxActivationDistance = 24,
		Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow,
		HoldDuration = 1,
		ObjectText = "Orb",
		RequiresLineOfSight = false,
		
		Parent = orbPart,
	}

	return {
		Destroy = function()
			destructor:Destroy()
		end
	}
end

return OrbClient