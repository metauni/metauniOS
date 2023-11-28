local Remotes = script.Parent.Remotes

local PlayerIdToVRStatus = {}

return {
	Start = function(_self)
		Remotes.ReportVREnabled.OnServerEvent:Connect(function(player: Player, vrEnabled: boolean)
			PlayerIdToVRStatus[player.UserId] = vrEnabled
		end)
	end,

	GetVREnabled = function(player: Player)
		return PlayerIdToVRStatus[player.UserId]
	end,
}