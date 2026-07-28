#pragma mark - nsview metatable (UIKit uses "uiview")

static int nsview_index(lua_State *L) {
	id obj = (__bridge id)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	const char *key = lua_tostring(L, 2);
	if (!key) { lua_pushnil(L); return 1; }

	NSString *kvcKey = [NSString stringWithUTF8String:key];
	@try {
		id value = [obj valueForKey:kvcKey];
		push_objc_value(L, value);
		return 1;
	} @catch (NSException *e) {
	}

	if (strcmp(key, "add") == 0) {
		lua_pushcfunction(L, bridge_add);
		return 1;
	}
	if (strcmp(key, "layout") == 0) {
		lua_pushcfunction(L, bridge_layout);
		return 1;
	}
	if (strcmp(key, "setContentSize") == 0) {
		lua_pushcfunction(L, bridge_set_content_size);
		return 1;
	}
	if (strcmp(key, "show") == 0 && [obj isKindOfClass:[UIWindow class]]) {
		lua_pushcfunction(L, bridge_show);
		return 1;
	}

	id src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (src) {
		if (strcmp(key, "addRow") == 0) {
			lua_pushcfunction(L, bridge_tableview_add);
			return 1;
		}
		if (strcmp(key, "removeRow") == 0) {
			lua_pushcfunction(L, bridge_tableview_remove);
			return 1;
		}
		if (strcmp(key, "clearRows") == 0) {
			lua_pushcfunction(L, bridge_tableview_clear);
			return 1;
		}
		if (strcmp(key, "rowCount") == 0) {
			lua_pushinteger(L, (lua_Integer)((LuaTableViewSource *)src).rows.count);
			return 1;
		}
	}

	lua_pushnil(L);
	return 1;
}

static int nsview_newindex(lua_State *L) {
	id obj = (__bridge id)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	const char *key = lua_tostring(L, 2);
	if (!key) return luaL_error(L, "invalid property name");

	NSString *kvcKey = [NSString stringWithUTF8String:key];
	id value = lua_to_objc_value(L, 3);

	@try {
		[obj setValue:value forKey:kvcKey];
	} @catch (NSException *e) {
		return luaL_error(L, "cannot set '%s': %s", key, e.description.UTF8String);
	}

	return 0;
}
