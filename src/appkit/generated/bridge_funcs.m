/* AUTO-GENERATED — do not edit by hand.
 * Regenerate with:  python3 tools/gen_bridge.py --xml tools/AppKit.xml
 * Source:           tools/AppKit.xml
 */

/* Generated bridge_xxx() functions */

static int bridge_AppKitControls_vstack(lua_State *L) {

	NSView *obj = [[NSView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisVStack), OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_hstack(lua_State *L) {

	NSView *obj = [[NSView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisHStack), OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_hsplit(lua_State *L) {

	NSSplitView *obj = [[NSSplitView alloc] initWithFrame:NSZeroRect];
	obj.vertical = YES;
	obj.dividerStyle = NSSplitViewDividerStyleThin;
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisHSplit), OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_vsplit(lua_State *L) {

	NSSplitView *obj = [[NSSplitView alloc] initWithFrame:NSZeroRect];
	obj.vertical = NO;
	obj.dividerStyle = NSSplitViewDividerStyleThin;
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisVSplit), OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_separator(lua_State *L) {

	NSBox *obj = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, kSeparatorSize, kSeparatorSize)];
	obj.boxType = NSBoxSeparator;
	objc_setAssociatedObject(obj, &kKeys[kFixedHeightKey], @(kSeparatorSize), OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFillWidthKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_spacer(lua_State *L) {

	NSView *obj = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSpacerSize, kSpacerSize)];
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexBasisKey], @0, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_button(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	BOOL has_callback = !lua_isnoneornil(L, 2);
	int callback_ref = LUA_NOREF;
	if (has_callback) {
		luaL_checktype(L, 2, LUA_TFUNCTION);
		lua_pushvalue(L, 2);
		callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	NSButton *obj = [[NSButton alloc] initWithFrame:NSZeroRect];
	obj.title = [NSString stringWithUTF8String:title];
	obj.bezelStyle = NSBezelStyleRounded;
	[obj sizeToFit];
	if (has_callback) {
		objc_setAssociatedObject(obj, &kKeys[kCallbackKey], @(callback_ref), OBJC_ASSOCIATION_RETAIN);
		obj.target = [LuaButtonTarget shared];
		obj.action = @selector(onAction:);
	}
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_toggle(lua_State *L) {
	const char *label = luaL_checkstring(L, 1);
	BOOL is_on = (BOOL)lua_toboolean(L, 2);
	BOOL has_callback = !lua_isnoneornil(L, 3);
	int callback_ref = LUA_NOREF;
	if (has_callback) {
		luaL_checktype(L, 3, LUA_TFUNCTION);
		lua_pushvalue(L, 3);
		callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	NSButton *obj = [NSButton checkboxWithTitle:[NSString stringWithUTF8String:label] target:nil action:nil];
	obj.state = is_on ? NSControlStateValueOn : NSControlStateValueOff;
	[obj sizeToFit];
	if (has_callback) {
		objc_setAssociatedObject(obj, &kKeys[kCallbackKey], @(callback_ref), OBJC_ASSOCIATION_RETAIN);
		obj.target = [LuaButtonTarget shared];
		obj.action = @selector(onAction:);
	}
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_NSScrollView_setRefresh(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");
	if (lua_isnoneornil(L, 2)) {
		objc_setAssociatedObject(obj, &kKeys[kTableRefreshKey], nil, OBJC_ASSOCIATION_ASSIGN);
		return 0;
	}
	luaL_checktype(L, 2, LUA_TFUNCTION);
	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);
	objc_setAssociatedObject(obj, &kKeys[kTableRefreshKey], @(ref), OBJC_ASSOCIATION_RETAIN);
	return 0;
}

static int bridge_NSScrollView_onRowSelect(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");
	if (lua_isnoneornil(L, 2)) {
		objc_setAssociatedObject(table_scrollview(obj), &kKeys[kTableSelectionKey], nil, OBJC_ASSOCIATION_ASSIGN);
		return 0;
	}
	luaL_checktype(L, 2, LUA_TFUNCTION);
	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);
	objc_setAssociatedObject(table_scrollview(obj), &kKeys[kTableSelectionKey], @(ref), OBJC_ASSOCIATION_RETAIN);
	return 0;
}

static int bridge_NSScrollView_onRowActivate(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table or outline view");
	if (lua_isnoneornil(L, 2)) {
		NSScrollView *_sv = table_scrollview(obj);
		NSTableView *_table = (NSTableView *)_sv.documentView;
		_table.target = nil;
		_table.doubleAction = nil;
		objc_setAssociatedObject(table_scrollview(obj), &kKeys[kTableActivationKey], nil, OBJC_ASSOCIATION_ASSIGN);
		return 0;
	}
	luaL_checktype(L, 2, LUA_TFUNCTION);
	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);
	NSScrollView *_sv = table_scrollview(obj);
	NSTableView *_table = (NSTableView *)_sv.documentView;
	_table.target = src;
	_table.doubleAction = @selector(activateSelectedRow:);
	objc_setAssociatedObject(table_scrollview(obj), &kKeys[kTableActivationKey], @(ref), OBJC_ASSOCIATION_RETAIN);
	return 0;
}
