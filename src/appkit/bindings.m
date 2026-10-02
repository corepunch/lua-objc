/* Instance methods that supplement ordinary Objective-C/KVC dispatch. */
#if defined(GEN_CLASS_FORWARDS)
static int bridge_navigation_push(lua_State *L);
static int bridge_navigation_pop(lua_State *L);
static int bridge_NSScrollView_onRefresh(lua_State *L);
static int bridge_NSScrollView_onRowSelect(lua_State *L);
static int bridge_NSScrollView_onRowMove(lua_State *L);
static int bridge_NSScrollView_onRowSwipe(lua_State *L);
static int bridge_NSScrollView_onRowActivate(lua_State *L);
static int bridge_NSScrollView_onColumnSort(lua_State *L);
static int bridge_NSScrollView_onColumnButton(lua_State *L);
static int bridge_NSScrollView_onRowMenu(lua_State *L);
static int bridge_NSScrollView_setDragKey(lua_State *L);
static int bridge_NSScrollView_setSortIndicator(lua_State *L);
static int bridge_NSScrollView_onChange(lua_State *L);
static int bridge_NSTabView_addTab_impl(lua_State *L, NSTabView *self, const char * title, NSView * content);
static int bridge_NSTabView_removeTab_impl(lua_State *L, NSTabView *self, NSInteger index);
static int bridge_NSTabView_selectTab_impl(lua_State *L, NSTabView *self, NSInteger index);
static int bridge_NSTabView_tabCount_impl(lua_State *L, NSTabView *self);
static int bridge_NSTabView_onChange_impl(lua_State *L, NSTabView *self, LuaReg *callback);
static int bridge_NSWindow_addTabbedWindow(lua_State *L);
static int bridge_NSWindow_toggleSidebar(lua_State *L);
static int bridge_NSWindow_toggleDetail(lua_State *L);
static int bridge_NSWindow_focus(lua_State *L);
static int bridge_NSWindow_isFirstResponder(lua_State *L);
static int bridge_NSWindow_workspaceState(lua_State *L);
static int bridge_NSWindow_show(lua_State *L);
static int bridge_NSWindow_presentPanel(lua_State *L);
static BOOL write_window_capture(NSWindow *window, const char *prefix);
static int bridge_NSView_clearContainer(lua_State *L);
static int bridge_NSView_splitProportions(lua_State *L);
#endif /* GEN_CLASS_FORWARDS */

/* --- Argument-unpacking wrappers --- */
#if defined(GEN_CLASS_WRAPPERS)

static int bridge_LuaPathView_moveTo(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [LuaPathView class], "PathView");
	LuaPathView *self = (LuaPathView *)_obj;
	CGFloat x = (CGFloat)luaL_checknumber(L, 2);
	CGFloat y = (CGFloat)luaL_checknumber(L, 3);
	[self.path moveToPoint:NSMakePoint(x, y)];
	[self setNeedsDisplay:YES];
	return 0;
}

static int bridge_LuaPathView_lineTo(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [LuaPathView class], "PathView");
	LuaPathView *self = (LuaPathView *)_obj;
	CGFloat x = (CGFloat)luaL_checknumber(L, 2);
	CGFloat y = (CGFloat)luaL_checknumber(L, 3);
	[self.path lineToPoint:NSMakePoint(x, y)];
	[self setNeedsDisplay:YES];
	return 0;
}

static int bridge_LuaPathView_curveTo(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [LuaPathView class], "PathView");
	LuaPathView *self = (LuaPathView *)_obj;
	CGFloat cp1x = (CGFloat)luaL_checknumber(L, 2);
	CGFloat cp1y = (CGFloat)luaL_checknumber(L, 3);
	CGFloat cp2x = (CGFloat)luaL_checknumber(L, 4);
	CGFloat cp2y = (CGFloat)luaL_checknumber(L, 5);
	CGFloat endX = (CGFloat)luaL_checknumber(L, 6);
	CGFloat endY = (CGFloat)luaL_checknumber(L, 7);
	[self.path curveToPoint:NSMakePoint(endX, endY)
		controlPoint1:NSMakePoint(cp1x, cp1y)
		controlPoint2:NSMakePoint(cp2x, cp2y)];
	[self setNeedsDisplay:YES];
	return 0;
}

static int bridge_LuaPathView_closePath(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [LuaPathView class], "PathView");
	LuaPathView *self = (LuaPathView *)_obj;
	[self.path closePath];
	[self setNeedsDisplay:YES];
	return 0;
}

static int bridge_LuaPathView_clear(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [LuaPathView class], "PathView");
	LuaPathView *self = (LuaPathView *)_obj;
	[self.path removeAllPoints];
	[self setNeedsDisplay:YES];
	return 0;
}

static int bridge_LuaPathView_setStrokeColor(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [LuaPathView class], "PathView");
	LuaPathView *self = (LuaPathView *)_obj;
	CGFloat r = (CGFloat)luaL_checknumber(L, 2);
	CGFloat g = (CGFloat)luaL_checknumber(L, 3);
	CGFloat b = (CGFloat)luaL_checknumber(L, 4);
	CGFloat a = (CGFloat)luaL_optnumber(L, 5, 1.0);
	self.strokeColor = [NSColor colorWithRed:r green:g blue:b alpha:a];
	[self setNeedsDisplay:YES];
	return 0;
}

static int bridge_LuaPathView_setFillColor(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [LuaPathView class], "PathView");
	LuaPathView *self = (LuaPathView *)_obj;
	CGFloat r = (CGFloat)luaL_checknumber(L, 2);
	CGFloat g = (CGFloat)luaL_checknumber(L, 3);
	CGFloat b = (CGFloat)luaL_checknumber(L, 4);
	CGFloat a = (CGFloat)luaL_optnumber(L, 5, 1.0);
	self.fillColor = [NSColor colorWithRed:r green:g blue:b alpha:a];
	[self setNeedsDisplay:YES];
	return 0;
}

static int bridge_LuaPathView_setLineWidth(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [LuaPathView class], "PathView");
	LuaPathView *self = (LuaPathView *)_obj;
	CGFloat w = (CGFloat)luaL_checknumber(L, 2);
	self.lineWidth = w;
	[self setNeedsDisplay:YES];
	return 0;
}

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
	return bridge_NSTabView_onChange_impl(L, self, lua_reg_opt(L, 2));
}

/* window:capture(prefix) writes <prefix>.png and <prefix>.layout.xml, like
 * --capture, so a --capture-plan can capture several states in one run. */
static int bridge_NSWindow_capture(lua_State *L) {
	NSWindow *window = (NSWindow *)lua_objc_check_object(L, 1, [NSWindow class], "Window");
	const char *prefix = luaL_checkstring(L, 2);
	if (!write_window_capture(window, prefix)) return luaL_error(L, "capture: cannot write %s", prefix);
	return 0;
}

static int bridge_NSWindow_tabCount(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSWindow class], "Window");
	NSWindow *self = (NSWindow *)_obj;
	{
		lua_pushinteger(L, (lua_Integer)self.tabbedWindows.count);
		return 1;
	}
	return 0;
}

static int bridge_NSWindow_dismiss(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSWindow class], "Window");
	NSWindow *self = (NSWindow *)_obj;
	{
		if (self.sheetParent) [self.sheetParent endSheet:self];
		[self orderOut:nil];
		[self.parentWindow removeChildWindow:self];
	}
	return 0;
}

static int bridge_NSWindow_selectTab(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSWindow class], "Window");
	NSWindow *self = (NSWindow *)_obj;
	{
		if (self.tabGroup) {
			self.tabGroup.selectedWindow = self;
		}
		if (self.isVisible) {
			[self makeKeyAndOrderFront:nil];
		}
	}
	return 0;
}

/* Orders the window out without closing it, so its Lua state, timers and
 * views stay alive until it is shown again. */
static int bridge_NSWindow_hide(lua_State *L) {
	NSWindow *self = lua_objc_check_object(L, 1, [NSWindow class], "Window");
	[self orderOut:nil];
	return 0;
}

static int bridge_NSWindow_close(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSWindow class], "Window");
	NSWindow *self = (NSWindow *)_obj;
	[self close];
	return 0;
}

static int bridge_NSWindow_add(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSWindow class], "Window");
	NSWindow *self = (NSWindow *)_obj;
	NSView *view = check_view(L, 2);
	(void)self;
	(void)view;
	{
		return bridge_object_add_impl(L);
	}
	return 0;
}

// beginSheet requires two arguments including a block, beyond generic _perform.
static int bridge_NSWindow_presentSheet(lua_State *L) {
	NSWindow *sheet = lua_objc_check_object(L, 1, [NSWindow class], "Window");
	NSWindow *parent = lua_objc_check_object(L, 2, [NSWindow class], "Window");
	if (parent == sheet || parent.attachedSheet || sheet.sheetParent) return luaL_error(L, "sheet or parent is already presenting");
	sheet.level = NSNormalWindowLevel;
	sheet.appearance = parent.appearance;
	[parent beginSheet:sheet completionHandler:nil];
	return 0;
}

static int bridge_NSTextField_sizeToFit(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSTextField class], "TextField");
	NSTextField *self = (NSTextField *)_obj;
	[self sizeToFit];
	return 0;
}

static int bridge_NSProgressIndicator_start(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSProgressIndicator class], "ProgressIndicator");
	NSProgressIndicator *self = (NSProgressIndicator *)_obj;
	{
		[self startAnimation:nil];
	}
	return 0;
}

static int bridge_NSProgressIndicator_stop(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSProgressIndicator class], "ProgressIndicator");
	NSProgressIndicator *self = (NSProgressIndicator *)_obj;
	{
		[self stopAnimation:nil];
	}
	return 0;
}

static int bridge_NSPopUpButton_addItemsWithTitles(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSPopUpButton class], "PopUpButton");
	NSPopUpButton *self = (NSPopUpButton *)_obj;
	luaL_checktype(L, 2, LUA_TTABLE);
	id titles = lua_to_objc_value(L, 2);
	[self addItemsWithTitles:titles];
	return 0;
}

static int bridge_NSPopUpButton_selectIndex(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSPopUpButton class], "PopUpButton");
	NSPopUpButton *self = (NSPopUpButton *)_obj;
	NSInteger index = (NSInteger)luaL_checkinteger(L, 2);
	if (index >= 0 && index < self.numberOfItems) {
		[self selectItemAtIndex:index];
	}
	return 0;
}

static int bridge_NSView_addSubview(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSView class], "View");
	NSView *self = (NSView *)_obj;
	NSView *view = check_view(L, 2);
	NSInteger positioned = (NSInteger)luaL_checkinteger(L, 3);
	NSView *relativeTo = lua_isnoneornil(L, 4) ? nil : check_view(L, 4);
	[self addSubview:view positioned:positioned relativeTo:relativeTo];
	return 0;
}

static int bridge_NSView_scrollIntoView(lua_State *L) {
	NSView *view = check_view(L, 1);
	NSScrollView *scroll = view.enclosingScrollView;
	if (scroll) {
		NSRect target = [scroll.documentView convertRect:view.bounds fromView:view];
		NSPoint origin = scroll.contentView.bounds.origin;
		origin.y = scroll.documentView.isFlipped ? NSMinY(target) : NSMaxY(target) - scroll.contentSize.height;
		[scroll.contentView scrollToPoint:origin];
		[scroll reflectScrolledClipView:scroll.contentView];
	}
	return 0;
}

static int bridge_NSView_add(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSView class], "View");
	NSView *self = (NSView *)_obj;
	NSView *view = check_view(L, 2);
	(void)self;
	(void)view;
	{
		return bridge_object_add_impl(L);
	}
	return 0;
}

#endif /* GEN_CLASS_WRAPPERS */

/* --- MethodEntry dispatch arrays --- */
#if defined(GEN_CLASS_ARRAYS)
static MethodEntry TableMethods[] = {
	{"onRefresh",	bridge_NSScrollView_onRefresh},
	{"onRowSelect",	bridge_NSScrollView_onRowSelect},
	{"onRowMove",	bridge_NSScrollView_onRowMove},
	{"onRowSwipe",	bridge_NSScrollView_onRowSwipe},
	{"onRowActivate",	bridge_NSScrollView_onRowActivate},
	{"onColumnSort",	bridge_NSScrollView_onColumnSort},
	{"onColumnButton",	bridge_NSScrollView_onColumnButton},
	{"onRowMenu",	bridge_NSScrollView_onRowMenu},
	{"setDragKey",	bridge_NSScrollView_setDragKey},
	{"setSortIndicator",	bridge_NSScrollView_setSortIndicator},
	{NULL, NULL}
};

static MethodEntry TextViewMethods[] = {
	{"onChange",	bridge_NSScrollView_onChange},
	{NULL, NULL}
};

static MethodEntry TabViewMethods[] = {
	{"addTab",	bridge_NSTabView_addTab},
	{"removeTab",	bridge_NSTabView_removeTab},
	{"selectTab",	bridge_NSTabView_selectTab},
	{"tabCount",	bridge_NSTabView_tabCount},
	{"onChange",	bridge_NSTabView_onChange},
	{NULL, NULL}
};

static MethodEntry WindowMethods[] = {
	{"addTabbedWindow",	bridge_NSWindow_addTabbedWindow},
	{"capture",	bridge_NSWindow_capture},
	{"tabCount",	bridge_NSWindow_tabCount},
	{"toggleSidebar",	bridge_NSWindow_toggleSidebar},
	{"toggleDetail",	bridge_NSWindow_toggleDetail},
	{"dismiss",	bridge_NSWindow_dismiss},
	{"resize",	bridge_object_set_content_size},
	{"focus",	bridge_NSWindow_focus},
	{"isFirstResponder",	bridge_NSWindow_isFirstResponder},
	{"selectTab",	bridge_NSWindow_selectTab},
	{"workspaceState",	bridge_NSWindow_workspaceState},
	{"show",	bridge_NSWindow_show},
	{"close",	bridge_NSWindow_close},
	{"hide",	bridge_NSWindow_hide},
	{"add",	bridge_NSWindow_add},
	{"layout",	bridge_object_layout},
	{"presentPanel",	bridge_NSWindow_presentPanel},
	{"presentSheet",	bridge_NSWindow_presentSheet},
	{NULL, NULL}
};

static MethodEntry TextFieldMethods[] = {
	{"sizeToFit",	bridge_NSTextField_sizeToFit},
	{NULL, NULL}
};

static MethodEntry ProgressIndicatorMethods[] = {
	{"start",	bridge_NSProgressIndicator_start},
	{"stop",	bridge_NSProgressIndicator_stop},
	{NULL, NULL}
};

static MethodEntry PopUpButtonMethods[] = {
	{"addItemsWithTitles",	bridge_NSPopUpButton_addItemsWithTitles},
	{"selectIndex",	bridge_NSPopUpButton_selectIndex},
	{NULL, NULL}
};

static MethodEntry ViewMethods[] = {
	{"addSubview",	bridge_NSView_addSubview},
	{"layout",	bridge_object_layout},
	{"add",	bridge_NSView_add},
	{"clearContainer",	bridge_NSView_clearContainer},
	{"scrollIntoView", bridge_NSView_scrollIntoView},
	{"splitProportions",	bridge_NSView_splitProportions},
	{NULL, NULL}
};

static MethodEntry PathViewMethods[] = {
	{"moveTo",	bridge_LuaPathView_moveTo},
	{"lineTo",	bridge_LuaPathView_lineTo},
	{"curveTo",	bridge_LuaPathView_curveTo},
	{"closePath",	bridge_LuaPathView_closePath},
	{"clear",	bridge_LuaPathView_clear},
	{"setStrokeColor",	bridge_LuaPathView_setStrokeColor},
	{"setFillColor",	bridge_LuaPathView_setFillColor},
	{"setLineWidth",	bridge_LuaPathView_setLineWidth},
	{NULL, NULL}
};

#endif /* GEN_CLASS_ARRAYS */

/* --- nsview_index dispatch blocks --- */
#if defined(GEN_CLASS_INDEX)
if (objc_getAssociatedObject(obj, &kKeys[kNavigationControllerKey])) {
	if (strcmp(key, "push") == 0) { lua_pushcfunction(L, bridge_navigation_push); return 1; }
	if (strcmp(key, "pop") == 0) { lua_pushcfunction(L, bridge_navigation_pop); return 1; }
}
{
	id _sentinel_nsscrollview = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (_sentinel_nsscrollview) {
		lua_CFunction _m = lookupMethod(key, TableMethods);
		if (_m) { lua_pushcfunction(L, _m); return 1; }
	}
}

{
	id _sentinel_nsscrollview = objc_getAssociatedObject(obj, &kKeys[kTextViewSourceKey]);
	if (_sentinel_nsscrollview) {
		lua_CFunction _m = lookupMethod(key, TextViewMethods);
		if (_m) { lua_pushcfunction(L, _m); return 1; }
	}
}

{
	if ([obj isKindOfClass:[NSTabView class]]) {
		lua_CFunction _m = lookupMethod(key, TabViewMethods);
		if (_m) { lua_pushcfunction(L, _m); return 1; }
	}
}

{
	if ([obj isKindOfClass:[NSWindow class]]) {
		lua_CFunction _m = lookupMethod(key, WindowMethods);
		if (_m) { lua_pushcfunction(L, _m); return 1; }
	}
}

{
	if ([obj isKindOfClass:[NSTextField class]]) {
		lua_CFunction _m = lookupMethod(key, TextFieldMethods);
		if (_m) { lua_pushcfunction(L, _m); return 1; }
	}
}

{
	if ([obj isKindOfClass:[NSProgressIndicator class]]) {
		lua_CFunction _m = lookupMethod(key, ProgressIndicatorMethods);
		if (_m) { lua_pushcfunction(L, _m); return 1; }
	}
}

{
	if ([obj isKindOfClass:[NSPopUpButton class]]) {
		lua_CFunction _m = lookupMethod(key, PopUpButtonMethods);
		if (_m) { lua_pushcfunction(L, _m); return 1; }
	}
}

{
	if ([obj isKindOfClass:[NSScrollView class]] && strcmp(key, "scrollTo") == 0) {
		lua_pushcfunction(L, bridge_NSScrollView_scrollTo);
		return 1;
	}
}

{
	if ([obj isKindOfClass:[LuaArcView class]]) {
		if (strcmp(key, "arcBounds") == 0) {
			lua_pushcfunction(L, bridge_LuaArcView_arcBounds);
			return 1;
		}
	}
}

{
	if ([obj isKindOfClass:[LuaPathView class]]) {
		lua_CFunction _m = lookupMethod(key, PathViewMethods);
		if (_m) { lua_pushcfunction(L, _m); return 1; }
	}
}

{
	if ([obj isKindOfClass:[NSView class]]) {
		lua_CFunction _m = lookupMethod(key, ViewMethods);
		if (_m) { lua_pushcfunction(L, _m); return 1; }
	}
}

#endif /* GEN_CLASS_INDEX */
