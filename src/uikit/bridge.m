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
static char kAlignmentKey;
static char kFixedWidthKey;
static char kFixedHeightKey;
static const CGFloat kStackSpacing = 8.0;
static lua_State *gL = NULL;

#define LUA_OBJC_EXTERNAL_STATE_OWNER 1
#define LUA_OBJC_HTTP_USER_AGENT \
	@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " \
	@"AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
#define LUA_OBJC_VIEW_CLASS UIView
#define LUA_OBJC_WINDOW_CLASS UIWindow
#define LUA_OBJC_VIEW_METATABLE "uiview"
#define LUA_OBJC_WINDOW_METATABLE "uiwindow"
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
#include "generated/bridge_funcs.m"
#pragma mark - Module registration

static const luaL_Reg bridge_lib[] = {
#define GEN_BRIDGE_LIB
#include "generated/bridge_lib.inc"
#undef GEN_BRIDGE_LIB
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
	register_metatable(L, "nsobject");
	luaL_newlib(L, bridge_lib);
	return 1;
}
