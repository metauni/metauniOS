local VRService = game:GetService("VRService")
local Remotes = script.Parent.Remotes

return {
	Start = function(_self)
		Remotes.ReportVREnabled:FireServer(VRService.VREnabled)
	end,
}