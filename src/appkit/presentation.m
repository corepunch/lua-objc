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
	if ([name isEqualToString:@"menu"]) return NSVisualEffectMaterialMenu;
	if ([name isEqualToString:@"sidebar"]) return NSVisualEffectMaterialSidebar;
	if ([name isEqualToString:@"headerView"]) return NSVisualEffectMaterialHeaderView;
	return NSVisualEffectMaterialPopover;
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

static int bridge_panel_style_state(lua_State *L) {
	id obj = check_objc(L, 1);
	if (![obj isKindOfClass:[LuaPanel class]]) {
		return luaL_error(L, "panelStyleState requires a panel");
	}
	LuaPanel *panel = (LuaPanel *)obj;
	lua_newtable(L);
	lua_pushboolean(L, panel.hasShadow);
	lua_setfield(L, -2, "usesNativeShadow");
	lua_pushboolean(L,
		(panel.styleMask & NSWindowStyleMaskTitled) != 0
		&& (panel.styleMask & NSWindowStyleMaskFullSizeContentView) != 0);
	lua_setfield(L, -2, "usesNativeFrame");
	return 1;
}

static int bridge_present_panel(lua_State *L) {
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

static int bridge_dismiss_window(lua_State *L) {
	id obj = check_objc(L, 1);
	if (![obj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "dismissWindow requires a window");
	}
	NSWindow *window = (NSWindow *)obj;
	[window orderOut:nil];
	[window.parentWindow removeChildWindow:window];
	return 0;
}

static int bridge_focus(lua_State *L) {
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

static int bridge_is_first_responder(lua_State *L) {
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

#pragma mark - Generic Menu Items

@interface LuaMenuActionTarget : NSObject
@property (nonatomic) int callbackRef;
@property (nonatomic, weak) LuaStateOwner *owner;
@end

@implementation LuaMenuActionTarget

- (void)dealloc {
	lua_State *callL = _owner.L;
	if (_callbackRef != LUA_NOREF && callL) {
		luaL_unref(callL, LUA_REGISTRYINDEX, _callbackRef);
	}
}

- (void)performAction:(id)sender {
	lua_State *callL = _owner.L;
	if (_callbackRef == LUA_NOREF || !callL) return;
	lua_rawgeti(callL, LUA_REGISTRYINDEX, _callbackRef);
	lua_objc_pcall(callL, 0, 0, "menu action");
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

static int bridge_menu_item(lua_State *L) {
	const char *menuC = luaL_checkstring(L, 1);
	const char *titleC = luaL_checkstring(L, 2);
	const char *keyC = luaL_optstring(L, 3, "");
	const char *modifiersC = luaL_optstring(L, 4, "command");
	luaL_checktype(L, 5, LUA_TFUNCTION);

	NSString *menuTitle = [NSString stringWithUTF8String:menuC];
	NSString *itemTitle = [NSString stringWithUTF8String:titleC];
	NSMenuItem *menuItem = [NSApp.mainMenu itemWithTitle:menuTitle];
	if (!menuItem) {
		menuItem = [[NSMenuItem alloc] initWithTitle:menuTitle
			action:nil keyEquivalent:@""];
		menuItem.submenu = [[NSMenu alloc] initWithTitle:menuTitle];
		[NSApp.mainMenu addItem:menuItem];
	}

	NSMenu *menu = menuItem.submenu;
	NSMenuItem *existing = [menu itemWithTitle:itemTitle];
	if (existing) [menu removeItem:existing];

	lua_pushvalue(L, 5);
	LuaMenuActionTarget *target = [[LuaMenuActionTarget alloc] init];
	target.callbackRef = luaL_ref(L, LUA_REGISTRYINDEX);
	target.owner = owner_for_state(L);
	NSMenuItem *item = [[NSMenuItem alloc]
		initWithTitle:itemTitle
			  action:@selector(performAction:)
	   keyEquivalent:[NSString stringWithUTF8String:keyC]];
	item.target = target;
	item.keyEquivalentModifierMask = menu_modifiers(
		[NSString stringWithUTF8String:modifiersC]);
	objc_setAssociatedObject(item, &kKeys[kMenuTargetKey], target,
		OBJC_ASSOCIATION_RETAIN);
	[menu addItem:item];
	push_objc(L, item, "nsobject");
	return 1;
}
