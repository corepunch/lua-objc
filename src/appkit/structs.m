/* Lua value userdata for AppKit structs. */

#if defined(GEN_STRUCT_HELPERS)
static NSSize *check_NSSize(lua_State *L, int idx) {
	return (NSSize *)luaL_checkudata(L, idx, "lua_objc.struct.NSSize");
}

static void push_NSSize(lua_State *L, NSSize value) {
	NSSize *box = (NSSize *)lua_newuserdata(L, sizeof(NSSize));
	*box = value;
	luaL_setmetatable(L, "lua_objc.struct.NSSize");
}

static int index_NSSize(lua_State *L) {
	NSSize *value = check_NSSize(L, 1);
	const char *key = luaL_checkstring(L, 2);
	if (strcmp(key, "width") == 0) {
		lua_pushnumber(L, value->width);
		return 1;
	}
	if (strcmp(key, "height") == 0) {
		lua_pushnumber(L, value->height);
		return 1;
	}
	lua_pushnil(L);
	return 1;
}

static int newindex_NSSize(lua_State *L) {
	NSSize *value = check_NSSize(L, 1);
	const char *key = luaL_checkstring(L, 2);
	if (strcmp(key, "width") == 0) {
		value->width = (CGFloat)luaL_checknumber(L, 3);
		return 0;
	}
	if (strcmp(key, "height") == 0) {
		value->height = (CGFloat)luaL_checknumber(L, 3);
		return 0;
	}
	return luaL_error(L, "unknown NSSize field: %s", key);
}

static int bridge_NSSize(lua_State *L) {
	NSSize value = {0};
	if (lua_istable(L, 1)) {
		lua_getfield(L, 1, "width");
		value.width = (CGFloat)luaL_checknumber(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, 1, "height");
		value.height = (CGFloat)luaL_checknumber(L, -1);
		lua_pop(L, 1);
	} else {
		value.width = (CGFloat)luaL_checknumber(L, 1);
		value.height = (CGFloat)luaL_checknumber(L, 2);
	}
	push_NSSize(L, value);
	return 1;
}

static void register_NSSize(lua_State *L) {
	luaL_newmetatable(L, "lua_objc.struct.NSSize");
	lua_pushcfunction(L, index_NSSize);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, newindex_NSSize);
	lua_setfield(L, -2, "__newindex");
	lua_pop(L, 1);
}

static NSPoint *check_NSPoint(lua_State *L, int idx) {
	return (NSPoint *)luaL_checkudata(L, idx, "lua_objc.struct.NSPoint");
}

static void push_NSPoint(lua_State *L, NSPoint value) {
	NSPoint *box = (NSPoint *)lua_newuserdata(L, sizeof(NSPoint));
	*box = value;
	luaL_setmetatable(L, "lua_objc.struct.NSPoint");
}

static int index_NSPoint(lua_State *L) {
	NSPoint *value = check_NSPoint(L, 1);
	const char *key = luaL_checkstring(L, 2);
	if (strcmp(key, "x") == 0) {
		lua_pushnumber(L, value->x);
		return 1;
	}
	if (strcmp(key, "y") == 0) {
		lua_pushnumber(L, value->y);
		return 1;
	}
	lua_pushnil(L);
	return 1;
}

static int newindex_NSPoint(lua_State *L) {
	NSPoint *value = check_NSPoint(L, 1);
	const char *key = luaL_checkstring(L, 2);
	if (strcmp(key, "x") == 0) {
		value->x = (CGFloat)luaL_checknumber(L, 3);
		return 0;
	}
	if (strcmp(key, "y") == 0) {
		value->y = (CGFloat)luaL_checknumber(L, 3);
		return 0;
	}
	return luaL_error(L, "unknown NSPoint field: %s", key);
}

static int bridge_NSPoint(lua_State *L) {
	NSPoint value = {0};
	if (lua_istable(L, 1)) {
		lua_getfield(L, 1, "x");
		value.x = (CGFloat)luaL_checknumber(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, 1, "y");
		value.y = (CGFloat)luaL_checknumber(L, -1);
		lua_pop(L, 1);
	} else {
		value.x = (CGFloat)luaL_checknumber(L, 1);
		value.y = (CGFloat)luaL_checknumber(L, 2);
	}
	push_NSPoint(L, value);
	return 1;
}

static void register_NSPoint(lua_State *L) {
	luaL_newmetatable(L, "lua_objc.struct.NSPoint");
	lua_pushcfunction(L, index_NSPoint);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, newindex_NSPoint);
	lua_setfield(L, -2, "__newindex");
	lua_pop(L, 1);
}

static NSRect *check_NSRect(lua_State *L, int idx) {
	return (NSRect *)luaL_checkudata(L, idx, "lua_objc.struct.NSRect");
}

static void push_NSRect(lua_State *L, NSRect value) {
	NSRect *box = (NSRect *)lua_newuserdata(L, sizeof(NSRect));
	*box = value;
	luaL_setmetatable(L, "lua_objc.struct.NSRect");
}

static int index_NSRect(lua_State *L) {
	NSRect *value = check_NSRect(L, 1);
	const char *key = luaL_checkstring(L, 2);
	if (strcmp(key, "origin") == 0) {
		push_NSPoint(L, value->origin);
		return 1;
	}
	if (strcmp(key, "size") == 0) {
		push_NSSize(L, value->size);
		return 1;
	}
	lua_pushnil(L);
	return 1;
}

static int newindex_NSRect(lua_State *L) {
	NSRect *value = check_NSRect(L, 1);
	const char *key = luaL_checkstring(L, 2);
	if (strcmp(key, "origin") == 0) {
		value->origin = *check_NSPoint(L, 3);
		return 0;
	}
	if (strcmp(key, "size") == 0) {
		value->size = *check_NSSize(L, 3);
		return 0;
	}
	return luaL_error(L, "unknown NSRect field: %s", key);
}

static int bridge_NSRect(lua_State *L) {
	NSRect value = {0};
	if (lua_istable(L, 1)) {
		lua_getfield(L, 1, "origin");
		value.origin = *check_NSPoint(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, 1, "size");
		value.size = *check_NSSize(L, -1);
		lua_pop(L, 1);
	} else {
		value.origin = *check_NSPoint(L, 1);
		value.size = *check_NSSize(L, 2);
	}
	push_NSRect(L, value);
	return 1;
}

static void register_NSRect(lua_State *L) {
	luaL_newmetatable(L, "lua_objc.struct.NSRect");
	lua_pushcfunction(L, index_NSRect);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, newindex_NSRect);
	lua_setfield(L, -2, "__newindex");
	lua_pop(L, 1);
}

#endif /* GEN_STRUCT_HELPERS */

#if defined(GEN_STRUCT_REGISTER)
	register_NSSize(L);
	register_NSPoint(L);
	register_NSRect(L);
#endif /* GEN_STRUCT_REGISTER */
