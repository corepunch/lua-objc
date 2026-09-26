#pragma mark - Context Menu (right-click)

static const char kContextMenuDelegateKey;

/* Appends `{title, action, systemImage, disabled, separator}` records from the
 * array on top of the stack, then pops it. View context menus and table row
 * menus share this vocabulary. */
static void lua_menu_fill_from_stack(lua_State *L, NSMenu *menu) {
	if (!lua_istable(L, -1)) { lua_pop(L, 1); return; }

	int n = (int)lua_rawlen(L, -1);
	for (int i = 1; i <= n; i++) {
		lua_rawgeti(L, -1, i);
		if (!lua_istable(L, -1)) { lua_pop(L, 1); continue; }

		lua_getfield(L, -1, "separator");
		if (lua_toboolean(L, -1)) {
			[menu addItem:[NSMenuItem separatorItem]];
			lua_pop(L, 2);
			continue;
		}
		lua_pop(L, 1);

		lua_getfield(L, -1, "title");
		const char *titleC = lua_tostring(L, -1) ?: "";
		NSString *title = [NSString stringWithUTF8String:titleC];
		lua_pop(L, 1);

		NSMenuItem *item = [[NSMenuItem alloc]
			initWithTitle:title action:nil keyEquivalent:@""];

		lua_getfield(L, -1, "action");
		if (lua_isfunction(L, -1)) {
			LuaMenuActionTarget *target = [[LuaMenuActionTarget alloc] init];
			target.callback = lua_reg_create(L, lua_gettop(L), YES);
			item.action = @selector(performAction:);
			item.target = target;
			objc_setAssociatedObject(item, &kKeys[kMenuTargetKey], target,
				OBJC_ASSOCIATION_RETAIN);
		}
		lua_pop(L, 1);

		lua_getfield(L, -1, "disabled");
		if (lua_toboolean(L, -1)) item.enabled = NO;
		lua_pop(L, 1);

		lua_getfield(L, -1, "systemImage");
		const char *imgC = lua_tostring(L, -1);
		if (imgC) {
			NSImage *img = [NSImage imageWithSystemSymbolName:
				[NSString stringWithUTF8String:imgC]
				accessibilityDescription:nil];
			if (img) item.image = img;
		}
		lua_pop(L, 1);

		[menu addItem:item];
		lua_pop(L, 1);
	}
	lua_pop(L, 1);
}

@interface LuaContextMenuBuilder : NSObject <NSMenuDelegate>
@property (nonatomic) LuaReg *reg;
@end

@implementation LuaContextMenuBuilder

- (void)dealloc {
	[_reg dispose];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
	[menu removeAllItems];
	lua_State *L = lua_reg_live_state(_reg);
	if (!L || !lua_reg_push(_reg)) return;
	if (lua_objc_pcall(L, 0, 1, "context menu") != LUA_OK) return;
	lua_menu_fill_from_stack(L, menu);
}

@end

static int bridge_add_context_menu(lua_State *L) {
	NSView *view = check_view(L, 1);
	LuaReg *reg = lua_reg_opt(L, 2);
	if (!reg) {
		view.menu = nil;
		objc_setAssociatedObject(view, &kContextMenuDelegateKey, nil,
			OBJC_ASSOCIATION_RETAIN);
		return 0;
	}
	LuaContextMenuBuilder *builder = [LuaContextMenuBuilder new];
	builder.reg = reg;
	NSMenu *menu = [[NSMenu alloc] init];
	menu.delegate = builder;
	menu.autoenablesItems = NO;
	view.menu = menu;
	objc_setAssociatedObject(view, &kContextMenuDelegateKey, builder,
		OBJC_ASSOCIATION_RETAIN);
	return 0;
}

#pragma mark - Single Click

static const char kSingleClickHandlerKey;

@interface LuaSingleClickHandler : NSObject
@property (nonatomic) LuaReg *reg;
@end

@implementation LuaSingleClickHandler
- (void)dealloc { [_reg dispose]; }
- (void)fire:(NSClickGestureRecognizer *)r {
	if (r.state != NSGestureRecognizerStateRecognized) return;
	lua_State *L = lua_reg_live_state(self.reg);
	if (L && lua_reg_push(self.reg))
		lua_objc_pcall(L, 0, 0, "click");
}
@end

static int bridge_add_click(lua_State *L) {
	NSView *view = check_view(L, 1);
	LuaReg *reg = lua_reg_opt(L, 2);
	if (!reg) return 0;
	LuaSingleClickHandler *handler = [LuaSingleClickHandler new];
	handler.reg = reg;
	objc_setAssociatedObject(view, &kSingleClickHandlerKey, handler,
		OBJC_ASSOCIATION_RETAIN);
	NSClickGestureRecognizer *gr = [[NSClickGestureRecognizer alloc]
		initWithTarget:handler action:@selector(fire:)];
	gr.numberOfClicksRequired = 1;
	[view addGestureRecognizer:gr];
	return 0;
}

#pragma mark - NSWorkspace Operations

static int bridge_reveal_in_finder(lua_State *L) {
	const char *pathC = luaL_checkstring(L, 1);
	NSString *path = [NSString stringWithUTF8String:pathC];
	NSURL *url = [NSURL fileURLWithPath:path];
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[url]];
	return 0;
}

static int bridge_open_path(lua_State *L) {
	const char *pathC = luaL_checkstring(L, 1);
	NSURL *url = [NSURL fileURLWithPath:
		[NSString stringWithUTF8String:pathC]];
	BOOL ok = [[NSWorkspace sharedWorkspace] openURL:url];
	lua_pushboolean(L, ok);
	return 1;
}

static int bridge_move_to_trash(lua_State *L) {
	const char *pathC = luaL_checkstring(L, 1);
	NSURL *url = [NSURL fileURLWithPath:
		[NSString stringWithUTF8String:pathC]];
	NSError *error = nil;
	BOOL ok = [[NSFileManager defaultManager]
		trashItemAtURL:url resultingItemURL:nil error:&error];
	lua_pushboolean(L, ok);
	if (!ok && error) {
		lua_pushstring(L, error.localizedDescription.UTF8String);
		return 2;
	}
	return 1;
}

#pragma mark - Clipboard

static int bridge_clipboard_copy(lua_State *L) {
	const char *text = luaL_checkstring(L, 1);
	NSPasteboard *pb = [NSPasteboard generalPasteboard];
	[pb clearContents];
	[pb setString:[NSString stringWithUTF8String:text]
		  forType:NSPasteboardTypeString];
	return 0;
}

#pragma mark - NSAlert

static int bridge_alert(lua_State *L) {
	const char *titleC = luaL_checkstring(L, 1);
	const char *messageC = luaL_optstring(L, 2, "");
	luaL_checktype(L, 3, LUA_TTABLE);

	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = [NSString stringWithUTF8String:titleC];
	alert.informativeText = [NSString stringWithUTF8String:messageC];
	alert.alertStyle = NSAlertStyleWarning;

	int n = (int)lua_rawlen(L, 3);
	for (int i = 1; i <= n; i++) {
		lua_rawgeti(L, 3, i);
		const char *btnTitle = lua_tostring(L, -1) ?: "OK";
		[alert addButtonWithTitle:[NSString stringWithUTF8String:btnTitle]];
		lua_pop(L, 1);
	}

	NSModalResponse response = [alert runModal];
	lua_pushinteger(L, (lua_Integer)(response - NSAlertFirstButtonReturn + 1));
	return 1;
}

#pragma mark - Disk Free Space

static int bridge_disk_space(lua_State *L) {
	const char *pathC = luaL_checkstring(L, 1);
	NSError *error = nil;
	NSDictionary *attrs = [[NSFileManager defaultManager]
		attributesOfFileSystemForPath:
			[NSString stringWithUTF8String:pathC]
		error:&error];
	if (!attrs) { lua_pushnil(L); return 1; }

	lua_newtable(L);
	NSNumber *freeSize = attrs[NSFileSystemFreeSize];
	NSNumber *totalSize = attrs[NSFileSystemSize];
	lua_pushinteger(L,
		(lua_Integer)(freeSize.unsignedLongLongValue / 1024));
	lua_setfield(L, -2, "freeKb");
	lua_pushinteger(L,
		(lua_Integer)(totalSize.unsignedLongLongValue / 1024));
	lua_setfield(L, -2, "totalKb");
	return 1;
}
