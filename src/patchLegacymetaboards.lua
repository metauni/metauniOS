local CollectionService = game:GetService("CollectionService")

return function ()
	for _, instance in CollectionService:GetTagged("metaboard") do
		if instance:IsA("Model") then
			assert(instance.PrimaryPart, "[metauniOS] Model metaboard must have PrimaryPart"..tostring(instance:GetFullName()))
			CollectionService:RemoveTag(instance, "metaboard")
			local faceValue = instance:FindFirstChild("Face")
			if faceValue then
				faceValue.Parent = instance.PrimaryPart
			end
			local persistIdValue = instance:FindFirstChild("PersistId")
			if persistIdValue then
				persistIdValue.Parent = instance.PrimaryPart
			end
			CollectionService:AddTag(instance.PrimaryPart, "metaboard")
		end
	end

	CollectionService:GetInstanceAddedSignal("metaboard"):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			error("[metauniOS] Legacy model metaboard added after startup"..tostring(instance:GetFullName()))
		end
	end)
end