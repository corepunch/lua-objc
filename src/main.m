#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#include <dlfcn.h>
#include <libgen.h>
#include <limits.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

enum {
	kAxisKey,
	kNavigationControllerKey,
	kScrollViewportSizeKey,
	kScrollContentKey,
	kButtonContentKey,
	kFlexibleKey,
	kTableSourceKey,
	kCallbackKey,
	kToolbarDelegateKey,
	kColumnAlignmentKey,
	kColumnSystemImageKey,
	kResizeObserverKey,
	kPaddingKey,
	kPaddingHorizontalKey,
	kPaddingLeadingKey,
	kPaddingTrailingKey,
	kPaddingVerticalKey,
	kPaddingTopKey,
	kPaddingBottomKey,
	kSpacingKey,
	kAlignmentKey,
	kFixedWidthKey,
	kFixedHeightKey,
	kMinWidthKey,
	kMinHeightKey,
	kMaxWidthKey,
	kMaxHeightKey,
	kFlexGrowKey,
	kFlexShrinkKey,
	kFlexBasisKey,
	kFillWidthKey,
	kFillHeightKey,
	kBackgroundColorKey,
	kCornerRadiusKey,
	kClipsToBoundsKey,
	kImageLayoutSizeKey,
	kTableSpinnerKey,
	kTableSelectionKey,
	kTableActivationKey,
	kTableRefreshKey,
	kTableSortKey,
	kTableMoveKey,
	kTextChangeKey,
	kTextChangeObserverKey,
	kTextFieldDelegateKey,
	kTextProgrammaticKey,
	kTextWrapKey,
	kMenuTargetKey,
	kSplitPaneFrameObserverKey,
	kSplitProportionsKey,
	kSplitProportionsAppliedKey,
	kColumnFlexKey,
	kColumnCellKey,
	kColumnSortableKey,
	kTabViewDelegateKey,
	kTableScrollViewKey,
	kWorkspaceSafeAreaContentKey,
	kTextViewSourceKey,
	kWindowCloseKey,
	kKeyCount
};
static char kKeys[kKeyCount];
static const CGFloat kStackSpacing = 8.0;

/* Every value that controls visual appearance or layout has a named constant
 * so that tuning across the codebase is a single-section edit. Add new constants
 * here instead of embedding raw numbers in code. */

/* ----- Table / Outline cells ----- */
#define kIconBadgeCornerFraction       0.23
#define kIconBadgeSymbolScale          0.66
#define kTableCellImageWidth            18
#define kTableCellImageTextGap           8
#define kTableCellImageLeadingInset      0
#define kTableCellTextLeadingInset       8
#define kTableCellTextTrailingInset      8
#define kTableCellSymbolPointSize       13
#define kTableCellSecondaryFontSize     11
#define kTableCellLoadingGap             4
#define kTableCellLineSpacing            2
#define kTableCellLevelTextWidth        38
#define kTableCellLevelGap               8
#define kTableCellLevelHeight           12
#define kTableCellCurveInsetH            4
#define kTableCellCurveInsetV           10
#define kTableCellCurvePathWidth       100
#define kTableCellCurvePathHeight       32
#define kTableCellCurveLineWidth       1.5
#define kTableColumnMinWidth            40
#define kTableDefaultWidth             400
#define kTableDefaultHeight            200
#define kTableIntercellSpacingH          3
#define kTableIntercellSpacingV          2
#define kLayoutDebugGeometryTolerance  0.75
#define kLayoutDebugMaxTableRows          4
#define kLazyCollectionWidth            400
#define kLazyCollectionHeight           200
#define kLazyRowHeight                   44
#define kLazyItemSpacing                  8
#define kLazyMinimumItemWidth             1
#define kLazyStackColumns                 1
#define kLazyGridColumns                  2
#define kOutlineRowHeight              24
#define kOutlineIndentation            16
#define kOutlineDisclosureContentGap    8
#define kOutlineDefaultWidth           400
#define kOutlineDefaultHeight          200

/* ----- ActionButton ----- */
#define kActionBtnSymbolSize            17
#define kActionBtnSymbolSizeRow         20
#define kActionBtnTitleFontSize         13
#define kActionBtnSubtitleFontSize      11
#define kActionBtnDetailFontSize        11
#define kActionBtnTitleMaxLines          2
#define kActionBtnHeightPrimary         64
#define kActionBtnHeightPlain           58
#define kActionBtnHeightRow             52
#define kActionBtnHeightLink            40
#define kActionBtnWidth                220
#define kActionBtnIconWidth             24
#define kActionBtnIconWidthRow          28
#define kActionBtnIconGap               12
#define kActionBtnInsetPlain            12
#define kActionBtnInsetRow              14
#define kActionBtnInsetLink             20
#define kActionBtnDetailWidth           72
#define kActionBtnDetailHeight          16
#define kActionBtnDetailGap             12
#define kActionBtnTitleSubtitleGap       1
#define kActionBtnTextExtraInset        16
#define kActionBtnCornerRadius           8
#define kActionBtnHoverPrimary          0.85
#define kActionBtnHoverSecondary        0.07
#define kActionBtnSubtitleAlpha         0.75

/* ----- Spacer & Separator ----- */
#define kSpacerSize                     10
#define kSeparatorSize                   1

/* ----- Image ----- */
#define kDefaultImageMaxWidth          400.0
#define kImageViewerDefaultWidth       640
#define kImageViewerDefaultHeight      480
#define kImageViewerMinZoomScale        0.05
#define kImageViewerDefaultZoomScale    1.0

/* ----- System Image / SF Symbols ----- */
#define kDefaultSymbolPointSize         17

/* ----- Code Editor ----- */
#define kEditorFontSize                 13
#define kEditorDefaultWidth            400
#define kEditorDefaultHeight           300

/* ----- Workspace Split Controller ----- */
#define kWorkspaceSidebarWidth         240
#define kWorkspaceSidebarMinWidth      160
#define kWorkspaceSidebarMaxWidth      420
#define kWorkspaceDetailWidth          330
#define kWorkspaceDetailMinWidth       280
#define kWorkspaceDetailMaxWidth       420
#define kWorkspaceContentDividerIndex    0
#define kWorkspaceDetailDividerIndex     1

/* ----- Symbol Toggle ----- */
#define kSymbolToggleSize               28
#define kSymbolTogglePointSize          13

/* ----- Loading Spinner ----- */
#define kLoadingSpinnerSize             32

/* ----- Layout Engine ----- */
#define kLayoutDefaultWidth            400
#define kMinLeafWidth                    1
#define kMinLeafHeight                  22
#define kFlexEpsilon                    0.5

/* ----- Preview / Render ----- */
#define kRenderDefaultWidth            400
#define kRenderDefaultHeight           300

/* ----- Misc ----- */
#define kFallbackBackingScale            2.0
#define kFSWatcherLatency                0.2

#define LUA_OBJC_HTTP_USER_AGENT \
	@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
	@"AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
#define LUA_OBJC_VIEW_CLASS NSView
#define LUA_OBJC_WINDOW_CLASS NSWindow
#define LUA_OBJC_VIEW_METATABLE "nsview"
#define LUA_OBJC_WINDOW_METATABLE "nswindow"

#include "shared/lua_bridge_support.m"
#include "shared/lua_error.m"
#include "shared/lua_async.m"
#include "shared/performance_signpost.m"
#include "shared/lua_dealloc_watch.m"

/* Replaces any previously registered LuaReg at `key`. */
static void bridge_set_optional_callback(
	lua_State *L, id target, const void *key, int argIdx
) {
	lua_reg_store(target, key, lua_reg_opt(L, argIdx));
}

#include "appkit/bezier_path.m"
#include "appkit/table_data_source.m"
#include "appkit/outline_data_source.m"
#include "appkit/action_button.m"
#include "appkit/runtime.m"
#include "appkit/toolbar.m"
#include "appkit/presentation.m"
#include "appkit/text_field.m"
#include "appkit/views.m"
#include "shared/flow_layout.m"
#include "appkit/layout.m"
#include "appkit/layout_debug.m"
#include "appkit/controls.m"
#include "appkit/outline.m"
#include "appkit/editor.m"
#include "appkit/tabview.m"
#include "appkit/navigation.m"
#include "appkit/platform.m"
#include "appkit/haptics.m"
#include "appkit/webview.m"

#include "appkit/workspace.m"
#include "appkit/constructors.m"
#include "appkit/reorder_container.m"
#include "appkit/lazy_collection.m"
#include "shared/parity_batch.m"
#include "appkit/parity_batch.m"
#pragma mark - Module registration

static const luaL_Reg bridge_lib[] = {
	{"_hapticsAvailable", bridge_haptics_available},
	{"_reduceMotionEnabled", bridge_reduce_motion_enabled},
	{"_hapticImpact", bridge_haptic_impact},
	{"_hapticSelection", bridge_haptic_selection},
	{"_hapticNotification", bridge_haptic_notification},
	{"_webView", bridge_webview},
	{"_webViewAction", bridge_webview_action},
	{"_testRowSwipe", bridge_test_row_swipe},
	{"_parityMeasure", bridge_parity_measure},
	{"_parityCapturePNG", bridge_parity_capture_png},
	{"_parityWrite", bridge_parity_write},
	{"_parityJSON", bridge_parity_json},
	{"_parityReadJSON", bridge_parity_read_json},
	{"_parityDocumentsDirectory", bridge_parity_documents},
	{"Size", bridge_NSSize},
	{"Point", bridge_NSPoint},
	{"Rect", bridge_NSRect},
	{"_vstack", bridge_AppKitControls_vstack},
	{"_hstack", bridge_AppKitControls_hstack},
	{"_flowStack", bridge_AppKitControls_flowStack},
	{"_zstack", bridge_AppKitControls_zstack},
	{"_scrollView", bridge_AppKitControls_scrollView},
	{"_hsplit", bridge_AppKitControls_hsplit},
	{"_vsplit", bridge_AppKitControls_vsplit},
	{"_separator", bridge_AppKitControls_separator},
	{"_spacer", bridge_AppKitControls_spacer},
	{"_linearGradient", bridge_AppKitControls_linearGradient},
	{"_hitTestTarget", bridge_hit_test_target},
	{"_hostingController", bridge_hosting_controller},
	{"_navigationStack", bridge_navigation_stack},
	{"_label", bridge_AppKitControls_label},
	{"_textField", bridge_AppKitControls_textField},
	{"_secureTextField", bridge_AppKitControls_secureTextField},
	{"_searchField", bridge_AppKitControls_searchField},
	{"_box", bridge_AppKitControls_box},
	{"_progressIndicator", bridge_AppKitControls_progressIndicator},
	{"_tableCellView", bridge_AppKitControls_tableCellView},
	{"_popUpButton", bridge_AppKitControls_popUpButton},
	{"_menu", bridge_AppKitControls_menu},
	{"_slider", bridge_AppKitControls_slider},
	{"_stepper", bridge_AppKitControls_stepper},
	{"_picker", bridge_AppKitControls_picker},
	{"_datePicker", bridge_AppKitControls_datePicker},
	{"_colorPicker", bridge_AppKitControls_colorPicker},
	{"_button", bridge_AppKitControls_button},
	{"_link", bridge_AppKitControls_link},
	{"_toggle", bridge_AppKitControls_toggle},
	{"_tableColumnWidths", bridge_AppKit_table_column_widths},
	{"_tableCell", bridge_table_cell},
	{"_tableCellFrames", bridge_AppKit_table_cell_frames},
	{"_tableSpinnerFrame", bridge_AppKit_table_spinner_frame},
	{"_toolbar_item", bridge_AppKit_toolbar_item},
	{"_window", bridge_AppKit_window},
	{"_setWindowWorkspace", bridge_AppKit_set_window_workspace},
	{"_image", bridge_AppKit_image},
	{"_imageViewer", bridge_AppKit_image_viewer},
	{"_systemImage", bridge_AppKit_system_image},
	{"_systemColor", bridge_AppKit_system_color},
	{"_addDoubleClick", bridge_AppKit_add_double_click},
	{"_addDrag", bridge_add_drag},
	{"_addHoverTooltip", bridge_AppKit_add_hover_tooltip},
	{"_tableview", bridge_AppKit_tableview},
	{"_attachReorder", bridge_AppKitReorder_attach},
	{"_testReorderMove", bridge_AppKitReorder_testMove},
	{"_lazyCollection", bridge_AppKitLazy_collection},
	{"_lazyCollectionStats", bridge_AppKitLazy_stats},
	{"_actionButton", bridge_AppKit_action_button},
	{"_glassEffect", bridge_AppKit_glass_effect},
	{"_glassEffectContainer", bridge_glass_effect_container},
	{"_panel", bridge_AppKit_panel},
	{"_sheet", bridge_sheet},
	{"_panelStyleState", bridge_AppKit_panel_style_state},
	{"_menuItem", bridge_AppKit_menu_item},
	{"_textFieldCallbacks", bridge_AppKit_text_field_callbacks},
	{"_textFieldTestInput", bridge_AppKit_text_field_test_input},
	{"_textFieldTestCommand", bridge_AppKit_text_field_test_command},
	{"_textView", bridge_AppKit_text_view},
	{"_symbolToggle", bridge_AppKit_symbol_toggle},
	{"_symbolButton", bridge_AppKit_symbol_button},
	{"_tabview", bridge_AppKit_tabview},
	{"_segmentedControl", bridge_AppKit_segmented_control},
	{"_watchFile", bridge_AppKit_watch_file},
	{"_pickFolder", bridge_AppKit_pick_folder},
	{"_pickFile", bridge_AppKit_pick_file},
	{"_outlineview", bridge_AppKit_outlineview},
	{"_listDirectory", bridge_AppKit_list_directory},
	{"_timerAfter", bridge_AppKit_timer_after},
	{"_httpGet", bridge_AppKit_http_get},
	{"_jsonParse", bridge_AppKit_json_parse},
	{"_font", bridge_AppKit_font},
	{"_pathView", bridge_pathView},
	{"_setCurrentScope", bridge_set_current_scope},
	{"_invokeAction", bridge_invoke_action},
	{"_onWindowClose", bridge_on_window_close},
	{"_invalidateHandle", bridge_invalidate_handle},
	{"_watchDealloc", bridge_dealloc_watch},
	{"_deallocCount", bridge_dealloc_count},
	{"_deallocReset", bridge_dealloc_reset},
	{"_runLoopTick", bridge_runloop_tick},
	{"_addContextMenu", bridge_AppKit_add_context_menu},
	{"_addClick", bridge_AppKit_add_click},
	{"_revealInFinder", bridge_AppKit_reveal_in_finder},
	{"_openPath", bridge_AppKit_open_path},
	{"_moveToTrash", bridge_AppKit_move_to_trash},
	{"_clipboardCopy", bridge_AppKit_clipboard_copy},
	{"_alert", bridge_AppKit_alert},
	{"_diskSpace", bridge_AppKit_disk_space},
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

int luaopen_bridge(lua_State *L) {
	lua_objc_init_handles(L);
	register_luareg_metatable(L);
	register_metatable(L, "nsview");
	register_metatable(L, "nswindow");
	register_metatable(L, "nsobject");
#define GEN_STRUCT_REGISTER
#include "appkit/structs.m"
#undef GEN_STRUCT_REGISTER
	luaL_newlib(L, bridge_lib);
	return 1;
}

#pragma mark - Main

/*
 * The executable is intentionally a tiny loader. AppKit.dylib owns the host
 * runtime as well as luaopen_AppKit, so the same image that Lua requires also
 * owns every AppKit control, layout key, callback target, and canvas service.
 */
int lua_objc_main(int argc, char *argv[]) {
	[NSApplication sharedApplication];

	/* Standard main menu with Edit menu so keyboard shortcuts
	 * (Cmd+C/V/X/Z/Shift+Z/A) work for NSTextView code editors.
	 * NSTextView handles cut:/copy:/paste:/undo:/redo:/selectAll:
	 * natively through the responder chain. */
	NSMenu *mainMenu = [[NSMenu alloc] init];
	NSMenuItem *appItem = [[NSMenuItem alloc] init];
	[mainMenu addItem:appItem];

	NSMenu *appMenu = [[NSMenu alloc] init];
	appItem.submenu = appMenu;
	[appMenu addItemWithTitle:@"Quit" action:@selector(terminate:)
		keyEquivalent:@"q"];

	NSMenuItem *editItem = [[NSMenuItem alloc] init];
	editItem.title = @"Edit";
	[mainMenu addItem:editItem];

	NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
	editItem.submenu = editMenu;
	[editMenu addItemWithTitle:@"Undo" action:@selector(undo:)
		keyEquivalent:@"z"];
	[editMenu addItemWithTitle:@"Redo" action:@selector(redo:)
		keyEquivalent:@"Z"];  /* Cmd+Shift+Z */
	[editMenu addItem:[NSMenuItem separatorItem]];
	[editMenu addItemWithTitle:@"Cut" action:@selector(cut:)
		keyEquivalent:@"x"];
	[editMenu addItemWithTitle:@"Copy" action:@selector(copy:)
		keyEquivalent:@"c"];
	[editMenu addItemWithTitle:@"Paste" action:@selector(paste:)
		keyEquivalent:@"v"];
	[editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:)
		keyEquivalent:@"a"];

	NSApp.mainMenu = mainMenu;

	const char *appearance = NULL;
	const char *script = NULL;
	int preview_mode = 0;
	CGFloat preview_width = kRenderDefaultWidth;
	CGFloat preview_height = kRenderDefaultHeight;
	BOOL layout_width_set = NO;
	BOOL layout_height_set = NO;
	const char *preview_out = NULL;
	const char *layout_out = NULL;
	const char *screenshot_out = NULL;
	const char *internal_screenshot_out = NULL;
	const char *script_args[256];
	int script_arg_count = 0;

	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--preview") == 0) {
			preview_mode = 1;
		} else if (strncmp(argv[i], "--width=", 8) == 0) {
			preview_width = atof(argv[i] + 8);
			layout_width_set = YES;
		} else if (strncmp(argv[i], "--height=", 9) == 0) {
			preview_height = atof(argv[i] + 9);
			layout_height_set = YES;
		} else if (strncmp(argv[i], "--out=", 6) == 0) {
			preview_out = argv[i] + 6;
		} else if (strncmp(argv[i], "--dump-layout=", 14) == 0) {
			layout_out = argv[i] + 14;
		} else if (strncmp(argv[i], "--screenshot=", 13) == 0) {
			screenshot_out = argv[i] + 13;
		} else if (strncmp(argv[i], "--internal-screenshot=", 22) == 0) {
			internal_screenshot_out = argv[i] + 22;
		} else if (strncmp(argv[i], "--appearance=", 13) == 0) {
			appearance = argv[i] + 13;
		} else if (strcmp(argv[i], "--appearance") == 0 && i + 1 < argc) {
			appearance = argv[++i];
		} else if (script && script_arg_count < 256) {
			script_args[script_arg_count++] = argv[i];
		} else if (argv[i][0] != '-') {
			if (!script) {
				script = argv[i];
			} else if (script_arg_count < (int)(sizeof(script_args) / sizeof(script_args[0]))) {
				script_args[script_arg_count++] = argv[i];
			}
		} else if (script_arg_count < (int)(sizeof(script_args) / sizeof(script_args[0]))) {
			/* Preserve app-level switches supplied before the entry point. */
			script_args[script_arg_count++] = argv[i];
		}
	}

	if (!script) script = "demo/hello";

	// If script path is a directory, look for init.lua inside it.
	{
		static char resolvedPath[PATH_MAX];
		BOOL isDir = NO;
		if ([[NSFileManager defaultManager]
			fileExistsAtPath:[NSString stringWithUTF8String:script]
				 isDirectory:&isDir] && isDir) {
			NSString *initPath = [[NSString stringWithUTF8String:script]
				stringByAppendingPathComponent:@"init.lua"];
			snprintf(resolvedPath, sizeof(resolvedPath), "%s",
				[initPath UTF8String]);
			script = resolvedPath;
		}
	}

	lua_State *L = luaL_newstate();
	luaL_openlibs(L);

	LuaStateOwner *mainOwner = [[LuaStateOwner alloc] initWithState:L];
	(void)mainOwner;  /* released by ARC at return → -dealloc → lua_close */

	luaL_requiref(L, "AppKitNative", luaopen_bridge, 1);
	lua_pop(L, 1);

	if (appearance && strcmp(appearance, "system") != 0) {
		lua_pushstring(L, appearance);
		lua_setglobal(L, "_LAUNCH_APPEARANCE");
	}

	lua_newtable(L);
	if (script) {
		lua_pushinteger(L, 0);
		lua_pushstring(L, script);
		lua_settable(L, -3);
	}
	for (int i = 0; i < script_arg_count; i++) {
		lua_pushinteger(L, i + 1);
		lua_pushstring(L, script_args[i]);
		lua_settable(L, -3);
	}
	lua_setglobal(L, "arg");

	char cwd[4096];
	if (getcwd(cwd, sizeof(cwd))) {
		char frameworkDirectory[PATH_MAX] = "";
		Dl_info imageInfo;
		if (dladdr((const void *)&lua_objc_main, &imageInfo)
			&& imageInfo.dli_fname) {
			char imagePath[PATH_MAX];
			snprintf(imagePath, sizeof(imagePath), "%s", imageInfo.dli_fname);
			snprintf(frameworkDirectory, sizeof(frameworkDirectory), "%s",
				dirname(imagePath));
		}

		lua_getglobal(L, "package");
		lua_getfield(L, -1, "path");
		const char *defpath = lua_tostring(L, -1);
		char newpath[8192];
		snprintf(newpath, sizeof(newpath), "%s;%s/?.lua;%s/lua/?.lua", defpath, cwd, cwd);
		lua_pushstring(L, newpath);
		lua_setfield(L, -3, "path");
		lua_pop(L, 1);

		lua_getfield(L, -1, "cpath");
		const char *defcpath = lua_tostring(L, -1);
		char newcpath[8192];
		snprintf(newcpath, sizeof(newcpath), "%s;%s/build/?.dylib;%s/?.dylib",
			defcpath, cwd, frameworkDirectory);
		lua_pushstring(L, newcpath);
		lua_setfield(L, -3, "cpath");
		lua_pop(L, 2);
	}

	{
		extern int luaopen_AppKit(lua_State *L);
		luaL_requiref(L, "AppKit", luaopen_AppKit, 1);
		lua_getglobal(L, "package");
		lua_getfield(L, -1, "loaded");
		lua_pushvalue(L, -3);
		lua_setfield(L, -2, "ns");
		lua_pop(L, 3);
	}

	if (preview_mode) {
		/* --preview: eval the script in the main state, render to PNG. */
		FILE *fp = fopen(script, "r");
		if (!fp) {
			fprintf(stderr, "preview: cannot open %s\n", script);
			return 1;
		}
		fseek(fp, 0, SEEK_END);
		long fsize = ftell(fp);
		rewind(fp);
		char *code = malloc((size_t)fsize + 1);
		fread(code, 1, (size_t)fsize, fp);
		code[fsize] = '\0';
		fclose(fp);

		char *wrapped = malloc((size_t)fsize + 256);
		snprintf(wrapped, (size_t)fsize + 256,
			"local ns=require('AppKit');"
			"local __rr;"
			"ns.Window=function(p) __rr=ns.VStack(p) return __rr end;"
			"ns.Preview=function(p) __rr=ns.VStack(p) return __rr end;"
			"local __rok,__ret=pcall(function()\n%s\nend);"
			"if not __rok then error(__ret) end;"
			"return __ret or __rr",
			code);
		free(code);

		NSString *previewSource = [NSString stringWithFormat:@"@%s", script];
		if (luaL_loadbufferx(L, wrapped, strlen(wrapped),
			previewSource.UTF8String, "t") != LUA_OK ||
			lua_pcall(L, 0, 1, 0) != LUA_OK) {
			report_lua_error(L, "preview");
			free(wrapped);
			return 1;
		}
		free(wrapped);

		id resultObj = nil;
		ObjCRef *ref = luaL_testudata(L, -1, "nsview");
		if (!ref) ref = luaL_testudata(L, -1, "nswindow");
		if (ref) resultObj = (__bridge id)ref->ptr;

		if (!resultObj || ![resultObj isKindOfClass:[NSView class]]) {
			fprintf(stderr, "preview: script did not return a view\n");
			return 1;
		}

		NSView *view = (NSView *)resultObj;
		view.frame = NSMakeRect(0, 0, preview_width, preview_height);
		layout_recursive(view, preview_width);

		NSData *png = offscreen_render(view, preview_width, preview_height);
		lua_settop(L, 0);

		if (!png) {
			fprintf(stderr, "preview: render failed\n");
			return 1;
		}

		int write_ok = 0;
		if (!preview_out || strcmp(preview_out, "-") == 0) {
			write_ok = fwrite(png.bytes, 1, png.length, stdout) == (size_t)png.length;
		} else {
			FILE *out = fopen(preview_out, "wb");
			if (out) {
				write_ok = fwrite(png.bytes, 1, png.length, out) == (size_t)png.length;
				fclose(out);
			}
		}

		return write_ok ? 0 : 1;
	}

	BOOL testMode = NO;
	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--test") == 0) testMode = YES;
	}
	if (layout_out || testMode) {
		lua_pushboolean(L, 1);
		lua_setglobal(L, "__headless");
	}

	if (luaL_dofile(L, script) != LUA_OK) {
		report_lua_error(L, "script");
		return 1;
	}
	if (testMode) return 0;

	/*
	 * If the script returned a table with a `new` method, treat it as an
	 * app class: call class.new() then instance:createWindow().
	 * Scripts that self-start (creating a window as a side effect) return
	 * nil or a window — this path is skipped for backward compatibility.
	 */
	/*
	 * require() pushes two values: the module and the filename it was loaded
	 * from. Pop any trailing non-table values so the class table is on top.
	 */
	while (lua_gettop(L) > 0 && !lua_istable(L, -1))
		lua_pop(L, 1);
	if (lua_istable(L, -1)) {
		lua_getfield(L, -1, "new");
		if (lua_isfunction(L, -1)) {
			lua_pushvalue(L, -2);  /* class as self */
			if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
				report_lua_error(L, "new");
			} else if (lua_istable(L, -1)) {
				lua_getfield(L, -1, "createWindow");
				if (lua_isfunction(L, -1)) {
					lua_pushvalue(L, -2);  /* instance as self */
					if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
						report_lua_error(L, "createWindow");
					} else {
						/*
						 * Keep the launch controller and its window alive for the
						 * lifetime of the run loop. Many examples store their
						 * NSWindow and callback closures on the instance, so
						 * dropping the last Lua root here can deallocate the
						 * whole window tree before AppKit has a chance to display it.
						 */
						lua_pushvalue(L, -2);
						luaL_ref(L, LUA_REGISTRYINDEX);
						lua_pushvalue(L, -1);
						luaL_ref(L, LUA_REGISTRYINDEX);
					}
				}
			}
		}
	}

	[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
	[NSApp finishLaunching];
	if (layout_out) {
		NSWindow *window = lua_objc_app_window();
		if (window && (layout_width_set || layout_height_set)) {
			NSSize size = window.contentView.bounds.size;
			if (layout_width_set) size.width = preview_width;
			if (layout_height_set) size.height = preview_height;
			[window setContentSize:size];
		}
		if (!window || !write_layout_debug_dump(window, layout_out)) {
			fprintf(stderr, "layout dump: cannot write %s\n", layout_out);
			return 1;
		}
		return 0;
	}
	[NSApp unhide:nil];
	[NSApp activate];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
		[NSApp unhide:nil];
		[NSApp activate];
		for (NSWindow *window in NSApp.windows) {
			if (window.isVisible) {
				// Panels and sheets cannot become main; an attached sheet owns key focus.
				if (window.canBecomeKeyWindow && !window.attachedSheet) [window makeKeyAndOrderFront:nil];
				if (window.canBecomeMainWindow) [window makeMainWindow];
				[window orderFrontRegardless];
			}
		}
	});

	lua_settop(L, 0);

	/* Resize before the settling interval, so WindowServer and native container
	 * layout commit the requested geometry before either capture path runs. */
	if ((screenshot_out || internal_screenshot_out) && (layout_width_set || layout_height_set)) {
		NSWindow *window = lua_objc_app_window();
		NSSize size = window.contentView.bounds.size;
		if (layout_width_set) size.width = preview_width;
		if (layout_height_set) size.height = preview_height;
		[window setContentSize:size];
	}

	if (internal_screenshot_out) {
		NSString *screenshotPath = [NSString stringWithUTF8String:internal_screenshot_out];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
			NSWindow *window = lua_objc_app_window();
			NSData *png = nil;
			if (window && window.contentView) {
				[window.contentView layoutSubtreeIfNeeded];
				CGFloat captureWidth = layout_width_set
					? preview_width : window.contentView.bounds.size.width;
				CGFloat captureHeight = layout_height_set
					? preview_height : window.contentView.bounds.size.height;
				png = offscreen_render(window.contentView,
					captureWidth, captureHeight);
			}
			BOOL captured = png && [png writeToFile:screenshotPath atomically:YES];
			if (captured) {
				fprintf(stderr, "internal screenshot: wrote %s (%lu bytes)\n",
					internal_screenshot_out, (unsigned long)png.length);
			} else {
				fprintf(stderr, "internal screenshot: failed to write %s\n",
					internal_screenshot_out);
			}
			exit(captured ? EXIT_SUCCESS : EXIT_FAILURE);
		});
	} else if (screenshot_out) {
		NSString *screenshotPath = [NSString stringWithUTF8String:screenshot_out];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
			NSWindow *window = lua_objc_app_window();
			NSData *png = nil;
			[[NSFileManager defaultManager] removeItemAtPath:screenshotPath error:nil];
			if (window) {
				[window display];
				NSTask *capture = [[NSTask alloc] init];
				capture.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
				capture.arguments = @[@"-x", @"-l", @(window.windowNumber).stringValue, screenshotPath];
				NSError *error = nil;
				if ([capture launchAndReturnError:&error]) {
					[capture waitUntilExit];
					if (capture.terminationStatus == 0) png = [NSData dataWithContentsOfFile:screenshotPath];
				}
			}

			if (png) {
				[png writeToFile:screenshotPath atomically:YES];
			} else {
				fprintf(stderr, "screenshot: failed to capture window\n");
			}
			exit(png.length ? EXIT_SUCCESS : EXIT_FAILURE);
		});
	}

	[NSApp run];

	return 0;
}
