local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StudioMenu = require(ReplicatedStorage.OS.Replay.ReplayMenu.StudioMenu)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)

local Remotes = script.Parent.Remotes

local export = {}

local RecordingId = ValueObject.new(nil :: string?)
local RecordingName = ValueObject.new(nil :: string?)

function export.initNewStudio(orbPart: Part, recordingName: string)
	RecordingName.Value = recordingName

	local maid = Maid.new()

	local menu: StudioMenu.StudioMenu
	menu = StudioMenu {
		OnRecord = function()
			local ok, result = Remotes.StartRecording:InvokeServer(orbPart, recordingName)

			if not ok then
				warn(result)
				maid:Destroy()
				return
			end

			local recordingId: string = result
			RecordingId.Value = recordingId
			menu.SetPhaseRecording()

			local start = os.clock()
			maid._timer = RunService.RenderStepped:Connect(function()
				menu.SetTimer(os.clock() - start)
			end)
		end,
		OnStop = function()
			maid._timer = nil

			local ok, msg = Remotes.StopRecording:InvokeServer(orbPart)

			if ok then
				maid:Destroy()
			else
				warn(msg)
			end
		end,
	}

	menu.SetPhaseReady()

	maid._menu = menu

	maid:GiveTask(Blend.mount(Players.LocalPlayer.PlayerGui, {

		Blend.New "ScreenGui" {
			IgnoreGuiInset = true,
			menu.render()
		}
	}))

end

return export