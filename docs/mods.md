# Mods System

Everything here is optional. A mod written for stock Psych Engine 0.7.3 keeps working
untouched — the fields below only do something once you actually add them.

## pack.json

Drop a `pack.json` at the root of your mod folder (`mods/yourMod/pack.json`).

```json
{
	"name": "My Cool Mod",
	"description": "Adds a week and a couple of characters.",
	"version": "1.2.0",
	"engineVersion": ">=0.7.3",
	"restart": false,
	"runsGlobally": false,
	"iconFramerate": 10,
	"color": [170, 0, 255],
	"dependencies": ["someLibraryMod >= 1.0.0"],
	"incompatibilities": ["conflictingMod"]
}
```

| Field | Type | What it does |
| --- | --- | --- |
| `name` | string | Shown on the Mods menu. Defaults to the folder name. |
| `description` | string | Shown on the Mods menu. |
| `version` | string | Your mod's own version. Other mods can require it. |
| `engineVersion` | string | Engine version your mod needs, ex. `">=0.7.3"`. `apiVersion` also works. |
| `restart` | bool | Toggling or moving the mod restarts the game. |
| `runsGlobally` | bool | Assets and scripts load even when another mod is selected. |
| `iconFramerate` | int | FPS of the animated `pack.png` icon. |
| `color` | int[3] | RGB background color on the Mods menu. |
| `dependencies` | list | Mods that must be installed and enabled. |
| `incompatibilities` | list | Mods that must **not** be enabled at the same time. |

### Dependencies and incompatibilities

`dependencies` and `incompatibilities` name mods by their **folder name**, not their
display name. Three shapes are accepted, pick whichever you like:

```json
"dependencies": ["someLibraryMod"]
"dependencies": ["someLibraryMod >= 1.0.0", "anotherMod < 2.0"]
"dependencies": [{ "folder": "someLibraryMod", "version": ">=1.0.0" }]
"dependencies": { "someLibraryMod": ">=1.0.0" }
```

Version requirements accept `>=`, `>`, `<=`, `<`, `=` / `==`, or `*` for "any version".
A bare version like `"1.4"` means exactly that version. Versions compare piece by piece,
so `1.10` is newer than `1.9`, and `1.2` and `1.2.0` are the same version. A suffix like
`1.0.0-beta` compares as `1.0.0`. A mod that never declared a `version` counts as `0.0.0`,
so it fails any `>=` requirement.

## Load order

The Mods menu order is the priority order: the mod at the top wins when two mods ship the
same file. On top of that, a mod is always placed **before** the mods it depends on, so a
mod can override assets from its own dependency. Mods that declare no dependencies keep
exactly the order you set on the menu.

The resolved order is what the engine actually uses for weeks, credits, achievements,
global mods and the currently selected mod.

## Problems shown on the Mods menu

Mods that won't work get a `!` in front of their name on the list, and the reason is
printed under the description. What gets reported:

- `pack.json` (or `data/settings.json`) exists but couldn't be parsed — the parser error is shown as-is
- a dependency isn't installed
- a dependency is installed but turned off
- a dependency is installed but its version doesn't match the requirement
- another enabled mod is declared as incompatible
- two mods depend on each other, so the load order can't be resolved
- the mod asks for a different engine version

Version and engine mismatches are warnings (yellow); the rest are treated as fatal (red),
meaning the mod most likely won't run correctly as things stand.

## Mods menu extras

- **TAB** opens a search box. Typing dims everything that doesn't match and jumps to the
  first match. Dragging to reorder keeps working while the search is open. **ENTER** or
  **ESC** closes it.
- **MODS FOLDER** opens the `mods/` folder in your file browser (desktop only). It also
  shows up on the "no mods installed" screen.
- **RELOAD** now re-reads every `pack.json` from disk, so you can edit a mod's metadata
  and see the change without closing the game.

## For source modders

`backend.Mods` is the entry point:

```haxe
Mods.getMetadata(folder);      // filled-in pack.json, never null
Mods.getPack(folder);          // raw pack.json, unchanged from before
Mods.getLoadOrder();           // enabled mods, dependencies resolved
Mods.getIssues(folder);        // problems found on one mod, or all of them if omitted
Mods.hasFatalIssues(folder);
Mods.satisfiesVersion(v, req); // "1.2.0" against ">=1.0.0"
Mods.compareVersions(a, b);    // 1, 0 or -1
Mods.saveModsList(list);       // writes modsList.txt and refreshes the caches
Mods.reload();                 // drop every cache, re-read from disk
```

`modsList.txt` and every `pack.json` are parsed once and cached in memory. Before this,
`parseList()` re-read the file and `getPack()` re-parsed the JSON on **every** call, and
`modsList.txt` was rewritten on every single state change — noticeable on Android, where
storage I/O is slow. The file is now only written when its contents actually changed.

Caches are dropped automatically when the mod list changes, and `Mods.reload()` drops
everything if you edited mod folders while the game was running.
