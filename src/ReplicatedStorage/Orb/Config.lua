local Config = {
	ObjectTag = "metaorb",
	TransportTag = "metaorb_transport",
	WaypointTag = "metaorb_waypoint",
	PointOfInterestTag = "metaorb_poi",
	SpecialMoveTag = "metaorb_specialmove",
	DataStoreTag = "orb.",
	TweenTime = 5,
	RopeLength = 10,
	TransportWaitTime = 10,
	ListenFromPlayer = true, -- listen from the player or camera?
	EarName = "OrbEar",
	WhiteHaloName = "WhiteHalo",
	BlackHaloName = "BlackHalo",
	HaloOffset = 3,
	HaloSize = 2,
	GhostSpawnInterval = 3,
	GhostSpawnRadius = 50,
	FOVFactor = 1.1,
	SpeakerMoveDelay = 0.1 -- time between tweening orbs on speaker movement
}

Config.Defaults = {
	
}

return Config