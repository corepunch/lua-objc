#pragma mark - nsview metatable (UIKit uses "uiview")

static int bridge_tableview_on_row_move(lua_State *L);
static int bridge_tableview_on_row_swipe(lua_State *L);
static int bridge_clear_container(lua_State *L);
static int bridge_uikit_scroll_to(lua_State *L);
static int bridge_LuaArcView_arcBounds(lua_State *L);

@interface LuaArcView : UIView
@end

static int nsview_index(lua_State *L) {
	id obj = lua_objc_live_ptr(L, 1, lua_touserdata(L, 1));
	const char *key = lua_tostring(L, 2);
	if (!key) { lua_pushnil(L); return 1; }
	/* UIView operations must bypass KVC: KVC can treat a method-shaped key
	 * such as sizeToFit as an undefined, nil-valued property. */
	if (strcmp(key, "sizeToFit") == 0) {
		lua_pushcfunction(L, bridge_size_to_fit);
		return 1;
	}

	if ([obj isKindOfClass:UIView.class] && lua_objc_key_reads_geometry(key))
		uikit_layout_if_needed((UIView *)obj);
	NSString *kvcKey = [NSString stringWithUTF8String:key];
	@try {
		id value = [obj valueForKey:kvcKey];
		push_kvc_value(L, value);
		return 1;
	} @catch (NSException *e) {
	}

	if (strcmp(key, "add") == 0) {
		lua_pushcfunction(L, bridge_add);
		return 1;
	}
	if (strcmp(key, "clearContainer") == 0) {
		lua_pushcfunction(L, bridge_clear_container);
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
	if (strcmp(key, "scrollTo") == 0 && [obj isKindOfClass:[UIScrollView class]]) {
		lua_pushcfunction(L, bridge_uikit_scroll_to);
		return 1;
	}
	if (strcmp(key, "arcBounds") == 0 && [obj isKindOfClass:[LuaArcView class]]) {
		lua_pushcfunction(L, bridge_LuaArcView_arcBounds);
		return 1;
	}
	if (strcmp(key, "show") == 0 && [obj isKindOfClass:[UIWindow class]]) {
		lua_pushcfunction(L, bridge_show);
		return 1;
	}
	if ([obj isKindOfClass:[UINavigationController class]]) {
		if (strcmp(key, "push") == 0) { lua_pushcfunction(L, bridge_UIKitNavigation_push); return 1; }
		if (strcmp(key, "pop") == 0) { lua_pushcfunction(L, bridge_UIKitNavigation_pop); return 1; }
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
		if (strcmp(key, "onRowMove") == 0) {
			lua_pushcfunction(L, bridge_tableview_on_row_move);
			return 1;
		}
		if (strcmp(key, "onRowSwipe") == 0) {
			lua_pushcfunction(L, bridge_tableview_on_row_swipe);
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
	id obj = lua_objc_live_ptr(L, 1, lua_touserdata(L, 1));
	const char *key = lua_tostring(L, 2);
	if (!key) return luaL_error(L, "invalid property name");

	NSString *kvcKey = [NSString stringWithUTF8String:key];
	id value = lua_to_kvc_value(L, 3);

	@try {
		[obj setValue:value forKey:kvcKey];
	} @catch (NSException *e) {
		return luaL_error(L, "cannot set '%s': %s", key, e.description.UTF8String);
	}
	if ([obj isKindOfClass:UIView.class] && lua_objc_key_affects_layout(key))
		uikit_invalidate_layout((UIView *)obj);

	return 0;
}
