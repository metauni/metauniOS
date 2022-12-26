local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local RavenErrorLogRemoteEvent = ReplicatedStorage:WaitForChild("RavenErrorLog")

-- Error logging
local function onError(message, trace, script)
    RavenErrorLogRemoteEvent:FireServer(message, trace)
end
ScriptContext.Error:Connect(onError)

-- Game analytics
local GameAnalytics = require(ReplicatedStorage.GameAnalytics)
GameAnalytics:initClient()