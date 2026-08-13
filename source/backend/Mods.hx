package backend;

import haxe.Json;

typedef ModsList = {
	enabled:Array<String>,
	disabled:Array<String>,
	all:Array<String>
};

/**
 * A single entry of a mod's `dependencies`/`incompatibilities` list.
 * `version` is a requirement such as ">=1.2.0", `null` means "any version".
 */
typedef ModDependency = {
	folder:String,
	version:String
};

/**
 * Everything the engine reads out of a mod's pack.json, parsed once and cached.
 * Every field has a sane default, so mods without a pack.json still work.
 */
typedef ModMetadata = {
	folder:String,
	name:String,
	description:String,
	version:String,
	restart:Bool,
	runsGlobally:Bool,
	standalone:Bool,
	iconFramerate:Int,
	color:Array<Dynamic>,
	dependencies:Array<ModDependency>,
	incompatibilities:Array<ModDependency>,
	engineVersion:String,
	pack:Dynamic
};

enum ModIssueKind {
	BROKEN_PACK; // pack.json is there but couldn't be parsed
	MISSING_DEPENDENCY; // a required mod isn't installed
	DISABLED_DEPENDENCY; // a required mod is installed but turned off
	OUTDATED_DEPENDENCY; // a required mod is installed but its version doesn't match
	INCOMPATIBLE; // another enabled mod is declared as incompatible
	ENGINE_MISMATCH; // pack.json asks for a different engine version
	CIRCULAR_DEPENDENCY; // dependency loop, load order can't be resolved
}

/**
 * A problem found on an installed mod. `fatal` means the mod most likely won't work at all.
 */
typedef ModIssue = {
	mod:String,
	kind:ModIssueKind,
	target:String,
	message:String,
	fatal:Bool
};

class Mods
{
	/**
	 * Stands for the base game on the Mods menu, which lists it as something you enter like any mod.
	 * A folder name can never contain a slash, so this can't collide with a real mod.
	 */
	public static inline var BASE_GAME:String = '//base';

	/**
	 * The mod you entered from the Mods menu, empty for the base game.
	 * Only this mod and the global ones contribute content, so nothing leaks into the base
	 * Freeplay/Story anymore. Survives FlxG.resetGame(), which is how entering a mod is applied.
	 */
	public static var activeMod:String = '';

	static public var currentModDirectory:String = '';
	public static var ignoreModFolders:Array<String> = [
		'characters',
		'custom_events',
		'custom_notetypes',
		'data',
		'songs',
		'music',
		'sounds',
		'shaders',
		'videos',
		'images',
		'stages',
		'weeks',
		'fonts',
		'scripts',
		'achievements'
	];

	private static var globalMods:Array<String> = [];

	// Caches. Everything in here is rebuilt from disk by reload().
	private static var _listCache:ModsList = null;
	private static var _dirCache:Array<String> = null;
	private static var _packCache:Map<String, Dynamic> = new Map<String, Dynamic>();
	private static var _packErrors:Map<String, String> = new Map<String, String>();
	private static var _metaCache:Map<String, ModMetadata> = new Map<String, ModMetadata>();
	private static var _loadOrder:Array<String> = null;
	private static var _activeMods:Array<String> = null;
	private static var _cyclicMods:Array<String> = [];
	private static var _issues:Array<ModIssue> = null;
	private static var _lastSavedList:String = null;

	inline public static function getGlobalMods()
		return globalMods;

	public static function pushGlobalMods()
	{
		globalMods = [];
		for (mod in getLoadOrder())
			if (getMetadata(mod).runsGlobally) globalMods.push(mod);
		return globalMods;
	}

	public static function getModDirectories():Array<String>
	{
		if (_dirCache != null) return _dirCache.copy();

		var list:Array<String> = [];
		#if MODS_ALLOWED
		var modsFolder:String = Paths.mods();
		if(FileSystem.exists(modsFolder)) {
			for (folder in Paths.readDirectory(modsFolder))
			{
				var path = haxe.io.Path.join([modsFolder, folder]);
				if (FileSystem.isDirectory(path) && !ignoreModFolders.contains(folder.toLowerCase()) && !list.contains(folder))
					list.push(folder);
			}
		}
		#end
		_dirCache = list;
		return list.copy();
	}

	inline public static function mergeAllTextsNamed(path:String, defaultDirectory:String = null, allowDuplicates:Bool = false)
	{
		if(defaultDirectory == null) defaultDirectory = Paths.getSharedPath();
		defaultDirectory = defaultDirectory.trim();
		if(!defaultDirectory.endsWith('/')) defaultDirectory += '/';
		if(!defaultDirectory.startsWith('assets/')) defaultDirectory = 'assets/$defaultDirectory';

		var mergedList:Array<String> = [];
		var paths:Array<String> = directoriesWithFile(defaultDirectory, path);

		var defaultPath:String = defaultDirectory + path;
		if(paths.contains(defaultPath))
		{
			paths.remove(defaultPath);
			paths.insert(0, defaultPath);
		}

		for (file in paths)
		{
			var list:Array<String> = CoolUtil.coolTextFile(file);
			for (value in list)
				if((allowDuplicates || !mergedList.contains(value)) && value.length > 0)
					mergedList.push(value);
		}
		return mergedList;
	}

	inline public static function directoriesWithFile(path:String, fileToFind:String, mods:Bool = true)
	{
		var foldersToCheck:Array<String> = [];
		#if sys
		if(FileSystem.exists(path + fileToFind))
		#end
			foldersToCheck.push(path + fileToFind);

		#if MODS_ALLOWED
		if(mods)
		{
			// Global mods first
			for(mod in Mods.getGlobalMods())
			{
				var folder:String = Paths.mods(mod + '/' + fileToFind);
				if(FileSystem.exists(folder) && !foldersToCheck.contains(folder)) foldersToCheck.push(folder);
			}

			// Then "PsychEngine/mods/" main folder
			var folder:String = Paths.mods(fileToFind);
			if(FileSystem.exists(folder) && !foldersToCheck.contains(folder)) foldersToCheck.push(Paths.mods(fileToFind));

			// And lastly, the loaded mod's folder
			if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			{
				var folder:String = Paths.mods(Mods.currentModDirectory + '/' + fileToFind);
				if(FileSystem.exists(folder) && !foldersToCheck.contains(folder)) foldersToCheck.push(folder);
			}
		}
		#end
		return foldersToCheck;
	}

	/**
	 * Raw pack.json contents, kept for backwards compatibility with older code and scripts.
	 * Prefer getMetadata(), which fills in defaults and parses the newer fields.
	 */
	public static function getPack(?folder:String = null):Dynamic
	{
		#if MODS_ALLOWED
		if(folder == null) folder = Mods.currentModDirectory;
		if(folder == null) folder = '';

		if(_packCache.exists(folder)) return _packCache.get(folder);

		var parsed:Dynamic = null;
		var path = Paths.mods(folder + '/pack.json');
		if(FileSystem.exists(path)) {
			try {
				#if sys
				var rawJson:String = File.getContent(path);
				#else
				var rawJson:String = Assets.getText(path);
				#end
				if(rawJson != null && rawJson.length > 0) parsed = tjson.TJSON.parse(rawJson);
			} catch(e:Dynamic) {
				// Remembered instead of just traced, so the Mods menu can show it to whoever made the mod
				_packErrors.set(folder, Std.string(e));
				trace('Mods: couldn\'t parse "$path": $e');
			}
		}
		_packCache.set(folder, parsed);
		return parsed;
		#else
		return null;
		#end
	}

	/**
	 * pack.json turned into a filled-in structure. Never returns null.
	 */
	public static function getMetadata(?folder:String = null):ModMetadata
	{
		if(folder == null) folder = Mods.currentModDirectory;
		if(folder == null) folder = '';

		var cached:ModMetadata = _metaCache.get(folder);
		if(cached != null) return cached;

		var pack:Dynamic = getPack(folder);
		var meta:ModMetadata = {
			folder: folder,
			name: folder,
			description: 'No description provided.',
			version: null,
			restart: false,
			runsGlobally: false,
			standalone: false,
			iconFramerate: 10,
			color: null,
			dependencies: [],
			incompatibilities: [],
			engineVersion: null,
			pack: pack
		};

		if(pack != null)
		{
			var value:Dynamic = Reflect.field(pack, 'name');
			if(value != null) meta.name = Std.string(value);

			value = Reflect.field(pack, 'description');
			if(value != null) meta.description = Std.string(value);

			value = Reflect.field(pack, 'version');
			if(value != null) meta.version = Std.string(value).trim();

			meta.restart = (Reflect.field(pack, 'restart') == true);
			meta.runsGlobally = (Reflect.field(pack, 'runsGlobally') == true);
			meta.standalone = (Reflect.field(pack, 'standalone') == true);

			value = Reflect.field(pack, 'iconFramerate');
			if(value != null)
			{
				var fps:Null<Int> = Std.parseInt(Std.string(value));
				if(fps != null && fps > 0) meta.iconFramerate = fps;
			}

			value = Reflect.field(pack, 'color');
			if(value != null && Std.isOfType(value, Array)) meta.color = cast value;

			// "apiVersion" is accepted as an alias so both naming habits work
			value = Reflect.field(pack, 'engineVersion');
			if(value == null) value = Reflect.field(pack, 'apiVersion');
			if(value != null) meta.engineVersion = Std.string(value).trim();

			meta.dependencies = parseDependencies(Reflect.field(pack, 'dependencies'));
			meta.incompatibilities = parseDependencies(Reflect.field(pack, 'incompatibilities'));
		}

		_metaCache.set(folder, meta);
		return meta;
	}

	// Splits "someMod >= 1.2.0" into the folder name and the version requirement
	private static var _depRegex:EReg = ~/^([^\s><=!]+)\s*(.*)$/;

	private static function parseDependencies(value:Dynamic):Array<ModDependency>
	{
		var out:Array<ModDependency> = [];
		if(value == null) return out;

		if(Std.isOfType(value, String)) value = [value];

		if(Std.isOfType(value, Array))
		{
			// ["someMod", "otherMod >= 1.2.0"] or [{"folder": "someMod", "version": ">=1.2.0"}]
			var entries:Array<Dynamic> = cast value;
			for (entry in entries)
			{
				if(entry == null) continue;

				if(Std.isOfType(entry, String))
				{
					var dep:ModDependency = parseDependencyString(cast entry);
					if(dep != null) out.push(dep);
					continue;
				}

				var name:Dynamic = Reflect.field(entry, 'folder');
				if(name == null) name = Reflect.field(entry, 'name');
				if(name == null) continue;

				var requirement:Dynamic = Reflect.field(entry, 'version');
				out.push({
					folder: Std.string(name).trim(),
					version: requirement != null ? Std.string(requirement).trim() : null
				});
			}
			return out;
		}

		// {"someMod": ">=1.2.0"}
		for (field in Reflect.fields(value))
		{
			var requirement:Dynamic = Reflect.field(value, field);
			out.push({
				folder: field.trim(),
				version: requirement != null ? Std.string(requirement).trim() : null
			});
		}
		return out;
	}

	private static function parseDependencyString(entry:String):ModDependency
	{
		var trimmed:String = entry.trim();
		if(trimmed.length < 1) return null;

		if(_depRegex.match(trimmed))
		{
			var requirement:String = _depRegex.matched(2).trim();
			return {folder: _depRegex.matched(1), version: requirement.length > 0 ? requirement : null};
		}
		return {folder: trimmed, version: null};
	}

	/**
	 * Compares two dotted version strings. Returns 1 if a > b, -1 if a < b, 0 if they match.
	 * Missing pieces count as 0, so "1.2" and "1.2.0" are the same version.
	 */
	public static function compareVersions(a:String, b:String):Int
	{
		var left:Array<Int> = splitVersion(a);
		var right:Array<Int> = splitVersion(b);
		var length:Int = Std.int(Math.max(left.length, right.length));

		for (i in 0...length)
		{
			var numA:Int = i < left.length ? left[i] : 0;
			var numB:Int = i < right.length ? right[i] : 0;
			if(numA != numB) return numA > numB ? 1 : -1;
		}
		return 0;
	}

	private static function splitVersion(version:String):Array<Int>
	{
		var out:Array<Int> = [];
		if(version == null) return out;

		for (piece in version.trim().split('.'))
		{
			// Stops at the first non digit so tags like "1.0.0-beta" still compare as 1.0.0
			var digits:String = '';
			for (i in 0...piece.length)
			{
				var digit:String = piece.charAt(i);
				if(digit >= '0' && digit <= '9') digits += digit;
				else break;
			}

			var parsed:Int = 0;
			if(digits.length > 0) parsed = Std.parseInt(digits);
			out.push(parsed);
		}
		return out;
	}

	/**
	 * Checks a version against a requirement like ">=1.2.0", "<2.0", "1.4" or "*".
	 * A mod that never declared a version counts as 0.0.0.
	 */
	public static function satisfiesVersion(version:String, requirement:String):Bool
	{
		if(requirement == null) return true;

		var wanted:String = requirement.trim();
		if(wanted.length < 1 || wanted == '*') return true;

		var operator:String = '==';
		for (candidate in ['>=', '<=', '==', '>', '<', '='])
		{
			if(wanted.startsWith(candidate))
			{
				operator = candidate;
				wanted = wanted.substr(candidate.length).trim();
				break;
			}
		}
		if(wanted.length < 1) return true;

		var result:Int = compareVersions(version != null ? version : '0', wanted);
		return switch(operator)
		{
			case '>=': result >= 0;
			case '<=': result <= 0;
			case '>': result > 0;
			case '<': result < 0;
			default: result == 0;
		};
	}

	public static var updatedOnState(default, set):Bool = false;
	private static function set_updatedOnState(value:Bool):Bool
	{
		// Going back to false means a state changed, folders may have been added or removed since
		if(!value)
		{
			_listCache = null;
			_dirCache = null;
		}
		return updatedOnState = value;
	}

	public static function parseList():ModsList {
		if(!updatedOnState) updateModList();
		if(_listCache == null) _listCache = readModsList();

		// Callers (the Mods menu especially) edit what they get back, so hand out copies
		return {
			enabled: _listCache.enabled.copy(),
			disabled: _listCache.disabled.copy(),
			all: _listCache.all.copy()
		};
	}

	private static function readModsList():ModsList
	{
		var list:ModsList = {enabled: [], disabled: [], all: []};
		#if MODS_ALLOWED
		try {
			for (mod in CoolUtil.coolTextFile('modsList.txt'))
			{
				if(mod.trim().length < 1) continue;

				var dat = mod.split("|");
				list.all.push(dat[0]);
				if (dat[1] == "1")
					list.enabled.push(dat[0]);
				else
					list.disabled.push(dat[0]);
			}
		} catch(e) {
			trace(e);
		}
		#end
		return list;
	}

	private static function updateModList()
	{
		#if MODS_ALLOWED
		_dirCache = null; // folders may have been added or removed, scan again

		// Find all that are already ordered
		var list:Array<Array<Dynamic>> = [];
		var added:Array<String> = [];
		try {
			for (mod in CoolUtil.coolTextFile('modsList.txt'))
			{
				var dat:Array<String> = mod.split("|");
				var folder:String = dat[0];
				if(folder.trim().length > 0 && FileSystem.exists(Paths.mods(folder)) && FileSystem.isDirectory(Paths.mods(folder)) && !added.contains(folder))
				{
					added.push(folder);
					list.push([folder, (dat[1] == "1")]);
				}
			}
		} catch(e) {
			trace(e);
		}

		// Scan for folders that aren't on modsList.txt yet
		// (getModDirectories() already skipped non folders and the ignored names)
		for (folder in getModDirectories())
		{
			if(folder.trim().length > 0 && !added.contains(folder))
			{
				added.push(folder);
				list.push([folder, true]); //i like it false by default. -bb //Well, i like it True! -Shadow Mario (2022)
				//Shadow Mario (2023): What the fuck was bb thinking
			}
		}

		var fileStr:String = '';
		for (values in list)
		{
			if(fileStr.length > 0) fileStr += '\n';
			fileStr += values[0] + '|' + (values[1] ? '1' : '0');
		}

		// This runs on every state change, so only touch the disk when something actually changed
		if(fileStr != _lastSavedList)
		{
			File.saveContent('modsList.txt', fileStr);
			_lastSavedList = fileStr;
			clearResolvedCache();
			//trace('Saved modsList.txt');
		}

		// Feed the cache straight from what we just built, no second read needed
		_listCache = {enabled: [], disabled: [], all: []};
		for (values in list)
		{
			var folder:String = values[0];
			_listCache.all.push(folder);
			if(values[1] == true) _listCache.enabled.push(folder);
			else _listCache.disabled.push(folder);
		}

		updatedOnState = true;
		#end
	}

	/**
	 * Writes modsList.txt and keeps the cache in sync, so the next parseList() doesn't hit the disk.
	 */
	public static function saveModsList(list:ModsList)
	{
		#if MODS_ALLOWED
		var fileStr:String = '';
		var updated:ModsList = {enabled: [], disabled: [], all: []};

		for (mod in list.all)
		{
			// The Mods menu keeps the base game in its list, it isn't a folder and never gets saved
			if(mod == null || mod.trim().length < 1 || mod == BASE_GAME) continue;

			var on:Bool = !list.disabled.contains(mod);
			if(fileStr.length > 0) fileStr += '\n';
			fileStr += mod + '|' + (on ? '1' : '0');

			updated.all.push(mod);
			if(on) updated.enabled.push(mod);
			else updated.disabled.push(mod);
		}

		File.saveContent('modsList.txt', fileStr);
		_lastSavedList = fileStr;
		_listCache = updated;
		clearResolvedCache();
		#end
	}

	/**
	 * Order the enabled mods are actually loaded in, dependencies taken into account.
	 * A mod is placed *before* what it depends on, so it can override its own dependencies.
	 * Mods that declare nothing keep exactly the order set on the Mods menu.
	 */
	public static function getLoadOrder():Array<String>
	{
		// Refresh the list first, it may drop the cached order we're about to check
		var enabled:Array<String> = parseList().enabled;
		if(_loadOrder != null) return _loadOrder.copy();

		var position:Map<String, Int> = new Map<String, Int>();
		for (i => mod in enabled) position.set(mod, i);

		// dependents[mod] counts how many enabled mods need "mod" loaded after them
		var dependencies:Map<String, Array<String>> = new Map<String, Array<String>>();
		var dependents:Map<String, Int> = new Map<String, Int>();
		for (mod in enabled) dependents.set(mod, 0);

		for (mod in enabled)
		{
			var mine:Array<String> = [];
			for (dep in getMetadata(mod).dependencies)
			{
				// Missing or disabled dependencies are reported by validate(), ignored here
				if(dep.folder == mod || !position.exists(dep.folder) || mine.contains(dep.folder)) continue;

				mine.push(dep.folder);
				dependents.set(dep.folder, dependents.get(dep.folder) + 1);
			}
			dependencies.set(mod, mine);
		}

		var order:Array<String> = [];
		var ready:Array<String> = [];
		for (mod in enabled) if(dependents.get(mod) == 0) ready.push(mod);

		while(ready.length > 0)
		{
			// Ties keep the user's own order, so the result is stable
			var pick:Int = 0;
			for (i in 1...ready.length)
				if(position.get(ready[i]) < position.get(ready[pick])) pick = i;

			var mod:String = ready.splice(pick, 1)[0];
			order.push(mod);

			for (dep in dependencies.get(mod))
			{
				var left:Int = dependents.get(dep) - 1;
				dependents.set(dep, left);
				if(left == 0) ready.push(dep);
			}
		}

		// Whatever is left sits in a dependency loop, keep the user's order for those
		_cyclicMods = [];
		if(order.length < enabled.length)
		{
			for (mod in enabled)
			{
				if(order.contains(mod)) continue;
				_cyclicMods.push(mod);
				order.push(mod);
			}
		}

		_loadOrder = order;
		return order.copy();
	}

	/**
	 * The mods whose content is live right now: the mod you entered, plus every global mod.
	 * Everything else is installed but dormant, so an enabled mod no longer dumps its songs
	 * into the base game's Freeplay just for being enabled.
	 */
	public static function getActiveMods():Array<String>
	{
		if(_activeMods != null) return _activeMods.copy();

		var order:Array<String> = getLoadOrder();
		var out:Array<String> = [];

		// The mod you entered outranks the global ones, same as Paths.modFolders() does
		if(activeMod != null && activeMod.length > 0 && order.contains(activeMod))
			out.push(activeMod);

		for (mod in order)
			if(!out.contains(mod) && getMetadata(mod).runsGlobally) out.push(mod);

		_activeMods = out;
		return out.copy();
	}

	/**
	 * Enters a mod, or the base game when given null, an empty string or BASE_GAME.
	 * The caller is expected to restart the game afterwards so nothing stays cached from before.
	 */
	public static function enterMod(folder:String)
	{
		if(folder == null || folder == BASE_GAME) folder = '';

		activeMod = folder;
		currentModDirectory = folder;
		_activeMods = null;
	}

	public static function exitMod()
	{
		enterMod('');
	}

	inline public static function isModActive():Bool
		return activeMod != null && activeMod.length > 0;

	/**
	 * A standalone mod replaces the base game instead of adding to it, so the vanilla weeks
	 * are left out while it's the active mod. Set "standalone": true on its pack.json.
	 */
	public static function isStandalone():Bool
	{
		if(!isModActive()) return false;
		return getMetadata(activeMod).standalone;
	}

	/**
	 * Every problem found on the installed mods, rechecked whenever the mod list changes.
	 */
	public static function validate():Array<ModIssue>
	{
		var result:Array<ModIssue> = [];
		#if MODS_ALLOWED
		var list:ModsList = parseList();
		getLoadOrder(); // fills _cyclicMods
		var engineVersion:String = states.MainMenuState.psychEngineVersion;

		for (folder in list.all)
		{
			var meta:ModMetadata = getMetadata(folder);

			if(_packErrors.exists(folder))
				result.push({
					mod: folder, kind: ModIssueKind.BROKEN_PACK, target: null, fatal: true,
					message: 'pack.json couldn\'t be read: ' + _packErrors.get(folder)
				});

			// A turned off mod can't break anything, so the rest only matters when it's on
			if(!list.enabled.contains(folder)) continue;

			if(meta.engineVersion != null && !satisfiesVersion(engineVersion, meta.engineVersion))
				result.push({
					mod: folder, kind: ModIssueKind.ENGINE_MISMATCH, target: engineVersion, fatal: false,
					message: 'Made for Psych Engine ${meta.engineVersion}, this build is $engineVersion.'
				});

			for (dep in meta.dependencies)
			{
				if(!list.all.contains(dep.folder))
				{
					result.push({
						mod: folder, kind: ModIssueKind.MISSING_DEPENDENCY, target: dep.folder, fatal: true,
						message: 'Needs "${dep.folder}", which isn\'t installed.'
					});
				}
				else if(!list.enabled.contains(dep.folder))
				{
					result.push({
						mod: folder, kind: ModIssueKind.DISABLED_DEPENDENCY, target: dep.folder, fatal: true,
						message: 'Needs "${dep.folder}", which is turned off.'
					});
				}
				else if(dep.version != null && !satisfiesVersion(getMetadata(dep.folder).version, dep.version))
				{
					var installed:String = getMetadata(dep.folder).version;
					if(installed == null) installed = 'no version';
					result.push({
						mod: folder, kind: ModIssueKind.OUTDATED_DEPENDENCY, target: dep.folder, fatal: false,
						message: 'Needs "${dep.folder}" ${dep.version}, found $installed.'
					});
				}
			}

			for (clash in meta.incompatibilities)
			{
				if(!list.enabled.contains(clash.folder)) continue;
				if(clash.version != null && !satisfiesVersion(getMetadata(clash.folder).version, clash.version)) continue;

				result.push({
					mod: folder, kind: ModIssueKind.INCOMPATIBLE, target: clash.folder, fatal: true,
					message: 'Can\'t be used together with "${clash.folder}".'
				});
			}

			if(_cyclicMods.contains(folder))
				result.push({
					mod: folder, kind: ModIssueKind.CIRCULAR_DEPENDENCY, target: null, fatal: true,
					message: 'Sits in a dependency loop, its load order couldn\'t be resolved.'
				});
		}
		#end

		_issues = result;
		return result.copy();
	}

	/**
	 * Problems found on one mod, or on every mod when no folder is given.
	 */
	public static function getIssues(?folder:String = null):Array<ModIssue>
	{
		ensureValidated();
		if(folder == null) return _issues.copy();

		var out:Array<ModIssue> = [];
		for (issue in _issues) if(issue.mod == folder) out.push(issue);
		return out;
	}

	public static function hasFatalIssues(folder:String):Bool
	{
		ensureValidated();
		for (issue in _issues) if(issue.fatal && issue.mod == folder) return true;
		return false;
	}

	private static function ensureValidated()
	{
		// Refresh the list first, it may drop the cached issues we're about to check
		parseList();
		if(_issues == null) validate();
	}

	// Load order and issues both depend on which mods are enabled
	private static function clearResolvedCache()
	{
		_loadOrder = null;
		_activeMods = null;
		_cyclicMods = [];
		_issues = null;
	}

	/**
	 * Throws away everything cached and re-reads it from disk on the next use.
	 * Call it after mod folders were edited while the game was running.
	 */
	public static function reload()
	{
		_packCache.clear();
		_packErrors.clear();
		_metaCache.clear();
		_dirCache = null;
		_lastSavedList = null;
		clearResolvedCache();
		updatedOnState = false; // also drops _listCache
	}

	/**
	 * Pins asset lookups back to the mod you entered.
	 * States reassign currentModDirectory all the time (per song, per week), so they call this
	 * to get back to a known state. Falls back to the base game if that mod is gone or turned off.
	 */
	public static function loadTopMod()
	{
		Mods.currentModDirectory = '';

		#if MODS_ALLOWED
		if(isModActive() && getActiveMods().contains(activeMod))
			Mods.currentModDirectory = activeMod;
		#end
	}
}
