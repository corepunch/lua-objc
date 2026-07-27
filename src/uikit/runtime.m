#pragma mark - Lua helpers

static int bridge_tableview_add(lua_State *L);
static int bridge_tableview_remove(lua_State *L);
static int bridge_tableview_clear(lua_State *L);
static int bridge_set_text(lua_State *L);
static void layout_recursive(UIView *view, CGFloat width);

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

