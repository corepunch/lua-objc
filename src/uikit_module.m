#include <lua.h>
#include <lauxlib.h>

int luaopen_UIKitNative(lua_State *L);

#include "uikit_bridge.m"
#include "generated/UIKit.lua.h"

/*
 * UIKit is self-contained: its native control table and declarative Lua
 * conveniences enter package.loaded together. The private native module is
 * registered first so the embedded source can require it without exposing a
 * second library that applications need to understand.
 */
int luaopen_UIKit(lua_State *L) {
	luaL_requiref(L, "UIKitNative", luaopen_UIKitNative, 0);
	lua_pop(L, 1);

	int status = luaL_loadbufferx(
		L,
		(const char *)UIKit_lua,
		(size_t)UIKit_lua_len,
		"@UIKit.lua",
		"t");
	if (status != LUA_OK) {
		return lua_error(L);
	}
	status = lua_pcall(L, 0, 1, 0);
	if (status != LUA_OK) {
		return lua_error(L);
	}
	return 1;
}
