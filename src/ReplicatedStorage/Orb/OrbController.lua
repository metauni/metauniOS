local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Common = script.Parent

local Gui = require(script.Parent.Gui)
local Halos = require(script.Parent.Halos)
local Rx = require(ReplicatedStorage.Rx)
local Rxi = require(ReplicatedStorage.Rxi)
local IconController = require(ReplicatedStorage.Icon.IconController)
local Remotes = script.Parent.Remotes
local Sift = require(ReplicatedStorage.Packages.Sift)

return {
	
	Start = function()
		
		if Common:GetAttribute("OrbServerInitialised") == nil then
			Common:GetAttributeChangedSignal("OrbServerInitialised"):Wait()
		end
		
		local localPlayer = Players.LocalPlayer
		local localCharacter = localPlayer.Character or localPlayer.CharacterAdded:Wait()
		
		Gui.Init()
		Halos.Init()

		Players.LocalPlayer.CharacterAdded:Connect(function(character)
			-- When resetting
			Gui.OnResetCharacter()
		end)
		
		Players.LocalPlayer.CharacterRemoving:Connect(function()
			Gui.Detach()
			Gui.RemoveEar()
		end)

		local function observeCharacter()
			return Rx.of(Players.LocalPlayer):Pipe {
				Rxi.property("Character"),
				Rxi.notNil(),
			}
		end

		local function observeHumanoidMovement()
			return observeCharacter():Pipe {
				Rxi.findFirstChildOfClass("Humanoid"),
				Rxi.notNil(),
				Rx.switchMap(function(humanoid: Humanoid)
					return Rx.of(humanoid):Pipe {
						Rxi.property("MoveDirection"),
						Rx.mapTo(humanoid)
					}
				end)
			}
		end

		local speakerIcon = IconController.getIcon("Speaker")
		local cleanupFaceAudience = nil
		local tween

		local function tryCleanup()
			if cleanupFaceAudience then
				cleanupFaceAudience()
				cleanupFaceAudience = nil
			end
		end

		local function startFacing()

			local orb: Model | Part = Gui.Orb
			local initialOrbPos = (orb:IsA("Model") and orb.PrimaryPart or orb).Position
			local initialPoi = Gui.PointOfInterest(initialOrbPos)
			
			tryCleanup()
			local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad)

			-- Observe the humanoid, humanoidRootPart, orbPosition and latest poi
			local observer = Rx.combineLatest({
				observeHumanoidMovement(),
				observeCharacter():Pipe {Rxi.findFirstChildWithClass("Part", "HumanoidRootPart"), Rxi.notNil()},
				-- Observe the Orbs target location and poi pos, defaults to inital values
				Rx.fromSignal(Remotes.OrbTweeningStart.OnClientEvent):Pipe {
					Rx.where(function(otherOrb, pos, poi)
						return otherOrb == orb and pos ~= nil and poi ~= nil
					end);
					Rx.map(function(_, orbPos, poi)
						return {orbPos, poi}
					end);
					Rx.defaultsTo({initialOrbPos, initialPoi});
				},
			}):Pipe {
				Rx.map(function(data)
					-- humanoid, rootPart, orbPos, poi
					return data[1], data[2], data[3][1], data[3][2]
				end)
			}

			cleanupFaceAudience = observer:Subscribe(function(humanoid: Humanoid, root: Part, orbPos: Vector3, poi: Model | Part)

				-- We're either about to tween elsewhere or not tween at all
				if tween then
					tween:Cancel()
				end
				-- We're moving, don't rotate
				if humanoid.MoveDirection.Magnitude ~= 0 then
					return
				end

				local targets = {}
				for _, c in ipairs(poi:GetChildren()) do
						if c:IsA("ObjectValue") and c.Name == "Target" then
								if c.Value ~= nil then
										table.insert(targets, c.Value.Position)
								end
						end
				end

				local centroid = Sift.Array.reduce(targets, function(acc, target)
					return acc + target
				end) / #targets

				-- We're not on same side of the orb as the targets
				if (root.Position - orbPos).Unit:Dot((centroid - orbPos).Unit) < 0 then
					return
				end

				-- We're on the other side of the boards (with a buffer)
				if (root.Position - orbPos).Magnitude > (centroid - orbPos).Magnitude * 1.1 then
					return
				end
				
				local target = Vector3.new(orbPos.X, root.Position.Y, orbPos.Z)
				tween = TweenService:Create(root, tweenInfo, {
					CFrame = CFrame.lookAt(root.Position, target)
				})
				tween:Play()
			end)
		end

		speakerIcon.selected:Connect(startFacing)
		speakerIcon.deselected:Connect(tryCleanup)
	end
}

