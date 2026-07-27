#pragma mark - Lua helpers

static int bridge_tableview_add(lua_State *L);
static int bridge_tableview_remove(lua_State *L);
static int bridge_tableview_clear(lua_State *L);
static int bridge_set_text(lua_State *L);
static void layout_recursive(UIView *view, CGFloat width);

static void push_objc(lua_State *L, id obj, const char *meta) {
	ObjCRef *ref = lua_newuserdata(L, sizeof(ObjCRef));
	ref->ptr = (void *)CFBridgingRetain(obj);
	luaL_setmetatable(L, meta);
}

static id check_objc(lua_State *L, int idx) {
	ObjCRef *ref = luaL_testudata(L, idx, "uiview");
	if (ref) return (__bridge id)ref->ptr;
	ref = luaL_testudata(L, idx, "uiwindow");
	if (ref) return (__bridge id)ref->ptr;
	luaL_typeerror(L, idx, "uiview or uiwindow");
	return nil;
}

static UIView *check_view(lua_State *L, int idx) {
	id obj = check_objc(L, idx);
	return (UIView *)obj;
}

static int gc_objc(lua_State *L) {
	ObjCRef *ref = lua_touserdata(L, 1);
	if (ref->ptr) {
		CFRelease(ref->ptr);
		ref->ptr = NULL;
	}
	return 0;
}

static void push_objc_value(lua_State *L, id value) {
	if (!value || value == [NSNull null]) {
		lua_pushnil(L);
	} else if ([value isKindOfClass:[NSString class]]) {
		lua_pushstring(L, [(NSString *)value UTF8String]);
	} else if ([value isKindOfClass:[NSNumber class]]) {
		NSNumber *num = (NSNumber *)value;
		NSString *typeStr = [NSString stringWithUTF8String:num.objCType];
		if ([typeStr isEqualToString:@"c"] || [typeStr isEqualToString:@"B"]) {
			lua_pushboolean(L, num.boolValue);
		} else {
			lua_pushnumber(L, num.doubleValue);
		}
	} else if ([value isKindOfClass:[UIView class]]) {
		push_objc(L, value, "uiview");
	} else if ([value isKindOfClass:[UIWindow class]]) {
		push_objc(L, value, "uiwindow");
	} else if ([value isKindOfClass:[NSObject class]]) {
		push_objc(L, value, "nsobject");
	} else {
		lua_pushstring(L, [[value description] UTF8String]);
	}
}

static id lua_to_objc_value(lua_State *L, int idx) {
	switch (lua_type(L, idx)) {
		case LUA_TNIL:
			return nil;
		case LUA_TBOOLEAN:
			return @(lua_toboolean(L, idx));
		case LUA_TNUMBER: {
			double d = lua_tonumber(L, idx);
			if (d == floor(d) && d <= (double)NSIntegerMax && d >= (double)NSIntegerMin)
				return @((NSInteger)d);
			return @(d);
		}
		case LUA_TSTRING:
			return [NSString stringWithUTF8String:lua_tostring(L, idx)];
		default:
			return nil;
	}
}

