local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local RavenErrorLogRemoteEvent = ReplicatedStorage:WaitForChild("RavenErrorLog")

local function onError(message, trace, script)
    RavenErrorLogRemoteEvent:FireServer(message, trace)
end
ScriptContext.Error:Connect(onError)