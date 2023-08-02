# metauniOS
The metauni Operating System.

## Setup
```bash
aftman install
wally install
rojo serve

# Now sync with Rojo plugin in Roblox Studio
```

If wally.toml is updated, stop the rojo server, then `wally install` before
restarting the rojo server.

## Publishing
metauniOS is versioned via the current commit hash and branch - these are printed
to the console on game startup, unless the code has been rojo synced via Roblox
Studio, in which case it will just say "dev".
It's best to commit and push all changes before publishing to all the pockets.

We publish using the [lune luau runtime](https://lune-org.github.io/docs)
(previously used remodel, which is now deprecated).
```bash
# Publish to every place in lune/placeIds.lua
lune publish all

# Publish to specific places
lune publish TheRisingSea MoonlightForest
```

## Purpose

The primary purpose of metauniOS is to unite the separated system of packages (metaportal, orb, metaboard, metaadmin), so that deeper integration of these components is better and easier to maintain. Often, features we want to add to metauni require additions to multiple packages, and this multiplies the amount of git maintenance, package publishing and game publishing needed to work on a feature.

An intentional goal is for the structure to be as flexible and lightweight as possible, as to not make it impenetrable to new contributors.

## Structure

The overall structure that is synced by rojo looks like this

```
ServerScriptService:
	OS:
		<src/ServerScriptService/OS/*>
ReplicatedStorage:
	Packages:
		<packages from Wally>
		<CompiledPackages/*>
	OS:
		<src/ServerScriptService/OS/*>
StarterPlayer:
	StarterPlayerScripts:
		metauniOSClient
```

> Previously we had everything compiled under one folder in ServerScriptService, but this makes it impossible to use tools like Hoarcekat, or otherwise execute scripts outside of run-time (since the paths to the scripts change)

Due to the nature of partially-managed rojo, if we remove/rename/move a "top-level" child of a container in the repository, rojo will not delete the instance in Roblox Studio (unless the server is already running). The same goes for our publish system, since we cannot distinguish "removed from the repo" and "non-source controlled instance" - i.e. something that was made just in one place file. Hence we must be conservative with top-level instances. Indirect descendents can be deleted/renamed/moved freely.

## Lune

Lune is a luau runtime that makes it much easier to inspect instances across all pockets. See lune/inspector.lua for a helpful module.

## Services + Controllers

Previous integration between packages was DataModel only, however, some data, like the board data of a metaboard, cannot be stored in the DataModel for performance reasons. So it must be passed via ModuleScripts. To faciliate this, we convert would-be server Scripts to ModuleScripts, which supply optional `:Init()` and `:Start()` methods + whatever other data to interface with.

Any ModuleScript which is a descendant of ServerScriptService or ReplicatedStorage with a name ending with `Service` will be treated as a service. This gives flexibility in code structure. On startup, once everything is properly distributed, the `:Init()` method of every service is called. Then the same for the `:Start()` method.

The dual notion for Clients is a `Controller`. Any ModuleScript which is a descendant of ReplicatedStorage with a name ending with `Controller` will be required from a LocalScript, once `ReplicatedStorage:GetAttribute("metauniOSInstalled") == true`. Their Init and Start methods will be called just like they are for services.