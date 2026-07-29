/* Instance methods that supplement ordinary Objective-C/KVC dispatch. */
#if defined(GEN_CLASS_FORWARDS)
static int bridge_AppKitControls_vstack(lua_State *L);
static int bridge_AppKitControls_hstack(lua_State *L);
static int bridge_AppKitControls_hsplit(lua_State *L);
static int bridge_AppKitControls_vsplit(lua_State *L);
static int bridge_AppKitControls_separator(lua_State *L);
static int bridge_AppKitControls_spacer(lua_State *L);
static int bridge_AppKitControls_textField(lua_State *L);
static int bridge_AppKitControls_box(lua_State *L);
static int bridge_AppKitControls_progressIndicator(lua_State *L);
static int bridge_AppKitControls_tableCellView(lua_State *L);
static int bridge_AppKitControls_popUpButton(lua_State *L);
static int bridge_AppKitControls_button(lua_State *L);
static int bridge_AppKitControls_toggle(lua_State *L);
static int bridge_NSScrollView_onRefresh(lua_State *L);
static int bridge_NSScrollView_onRowSelect(lua_State *L);
static int bridge_NSScrollView_onRowActivate(lua_State *L);
static int bridge_table_column_widths(lua_State *L);
static int bridge_table_cell_frames(lua_State *L);
static int bridge_toolbar_item(lua_State *L);
static int bridge_canvas_toolbar_items(lua_State *L);
static int bridge_window(lua_State *L);
static int bridge_set_window_workspace(lua_State *L);
static int bridge_image(lua_State *L);
static int bridge_image_viewer(lua_State *L);
static int bridge_system_image(lua_State *L);
static int bridge_system_color(lua_State *L);
static int bridge_tableview(lua_State *L);
static int bridge_action_button(lua_State *L);
static int bridge_panel(lua_State *L);
static int bridge_panel_style_state(lua_State *L);
static int bridge_menu_item(lua_State *L);
static int bridge_text_field_callbacks(lua_State *L);
static int bridge_text_field_test_input(lua_State *L);
static int bridge_text_field_test_command(lua_State *L);
static int bridge_text_view(lua_State *L);
static int bridge_symbol_toggle(lua_State *L);
static int bridge_symbol_button(lua_State *L);
static int bridge_eval(lua_State *L);
static int bridge_tabview(lua_State *L);
static int bridge_segmented_control(lua_State *L);
static int bridge_watch_file(lua_State *L);
static int bridge_pick_folder(lua_State *L);
static int bridge_pick_file(lua_State *L);
static int bridge_outlineview(lua_State *L);
static int bridge_list_directory(lua_State *L);
static int bridge_timer_after(lua_State *L);
static int bridge_http_get(lua_State *L);
static int bridge_json_parse(lua_State *L);
static int bridge_font(lua_State *L);
static int bridge_NSScrollView_onChange_impl(lua_State *L);
static int bridge_NSTabView_addTab_impl(lua_State *L, NSTabView *self, const char * title, NSView * content);
static int bridge_NSTabView_removeTab_impl(lua_State *L, NSTabView *self, NSInteger index);
static int bridge_NSTabView_selectTab_impl(lua_State *L, NSTabView *self, NSInteger index);
static int bridge_NSTabView_tabCount_impl(lua_State *L, NSTabView *self);
static int bridge_NSTabView_onChange_impl(lua_State *L, NSTabView *self, int callback);
static int bridge_NSWindow_addTabbedWindow_impl(lua_State *L);
static int bridge_NSWindow_toggleSidebar_impl(lua_State *L);
static int bridge_NSWindow_focus_impl(lua_State *L);
static int bridge_NSWindow_isFirstResponder_impl(lua_State *L);
static int bridge_NSWindow_workspaceState_impl(lua_State *L);
static int bridge_NSWindow_show_impl(lua_State *L);
static int bridge_NSWindow_presentPanel_impl(lua_State *L);
static int bridge_NSView_renderToPNG_impl(lua_State *L);
static int bridge_NSView_clearContainer_impl(lua_State *L);
static int bridge_NSView_splitProportions_impl(lua_State *L);
#endif /* GEN_CLASS_FORWARDS */

/* --- Auto-generated wrapper functions --- */
#if defined(GEN_CLASS_WRAPPERS)
static int bridge_AppKit_table_column_widths(lua_State *L) {
	return bridge_table_column_widths(L);
}

static int bridge_AppKit_table_cell_frames(lua_State *L) {
	return bridge_table_cell_frames(L);
}

static int bridge_AppKit_toolbar_item(lua_State *L) {
	return bridge_toolbar_item(L);
}

static int bridge_AppKit_canvas_toolbar_items(lua_State *L) {
	return bridge_canvas_toolbar_items(L);
}

static int bridge_AppKit_window(lua_State *L) {
	return bridge_window(L);
}

static int bridge_AppKit_set_window_workspace(lua_State *L) {
	return bridge_set_window_workspace(L);
}

static int bridge_AppKit_image(lua_State *L) {
	return bridge_image(L);
}

static int bridge_AppKit_image_viewer(lua_State *L) {
	return bridge_image_viewer(L);
}

static int bridge_AppKit_system_image(lua_State *L) {
	return bridge_system_image(L);
}

static int bridge_AppKit_system_color(lua_State *L) {
	return bridge_system_color(L);
}

static int bridge_AppKit_tableview(lua_State *L) {
	return bridge_tableview(L);
}

static int bridge_AppKit_action_button(lua_State *L) {
	return bridge_action_button(L);
}

static int bridge_AppKit_panel(lua_State *L) {
	return bridge_panel(L);
}

static int bridge_AppKit_panel_style_state(lua_State *L) {
	return bridge_panel_style_state(L);
}

static int bridge_AppKit_menu_item(lua_State *L) {
	return bridge_menu_item(L);
}

static int bridge_AppKit_text_field_callbacks(lua_State *L) {
	return bridge_text_field_callbacks(L);
}

static int bridge_AppKit_text_field_test_input(lua_State *L) {
	return bridge_text_field_test_input(L);
}

static int bridge_AppKit_text_field_test_command(lua_State *L) {
	return bridge_text_field_test_command(L);
}

static int bridge_AppKit_text_view(lua_State *L) {
	return bridge_text_view(L);
}

static int bridge_AppKit_symbol_toggle(lua_State *L) {
	return bridge_symbol_toggle(L);
}

static int bridge_AppKit_symbol_button(lua_State *L) {
	return bridge_symbol_button(L);
}

static int bridge_AppKit_eval(lua_State *L) {
	return bridge_eval(L);
}

static int bridge_AppKit_tabview(lua_State *L) {
	return bridge_tabview(L);
}

static int bridge_AppKit_segmented_control(lua_State *L) {
	return bridge_segmented_control(L);
}

static int bridge_AppKit_watch_file(lua_State *L) {
	return bridge_watch_file(L);
}

static int bridge_AppKit_pick_folder(lua_State *L) {
	return bridge_pick_folder(L);
}

static int bridge_AppKit_pick_file(lua_State *L) {
	return bridge_pick_file(L);
}

static int bridge_AppKit_outlineview(lua_State *L) {
	return bridge_outlineview(L);
}

static int bridge_AppKit_list_directory(lua_State *L) {
	return bridge_list_directory(L);
}

static int bridge_AppKit_timer_after(lua_State *L) {
	return bridge_timer_after(L);
}

static int bridge_AppKit_http_get(lua_State *L) {
	return bridge_http_get(L);
}

static int bridge_AppKit_json_parse(lua_State *L) {
	return bridge_json_parse(L);
}

static int bridge_AppKit_font(lua_State *L) {
	return bridge_font(L);
}

static int bridge_NSScrollView_onChange(lua_State *L) {
	(void)lua_objc_check_object(L, 1, [NSScrollView class], "TextView");
	if (!lua_isnoneornil(L, 2)) luaL_checktype(L, 2, LUA_TFUNCTION);
	return bridge_NSScrollView_onChange_impl(L);
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
	int callback;
	LUA_OPT_CALLBACK_REF(L, 2, callback);
	return bridge_NSTabView_onChange_impl(L, self, callback);
}

static int bridge_NSWindow_addTabbedWindow(lua_State *L) {
	(void)lua_objc_check_object(L, 1, [NSWindow class], "Window");
	(void)lua_objc_check_object(L, 2, [NSWindow class], "NSWindow");
	(void)luaL_optstring(L, 3, "above");
	return bridge_NSWindow_addTabbedWindow_impl(L);
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

static int bridge_NSWindow_toggleSidebar(lua_State *L) {
	(void)lua_objc_check_object(L, 1, [NSWindow class], "Window");
	return bridge_NSWindow_toggleSidebar_impl(L);
}

static int bridge_NSWindow_dismiss(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSWindow class], "Window");
	NSWindow *self = (NSWindow *)_obj;
	{
		[self orderOut:nil];
		[self.parentWindow removeChildWindow:self];
	}
	return 0;
}

static int bridge_NSWindow_resize(lua_State *L) {
	(void)lua_objc_check_object(L, 1, [NSWindow class], "Window");
	return bridge_object_set_content_size_impl(L);
}

static int bridge_NSWindow_focus(lua_State *L) {
	(void)lua_objc_check_object(L, 1, [NSWindow class], "Window");
	(void)check_view(L, 2);
	return bridge_NSWindow_focus_impl(L);
}

static int bridge_NSWindow_isFirstResponder(lua_State *L) {
	(void)lua_objc_check_object(L, 1, [NSWindow class], "Window");
	(void)check_view(L, 2);
	return bridge_NSWindow_isFirstResponder_impl(L);
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

static int bridge_NSWindow_workspaceState(lua_State *L) {
	(void)lua_objc_check_object(L, 1, [NSWindow class], "Window");
	return bridge_NSWindow_workspaceState_impl(L);
}

static int bridge_NSWindow_show(lua_State *L) {
	(void)lua_objc_check_object(L, 1, [NSWindow class], "Window");
	return bridge_NSWindow_show_impl(L);
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

static int bridge_NSWindow_layout(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSWindow class], "Window");
	NSWindow *self = (NSWindow *)_obj;
	CGFloat width = (CGFloat)luaL_optnumber(L, 2, 400);
	(void)self;
	(void)width;
	{
		return bridge_object_layout_impl(L);
	}
	return 0;
}

static int bridge_NSWindow_presentPanel(lua_State *L) {
	(void)lua_objc_check_object(L, 1, [NSWindow class], "Window");
	(void)lua_objc_check_object(L, 2, [NSWindow class], "NSWindow");
	(void)luaL_optnumber(L, 3, 0);
	return bridge_NSWindow_presentPanel_impl(L);
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

static int bridge_NSView_addSubview(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSView class], "View");
	NSView *self = (NSView *)_obj;
	NSView *view = check_view(L, 2);
	NSInteger positioned = (NSInteger)luaL_checkinteger(L, 3);
	NSView *relativeTo = lua_isnoneornil(L, 4) ? nil : check_view(L, 4);
	[self addSubview:view positioned:positioned relativeTo:relativeTo];
	return 0;
}

static int bridge_NSView_layout(lua_State *L) {
	id _obj = lua_objc_check_object(L, 1, [NSView class], "View");
	NSView *self = (NSView *)_obj;
	CGFloat width = (CGFloat)luaL_optnumber(L, 2, 400);
	(void)self;
	(void)width;
	{
		return bridge_object_layout_impl(L);
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

static int bridge_NSView_renderToPNG(lua_State *L) {
	(void)lua_objc_check_object(L, 1, [NSView class], "View");
	(void)luaL_checkstring(L, 2);
	(void)luaL_optnumber(L, 3, 0);
	(void)luaL_optnumber(L, 4, 0);
	return bridge_NSView_renderToPNG_impl(L);
}

static int bridge_NSView_clearContainer(lua_State *L) {
	(void)lua_objc_check_object(L, 1, [NSView class], "View");
	return bridge_NSView_clearContainer_impl(L);
}

static int bridge_NSView_splitProportions(lua_State *L) {
	(void)lua_objc_check_object(L, 1, [NSView class], "View");
	luaL_checktype(L, 2, LUA_TTABLE);
	return bridge_NSView_splitProportions_impl(L);
}

#endif /* GEN_CLASS_WRAPPERS */

/* --- MethodEntry dispatch arrays --- */
#if defined(GEN_CLASS_ARRAYS)
static MethodEntry LayoutViewMethods[] = {
	{NULL, NULL}
};

static MethodEntry TableMethods[] = {
	{"onRefresh",	bridge_NSScrollView_onRefresh},
	{"onRowSelect",	bridge_NSScrollView_onRowSelect},
	{"onRowActivate",	bridge_NSScrollView_onRowActivate},
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
	{"tabCount",	bridge_NSWindow_tabCount},
	{"toggleSidebar",	bridge_NSWindow_toggleSidebar},
	{"dismiss",	bridge_NSWindow_dismiss},
	{"resize",	bridge_NSWindow_resize},
	{"focus",	bridge_NSWindow_focus},
	{"isFirstResponder",	bridge_NSWindow_isFirstResponder},
	{"selectTab",	bridge_NSWindow_selectTab},
	{"workspaceState",	bridge_NSWindow_workspaceState},
	{"show",	bridge_NSWindow_show},
	{"close",	bridge_NSWindow_close},
	{"add",	bridge_NSWindow_add},
	{"layout",	bridge_NSWindow_layout},
	{"presentPanel",	bridge_NSWindow_presentPanel},
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
	{NULL, NULL}
};

static MethodEntry NativeTextViewMethods[] = {
	{NULL, NULL}
};

static MethodEntry ViewMethods[] = {
	{"addSubview",	bridge_NSView_addSubview},
	{"layout",	bridge_NSView_layout},
	{"add",	bridge_NSView_add},
	{"renderToPNG",	bridge_NSView_renderToPNG},
	{"clearContainer",	bridge_NSView_clearContainer},
	{"splitProportions",	bridge_NSView_splitProportions},
	{NULL, NULL}
};

#endif /* GEN_CLASS_ARRAYS */

/* --- nsview_index dispatch blocks --- */
#if defined(GEN_CLASS_INDEX)
{
	if ([obj isKindOfClass:[NSView class]]) {
		lua_CFunction _m = lookupMethod(key, LayoutViewMethods);
		if (_m) { lua_pushcfunction(L, _m); return 1; }
	}
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
	if ([obj isKindOfClass:[NSTextView class]]) {
		lua_CFunction _m = lookupMethod(key, NativeTextViewMethods);
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
