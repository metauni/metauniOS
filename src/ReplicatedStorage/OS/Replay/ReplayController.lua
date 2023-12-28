local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StageUI = require(ReplicatedStorage.OS.Replay.ReplayMenu.StageUI)
local StudioMenu = require(ReplicatedStorage.OS.Replay.ReplayMenu.StudioMenu)
local Blend = require(ReplicatedStorage.Util.Blend)
local Maid = require(ReplicatedStorage.Util.Maid)
local Rx = require(ReplicatedStorage.Util.Rx)
local Rxi = require(ReplicatedStorage.Util.Rxi)
local ValueObject = require(ReplicatedStorage.Util.ValueObject)

local Remotes = script.Parent.Remotes

local export = { maid = Maid.new()}

local RecordingId = ValueObject.new(nil :: string?)
local RecordingName = ValueObject.new(nil :: string?)

function export.Start()
	
end

function export.showStageUI(orb)

	export.maid._stage = Blend.mount(Players.LocalPlayer.PlayerGui, {
		Blend.New "ScreenGui" {
			Name = "ReplayStageUI",
			IgnoreGuiInset = true,
			Enabled = Rxi.attributeOf(orb, "ReplayActive"),

			StageUI {
				ReplayName = Rxi.attributeOf(orb, "ReplayName"),
				ReplayId = Rxi.attributeOf(orb, "ReplayId"),
				PlayState = Rxi.attributeOf(orb, "ReplayPlayState"),
				Timestamp = Rxi.attributeOf(orb, "ReplayTimestamp"),
				Duration = Rxi.attributeOf(orb, "ReplayDuration"),
				OnStop = function()
					Remotes.Stop:FireServer(orb)
				end,
				OnTogglePlaying = function()
					if orb:GetAttribute("ReplayPlayState") == "Paused" then
						Remotes.Play:FireServer(orb)
					else
						Remotes.Pause:FireServer(orb)
					end
				end,
				OnSkipAhead = function(seconds)
					Remotes.SkipAhead:FireServer(orb, seconds)
				end,
				OnSkipBack = function(seconds)
					Remotes.SkipBack:FireServer(orb, seconds)
				end,
			}
		},
	
	})
end

function export.destroyStageUI()
	export.maid._stage = nil
end

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