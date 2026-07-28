/* AUTO-GENERATED — do not edit by hand.
 * Regenerate with:  python3 tools/gen_bridge.py --xml tools/bridge.xml
 * Source:           tools/bridge.xml
 */

/* --- _impl forward declarations --- */
#if defined(GEN_CLASS_FORWARDS)
static int bridge_NSTabView_addTab_impl(lua_State *L, NSTabView *self, const char * title, NSView * content);
static int bridge_NSTabView_removeTab_impl(lua_State *L, NSTabView *self, NSInteger index);
static int bridge_NSTabView_selectTab_impl(lua_State *L, NSTabView *self, NSInteger index);
static int bridge_NSTabView_tabCount_impl(lua_State *L, NSTabView *self);
static int bridge_NSTabView_onChange_impl(lua_State *L, NSTabView *self, int callback);
#endif /* GEN_CLASS_FORWARDS */

/* --- Auto-generated wrapper functions --- */
#if defined(GEN_CLASS_WRAPPERS)
static int bridge_NSTabView_addTab(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSTabView class], "TabView");
	NSTabView *self = (NSTabView *)_obj;
	const char *title = luaL_checkstring(L, 2);
	NSView *content = check_view(L, 3);
	return bridge_NSTabView_addTab_impl(L, self, title, content);
}

static int bridge_NSTabView_removeTab(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSTabView class], "TabView");
	NSTabView *self = (NSTabView *)_obj;
	NSInteger index = (NSInteger)luaL_checkinteger(L, 2);
	return bridge_NSTabView_removeTab_impl(L, self, index);
}

static int bridge_NSTabView_selectTab(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSTabView class], "TabView");
	NSTabView *self = (NSTabView *)_obj;
	NSInteger index = (NSInteger)luaL_checkinteger(L, 2);
	return bridge_NSTabView_selectTab_impl(L, self, index);
}

static int bridge_NSTabView_tabCount(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSTabView class], "TabView");
	NSTabView *self = (NSTabView *)_obj;
	return bridge_NSTabView_tabCount_impl(L, self);
}

static int bridge_NSTabView_onChange(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSTabView class], "TabView");
	NSTabView *self = (NSTabView *)_obj;
	BOOL has_callback = !lua_isnoneornil(L, 2);
	int callback = LUA_NOREF;
	if (has_callback) {
		luaL_checktype(L, 2, LUA_TFUNCTION);
		lua_pushvalue(L, 2);
		callback = luaL_ref(L, LUA_REGISTRYINDEX);
	}
	return bridge_NSTabView_onChange_impl(L, self, callback);
}

#endif /* GEN_CLASS_WRAPPERS */

/* --- MethodEntry dispatch arrays --- */
#if defined(GEN_CLASS_ARRAYS)
static MethodEntry TabViewMethods[] = {
	{"addTab",	bridge_NSTabView_addTab},
	{"removeTab",	bridge_NSTabView_removeTab},
	{"selectTab",	bridge_NSTabView_selectTab},
	{"tabCount",	bridge_NSTabView_tabCount},
	{"onChange",	bridge_NSTabView_onChange},
	{NULL, NULL}
};

#endif /* GEN_CLASS_ARRAYS */

/* --- nsview_index dispatch blocks --- */
#if defined(GEN_CLASS_INDEX)
{
	if ([obj isKindOfClass:[NSTabView class]]) {
		lua_CFunction _m = lookupMethod(key, TabViewMethods);
		if (_m) { lua_pushcfunction(L, _m); return 1; }
	}
}

#endif /* GEN_CLASS_INDEX */
