package psychlua;

#if LUA_ALLOWED
import llua.State;
import llua.Lua;
import llua.LuaL;
import llua.Convert;

/**
 * Native Lua module system: defines import() on every Lua state.
 *
 * The exported module table stays NATIVE to the interpreter: import() only receives
 * strings from Haxe (__getModulePath / __getModuleContent), so module functions survive.
 * Usage from Lua:
 *   local lib = import('scripts/myLib')
 *   lib.doThing()
 *
 * Modules must be mod-side .lua files (resolved with the same mod -> global -> shared
 * hierarchy used by addLuaScript), and export their API by returning a table.
 */
class LuaImport
{
	public static var SOURCE:String = "
local __moduleCache = {}

function import(moduleName)
	local cached = __moduleCache[moduleName]
	if cached ~= nil then return cached end

	local modulePath = __getModulePath(moduleName)
	if modulePath == nil or modulePath == false then
		error('import: module ' .. tostring(moduleName) .. ' not found')
	end

	local content = __getModuleContent(modulePath)
	if content == nil or content == false then
		error('import: could not read module ' .. tostring(moduleName))
	end

	local chunk, loadErr = loadstring(content, '@' .. tostring(moduleName))
	if chunk == nil then
		error('import: syntax error in module ' .. tostring(moduleName) .. ': ' .. tostring(loadErr))
	end

	local ok, result = pcall(chunk)
	if not ok then
		error('import: error running module ' .. tostring(moduleName) .. ': ' .. tostring(result))
	end

	__moduleCache[moduleName] = result
	return result
end
";

	/** Runs the bootstrap on a Lua state. Call BEFORE loading the script, so top-level import() works. */
	public static function install(lua:State, scriptName:String):Void
	{
		if(lua == null) return;
		// luaL_dostring returns 0 on success (C convention)
		if(LuaL.dostring(lua, SOURCE) != 0)
		{
			var err:Dynamic = Convert.fromLua(lua, -1);
			FunkinLua.luaTrace('Error on import bootstrap ($scriptName): $err', false, false, FlxColor.RED);
			Lua.pop(lua, 1);
		}
	}
}
#end
