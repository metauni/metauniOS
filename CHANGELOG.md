# Changelog

## About
We don't have release versions (except the git hash of the latest commit),
so changes are loosely divided by date (dd/mm/yy), usually corresponding to
date pushed, rather than date-commited.

See #metauni-commits in the metauni discord to find commits by date

### 08/08/23
- Quieter orb attach/detach sounds

### 07/08/23
- Added [Macro class](./src/ReplicatedStorage/OS/Macro.lua)
- Added Shift + H toggle to hide (almost) everything for orbcam recording.
	- Note: Cmd/Ctrl + Shift + G hides the Roblox menu too.

### 05/08/23
- Changed Orbcam so client zooms camera instead of moving when looking at boards
	- Previously it moved forward/backward to account for the screen aspect ratio. The orb itself is (and was) positioned so that the hypothetical "server camera" would be correct according to an assumed aspect ratio (16:9), and the clients would do their own positioning calculation with their actual aspect ratio.
	- This was a problem because someone with a narrow aspect ratio might see the speaker blocking the view, while the speaker is out of frame on their own client.
- Added shift-to-run, with :SetWalkSpeed(), :SetSprintSpeed() methods for Humanoid wrapper.
- Added basic schedule to PocketMenu

### 03/08/23
- Removed sound that plays when ghost is made for player teleport
- Updated metaboard to find ReplicatedStorage.OS.Pocket
- Fixed BoardDecalService race condition
- Tighter margins around boards in orbcam
	- It's now pixel based, so doesn't vary with board size
- Changed default board mode to single board
- Changed Orbcam UI to be smaller

### 02/08/23
- Replaced remodel with lune
	- Remodel is deprecated
	- Lune is a well-featured luau runtime and supports more native read/write of Instance properties.
- Restructured directory and rojo project
	- Old method was to compile, to one instance under ServerScriptService then distribute on startup
	- This made hoarcekat impossible to use because almost every `require(path)` would be wrong outside runtime.
	- Now everything is in ReplicatedStorage.OS, ReplicatedStorage.Packages, or ServerScriptService.OS (except metauniOSServer and metauniOSClient)
- Added CompiledPackages folder, with manual inclusions into the Packages folder (see src/ReplicatedStorage/Packages.project.json)
- Added LegacyGuiService to replace StarterGui
- Added Binder and BaseObject classes (adapted from NevermoreEngine)
- Added Humanoid wrapper class for Humanoids
- Added softer running sounds
	- Sounds more like running through grass and is much quieter overall
	- Adjusts playback speed with WalkSpeed
- Added basic pocket menu to the Rising Sea on startup
- Fixed crash bug when no NPCs folder is found
- Added SeminarService
- Changed publish scripts
	- Nicer, sleeker console output
	- Allowed placeId inputs
	- Use CloudAPI for publishing which has better success rate (but fails if place is open in Studio - a good thing!)
	- Need to setup your own publishing key if you want to publish

