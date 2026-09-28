#include <lua.h>
#include <lauxlib.h>

/*
 * The AppKit Lua layer ships beside the native runtime in Resources/lua.
 * Loading it from its resource path keeps the Xcode app build on the same
 * source files developers edit and lets the app copy those files normally.
 */
int luaopen_AppKit(lua_State *L) {
	int status = luaL_loadfilex(L, "lua/embedded/AppKit.lua", "t");
	if (status != LUA_OK) {
		return lua_error(L);
	}

	status = lua_pcall(L, 0, 1, 0);
	if (status != LUA_OK) {
		return lua_error(L);
	}
	return 1;
}
