/* AUTO-GENERATED — do not edit by hand.
 * Regenerate with:  python3 tools/gen_bridge.py --xml tools/UIKit.xml
 * Source:           tools/UIKit.xml
 */

/* --- _impl forward declarations --- */
#if defined(GEN_CLASS_FORWARDS)
static int bridge_UIKitControls_vstack(lua_State *L);
static int bridge_UIKitControls_hstack(lua_State *L);
static int bridge_UIKitControls_hsplit(lua_State *L);
static int bridge_UIKitControls_spacer(lua_State *L);
static int bridge_UIKitControls_button(lua_State *L);
static int bridge_UIKitControls_toggle(lua_State *L);
static int bridge_window(lua_State *L);
static int bridge_image(lua_State *L);
static int bridge_add(lua_State *L);
static int bridge_layout(lua_State *L);
static int bridge_set_content_size(lua_State *L);
static int bridge_tableview(lua_State *L);
static int bridge_show(lua_State *L);
static int bridge_create(lua_State *L);
static int bridge_font(lua_State *L);
static int bridge_perform(lua_State *L);
static int bridge_callback(lua_State *L);
static int bridge_timer_after(lua_State *L);
static int bridge_http_get(lua_State *L);
static int bridge_json_parse(lua_State *L);
#endif /* GEN_CLASS_FORWARDS */

/* --- Auto-generated wrapper functions --- */
#if defined(GEN_CLASS_WRAPPERS)
static int bridge_UIKit_window(lua_State *L) {
	return bridge_window(L);
}

static int bridge_UIKit_image(lua_State *L) {
	return bridge_image(L);
}

static int bridge_UIKit_add(lua_State *L) {
	return bridge_add(L);
}

static int bridge_UIKit_layout(lua_State *L) {
	return bridge_layout(L);
}

static int bridge_UIKit_set_content_size(lua_State *L) {
	return bridge_set_content_size(L);
}

static int bridge_UIKit_tableview(lua_State *L) {
	return bridge_tableview(L);
}

static int bridge_UIKit_show(lua_State *L) {
	return bridge_show(L);
}

static int bridge_UIKit_create(lua_State *L) {
	return bridge_create(L);
}

static int bridge_UIKit_font(lua_State *L) {
	return bridge_font(L);
}

static int bridge_UIKit_perform(lua_State *L) {
	return bridge_perform(L);
}

static int bridge_UIKit_callback(lua_State *L) {
	return bridge_callback(L);
}

static int bridge_UIKit_timer_after(lua_State *L) {
	return bridge_timer_after(L);
}

static int bridge_UIKit_http_get(lua_State *L) {
	return bridge_http_get(L);
}

static int bridge_UIKit_json_parse(lua_State *L) {
	return bridge_json_parse(L);
}

#endif /* GEN_CLASS_WRAPPERS */

/* --- MethodEntry dispatch arrays --- */
#if defined(GEN_CLASS_ARRAYS)
static MethodEntry LayoutViewMethods[] = {
	{NULL, NULL}
};

#endif /* GEN_CLASS_ARRAYS */

/* --- nsview_index dispatch blocks --- */
#if defined(GEN_CLASS_INDEX)
{
	if ([obj isKindOfClass:[UIView class]]) {
		lua_CFunction _m = lookupMethod(key, LayoutViewMethods);
		if (_m) { lua_pushcfunction(L, _m); return 1; }
	}
}

#endif /* GEN_CLASS_INDEX */
