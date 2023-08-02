local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Promise = require(ReplicatedStorage.Packages.Promise)
local New = Fusion.New
local Hydrate = Fusion.Hydrate
local Value = Fusion.Value
local Children = Fusion.Children
local Computed = Fusion.Computed

local Destructor = require(ReplicatedStorage.OS.Destructor)
local Rx = require(ReplicatedStorage.OS.Rx)
local Rxi = require(ReplicatedStorage.OS.Rxi)
local Rxf = require(ReplicatedStorage.OS.Rxf)

local Remotes = ReplicatedStorage.OS.OrbController.Remotes
local Config = require(ReplicatedStorage.OS.OrbController.Config)

return function(player: Player)
	
	local destructor = Destructor.new()

	local earHaloTemplate = script.Parent:WaitForChild("EarHalo")
	local eyeHaloTemplate = script.Parent:WaitForChild("EyeHalo")

	local PlayerToOrb: Folder = ReplicatedStorage.OS.OrbController.PlayerToOrb

	local observeAttachedOrb =
		Rx.of(PlayerToOrb):Pipe {
			Rxi.findFirstChildWithClass("ObjectValue", tostring(player.UserId)),
			Rxi.property("Value"),
		}

	local observeSpeaker =
		observeAttachedOrb:Pipe {
			Rxi.findFirstChildWithClass("ObjectValue", "Speaker"),
			Rxi.property("Value"),
		}

	local observeWaypoint =
		observeAttachedOrb:Pipe {
			Rxi.findFirstChildWithClass("CFrameValue", "Waypoint"),
			Rxi.property("Value")
		}

	-- Detach from Orb on reset
	destructor:Add(
		Rx.of(player):Pipe {
			Rxi.property("Character"),
			Rxi.findFirstChild("Humanoid"),
			Rxi.notNil(),
			Rx.switchMap(function(humanoid: Humanoid)
				return Rx.fromSignal(humanoid.Died)
			end)
		}:Subscribe(function()
			local orbValue = PlayerToOrb:FindFirstChild(tostring(player.UserId))
			if not orbValue then
				return
			end

			if orbValue.Value then
				local speakerValue = orbValue.Value:FindFirstChild("Speaker")
				if speakerValue and speakerValue.Value == Players.LocalPlayer then
					speakerValue.Value = nil
				end
			end
			orbValue.Value = nil
		end)
	)

	destructor:Add(
		Rx.combineLatest{
			Halos = Rx.of(player):Pipe{
				Rxi.property("Character"),
				Rxi.findFirstChildWithClass("MeshPart", "Head"),
				Rx.map(function(head: MeshPart)
					if not head then
						return {}
					end

					local earHalo = earHaloTemplate:Clone()
					earHalo.Parent = head
					earHalo.CFrame = head.CFrame * CFrame.new(0,Config.HaloOffset,0) * CFrame.Angles(0,0,math.pi/2)
					earHalo.WeldConstraint.Part1 = head
					earHalo.Archivable = false

					local eyeHalo = eyeHaloTemplate:Clone()
					eyeHalo.Parent = head
					eyeHalo.CFrame = head.CFrame * CFrame.new(0,Config.HaloOffset,0) * CFrame.Angles(0,0,math.pi/2)
					eyeHalo.WeldConstraint.Part1 = head
					eyeHalo.Archivable = false

					return {earHalo, eyeHalo}
				end),
			},
			OrbcamActive = Rx.fromSignal(Remotes.OrbcamStatus.OnServerEvent):Pipe{
				Rx.where(function(triggeredPlayer: Player, _triggeredOrb: Part, _active: boolean)
					return triggeredPlayer == player
				end),
				Rx.map(function(_triggeredPlayer: Player, _triggeredOrb: Part, active: boolean)
					return active
				end),
				Rx.defaultsTo(false)
			},
			AttachedOrb = observeAttachedOrb,
			Speaker = observeSpeaker,
		}:Subscribe(function(data)
			local earHalo: UnionOperation? = data.Halos[1]
			local eyeHalo: UnionOperation? = data.Halos[2]
			local orbcamActive: boolean = data.OrbcamActive
			local attached: boolean = data.AttachedOrb
			local speaker: Player? = data.Speaker

			if not earHalo or not eyeHalo then
				return
			end

			local showEar = earHalo and attached and (speaker ~= player)
			local showEye = eyeHalo and showEar and orbcamActive

			if showEar then
				earHalo.Transparency = 0.8
			else
				earHalo.Transparency = 1
			end

			if showEye then
				eyeHalo.Transparency = 0
			else
				eyeHalo.Transparency = 1
			end
		end)
	)

	-- Emit the observed part's position (or nil) every second, but only when it has changed
	local function throttledMovement(interval: number)
		return function(source: Observable)
			return source:Pipe {
				Rx.switchMap(function(part: Part)
					return Rx.timer(0, interval):Pipe({
						Rx.map(function()
							return part and part.Position or nil
						end)
					})
				end),
				Rx.distinct(),
			}
		end
	end

	local Ghost = Value(nil)
	export type Mode = "hidden" | "fading" | "seeking" | "standing"
	local Mode: Value<Mode> = Value("hidden")

	local function buildGhost(character)
		character.Archivable = true
		local ghost = character:Clone()
		character.Archivable = false

		ghost.Name = character.Name.."-ghost"

		if ghost.Head then
			if ghost.Head:FindFirstChild("EarRing") then
				ghost.Head:FindFirstChild("EarRing"):Destroy()
			end
			if ghost.Head:FindFirstChild("EyeRing") then
				ghost.Head:FindFirstChild("EyeRing"):Destroy()
			end
		end

		for _, desc in ipairs(ghost:GetDescendants()) do
			if desc:IsA("BasePart") then
				local spookyTransparency = 1 - (0.2 * (1 - desc.Transparency))
				CollectionService:AddTag(desc, "spooky_part")

				Hydrate(desc) {
					Transparency = 1,

					[Fusion.Cleanup] = 
						Rxf.fromState(Mode):Subscribe(function(mode: Mode)
							if mode == "hidden" or mode == "fading" then
								desc:SetAttribute("spooky_transparency", 1)
							else
								desc:SetAttribute("spooky_transparency", spookyTransparency)
							end
						end),
				}
			end
		end

		local ghostAttachment = New "Attachment" {}
		local alignGhost = New "AlignOrientation" {
			Mode = Enum.OrientationAlignmentMode.OneAttachment,
			Attachment0 = ghostAttachment,
			Enabled = Computed(function()
				return Mode:get() == "standing"
			end),
		}

		Hydrate(ghost.Humanoid) {
			DisplayName = ghost.Humanoid.DisplayName.." (ghost)",
			DisplayDistanceType = Computed(function()
				if Mode:get() == "standing" then
					return Enum.HumanoidDisplayDistanceType.Viewer
				else 
					return Enum.HumanoidDisplayDistanceType.None
				end
			end)
		}

		Hydrate(ghost.PrimaryPart) {

			[Children] = {
				ghostAttachment,
				alignGhost,
			},

			-- When the ghost is standing, make it look at the speaker or the orb
			[Fusion.Cleanup] = Rx.combineLatest{
				GhostPos = Rx.of(ghost.PrimaryPart):Pipe {
					throttledMovement(0.5),
				},
				SpeakerPos = observeSpeaker:Pipe {
					Rxi.property("Character"),
					Rxi.property("PrimaryPart"),
					throttledMovement(0.5),
				},
				OrbPos = observeAttachedOrb:Pipe {
					throttledMovement(0.5),
				}
			}:Subscribe(function(data)
				local target = data.SpeakerPos or data.OrbPos
				if target and data.GhostPos then
					local dir = (target - data.GhostPos) * Vector3.new(1,0,1)
					alignGhost.CFrame = CFrame.lookAt(data.GhostPos, data.GhostPos + dir)
				end
			end)
		}

		return Hydrate(ghost) {
			Parent = Computed(function()
				-- This means that the ghost is still parented with mode == fading
				-- so that client has time to fade out ghost
				return if Mode:get() == "hidden" then nil else workspace
			end, Fusion.doNothing)
		}
	end

	destructor:Add(
		Rx.combineLatest{
			Character = Rx.of(player):Pipe{
				Rxi.property("Character")
			},
			AttachedOrb = observeAttachedOrb,
		}
		:Subscribe(function(data)
			local ghost = Ghost:get(false)
			if ghost then
				ghost:Destroy()
			end

			Mode:set("hidden")

			if data.Character and data.AttachedOrb then
				Ghost:set(buildGhost(data.Character))
			end
		end)
	)

	destructor:Add(
		Rx.combineLatest{
			Rxf.fromState(Mode),
			Rxf.fromState(Ghost):Pipe {
				Rxi.findFirstChildWithClass("Humanoid", "Humanoid"),
			},
			Rxf.fromState(Ghost):Pipe {
				Rxi.property("Parent")
			}
		}:Pipe {
			Rx.unpacked
		}:Subscribe(function(mode: Mode, ghostHumanoid: Humanoid?, ghostParent: any)
			if ghostHumanoid then
				if ghostParent == workspace and mode == "seeking" then
					local animation = script.Parent.WalkAnim
					local animationTrack = ghostHumanoid.Animator:LoadAnimation(animation)
					animationTrack:Play()
				elseif mode ~= "fading" then
					for _, track in ghostHumanoid:GetPlayingAnimationTracks() do
						track:Stop()
					end
				end
			end
		end)
	)

	local fadePromise
	destructor:Add(function()
		if fadePromise then
			fadePromise:cancel()
			fadePromise = nil
		end
	end)

	destructor:Add(
		Fusion.Observer(Mode):onChange(function()
			if fadePromise and Mode:get() ~= "fading" then
				fadePromise:cancel()
				fadePromise = nil
			end
		end)
	)

	-- Update the ghost cframe and mode depending on the relative positions of
	-- the orb, waypoint character and ghost
	-- If the character walks far enough away from the orb/waypoint
	-- then the ghost should appear and find a good spot to stand in the audience.
	destructor:Add(
		Rx.combineLatest{
			Waypoint = observeWaypoint,
			Character = Rx.of(player):Pipe{
				Rxi.property("Character")
			},
			Speaker = observeSpeaker,
			AttachedOrb = observeAttachedOrb,
			GhostHumanoid = Rxf.fromState(Ghost):Pipe {
				Rxi.findFirstChildWithClass("Humanoid", "Humanoid"),
			},
			
			-- Is the ghost seeking and making progress or is it probably stuck?
			Progress = Rx.combineLatest {
				Ghost = Rxf.fromState(Ghost),
				Mode = Rxf.fromState(Mode),
			}:Pipe {
				Rx.switchMap(function(data)
					local ghost: Model? = data.Ghost
					local mode: Mode = data.Mode
					
					if not ghost or mode ~= "seeking" then
						return Rx.of(true)
					end

					return Rx.of(ghost):Pipe {
						Rxi.property("PrimaryPart"),
						Rxi.notNil(),
						Rx.switchMap(function(part: Part)
							return Rx.timer(2, 0.5):Pipe {
								Rx.map(function(_)
									return part.Position
								end),
								Rx.scan(function(acc, position: Vector3?)
									if not position then
										return acc
									end
									table.insert(acc, position)
									if #acc > 2 then
										table.remove(acc, 1)
									end
									return acc
								end, {}),
								Rx.map(function(positions: {Vector3})
									if #positions < 2 then
										return true
									end
									return (positions[1] - positions[2]).Magnitude > 0.1
								end)
							}
						end)
					}
				end)
			},
			_movement = Rx.merge{
				Rx.of(player):Pipe{
					Rxi.property("Character"),
					Rxi.property("PrimaryPart"),
					throttledMovement(0.5),
				},
				observeSpeaker:Pipe{
					Rxi.property("Character"),
					Rxi.property("PrimaryPart"),
					throttledMovement(0.5),
				},
				Rxf.fromState(Ghost):Pipe {
					Rxi.findFirstChildWithClass("Humanoid", "Humanoid"),
					Rxi.notNil(),
					Rx.switchMap(function(humanoid: Humanoid)
						return Rx.fromSignal(humanoid.MoveToFinished)
					end),
				}
			},
		}:Subscribe(function(data)
			local waypoint: CFrame? = data.Waypoint
			local character: Model? = data.Character
			local attachedOrb: Part? = data.AttachedOrb
			local ghostHumanoid: Humanoid? = data.GhostHumanoid
			local speaker: Player? = data.Speaker
			local progress: boolean = data.Progress

			local mode: Mode = Mode:get(false)
			
			-- No ghost needed in these situations
			if
				not attachedOrb
				or
				speaker == player
				or
				not ghostHumanoid
				or
				not waypoint
				or
				(character and (character.PrimaryPart.Position - waypoint.Position).Magnitude <= Config.GhostSpawnRadius)
			then
				if mode ~= "fading" and mode ~= "hidden" then
					Mode:set("fading")
					fadePromise = 
						Promise.delay(2)
							:andThen(function()
								Mode:set("hidden")
							end)
				end
				return
			end

			local ghost: Model = ghostHumanoid.Parent

			if mode == "fading" then
				return
			end

			if mode == "seeking" then
				if not progress then
					Mode:set("standing")
					ghost:PivotTo(CFrame.new(ghostHumanoid.WalkToPoint) * ghost:GetPivot().Rotation)
				end
				return
			end

			-- Know now that mode is either "hidden" or "standing"

			if mode == "hidden" or (ghostHumanoid.WalkToPoint - waypoint.Position).Magnitude > Config.GhostSpawnRadius then
				-- Find somewhere to stand behind orb, try 10 times.
				local position do
					local success = false
					for _=1, 10 do

						local angle = math.pi * (3/4) * math.random() - math.pi/2
						local standBackDistance = Config.GhostMinOrbRadius + (Config.GhostMaxOrbRadius - Config.GhostMinOrbRadius) * math.random()
						position = (waypoint * CFrame.Angles(0,angle,0) * CFrame.new(0,0,standBackDistance)).Position + Vector3.new(0, ghostHumanoid.HipHeight + ghost.PrimaryPart.Size.Y/2, 0)
						
						local overlapParams = OverlapParams.new()
						overlapParams.FilterDescendantsInstances = {ghost}
						overlapParams.MaxParts = 1
						
						local parts = workspace:GetPartBoundsInRadius(position, 0.5, overlapParams)
						if #parts ~= 0 then
							continue
						end

						success = true
						-- Success. Now raycast down in-case orb is higher than ground at position

						local ghostRaycastParams = RaycastParams.new()
						ghostRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
						ghostRaycastParams.FilterDescendantsInstances = {ghost}
						local raycastResult = workspace:Raycast(position, -Vector3.yAxis * 50, ghostRaycastParams)
						if raycastResult then
							position = Vector3.new(position.X, raycastResult.Position.Y + ghostHumanoid.HipHeight + ghost.PrimaryPart.Size.Y/2, position.Z)
						end
					end
					if not success then
						return
					end
				end

				-- Now go to that spot

				if character then
	
					if mode == "hidden" then
						if character then
							local dir = position - character:GetPivot().Position
							local startOffset = character:GetExtentsSize().Z
							ghost:PivotTo(CFrame.lookAt(character:GetPivot().Position + startOffset * dir.Unit, position))
						else
							ghost:PivotTo(CFrame.lookAt(position, position + (waypoint - position) * Vector3.new(1,0,1)))
							Mode:set("standing")
							return
						end
					end
					Mode:set("seeking")
					-- Delay gives frames for humanoid to initialise after
					-- joining workspace
					task.delay(0.1, function()
						ghostHumanoid:MoveTo(position)
					end)
				end
			end
		end)
	)

	destructor:Add(
		Rx.fromSignal(Remotes.Teleport.OnServerEvent):Pipe {
			Rx.where(function(triggeredPlayer: Player)
				return triggeredPlayer == player
			end),
			Rx.mapTo("teleport pls!"),
			Rx.withLatestFrom {
				observeAttachedOrb,
				Rxf.fromState(Ghost),
				Rxf.fromState(Mode),
				observeSpeaker,
			},
			Rx.unpacked,
		}:Subscribe(function(_eventTrigger: any, attachedOrb: Part?, ghost: Model?, mode: Mode, speaker: Player?)
			if ghost then
				if mode == "standing" and ghost then
					local ghostCFrame = ghost:GetPivot()
					Mode:set("hidden")
					-- Replace ghost
					player.Character:PivotTo(ghostCFrame)
				else
					for _, otherPlayer in Players:GetPlayers() do
						local orbValue = PlayerToOrb:FindFirstChild(otherPlayer.UserId)
						if 
							otherPlayer ~= player
							and otherPlayer ~= speaker
							and otherPlayer.Character
							and orbValue
							and orbValue.Value == attachedOrb
						then
							-- Land on top of an audience member
							player.Character:PivotTo(otherPlayer.Character:GetPivot() + Vector3.new(0,10,0))
							return
						end
					end
					-- If all else fails, go 10 studs back and up from the orb
					player.Character:PivotTo(attachedOrb.CFrame * CFrame.new(0,10, 20))
				end
			end
		end)
	)

	return destructor
end