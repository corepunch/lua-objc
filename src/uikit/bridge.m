#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Security/Security.h>
#import <QuartzCore/QuartzCore.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

static char kAxisKey;
static char kWindowCloseKey;
static char kTextFieldDelegateKey;
static char kFlexibleKey;
static char kTableSourceKey;
static char kCallbackKey;
static char kResizeObserverKey;
static char kPaddingKey;
static char kPaddingHorizontalKey;
static char kPaddingLeadingKey;
static char kPaddingTrailingKey;
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
static char kHostSafeAreaTopKey;
static char kImageLayoutSizeKey;
static char kScrollContentKey;
static char kButtonContentKey;
static const CGFloat kImageMaxWidth = 400.0;
static const CGFloat kStackSpacing = 8.0;
static const CGFloat kSeparatorThickness = 1.0;
static const CGFloat kPreviewWidth = 393.0;
static const CGFloat kPreviewHeight = 740.0;
static const CGFloat kPreviewBezel = 10.0;
static const CGFloat kPreviewScreenRadius = 42.0;
static const CGFloat kPreviewMargin = 8.0;
static const CGFloat kPreviewTrimWidth = 2.0;
static const CGFloat kSidebarIconSize = 20.0;
static const CGFloat kSidebarIconSlotWidth = 32.0;
static const CGFloat kSidebarRowPadding = 8.0;
static const CGFloat kSidebarExpandedPadding = 12.0;
static const CGFloat kSidebarCollapsedPadding = 8.0;
static const CGFloat kSidebarExpandedWidth = 208.0;
static const CGFloat kSidebarCompactWidth = 184.0;
static const CGFloat kSidebarCollapsedWidth = 64.0;
static const CGFloat kBenchmarkScrollPointsPerSecond = 1500.0;
static const CGFloat kBenchmarkMinimumFrameRate = 60.0;
static const CGFloat kBenchmarkPreferredFrameRate = 120.0;
static const CGFloat kBenchmarkHitchFrameCount = 2.0;
static const NSTimeInterval kBenchmarkDuration = 4.0;
static const NSTimeInterval kBenchmarkTraceDuration = 30.0;
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
#include "../shared/performance_signpost.m"
#include "../shared/lua_dealloc_watch.m"

#include "table_data_source.m"
#include "action_target.m"
#include "runtime.m"
#include "../shared/flow_layout.m"
#include "layout.m"
#include "metatable.m"
#include "views.m"
#include "controls.m"
#include "tables.m"
#include "platform.m"
#include "constructors.m"
#include "text_field.m"
#include "hosting.m"
#include "preview.m"
#include "workspace.m"
#include "navigation.m"
#include "private_navigation_palettes.m"
#include "performance_probe.m"
#include "presentation.m"
#include "../shared/parity_batch.m"
#include "parity_batch.m"
#pragma mark - Module registration

static const luaL_Reg bridge_lib[] = {
	{"Size", bridge_CGSize},
	{"Point", bridge_CGPoint},
	{"Rect", bridge_CGRect},
	{"_preview", bridge_preview},
	{"_documentRead", bridge_document_read},
	{"_documentWrite", bridge_document_write},
	{"_credential", bridge_credential},
	{"_jsonEncode", bridge_json_encode},
	{"_httpRequest", bridge_http_request},
	{"_cancelRequest", bridge_cancel_request},
	{"_focus", bridge_focus},
	{"_hitTestTarget", bridge_hit_test_target},
	{"_parityMeasure", bridge_parity_measure},
	{"_parityWrite", bridge_parity_write},
	{"_parityJSON", bridge_parity_json},
	{"_parityReadJSON", bridge_parity_read_json},
	{"_parityDocumentsDirectory", bridge_parity_documents},
	{"_vstack", bridge_UIKitControls_vstack},
	{"_hstack", bridge_UIKitControls_hstack},
	{"_flowStack", bridge_UIKitControls_flowStack},
	{"_zstack", bridge_UIKitControls_zstack},
	{"_scrollView", bridge_UIKitControls_scrollView},
	{"_hsplit", bridge_UIKitControls_hsplit},
	{"_spacer", bridge_UIKitControls_spacer},
	{"_textFieldCallbacks", bridge_text_field_callbacks},
	{"_textFieldTestInput", bridge_text_field_test_input},
	{"_textFieldTestCommand", bridge_text_field_test_command},
	{"_textField", bridge_UIKitControls_textField},
	{"_searchField", bridge_UIKitControls_searchField},
	{"_textEditor", bridge_UIKitControls_textEditor},
	{"_label", bridge_UIKitControls_label},
	{"_separator", bridge_UIKitControls_separator},
	{"_progressIndicator", bridge_UIKitControls_progressIndicator},
	{"_progressView", bridge_UIKitControls_progressView},
	{"_pageControl", bridge_UIKitControls_pageControl},
	{"_linearGradient", bridge_UIKitControls_linearGradient},
	{"_button", bridge_UIKitControls_button},
	{"_link", bridge_UIKitControls_link},
	{"_menu", bridge_UIKitControls_menu},
	{"_materialView", bridge_UIKitControls_materialView},
	{"_glassEffect", bridge_UIKitControls_glassEffect},
	{"_webView", bridge_UIKitControls_webView},
	{"_webViewAction", bridge_UIKitControls_webViewAction},
	{"_hapticsAvailable", bridge_UIKit_hapticsAvailable},
	{"_reduceMotionEnabled", bridge_UIKit_reduceMotionEnabled},
	{"_hapticImpact", bridge_UIKit_hapticImpact},
	{"_hapticSelection", bridge_UIKit_hapticSelection},
	{"_hapticNotification", bridge_UIKit_hapticNotification},
	{"_addTap", bridge_UIKit_addTap},
	{"_addDrag", bridge_UIKit_addDrag},
	{"_toggle", bridge_UIKitControls_toggle},
	{"_slider", bridge_UIKitControls_slider},
	{"_stepper", bridge_UIKitControls_stepper},
	{"_picker", bridge_UIKitControls_picker},
	{"_datePicker", bridge_UIKitControls_datePicker},
	{"_colorPicker", bridge_UIKitControls_colorPicker},
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
	{"_testRowSwipe", bridge_test_row_swipe},
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
	{"_navigationPalette", bridge_UIKitNavigation_palette},
	{"_benchmarkScroll", bridge_UIKitBenchmark_scroll},
	{"_benchmarkStart", bridge_UIKitBenchmark_start},
	{"_navigationLink", bridge_UIKitNavigation_link},
	{"_presentSheet", bridge_UIKitPresentation_presentSheet},
	{"_dismiss", bridge_UIKitPresentation_dismiss},
	{"_confirm", bridge_UIKitPresentation_confirm},
	{"_setCurrentScope", bridge_set_current_scope},
	{"_invokeAction", bridge_invoke_action},
	{"_onWindowClose", bridge_on_window_close},
	{"_invalidateHandle", bridge_invalidate_handle},
	{"_watchDealloc", bridge_dealloc_watch},
	{"_deallocCount", bridge_dealloc_count},
	{"_deallocReset", bridge_dealloc_reset},
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
	install_external_lua_state_owner(L);
	lua_objc_init_handles(L);
	register_luareg_metatable(L);

	register_metatable(L, "uiview");
	register_metatable(L, "uiwindow");
	register_metatable(L, "uiviewcontroller");
	register_metatable(L, "nsobject");
#define GEN_STRUCT_REGISTER
#include "structs.m"
#undef GEN_STRUCT_REGISTER
	luaL_newlib(L, bridge_lib);
	lua_pushnumber(L, kSidebarIconSize);
	lua_setfield(L, -2, "sidebarIconSize");
	lua_pushnumber(L, kSidebarIconSlotWidth);
	lua_setfield(L, -2, "sidebarIconSlotWidth");
	lua_pushnumber(L, kSidebarRowPadding);
	lua_setfield(L, -2, "sidebarRowPadding");
	lua_pushnumber(L, kSidebarExpandedPadding);
	lua_setfield(L, -2, "sidebarExpandedPadding");
	lua_pushnumber(L, kSidebarCollapsedPadding);
	lua_setfield(L, -2, "sidebarCollapsedPadding");
	lua_pushnumber(L, kSidebarExpandedWidth);
	lua_setfield(L, -2, "sidebarExpandedWidth");
	lua_pushnumber(L, kSidebarCompactWidth);
	lua_setfield(L, -2, "sidebarCompactWidth");
	lua_pushnumber(L, kSidebarCollapsedWidth);
	lua_setfield(L, -2, "sidebarCollapsedWidth");
	return 1;
}
