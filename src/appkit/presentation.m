#pragma mark - Generic Panel Presentation

@interface LuaPanel : NSPanel
@end

@implementation LuaPanel

- (BOOL)canBecomeKeyWindow {
	return YES;
}

- (BOOL)canBecomeMainWindow {
	return NO;
}

@end

static NSVisualEffectMaterial panel_material(NSString *name) {
	static NameValueEntry PanelMaterialMap[] = {
		{@"menu",       NSVisualEffectMaterialMenu},
		{@"sidebar",    NSVisualEffectMaterialSidebar},
		{@"headerView", NSVisualEffectMaterialHeaderView},
		{nil, NSVisualEffectMaterialPopover}
	};
	return (NSVisualEffectMaterial)lookupNameValue(name, PanelMaterialMap,
		NSVisualEffectMaterialPopover);
}

static int bridge_panel(lua_State *L) {
	CGFloat width = luaL_checknumber(L, 1);
	CGFloat height = luaL_checknumber(L, 2);
	const char *materialC = luaL_optstring(L, 3, "popover");

	LuaPanel *panel = [[LuaPanel alloc]
		initWithContentRect:NSMakeRect(0, 0, width, height)
				  styleMask:(NSWindowStyleMaskTitled
					  | NSWindowStyleMaskFullSizeContentView)
					backing:NSBackingStoreBuffered
					  defer:NO];
	panel.titleVisibility = NSWindowTitleHidden;
	panel.titlebarAppearsTransparent = YES;
	panel.movableByWindowBackground = YES;
	panel.releasedWhenClosed = NO;
	panel.level = NSFloatingWindowLevel;
	panel.hasShadow = YES;
	panel.hidesOnDeactivate = NO;

	NSVisualEffectView *content = [[NSVisualEffectView alloc]
		initWithFrame:NSMakeRect(0, 0, width, height)];
	content.material = panel_material(
		[NSString stringWithUTF8String:materialC]);
	content.blendingMode = NSVisualEffectBlendingModeBehindWindow;
	content.state = NSVisualEffectStateFollowsWindowActiveState;
	panel.contentView = content;

	push_objc(L, panel, "nswindow");
	return 1;
}

// Sheets use an opaque semantic content surface, not floating-panel vibrancy.
static int bridge_sheet(lua_State *L) {
	CGFloat width = luaL_checknumber(L, 1), height = luaL_checknumber(L, 2);
	LuaPanel *sheet = [[LuaPanel alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
		styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
		backing:NSBackingStoreBuffered defer:NO];
	sheet.titleVisibility = NSWindowTitleHidden;
	sheet.titlebarAppearsTransparent = YES;
	sheet.releasedWhenClosed = NO;
	sheet.backgroundColor = NSColor.controlBackgroundColor;
	sheet.opaque = YES;
	sheet.hasShadow = YES;
	sheet.contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	push_objc(L, sheet, "nswindow");
	return 1;
}

static int bridge_NSWindow_presentPanel_impl(lua_State *L) {
	id panelObj = check_objc(L, 1);
	id parentObj = check_objc(L, 2);
	CGFloat offsetY = luaL_optnumber(L, 3, 0);
	if (![panelObj isKindOfClass:[NSPanel class]]
		|| ![parentObj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "presentPanel requires a panel and parent window");
	}

	NSPanel *panel = (NSPanel *)panelObj;
	NSWindow *parent = (NSWindow *)parentObj;
	NSRect parentFrame = parent.frame;
	NSRect panelFrame = panel.frame;
	panelFrame.origin.x = NSMidX(parentFrame) - panelFrame.size.width / 2;
	panelFrame.origin.y = NSMidY(parentFrame) - panelFrame.size.height / 2
		+ offsetY;
	[panel setFrame:panelFrame display:NO];
	panel.appearance = parent.appearance;
	[parent addChildWindow:panel ordered:NSWindowAbove];
	[panel makeKeyAndOrderFront:nil];
	return 0;
}

static int bridge_NSWindow_focus_impl(lua_State *L) {
	id windowObj = check_objc(L, 1);
	id viewObj = check_objc(L, 2);
	if (![windowObj isKindOfClass:[NSWindow class]]
		|| ![viewObj isKindOfClass:[NSView class]]) {
		return luaL_error(L, "focus requires a window and view");
	}
	BOOL focused = [(NSWindow *)windowObj makeFirstResponder:(NSView *)viewObj];
	lua_pushboolean(L, focused);
	return 1;
}

static int bridge_NSWindow_isFirstResponder_impl(lua_State *L) {
	id windowObj = check_objc(L, 1);
	id viewObj = check_objc(L, 2);
	if (![windowObj isKindOfClass:[NSWindow class]]
		|| ![viewObj isKindOfClass:[NSView class]]) {
		return luaL_error(L, "isFirstResponder requires a window and view");
	}
	NSWindow *window = (NSWindow *)windowObj;
	NSView *view = (NSView *)viewObj;
	id editor = [view isKindOfClass:[NSTextField class]]
		? [(NSTextField *)view currentEditor] : nil;
	lua_pushboolean(L, window.firstResponder == view
		|| (editor && window.firstResponder == editor));
	return 1;
}

#pragma mark - Main Menu

/* A Lua-backed menu command. `validate` runs whenever AppKit validates the
 * item (menu opening, key equivalents) and returns `enabled, checked`, the
 * Lua form of NSMenuItemValidation. Context menus turn autoenabling off, so
 * they never consult it. */
@interface LuaMenuActionTarget : NSObject <NSMenuItemValidation>
@property (nonatomic, strong) LuaReg *callback;
@property (nonatomic, strong) LuaReg *validate;
@property (nonatomic) BOOL disabled;
@end

@implementation LuaMenuActionTarget

- (void)dealloc {
	[_callback dispose];
	[_validate dispose];
}

- (void)performAction:(id)sender {
	lua_State *callL = lua_reg_live_state(_callback);
	if (!callL || !lua_reg_push(_callback)) return;
	lua_objc_pcall(callL, 0, 0, "menu action");
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
	if (_disabled) return NO;
	lua_State *L = _validate ? lua_reg_live_state(_validate) : NULL;
	if (!L || !lua_reg_push(_validate)) return YES;
	if (lua_objc_pcall(L, 0, 2, "menu validation") != LUA_OK) return NO;
	BOOL enabled = lua_isnil(L, -2) || lua_toboolean(L, -2);
	if (!lua_isnil(L, -1))
		item.state = lua_toboolean(L, -1) ? NSControlStateValueOn : NSControlStateValueOff;
	lua_pop(L, 2);
	return enabled;
}

@end

static NSEventModifierFlags menu_modifiers(NSString *names) {
	NSEventModifierFlags flags = 0;
	if ([names containsString:@"command"]) flags |= NSEventModifierFlagCommand;
	if ([names containsString:@"shift"]) flags |= NSEventModifierFlagShift;
	if ([names containsString:@"option"]) flags |= NSEventModifierFlagOption;
	if ([names containsString:@"control"]) flags |= NSEventModifierFlagControl;
	return flags;
}

/* The standard About panel reads the bundle name, which an unbundled
 * lua-objc process does not have; pass the declared name explicitly. */
@interface LuaAboutTarget : NSObject
@property (nonatomic, copy) NSString *applicationName;
@end

@implementation LuaAboutTarget
- (void)showAbout:(id)sender {
	[NSApp orderFrontStandardAboutPanelWithOptions:
		@{NSAboutPanelOptionApplicationName: _applicationName ?: @""}];
}
@end

static LuaAboutTarget *main_menu_about_target;

/* Help-menu search (NSUserInterfaceItemSearching). AppKit searches on a
 * background queue, so topics are immutable title/keyword pairs matched
 * natively; only choosing a result calls back into Lua, on the main thread. */
@interface LuaHelpTopic : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *keywords;
@property (nonatomic, strong) LuaReg *action;
@end

@implementation LuaHelpTopic
- (void)dealloc { [_action dispose]; }
@end

@interface LuaHelpSearch : NSObject <NSUserInterfaceItemSearching>
@property (nonatomic, copy) NSArray<LuaHelpTopic *> *topics;
@end

@implementation LuaHelpSearch

- (NSArray<LuaHelpTopic *> *)matches:(NSString *)query limit:(NSInteger)limit {
	NSMutableArray *found = [NSMutableArray array];
	NSArray<NSString *> *terms = [query.lowercaseString
		componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
	for (LuaHelpTopic *topic in _topics) {
		BOOL all = YES, any = NO;
		for (NSString *term in terms) {
			if (!term.length) continue;
			any = YES;
			if (![topic.keywords containsString:term]) { all = NO; break; }
		}
		if (any && all) [found addObject:topic];
		if ((NSInteger)found.count >= limit) break;
	}
	return found;
}

- (void)searchForItemsWithSearchString:(NSString *)searchString
	resultLimit:(NSInteger)resultLimit
	matchedItemHandler:(void (^)(NSArray *items))handleMatchedItems {
	handleMatchedItems([self matches:searchString limit:resultLimit]);
}

- (NSArray<NSString *> *)localizedTitlesForItem:(id)item {
	return @[((LuaHelpTopic *)item).title];
}

- (void)performActionForItem:(id)item {
	LuaReg *action = ((LuaHelpTopic *)item).action;
	lua_State *L = lua_reg_live_state(action);
	if (L && lua_reg_push(action)) lua_objc_pcall(L, 0, 0, "help topic");
}

@end

static LuaHelpSearch *main_menu_help_search;

/* An unbundled process is named after its executable ("lua-objc"). The menu
 * bar's bold application menu title, Dock tooltip and system alerts read the
 * process name and CFBundleName, so both carry the app's declared name. The
 * info dictionary is mutable in practice for the main bundle; the check
 * keeps this a no-op if AppKit ever hands out an immutable copy. */
static void set_application_name(NSString *name) {
	if (!name.length) return;
	NSProcessInfo.processInfo.processName = name;
	for (NSDictionary *info in @[NSBundle.mainBundle.infoDictionary ?: @{},
			NSBundle.mainBundle.localizedInfoDictionary ?: @{}])
		if ([info isKindOfClass:NSMutableDictionary.class])
			((NSMutableDictionary *)info)[@"CFBundleName"] = name;
}

static NSMenu *main_menu_build(lua_State *L, int index, NSString *title);

/* Keys XML cannot spell as characters are written by name. */
static NSString *main_menu_key(NSString *key) {
	static NSDictionary<NSString *, NSString *> *named;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		unichar backspace = NSBackspaceCharacter, forward = NSDeleteFunctionKey;
		unichar left = NSLeftArrowFunctionKey, right = NSRightArrowFunctionKey;
		unichar up = NSUpArrowFunctionKey, down = NSDownArrowFunctionKey;
		named = @{
			@"delete": [NSString stringWithCharacters:&backspace length:1],
			@"forwardDelete": [NSString stringWithCharacters:&forward length:1],
			@"return": @"\r", @"escape": @"\x1b", @"tab": @"\t", @"space": @" ",
			@"left": [NSString stringWithCharacters:&left length:1],
			@"right": [NSString stringWithCharacters:&right length:1],
			@"up": [NSString stringWithCharacters:&up length:1],
			@"down": [NSString stringWithCharacters:&down length:1],
		};
	});
	return named[key] ?: key;
}

/* One `{title, action | selector | role, keyEquivalent, modifiers, tag,
 * systemImage, checked, disabled, validate, items}` record or
 * `{separator = true}` on top of the stack. */
static NSMenuItem *main_menu_item(lua_State *L) {
	int item = lua_gettop(L);
	lua_getfield(L, item, "separator");
	BOOL separator = lua_toboolean(L, -1);
	lua_pop(L, 1);
	if (separator) return [NSMenuItem separatorItem];

	lua_getfield(L, item, "title");
	NSString *title = [NSString stringWithUTF8String:lua_tostring(L, -1) ?: ""];
	lua_getfield(L, item, "keyEquivalent");
	NSString *key = [NSString stringWithUTF8String:lua_tostring(L, -1) ?: ""];
	lua_getfield(L, item, "modifiers");
	NSString *modifiers = [NSString stringWithUTF8String:lua_tostring(L, -1) ?: "command"];
	lua_getfield(L, item, "selector");
	const char *selector = lua_tostring(L, -1);
	lua_getfield(L, item, "role");
	const char *role = lua_tostring(L, -1);
	NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title
		action:selector ? NSSelectorFromString([NSString stringWithUTF8String:selector]) : NULL
		keyEquivalent:main_menu_key(key)];
	menuItem.keyEquivalentModifierMask = menu_modifiers(modifiers);
	if (role && strcmp(role, "about") == 0) {
		menuItem.action = @selector(showAbout:);
		menuItem.target = main_menu_about_target;
	} else if (role && strcmp(role, "services") == 0) {
		menuItem.submenu = [[NSMenu alloc] initWithTitle:title];
		NSApp.servicesMenu = menuItem.submenu;
	}
	lua_pop(L, 5);

	lua_getfield(L, item, "action");
	if (lua_isfunction(L, -1)) {
		LuaMenuActionTarget *target = [[LuaMenuActionTarget alloc] init];
		target.callback = lua_reg_create(L, lua_gettop(L), YES);
		lua_getfield(L, item, "validate");
		target.validate = lua_reg_opt(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, item, "disabled");
		target.disabled = lua_toboolean(L, -1);
		lua_pop(L, 1);
		menuItem.action = @selector(performAction:);
		menuItem.target = target;
		objc_setAssociatedObject(menuItem, &kKeys[kMenuTargetKey], target,
			OBJC_ASSOCIATION_RETAIN);
	}
	lua_pop(L, 1);

	lua_getfield(L, item, "checked");
	if (lua_toboolean(L, -1)) menuItem.state = NSControlStateValueOn;
	lua_pop(L, 1);

	lua_getfield(L, item, "tag");
	menuItem.tag = (NSInteger)lua_tointeger(L, -1);
	lua_pop(L, 1);

	lua_getfield(L, item, "systemImage");
	const char *symbol = lua_tostring(L, -1);
	if (symbol && symbol[0])
		menuItem.image = [NSImage imageWithSystemSymbolName:
			[NSString stringWithUTF8String:symbol] accessibilityDescription:nil];
	lua_pop(L, 1);

	lua_getfield(L, item, "items");
	if (lua_istable(L, -1))
		menuItem.submenu = main_menu_build(L, lua_gettop(L), title);
	lua_pop(L, 1);
	return menuItem;
}

static NSMenu *main_menu_build(lua_State *L, int index, NSString *title) {
	NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
	int count = (int)lua_rawlen(L, index);
	for (int i = 1; i <= count; i++) {
		lua_rawgeti(L, index, i);
		if (lua_istable(L, -1)) [menu addItem:main_menu_item(L)];
		lua_pop(L, 1);
	}
	return menu;
}

/* _setMainMenu(appName, menus, helpTopics): replaces NSApp.mainMenu with
 * `{title, role, items}` menus assembled by the Lua command layer. Roles
 * hand AppKit the menus it manages itself: `services`, `windows` (window
 * list and tiling items) and `help` (the Help search field). */
static int bridge_set_main_menu(lua_State *L) {
	NSString *appName = [NSString stringWithUTF8String:luaL_checkstring(L, 1)];
	luaL_checktype(L, 2, LUA_TTABLE);
	set_application_name(appName);
	if (!main_menu_about_target) main_menu_about_target = [LuaAboutTarget new];
	main_menu_about_target.applicationName = appName;

	NSMenu *mainMenu = [[NSMenu alloc] init];
	NSApp.servicesMenu = nil;
	int count = (int)lua_rawlen(L, 2);
	for (int i = 1; i <= count; i++) {
		lua_rawgeti(L, 2, i);
		lua_getfield(L, -1, "title");
		NSString *title = [NSString stringWithUTF8String:luaL_optstring(L, -1, "")];
		lua_pop(L, 1);
		lua_getfield(L, -1, "items");
		NSMenu *menu = main_menu_build(L, lua_gettop(L), title);
		lua_pop(L, 1);
		lua_getfield(L, -1, "role");
		const char *role = lua_tostring(L, -1);
		if (role && strcmp(role, "windows") == 0) NSApp.windowsMenu = menu;
		if (role && strcmp(role, "help") == 0) NSApp.helpMenu = menu;
		lua_pop(L, 2);
		NSMenuItem *top = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
		top.submenu = menu;
		[mainMenu addItem:top];
	}
	NSApp.mainMenu = mainMenu;

	if (main_menu_help_search)
		[NSApp unregisterUserInterfaceItemSearchHandler:main_menu_help_search];
	main_menu_help_search = nil;
	if (lua_istable(L, 3)) {
		NSMutableArray *topics = [NSMutableArray array];
		int topicCount = (int)lua_rawlen(L, 3);
		for (int i = 1; i <= topicCount; i++) {
			lua_rawgeti(L, 3, i);
			LuaHelpTopic *topic = [LuaHelpTopic new];
			lua_getfield(L, -1, "title");
			topic.title = [NSString stringWithUTF8String:luaL_optstring(L, -1, "")];
			lua_getfield(L, -2, "keywords");
			topic.keywords = [[topic.title stringByAppendingFormat:@" %s",
				luaL_optstring(L, -1, "")] lowercaseString];
			lua_getfield(L, -3, "action");
			topic.action = lua_reg_opt(L, -1);
			lua_pop(L, 4);
			if (topic.action) [topics addObject:topic];
		}
		main_menu_help_search = [LuaHelpSearch new];
		main_menu_help_search.topics = topics;
		[NSApp registerUserInterfaceItemSearchHandler:main_menu_help_search];
	}
	return 0;
}

static void main_menu_push_snapshot(lua_State *L, NSMenu *menu) {
	[menu update];
	lua_createtable(L, (int)menu.numberOfItems, 0);
	for (NSInteger index = 0; index < menu.numberOfItems; index++) {
		NSMenuItem *item = [menu itemAtIndex:index];
		lua_newtable(L);
		if (item.separatorItem) {
			lua_pushboolean(L, 1); lua_setfield(L, -2, "separator");
		} else {
			lua_pushstring(L, item.title.UTF8String); lua_setfield(L, -2, "title");
			lua_pushstring(L, item.keyEquivalent.UTF8String); lua_setfield(L, -2, "keyEquivalent");
			NSEventModifierFlags flags = item.keyEquivalentModifierMask;
			NSMutableArray *names = [NSMutableArray array];
			if (flags & NSEventModifierFlagCommand) [names addObject:@"command"];
			if (flags & NSEventModifierFlagShift) [names addObject:@"shift"];
			if (flags & NSEventModifierFlagOption) [names addObject:@"option"];
			if (flags & NSEventModifierFlagControl) [names addObject:@"control"];
			lua_pushstring(L, [names componentsJoinedByString:@","].UTF8String);
			lua_setfield(L, -2, "modifiers");
			if (item.action) {
				lua_pushstring(L, NSStringFromSelector(item.action).UTF8String);
				lua_setfield(L, -2, "selector");
			}
			lua_pushboolean(L, item.enabled); lua_setfield(L, -2, "enabled");
			lua_pushboolean(L, item.state == NSControlStateValueOn); lua_setfield(L, -2, "checked");
			if (item.submenu) {
				main_menu_push_snapshot(L, item.submenu);
				lua_setfield(L, -2, "items");
			}
		}
		lua_rawseti(L, -2, index + 1);
	}
}

/* Headless tests read the installed main menu after AppKit validation:
 * `{title, items = {...}}` per menu plus the app, windows and help roles. */
static int bridge_main_menu_snapshot(lua_State *L) {
	NSMenu *mainMenu = NSApp.mainMenu;
	if (!mainMenu) { lua_pushnil(L); return 1; }
	lua_newtable(L);
	lua_pushstring(L, NSProcessInfo.processInfo.processName.UTF8String);
	lua_setfield(L, -2, "appName");
	lua_pushstring(L, NSApp.windowsMenu.title.UTF8String ?: "");
	lua_setfield(L, -2, "windowsMenu");
	lua_pushstring(L, NSApp.helpMenu.title.UTF8String ?: "");
	lua_setfield(L, -2, "helpMenu");
	lua_pushboolean(L, NSApp.servicesMenu != nil);
	lua_setfield(L, -2, "servicesMenu");
	lua_createtable(L, (int)mainMenu.numberOfItems, 0);
	for (NSInteger index = 0; index < mainMenu.numberOfItems; index++) {
		NSMenuItem *top = [mainMenu itemAtIndex:index];
		lua_newtable(L);
		lua_pushstring(L, top.submenu.title.UTF8String ?: "");
		lua_setfield(L, -2, "title");
		main_menu_push_snapshot(L, top.submenu);
		lua_setfield(L, -2, "items");
		lua_rawseti(L, -2, index + 1);
	}
	lua_setfield(L, -2, "menus");
	return 1;
}

/* _performMainMenuItem(menuTitle, itemTitle, ...) validates and performs the
 * item at that title path exactly as choosing it would. */
static int bridge_perform_main_menu_item(lua_State *L) {
	NSMenu *menu = NSApp.mainMenu;
	NSMenuItem *item = nil;
	int top = lua_gettop(L);
	for (int i = 1; i <= top; i++) {
		NSString *title = [NSString stringWithUTF8String:luaL_checkstring(L, i)];
		NSMenuItem *found = nil;
		for (NSMenuItem *candidate in menu.itemArray) {
			NSString *candidateTitle = i == 1 && candidate.submenu ? candidate.submenu.title : candidate.title;
			if ([candidateTitle isEqualToString:title]) { found = candidate; break; }
		}
		if (!found) return luaL_error(L, "main menu has no item \"%s\"", title.UTF8String);
		item = found;
		menu = found.submenu;
	}
	if (!item || item.submenu) return luaL_error(L, "main menu path names a menu, not a command");
	[item.menu update];
	if (!item.enabled || !item.action) return luaL_error(L, "main menu item \"%s\" is not enabled", item.title.UTF8String);
	[NSApp sendAction:item.action to:item.target from:item];
	return 0;
}

/* _searchHelp(query[, perform]) returns matching help-search titles in
 * order; with `perform`, chooses that 1-based result as the Help menu does. */
static int bridge_search_help(lua_State *L) {
	NSString *query = [NSString stringWithUTF8String:luaL_checkstring(L, 1)];
	NSInteger perform = (NSInteger)luaL_optinteger(L, 2, 0);
	NSArray<LuaHelpTopic *> *found = main_menu_help_search
		? [main_menu_help_search matches:query limit:NSIntegerMax] : @[];
	if (perform > 0) {
		if (perform > (NSInteger)found.count) return luaL_error(L, "help search has no result %d", (int)perform);
		[main_menu_help_search performActionForItem:found[perform - 1]];
		return 0;
	}
	lua_createtable(L, (int)found.count, 0);
	for (NSUInteger i = 0; i < found.count; i++) {
		lua_pushstring(L, found[i].title.UTF8String);
		lua_rawseti(L, -2, (int)i + 1);
	}
	return 1;
}
