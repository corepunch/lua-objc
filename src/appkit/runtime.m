#pragma mark - Lua helpers

static int bridge_tableview_add(lua_State *L);
static int bridge_tableview_remove(lua_State *L);
static int bridge_tableview_clear(lua_State *L);
static int bridge_table_show_loading(lua_State *L);
static int bridge_table_hide_loading(lua_State *L);
static int bridge_table_set_refresh(lua_State *L);
static int bridge_table_column_widths(lua_State *L);
static int bridge_table_refresh(lua_State *L);
static int bridge_table_set_selection(lua_State *L);
static int bridge_table_set_activation(lua_State *L);
static int bridge_tableview_replace(lua_State *L);
static int bridge_table_select_row(lua_State *L);
static int bridge_table_activate_row(lua_State *L);
static int bridge_set_text(lua_State *L);
static int bridge_text_view(lua_State *L);
static int bridge_text_view_get_text(lua_State *L);
static int bridge_text_view_set_text(lua_State *L);
static int bridge_text_view_on_change(lua_State *L);
static int bridge_text_view_set_language(lua_State *L);
static int bridge_text_view_set_wrap_mode(lua_State *L);
static int bridge_symbol_toggle(lua_State *L);
static int bridge_eval(lua_State *L);
static int bridge_clear_container(lua_State *L);
static int bridge_outlineview(lua_State *L);
static int bridge_list_directory(lua_State *L);
static int bridge_tabview(lua_State *L);
static int bridge_tab_add(lua_State *L);
static int bridge_tab_select(lua_State *L);
static int bridge_tab_remove(lua_State *L);
static int bridge_tab_count(lua_State *L);
static int bridge_tab_on_change(lua_State *L);
static int bridge_segmented_control(lua_State *L);
static int bridge_panel(lua_State *L);
static int bridge_panel_style_state(lua_State *L);
static int bridge_present_panel(lua_State *L);
static int bridge_dismiss_window(lua_State *L);
static int bridge_focus(lua_State *L);
static int bridge_is_first_responder(lua_State *L);
static int bridge_menu_item(lua_State *L);
static int bridge_text_field_callbacks(lua_State *L);
static int bridge_text_field_test_input(lua_State *L);
static int bridge_text_field_test_command(lua_State *L);
static void layout_recursive(NSView *view, CGFloat width);

static id check_objc(lua_State *L, int idx) {
	ObjCRef *ref = luaL_testudata(L, idx, "nsview");
	if (ref) return (__bridge id)ref->ptr;
	ref = luaL_testudata(L, idx, "nswindow");
	if (ref) return (__bridge id)ref->ptr;
	luaL_typeerror(L, idx, "nsview or nswindow");
	return nil;
}

static NSView *check_view(lua_State *L, int idx) {
	id obj = check_objc(L, idx);
	if ([obj isKindOfClass:[NSWindow class]]) {
		return [(NSWindow *)obj contentView];
	}
	return (NSView *)obj;
}

#define INDEX_NUMBER(name, kvar, fallback) \
	if (strcmp(key, name) == 0) { \
		NSNumber *v = objc_getAssociatedObject(obj, &kKeys[kvar]); \
		lua_pushnumber(L, v ? v.doubleValue : fallback); \
		return 1; \
	}

#define INDEX_NUMBER_OR_NIL(name, kvar) \
	if (strcmp(key, name) == 0) { \
		NSNumber *v = objc_getAssociatedObject(obj, &kKeys[kvar]); \
		if (v) lua_pushnumber(L, v.doubleValue); else lua_pushnil(L); \
		return 1; \
	}

#define INDEX_BOOL(name, kvar) \
	if (strcmp(key, name) == 0) { \
		NSNumber *v = objc_getAssociatedObject(obj, &kKeys[kvar]); \
		lua_pushboolean(L, v.boolValue); \
		return 1; \
	}

#define INDEX_STRING(name, kvar, fallback) \
	if (strcmp(key, name) == 0) { \
		NSString *v = objc_getAssociatedObject(obj, &kKeys[kvar]); \
		lua_pushstring(L, v ? v.UTF8String : fallback); \
		return 1; \
	}

#define NEWINDEX_NUMBER(name, kvar) \
	if (strcmp(key, name) == 0) { \
		objc_setAssociatedObject(obj, &kKeys[kvar], @(luaL_checknumber(L, 3)), OBJC_ASSOCIATION_RETAIN); \
		return 0; \
	}

#define NEWINDEX_NUMBER_CLAMP(name, kvar, expr) \
	if (strcmp(key, name) == 0) { \
		double val = luaL_checknumber(L, 3); \
		objc_setAssociatedObject(obj, &kKeys[kvar], @(expr), OBJC_ASSOCIATION_RETAIN); \
		return 0; \
	}

#define NEWINDEX_NILABLE_NUMBER(name, kvar) \
	if (strcmp(key, name) == 0) { \
		if (lua_isnil(L, 3)) { \
			objc_setAssociatedObject(obj, &kKeys[kvar], nil, OBJC_ASSOCIATION_ASSIGN); \
		} else { \
			objc_setAssociatedObject(obj, &kKeys[kvar], @(luaL_checknumber(L, 3)), OBJC_ASSOCIATION_RETAIN); \
		} \
		return 0; \
	}

#define NEWINDEX_NILABLE_NUMBER_CLAMP(name, kvar, expr) \
	if (strcmp(key, name) == 0) { \
		if (lua_isnil(L, 3)) { \
			objc_setAssociatedObject(obj, &kKeys[kvar], nil, OBJC_ASSOCIATION_ASSIGN); \
		} else { \
			double val = luaL_checknumber(L, 3); \
			objc_setAssociatedObject(obj, &kKeys[kvar], @(expr), OBJC_ASSOCIATION_RETAIN); \
		} \
		return 0; \
	}

#define NEWINDEX_BOOL(name, kvar) \
	if (strcmp(key, name) == 0) { \
		objc_setAssociatedObject(obj, &kKeys[kvar], @(lua_toboolean(L, 3)), OBJC_ASSOCIATION_RETAIN); \
		return 0; \
	}

#define NEWINDEX_STRING(name, kvar) \
	if (strcmp(key, name) == 0) { \
		objc_setAssociatedObject(obj, &kKeys[kvar], [NSString stringWithUTF8String:luaL_checkstring(L, 3)], OBJC_ASSOCIATION_RETAIN); \
		return 0; \
	}

static MethodEntry TableMethods[] = {
	{"addRow",       bridge_tableview_add},
	{"removeRow",    bridge_tableview_remove},
	{"clearRows",    bridge_tableview_clear},
	{"replaceRows",  bridge_tableview_replace},
	{"selectRow",    bridge_table_select_row},
	{"activateRow",  bridge_table_activate_row},
	{"rowCount",     NULL},
	{"showLoading",  bridge_table_show_loading},
	{"hideLoading",  bridge_table_hide_loading},
	{"refresh",      bridge_table_refresh},
	{"onRowSelect",  bridge_table_set_selection},
	{"onRowActivate", bridge_table_set_activation},
	{NULL, NULL}
};

static int nsview_index(lua_State *L) {
	id obj = (__bridge id)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	const char *key = lua_tostring(L, 2);
	if (!key) { lua_pushnil(L); return 1; }

#define GEN_PROPS_INDEX
#include "generated/bridge_props.m"
#undef GEN_PROPS_INDEX

	if (strcmp(key, "set_text") == 0 && [obj isKindOfClass:[NSTextField class]]) {
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

	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (src) {
		if (strcmp(key, "rowCount") == 0) {
			if ([src isKindOfClass:[LuaOutlineViewSource class]]) {
				lua_pushinteger(L,
					(lua_Integer)[(LuaOutlineViewSource *)src rowCount]);
			} else {
				lua_pushinteger(L,
					(lua_Integer)((LuaTableViewSource *)src).rows.count);
			}
			return 1;
		}
		lua_CFunction method = lookupMethod(key, TableMethods);
		if (method) {
			lua_pushcfunction(L, method);
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

#define GEN_PROPS_NEWINDEX
#include "generated/bridge_props.m"
#undef GEN_PROPS_NEWINDEX

	NSString *kvcKey = [NSString stringWithUTF8String:key];
	id value = lua_to_objc_value(L, 3);

	@try {
		[obj setValue:value forKey:kvcKey];
	} @catch (NSException *e) {
		return luaL_error(L, "cannot set '%s': %s", key, e.description.UTF8String);
	}

	return 0;
}
