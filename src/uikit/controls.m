#pragma mark - Button, toggle

static int bridge_button(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	int has_action = !lua_isnoneornil(L, 2);
	int ref = LUA_NOREF;
	if (has_action) {
		luaL_checktype(L, 2, LUA_TFUNCTION);
		lua_pushvalue(L, 2);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
	[btn setTitle:[NSString stringWithUTF8String:title] forState:UIControlStateNormal];
	[btn sizeToFit];

	if (has_action) {
		objc_setAssociatedObject(btn, &kCallbackKey, @(ref), OBJC_ASSOCIATION_RETAIN);
		[btn addTarget:[LuaButtonTarget shared] action:@selector(onAction:)
	  forControlEvents:UIControlEventTouchUpInside];
	}

	push_objc(L, btn, "uiview");
	return 1;
}

static int bridge_toggle(lua_State *L) {
	const char *label = luaL_checkstring(L, 1);
	int is_on = lua_toboolean(L, 2);
	int has_action = !lua_isnoneornil(L, 3);
	int ref = LUA_NOREF;
	if (has_action) {
		luaL_checktype(L, 3, LUA_TFUNCTION);
		lua_pushvalue(L, 3);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	UISwitch *sw = [[UISwitch alloc] init];
	sw.on = is_on;
	sw.accessibilityLabel = [NSString stringWithUTF8String:label];
	[sw sizeToFit];

	if (has_action) {
		objc_setAssociatedObject(sw, &kCallbackKey, @(ref), OBJC_ASSOCIATION_RETAIN);
		[sw addTarget:[LuaButtonTarget shared] action:@selector(onAction:)
	forControlEvents:UIControlEventValueChanged];
	}

	push_objc(L, sw, "uiview");
	return 1;
}
