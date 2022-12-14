# metauniOS
The metauni Operating System.

## Setup
```bash
aftman install
wally install
rojo serve
```

## Publishing
metauniOS is versioned via the current commit hash and branch - these are printed
to the console on game startup, unless the code has been rojo synced via Roblox
Studio, in which case it will just say "dev".
It's best to commit and push all changes before publishing to all the pockets.

```bash
# Publish to every place in placeIds.lua
remodel run publish.lua all

# Publish to specific places
remodel run publish.lua TheRisingSea MoonlightForest
```

## Dev (metaboard)

To test local changes to metaboard within metauniOS, duplicate the `dev-template.project.json` file and rename
it to `dev-local.project.json` (then it will be automatically gitignored).
Edit that project file so it has the correct path to your local metaboard repository.
It must be an absolute path.

Then to switch from using the published metaboard version to using your local metaboard
repo, temporarily comment out the metaboard dependency in `wally.toml`. Then rojo sync the
`dev-local.project.json` file.
```bash
rojo serve dev-local.project.json
```

Once you are happy with your changes
1. Update the version in `metaboard/wally.toml`
2. Run `wally publish` in the metaboard repo (You must have permission to publish under the `metauni/` scope)
3. Update the metaboard dependency version in `metauniOS/wally.toml`
4. Commit and push changes.
5. Publish metauniOS.

## Purpose

The primary purpose of metauniOS is to unite the separated system of packages (metaportal, orb, metaboard, metaadmin), so that deeper integration of these components is better and easier to maintain. Often, features we want to add to metauni require additions to multiple packages, and this multiplies the amount of git maintenance, package publishing and game publishing needed to work on a feature.

An intentional goal is for the structure to be as flexible and lightweight as possible, as to not make it impenetrable to new contributors.

## Structure

metauniOS is the game code of The Rising Sea + Pockets. The project is structure to match the vanilla Roblox hierarchy as much as possible, where the top level folders are ServerScriptService, ReplicatedStorage, StarterPlayerScripts etc, as opposed to living within metauniOS subfolders inside these containers (as was the case with metaportal, metaboard etc).

However it is not feasible to rojo sync these containers directly into TRS or other Pockets, since many of these place files have differing contents in those containers, and there is no way to know what is part of metauniOS and what is not. Hence it's impossible to know what is old metauniOS contents that need deleting (maybe a file was renamed or moved), and what has been manually added to a particular place file.

We instead compile everything under the metauniOS Server Script in ServerScriptService, which distributes everything on startup. The startup script then indicates that installation has finished with `ReplicatedStorage:SetAttribute("metauniOSInstalled", true)`.

## Services + Controllers

Previous integration between packages was DataModel only, however, some data, like the board data of a metaboard, cannot be stored in the DataModel for performance reasons. So it must be passed via ModuleScripts. To faciliate this, we convert would-be server Scripts to ModuleScripts, which supply optional `:Init()` and `:Start()` methods + whatever other data to interface with.

> **ATTENTION**: The point is *not* to replace DataModel communication with ModuleScript communication. In fact, DataModel communication is often better, since all DataModel data comes with changed-signals for free.

Any ModuleScript which is a descendant of ServerScriptService or ReplicatedStorage with a name ending with `Service` will be treated as a service. This gives flexibility in code structure. On startup, once everything is properly distributed, the `:Init()` method of every service is called. Then the same for the `:Start()` method.

The dual notion for Clients is a `Controller`. Any ModuleScript which is a descendant of ReplicatedStorage with a name ending with `Controller` will be required from a LocalScript, once `ReplicatedStorage:GetAttribute("metauniOSInstalled") == true`. Their Init and Start methods will be called just like they are for services.