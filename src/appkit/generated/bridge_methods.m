/* AUTO-GENERATED — do not edit by hand.
 * Regenerate with:  python3 tools/gen_bridge.py --xml tools/bridge.xml
 * Source:           tools/bridge.xml
 */

/* --- method C function forward declarations --- */
/* #include with GEN_METHODS_FORWARDS defined, before runtime.m method tables */
#if defined(GEN_METHODS_FORWARDS)
static int bridge_text_view_set_text(lua_State *L);
static int bridge_text_view_get_text(lua_State *L);
static int bridge_text_view_set_language(lua_State *L);
static int bridge_text_view_set_wrap_mode(lua_State *L);
static int bridge_text_view_on_change(lua_State *L);
static int bridge_tab_add(lua_State *L);
static int bridge_tab_remove(lua_State *L);
static int bridge_tab_select(lua_State *L);
static int bridge_tab_count(lua_State *L);
static int bridge_tab_on_change(lua_State *L);
static int bridge_add_tabbed_window(lua_State *L);
static int bridge_set_window_tabbing(lua_State *L);
static int bridge_window_tab_count(lua_State *L);
static int bridge_toggle_sidebar(lua_State *L);
static int bridge_dismiss_window(lua_State *L);
static int bridge_set_content_size(lua_State *L);
static int bridge_set_window_min_size(lua_State *L);
static int bridge_set_appearance(lua_State *L);
static int bridge_focus(lua_State *L);
static int bridge_is_first_responder(lua_State *L);
static int bridge_select_window_tab(lua_State *L);
static int bridge_window_workspace_state(lua_State *L);
static int bridge_show(lua_State *L);
static int bridge_add(lua_State *L);
static int bridge_layout(lua_State *L);
static int bridge_view_size(lua_State *L);
static int bridge_layout(lua_State *L);
static int bridge_view_size(lua_State *L);
static int bridge_view_frame_in_window(lua_State *L);
static int bridge_add(lua_State *L);
static int bridge_render_to_png(lua_State *L);
static int bridge_clear_container(lua_State *L);
static int bridge_split_set_proportions(lua_State *L);
static int bridge_set_content_size(lua_State *L);
static int bridge_callback(lua_State *L);
#endif /* GEN_METHODS_FORWARDS */

/* --- MethodEntry arrays for each method group --- */
/* #include with GEN_METHODS_ARRAYS defined, before nsview_index */
#if defined(GEN_METHODS_ARRAYS)
static MethodEntry TextViewMethods[] = {
	{"setText",	bridge_text_view_set_text},
	{"getText",	bridge_text_view_get_text},
	{"setLanguage",	bridge_text_view_set_language},
	{"setWrapMode",	bridge_text_view_set_wrap_mode},
	{"onChange",	bridge_text_view_on_change},
	{NULL, NULL}
};

static MethodEntry TabViewMethods[] = {
	{"addTab",	bridge_tab_add},
	{"removeTab",	bridge_tab_remove},
	{"selectTab",	bridge_tab_select},
	{"tabCount",	bridge_tab_count},
	{"onChange",	bridge_tab_on_change},
	{NULL, NULL}
};

static MethodEntry WindowMethods[] = {
	{"addTabbedWindow",	bridge_add_tabbed_window},
	{"setTabbing",	bridge_set_window_tabbing},
	{"tabCount",	bridge_window_tab_count},
	{"toggleSidebar",	bridge_toggle_sidebar},
	{"dismiss",	bridge_dismiss_window},
	{"setContentSize",	bridge_set_content_size},
	{"setMinSize",	bridge_set_window_min_size},
	{"setAppearance",	bridge_set_appearance},
	{"focus",	bridge_focus},
	{"isFirstResponder",	bridge_is_first_responder},
	{"selectTab",	bridge_select_window_tab},
	{"workspaceState",	bridge_window_workspace_state},
	{"show",	bridge_show},
	{"add",	bridge_add},
	{"layout",	bridge_layout},
	{"size",	bridge_view_size},
	{NULL, NULL}
};

static MethodEntry ViewMethods[] = {
	{"layout",	bridge_layout},
	{"size",	bridge_view_size},
	{"frameInWindow",	bridge_view_frame_in_window},
	{"add",	bridge_add},
	{"renderToPNG",	bridge_render_to_png},
	{"clearContainer",	bridge_clear_container},
	{"splitProportions",	bridge_split_set_proportions},
	{"setContentSize",	bridge_set_content_size},
	{"setCallback",	bridge_callback},
	{NULL, NULL}
};

#endif /* GEN_METHODS_ARRAYS */

/* --- nsview_index dispatch blocks --- */
/* #include with GEN_METHODS_INDEX defined, inside nsview_index body */
#if defined(GEN_METHODS_INDEX)
{
	id _sentinel_text_view = objc_getAssociatedObject(obj, &kKeys[kTextViewSourceKey]);
	if (_sentinel_text_view) {
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
	if ([obj isKindOfClass:[NSView class]]) {
		lua_CFunction _m = lookupMethod(key, ViewMethods);
		if (_m) { lua_pushcfunction(L, _m); return 1; }
	}
}

#endif /* GEN_METHODS_INDEX */
