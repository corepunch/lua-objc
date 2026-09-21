/* Lua value userdata for UIKit structs. */

#if defined(GEN_STRUCT_HELPERS)
static CGSize *check_CGSize(lua_State *L, int idx) {
	return (CGSize *)luaL_checkudata(L, idx, "lua_objc.struct.CGSize");
}

static void push_CGSize(lua_State *L, CGSize value) {
	CGSize *box = (CGSize *)lua_newuserdata(L, sizeof(CGSize));
	*box = value;
	luaL_setmetatable(L, "lua_objc.struct.CGSize");
}

static int index_CGSize(lua_State *L) {
	CGSize *value = check_CGSize(L, 1);
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

static int newindex_CGSize(lua_State *L) {
	CGSize *value = check_CGSize(L, 1);
	const char *key = luaL_checkstring(L, 2);
	if (strcmp(key, "width") == 0) {
		value->width = (CGFloat)luaL_checknumber(L, 3);
		return 0;
	}
	if (strcmp(key, "height") == 0) {
		value->height = (CGFloat)luaL_checknumber(L, 3);
		return 0;
	}
	return luaL_error(L, "unknown CGSize field: %s", key);
}

static int bridge_CGSize(lua_State *L) {
	CGSize value = {0};
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
	push_CGSize(L, value);
	return 1;
}

static void register_CGSize(lua_State *L) {
	luaL_newmetatable(L, "lua_objc.struct.CGSize");
	lua_pushcfunction(L, index_CGSize);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, newindex_CGSize);
	lua_setfield(L, -2, "__newindex");
	lua_pop(L, 1);
}

static CGPoint *check_CGPoint(lua_State *L, int idx) {
	return (CGPoint *)luaL_checkudata(L, idx, "lua_objc.struct.CGPoint");
}

static void push_CGPoint(lua_State *L, CGPoint value) {
	CGPoint *box = (CGPoint *)lua_newuserdata(L, sizeof(CGPoint));
	*box = value;
	luaL_setmetatable(L, "lua_objc.struct.CGPoint");
}

static int index_CGPoint(lua_State *L) {
	CGPoint *value = check_CGPoint(L, 1);
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

static int newindex_CGPoint(lua_State *L) {
	CGPoint *value = check_CGPoint(L, 1);
	const char *key = luaL_checkstring(L, 2);
	if (strcmp(key, "x") == 0) {
		value->x = (CGFloat)luaL_checknumber(L, 3);
		return 0;
	}
	if (strcmp(key, "y") == 0) {
		value->y = (CGFloat)luaL_checknumber(L, 3);
		return 0;
	}
	return luaL_error(L, "unknown CGPoint field: %s", key);
}

static int bridge_CGPoint(lua_State *L) {
	CGPoint value = {0};
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
	push_CGPoint(L, value);
	return 1;
}

static void register_CGPoint(lua_State *L) {
	luaL_newmetatable(L, "lua_objc.struct.CGPoint");
	lua_pushcfunction(L, index_CGPoint);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, newindex_CGPoint);
	lua_setfield(L, -2, "__newindex");
	lua_pop(L, 1);
}

static CGRect *check_CGRect(lua_State *L, int idx) {
	return (CGRect *)luaL_checkudata(L, idx, "lua_objc.struct.CGRect");
}

static void push_CGRect(lua_State *L, CGRect value) {
	CGRect *box = (CGRect *)lua_newuserdata(L, sizeof(CGRect));
	*box = value;
	luaL_setmetatable(L, "lua_objc.struct.CGRect");
}

static int index_CGRect(lua_State *L) {
	CGRect *value = check_CGRect(L, 1);
	const char *key = luaL_checkstring(L, 2);
	if (strcmp(key, "origin") == 0) {
		push_CGPoint(L, value->origin);
		return 1;
	}
	if (strcmp(key, "size") == 0) {
		push_CGSize(L, value->size);
		return 1;
	}
	lua_pushnil(L);
	return 1;
}

static int newindex_CGRect(lua_State *L) {
	CGRect *value = check_CGRect(L, 1);
	const char *key = luaL_checkstring(L, 2);
	if (strcmp(key, "origin") == 0) {
		value->origin = *check_CGPoint(L, 3);
		return 0;
	}
	if (strcmp(key, "size") == 0) {
		value->size = *check_CGSize(L, 3);
		return 0;
	}
	return luaL_error(L, "unknown CGRect field: %s", key);
}

static int bridge_CGRect(lua_State *L) {
	CGRect value = {0};
	if (lua_istable(L, 1)) {
		lua_getfield(L, 1, "origin");
		value.origin = *check_CGPoint(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, 1, "size");
		value.size = *check_CGSize(L, -1);
		lua_pop(L, 1);
	} else {
		value.origin = *check_CGPoint(L, 1);
		value.size = *check_CGSize(L, 2);
	}
	push_CGRect(L, value);
	return 1;
}

static void register_CGRect(lua_State *L) {
	luaL_newmetatable(L, "lua_objc.struct.CGRect");
	lua_pushcfunction(L, index_CGRect);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, newindex_CGRect);
	lua_setfield(L, -2, "__newindex");
	lua_pop(L, 1);
}

#endif /* GEN_STRUCT_HELPERS */

#if defined(GEN_STRUCT_REGISTER)
	register_CGSize(L);
	register_CGPoint(L);
	register_CGRect(L);
#endif /* GEN_STRUCT_REGISTER */
