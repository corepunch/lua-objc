#pragma mark - nsview metatable (UIKit uses "uiview")

static int nsview_index(lua_State *L) {
	id obj = (__bridge id)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	const char *key = lua_tostring(L, 2);
	if (!key) { lua_pushnil(L); return 1; }

	if (strcmp(key, "padding") == 0) {
		NSNumber *p = objc_getAssociatedObject(obj, &kPaddingKey);
		lua_pushnumber(L, p ? p.doubleValue : 12.0);
		return 1;
	}
	if (strcmp(key, "alignment") == 0) {
		NSString *a = objc_getAssociatedObject(obj, &kAlignmentKey);
		lua_pushstring(L, a ? a.UTF8String : "center");
		return 1;
	}
	if (strcmp(key, "fixedWidth") == 0) {
		NSNumber *w = objc_getAssociatedObject(obj, &kFixedWidthKey);
		lua_pushnumber(L, w ? w.doubleValue : 0);
		return 1;
	}
	if (strcmp(key, "fixedHeight") == 0) {
		NSNumber *h = objc_getAssociatedObject(obj, &kFixedHeightKey);
		lua_pushnumber(L, h ? h.doubleValue : 0);
		return 1;
	}

	if (strcmp(key, "setText") == 0 && [obj isKindOfClass:[UILabel class]]) {
		lua_pushcfunction(L, bridge_set_text);
		return 1;
	}

	NSString *kvcKey = [NSString stringWithUTF8String:key];
	@try {
		id value = [obj valueForKey:kvcKey];
		push_objc_value(L, value);
		return 1;
	} @catch (NSException *e) {
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

	if (strcmp(key, "padding") == 0) {
		double val = luaL_checknumber(L, 3);
		objc_setAssociatedObject(obj, &kPaddingKey, @(val), OBJC_ASSOCIATION_RETAIN);
		return 0;
	}
	if (strcmp(key, "alignment") == 0) {
		const char *val = luaL_checkstring(L, 3);
		objc_setAssociatedObject(obj, &kAlignmentKey,
			[NSString stringWithUTF8String:val], OBJC_ASSOCIATION_RETAIN);
		return 0;
	}
	if (strcmp(key, "fixedWidth") == 0) {
		double val = luaL_checknumber(L, 3);
		objc_setAssociatedObject(obj, &kFixedWidthKey, @(val), OBJC_ASSOCIATION_RETAIN);
		return 0;
	}
	if (strcmp(key, "fixedHeight") == 0) {
		double val = luaL_checknumber(L, 3);
		objc_setAssociatedObject(obj, &kFixedHeightKey, @(val), OBJC_ASSOCIATION_RETAIN);
		return 0;
	}

	NSString *kvcKey = [NSString stringWithUTF8String:key];
	id value = lua_to_objc_value(L, 3);

	@try {
		[obj setValue:value forKey:kvcKey];
	} @catch (NSException *e) {
		return luaL_error(L, "cannot set '%s': %s", key, e.description.UTF8String);
	}

	return 0;
}

