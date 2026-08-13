You can either edit files or add entirely new ones here.

HOW MODS ARE PLAYED:
The Mods menu is what launches the game. It lists "Friday Night Funkin'" (the base game) and
every mod you installed. Pick one, press ENTER, and the game restarts into that mod: its own
title screen, main menu, story mode and freeplay. Pressing back on the mod's main menu leaves
the mod and returns to the Mods menu.

That means your mod owns the whole game while it's the one being played, and it also means an
installed mod no longer dumps its songs into the base game's freeplay. Just drop your custom
images/logoBumpin.png, images/mainmenu/, data/introText.txt and so on into your mod folder and
they get used automatically.

ABOUT EDITTING:
It doesn't matter if you want to edit something in assets/shared/images/ or assets/preload/images/,
you will have to put the editted files in mods/images/, it will be handled automatically by the engine.

ABOUT pack.json:
Put a pack.json at the root of your mod folder to give it a name, description, icon framerate
and menu color. It can also declare a version, which engine version your mod needs, and which
other mods it depends on or clashes with:

	{
		"name": "My Cool Mod",
		"description": "Adds a week and a couple of characters.",
		"version": "1.2.0",
		"engineVersion": ">=0.7.3",
		"dependencies": ["someLibraryMod >= 1.0.0"],
		"incompatibilities": ["conflictingMod"]
	}

Mods listed in "dependencies" are named by their FOLDER name, and they have to be installed
and enabled. A mod is loaded before the mods it depends on, so it can override their assets.

If something is wrong (a broken pack.json, a missing or disabled dependency, a version that
doesn't match) the Mods menu marks the mod with a "!" and spells out the reason under its
description, so you don't have to guess.

All of this is optional, mods without a pack.json keep working exactly as before.
See docs/mods.md for the full list of fields.
