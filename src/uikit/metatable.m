#pragma mark - nsview metatable (UIKit uses "uiview")

/* Shared property macros — same pattern as AppKit runtime.m but using
 * direct key addresses (&kFooKey) instead of the enum array form. */
#define INDEX_NUMBER(name, kref, fallback) \
	if (strcmp(key, name) == 0) { \
		NSNumber *v = objc_getAssociatedObject(obj, kref); \
		lua_pushnumber(L, v ? v.doubleValue : fallback); \
		return 1; \
	}
#define INDEX_STRING(name, kref, fallback) \
	if (strcmp(key, name) == 0) { \
		NSString *v = objc_getAssociatedObject(obj, kref); \
		lua_pushstring(L, v ? v.UTF8String : fallback); \
		return 1; \
	}
#define NEWINDEX_NUMBER(name, kref) \
	if (strcmp(key, name) == 0) { \
		objc_setAssociatedObject(obj, kref, @(luaL_checknumber(L, 3)), OBJC_ASSOCIATION_RETAIN); \
		return 0; \
	}
#define NEWINDEX_STRING(name, kref) \
	if (strcmp(key, name) == 0) { \
		objc_setAssociatedObject(obj, kref, [NSString stringWithUTF8String:luaL_checkstring(L, 3)], OBJC_ASSOCIATION_RETAIN); \
		return 0; \
	}

static int nsview_index(lua_State *L) {
	id obj = (__bridge id)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	const char *key = lua_tostring(L, 2);
	if (!key) { lua_pushnil(L); return 1; }

#define GEN_PROPS_INDEX
#include "generated/bridge_props.m"
#undef GEN_PROPS_INDEX

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

