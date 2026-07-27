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
	kFlexibleKey,
	kTableSourceKey,
	kCallbackKey,
	kToolbarDelegateKey,
	kColumnAlignmentKey,
	kColumnSystemImageKey,
	kResizeObserverKey,
	kPaddingKey,
	kPaddingHorizontalKey,
	kPaddingVerticalKey,
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
	kImageLayoutSizeKey,
	kTableSpinnerKey,
	kTableSelectionKey,
	kTableActivationKey,
	kTableRefreshKey,
	kTextChangeKey,
	kTextFieldDelegateKey,
	kTextProgrammaticKey,
	kTextWrapKey,
	kMenuTargetKey,
	kSplitPaneFrameObserverKey,
	kSplitProportionsKey,
	kSplitProportionsAppliedKey,
	kCanvasToolbarItemsKey,
	kTableScrollViewKey,
	kColumnFlexKey,
	kTabViewDelegateKey,
	kKeyCount
};
static char kKeys[kKeyCount];
static const CGFloat kStackSpacing = 8.0;
static lua_State *gL = NULL;

/* Every value that controls visual appearance or layout has a named constant
 * so that tuning across the codebase is a single-section edit. Add new constants
 * here instead of embedding raw numbers in code. */

/* ----- Table / Outline cells ----- */
#define kTableCellImageWidth            16
#define kTableCellImageTextGap           2
#define kTableCellImageLeadingInset      0
#define kTableCellTextLeadingInset       2
#define kTableCellTextTrailingInset      8
#define kTableCellSymbolPointSize       13
#define kTableColumnMinWidth            40
#define kTableDefaultWidth             400
#define kTableDefaultHeight            200
#define kTableIntercellSpacingH          3
#define kTableIntercellSpacingV          2
#define kOutlineRowHeight              24
#define kOutlineIndentation            16
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

#include "appkit/table_data_source.m"
#include "appkit/outline_data_source.m"
#include "appkit/action_button.m"
#include "appkit/toolbar.m"
#include "appkit/runtime.m"
#include "appkit/presentation.m"
#include "appkit/text_field.m"
#include "appkit/views.m"
#include "appkit/layout.m"
#include "appkit/controls.m"
#include "appkit/outline.m"
#include "appkit/editor.m"
#include "appkit/tabview.m"
#include "appkit/platform.m"
#pragma mark - Module registration

static const luaL_Reg bridge_lib[] = {
	{"_window",           bridge_window},
	{"_vstack",           bridge_vstack},
	{"_hstack",           bridge_hstack},
	{"_hsplit",           bridge_hsplit},
	{"_vsplit",           bridge_vsplit},
	{"_splitSetProportions", bridge_split_set_proportions},
	{"_separator",        bridge_separator},
	{"_spacer",           bridge_spacer},
	{"_image",            bridge_image},
	{"_imageViewer",      bridge_image_viewer},
	{"_systemImage",      bridge_system_image},
	{"_systemColor",      bridge_system_color},
	{"_add",              bridge_add},
	{"_layout",           bridge_layout},
	{"_viewSize",         bridge_view_size},
	{"_viewFrameInWindow",bridge_view_frame_in_window},
	{"_setContentSize",   bridge_set_content_size},
	{"_setWindowMinSize", bridge_set_window_min_size},
	{"_setAppearance",    bridge_set_appearance},
	{"_panel",            bridge_panel},
	{"_panelStyleState",  bridge_panel_style_state},
	{"_presentPanel",     bridge_present_panel},
	{"_dismissWindow",    bridge_dismiss_window},
	{"_focus",            bridge_focus},
	{"_isFirstResponder", bridge_is_first_responder},
	{"_menuItem",         bridge_menu_item},
	{"_textFieldCallbacks", bridge_text_field_callbacks},
	{"_textFieldTestInput", bridge_text_field_test_input},
	{"_textFieldTestCommand", bridge_text_field_test_command},
	{"_tableview",        bridge_tableview},
	{"_toolbar_item",     bridge_toolbar_item},
	{"_canvas_toolbar_items", bridge_canvas_toolbar_items},
	{"_button",           bridge_button},
	{"_actionButton",     bridge_action_button},
	{"_toggle",           bridge_toggle},
	{"_timerAfter",      bridge_timer_after},
	{"_show",             bridge_show},
	{"_create",           bridge_create},
	{"_font",             bridge_font},
	{"_perform",          bridge_perform},
	{"_callback",         bridge_callback},
	{"_httpGet",         bridge_http_get},
	{"_jsonParse",       bridge_json_parse},
	{"_tableSetRefresh", bridge_table_set_refresh},
	{"_tableColumnWidths", bridge_table_column_widths},
	{"_tableCellFrames", bridge_table_cell_frames},
	{"_textView",         bridge_text_view},
	{"_textViewGetText",  bridge_text_view_get_text},
	{"_textViewSetText",  bridge_text_view_set_text},
	{"_textViewOnChange", bridge_text_view_on_change},
	{"_textViewSetLanguage", bridge_text_view_set_language},
	{"_textViewSetWrapMode", bridge_text_view_set_wrap_mode},
	{"_symbolToggle",       bridge_symbol_toggle},
	{"_symbolButton",       bridge_symbol_button},
	{"_eval",             bridge_eval},
	{"_clearContainer",   bridge_clear_container},
	{"_renderToPNG",      bridge_render_to_png},
	{"_watchFile",        bridge_watch_file},
	{"_pickFolder",       bridge_pick_folder},
	{"_pickFile",         bridge_pick_file},
	{"_outlineview",      bridge_outlineview},
	{"_listDirectory",    bridge_list_directory},
	{"_tabview",          bridge_tabview},
	{"_tabAdd",           bridge_tab_add},
	{"_tabSelect",        bridge_tab_select},
	{"_tabRemove",        bridge_tab_remove},
	{"_tabCount",         bridge_tab_count},
	{"_tabOnChange",      bridge_tab_on_change},
	{"_segmentedControl", bridge_segmented_control},
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
	register_metatable(L, "nsview");
	register_metatable(L, "nswindow");
	register_metatable(L, "nsobject");
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
	const char *preview_out = NULL;
	const char *script_args[256];
	int script_arg_count = 0;

	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--preview") == 0) {
			preview_mode = 1;
		} else if (strncmp(argv[i], "--width=", 8) == 0) {
			preview_width = atof(argv[i] + 8);
		} else if (strncmp(argv[i], "--height=", 9) == 0) {
			preview_height = atof(argv[i] + 9);
		} else if (strncmp(argv[i], "--out=", 6) == 0) {
			preview_out = argv[i] + 6;
		} else if (strncmp(argv[i], "--appearance=", 13) == 0) {
			appearance = argv[i] + 13;
		} else if (strcmp(argv[i], "--appearance") == 0 && i + 1 < argc) {
			appearance = argv[++i];
		} else if (argv[i][0] != '-') {
			if (!script) {
				script = argv[i];
			} else if (script_arg_count < (int)(sizeof(script_args) / sizeof(script_args[0]))) {
				script_args[script_arg_count++] = argv[i];
			}
		}
	}

	if (!script) script = "examples/hello.lua";

	lua_State *L = luaL_newstate();
	gL = L;
	luaL_openlibs(L);

	LuaStateOwner *mainOwner = [[LuaStateOwner alloc] initWithState:L];
	(void)mainOwner;  /* released by ARC at return → -dealloc → lua_close */

	luaL_requiref(L, "AppKitNative", luaopen_bridge, 1);
	lua_pop(L, 1);
	/* Compatibility for application code that still imports the old private
	 * name directly. Public framework code uses AppKitNative. */
	luaL_requiref(L, "bridge", luaopen_bridge, 1);
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

	if (preview_mode) {
		/* --preview: eval the script in canvas mode, render to PNG, write out. */
		lua_State *C = canvas_state_create();
		if (!C) {
			fprintf(stderr, "preview: failed to create canvas state\n");
			return 1;
		}

	/* Read the file into a string so we can pass it through bridge_eval's
		 * canvas wrapper (which intercepts ns.Window → ns.VStack). */
		FILE *fp = fopen(script, "r");
		if (!fp) {
			fprintf(stderr, "preview: cannot open %s\n", script);
			lua_close(C);
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

		if (luaL_loadstring(C, wrapped) != LUA_OK ||
			lua_pcall(C, 0, 1, 0) != LUA_OK) {
			report_lua_error(C, "preview");
			free(wrapped);
			lua_close(C);
			return 1;
		}
		free(wrapped);

		id resultObj = nil;
		ObjCRef *ref = luaL_testudata(C, -1, "nsview");
		if (!ref) ref = luaL_testudata(C, -1, "nswindow");
		if (ref) resultObj = (__bridge id)ref->ptr;

		if (!resultObj || ![resultObj isKindOfClass:[NSView class]]) {
			fprintf(stderr, "preview: script did not return a view\n");
			lua_close(C);
			return 1;
		}

		NSView *view = (NSView *)resultObj;
		view.frame = NSMakeRect(0, 0, preview_width, preview_height);
		layout_recursive(view, preview_width);

		NSData *png = offscreen_render(view, preview_width, preview_height);
		lua_close(C);

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

	if (luaL_dofile(L, script) != LUA_OK) {
		report_lua_error(L, "script");
		return 1;
	}

	[NSApp run];

	return 0;
}
