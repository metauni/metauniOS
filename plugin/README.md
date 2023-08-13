# Plugin

Tools for metauni development

## Features
- Place boards in a curve
	- Leave "Radius" blank for a flat curve (i.e. infinite radius)
- Activate plugin window to view and edit PersistIds
	- Click textbox on board to edit, enter to save
	- It will create a PersistId IntValue if one does not exist.

## Dev
To install, run 
```bash
cd plugin
wally install
rojo build default.project.json -o ~/Documents/Roblox/Plugins/metauni-tools.rbxm
```

If you enable "Reload plugins on file changed" under Studio Settings > Studio > Directories,
then Roblox Studio will reload the plugin every time you install it.