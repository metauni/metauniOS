# Changelog

## About
We don't have release versions (except the git hash of the latest commit),
so changes are loosely divided by date (dd/mm/yy), either corresponding to date-pushed or date committed.

See #metauni-commits in the metauni discord to find commits by date

## 18/09/24
- Added utility libraries `Util/Stream.luau` `Util/U.luau`, `Util/Value.luau`, `Util/Map.luau`
	- Stream is a dead-simple version of Rx/Observables.
	- U is a top-level utility library for creating instances, with straightforward syntactic sugar
		for common ways of stitching state and streams with instance properties.
		- Similar to Fusion but we just attach cleanup to `Instance.Destroying` instead of using scopes
		- Can just "assign" a stream or piece of state to property to bind it to the latest value
- Added types to GoodSignal.

## 12/2/24
- Improved board clicking method
	- Board clicking is now raycast based (instead of invisible "BoardButton" with SurfaceGui+TextButton). The raycast filters only metaboards.
	- Can request a board selection with metaboard.Client:PromiseBoardSelection(). On the next click/tap, the promise resolves with the selected board (or nil) and the board will not be opened.
	- Board clicking is triggered by TouchTap and InputEnded for mouse clicks (can cancel click by dragging off board).
	- Board highlighting on hover always (only for non-touch screens).

## 25/08/23
- Centralised GraphMenu so only one exists
	- Before each box would spawn their own menu. Now the GraphBoxController is passed as a service to the GraphBoxClient constructor, so they can all request to be the opened one.
- Changed ZIndex of the GraphBox grid from -1 to 0
- Changed default UVMap to torus.

## 18/08/23 - 23/08/23
- Added/amalgamated utility libraries (see [README](./src/ReplicatedStorage/Util/README.md))
- Added Rxi.propertyOf, Rxi.attributeOf
- Added Binder:AttachRemoteEvent
- Added GraphBox. Includes:
	- Parser: Parses mathematical expressions
	- ArrayExpr: Fast expression evaluator
	- DifferentiableFnUtils: Differentiates expressions
	- UVMap: DataType for uv-mappings, with position and normal map.
	- GraphBoxClient, GraphBoxServer: Classes for "GraphBox" tag
	- GraphMenu: UI for entering UV map.

## 14/08/23
- Fixed board decals not saving (duplicate legacy code hadn't been deleted from some place files)

## 12/08/23
- Added persistId viewing/editing to plugin.
- Fixed error caused when speaker unattaches with audience mode on
- Added alias methods GiveTask and DoCleaning to Maid for compatibility with BaseObject, Binder
- Added tooling for exporting types with wally packages (wally-package-types)
- Fixed orb attachment not resetting when player leaves (only worked on Reset Character before)
	- Also immediately detaches when Humanoid enters dead state (i.e. when body parts detach), instead of .Died event, which is later. This means the orb doesn't move erradically when the speaker dies.
- Changed proximity prompt speed for attaching from 1sec to 0.6sec
- Fixed PocketMenu UI not scaling for mobile
	- workspace.CurrentCamera.ViewportSize is not always correct on startup

## 10/08/23
- Added plugin with curved board placement feature.

### 08/08/23
- Quieter orb attach/detach sounds

### 07/08/23
- Added [Macro class](./src/ReplicatedStorage/Util/Macro.lua)
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

