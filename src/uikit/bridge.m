#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

static char kAxisKey;
static char kFlexibleKey;
static char kTableSourceKey;
static char kCallbackKey;
static char kResizeObserverKey;
static char kPaddingKey;
static char kPaddingHorizontalKey;
static char kPaddingVerticalKey;
static char kPaddingTopKey;
static char kPaddingBottomKey;
static char kAlignmentKey;
static char kFixedWidthKey;
static char kFixedHeightKey;
static char kMinWidthKey;
static char kMinHeightKey;
static char kMaxWidthKey;
static char kMaxHeightKey;
static char kSpacingKey;
static char kFlexGrowKey;
static char kFlexShrinkKey;
static char kFlexBasisKey;
static char kFillWidthKey;
static char kFillHeightKey;
static char kCornerRadiusKey;
static char kIgnoresSafeAreaKey;
static char kImageLayoutSizeKey;
static char kScrollContentKey;
static const CGFloat kImageMaxWidth = 400.0;
static const CGFloat kStackSpacing = 8.0;
static lua_State *gL = NULL;
static int bridge_UIKitNavigation_stack(lua_State *L);
static int bridge_UIKitNavigation_push(lua_State *L);
static int bridge_UIKitNavigation_pop(lua_State *L);

#define LUA_OBJC_EXTERNAL_STATE_OWNER 1
#define LUA_OBJC_HTTP_USER_AGENT \
	@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " \
	@"AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
#define LUA_OBJC_VIEW_CLASS UIView
#define LUA_OBJC_WINDOW_CLASS UIWindow
#define LUA_OBJC_VIEW_METATABLE "uiview"
#define LUA_OBJC_WINDOW_METATABLE "uiwindow"
#define LUA_OBJC_VIEWCONTROLLER_METATABLE "uiviewcontroller"
#include "../shared/lua_bridge_support.m"
#include "../shared/lua_error.m"
#include "../shared/lua_async.m"

#include "table_data_source.m"
#include "action_target.m"
#include "runtime.m"
#include "layout.m"
#include "metatable.m"
#include "views.m"
#include "controls.m"
#include "tables.m"
#include "platform.m"
#include "constructors.m"
#include "hosting.m"
#include "navigation.m"
#pragma mark - Module registration

static const luaL_Reg bridge_lib[] = {
	{"_vstack", bridge_UIKitControls_vstack},
	{"_hstack", bridge_UIKitControls_hstack},
	{"_zstack", bridge_UIKitControls_zstack},
	{"_scrollView", bridge_UIKitControls_scrollView},
	{"_hsplit", bridge_UIKitControls_hsplit},
	{"_spacer", bridge_UIKitControls_spacer},
	{"_textField", bridge_UIKitControls_textField},
	{"_label", bridge_UIKitControls_label},
	{"_separator", bridge_UIKitControls_separator},
	{"_progressIndicator", bridge_UIKitControls_progressIndicator},
	{"_pageControl", bridge_UIKitControls_pageControl},
	{"_linearGradient", bridge_UIKitControls_linearGradient},
	{"_button", bridge_UIKitControls_button},
	{"_toggle", bridge_UIKitControls_toggle},
	{"_slider", bridge_UIKitControls_slider},
	{"_stepper", bridge_UIKitControls_stepper},
	{"_window", bridge_window},
	{"_installScene", bridge_install_scene},
	{"_hostingController", bridge_hosting_controller},
	{"_image", bridge_image},
	{"_imageData", bridge_image_data},
	{"_systemImage", bridge_system_image},
	{"_systemColor", bridge_system_color},
	{"_add", bridge_add},
	{"_layout", bridge_layout},
	{"_setContentSize", bridge_set_content_size},
	{"_tableview", bridge_tableview},
	{"_show", bridge_show},
	{"_font", bridge_font},
	{"_timerAfter", bridge_timer_after},
	{"_httpGet", bridge_http_get},
	{"_jsonParse", bridge_json_parse},
	{"_tabview", bridge_tabview},
	{"_tabViewAddTab", bridge_UIKitTabView_addTab},
	{"_tabViewSelectTab", bridge_UIKitTabView_selectTab},
	{"_tabViewTabCount", bridge_UIKitTabView_tabCount},
	{"_tabViewOnChange", bridge_UIKitTabView_onChange},
	{"_navigationStack", bridge_UIKitNavigation_stack},
	{NULL, NULL},
};

static void register_metatable(lua_State *L, const char *name) {
	luaL_newmetatable(L, name);
	lua_pushcfunction(L, gc_objc);
	lua_setfield(L, -2, "__gc");
	lua_pushcfunction(L, nsview_index);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, nsview_newindex);
	lua_setfield(L, -2, "__newindex");
	lua_pop(L, 1);
}

int luaopen_UIKitNative(lua_State *L) {
	gL = L;
	install_external_lua_state_owner(L);

	register_metatable(L, "uiview");
	register_metatable(L, "uiwindow");
	register_metatable(L, "uiviewcontroller");
	register_metatable(L, "nsobject");
	luaL_newlib(L, bridge_lib);
	return 1;
}
