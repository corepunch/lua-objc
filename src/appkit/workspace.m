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

	NSWindow *parent = lua_isnoneornil(L, 4) ? nil : check_objc(L, 4);
	NSModalResponse response;
	if (parent) {
		if (![parent isKindOfClass:[NSWindow class]]) return luaL_error(L, "Alert parent must be a window");
		while (parent.attachedSheet) parent = parent.attachedSheet;
		__block NSModalResponse selected = NSModalResponseCancel;
		[alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse result) {
			selected = result;
			[NSApp stopModal];
		}];
		[NSApp runModalForWindow:alert.window];
		response = selected;
	} else {
		response = [alert runModal];
	}
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

#pragma mark - Volume capacity

/* Total and available capacity as Finder reports them. `important` includes
 * purgeable storage macOS will free for an app that needs it; `available` is
 * the file system's free space. Their difference is purgeable space. */
static int bridge_volume_capacity(lua_State *L) {
	NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:luaL_checkstring(L, 1)]];
	NSDictionary *values = [url resourceValuesForKeys:@[
		NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityKey,
		NSURLVolumeAvailableCapacityForImportantUsageKey,
		NSURLVolumeAvailableCapacityForOpportunisticUsageKey] error:nil];
	if (!values) { lua_pushnil(L); return 1; }
	lua_newtable(L);
	NSDictionary<NSString *, NSString *> *names = @{
		NSURLVolumeTotalCapacityKey: @"total",
		NSURLVolumeAvailableCapacityKey: @"available",
		NSURLVolumeAvailableCapacityForImportantUsageKey: @"important",
		NSURLVolumeAvailableCapacityForOpportunisticUsageKey: @"opportunistic"};
	for (NSString *key in names) {
		NSNumber *number = values[key];
		if (![number isKindOfClass:NSNumber.class]) continue;
		lua_pushnumber(L, number.doubleValue);
		lua_setfield(L, -2, names[key].UTF8String);
	}
	return 1;
}

#pragma mark - Opened files and Quick Look

/* The application delegate exists for two AppKit conventions that need an
 * object in the application's responder chain: folders and files dropped on
 * the Dock icon or opened from the Finder arrive as `application:openURLs:`,
 * and the shared Quick Look panel asks the responder chain for its
 * controller. It is installed on first use and implements nothing else, so
 * an app that never asks keeps AppKit's default behavior. */
@interface LuaApplicationDelegate : NSObject <NSApplicationDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate>
@property (nonatomic, strong) LuaReg *openHandler;
@property (nonatomic, strong) NSMutableArray<NSString *> *pendingPaths;
@property (nonatomic, copy) NSArray<NSURL *> *previewItems;
@property (nonatomic) NSInteger previewIndex;
@end

@implementation LuaApplicationDelegate
- (instancetype)init {
	if ((self = [super init])) _pendingPaths = [NSMutableArray array];
	return self;
}
// Opens that arrive before the app registers its handler, as they do when a
// folder dropped on the Dock icon launches the app, wait for it.
- (BOOL)deliver:(NSArray<NSString *> *)paths {
	lua_State *L = lua_reg_live_state(self.openHandler);
	if (!L || !paths.count || !lua_reg_push(self.openHandler)) return NO;
	lua_createtable(L, (int)paths.count, 0);
	for (NSUInteger i = 0; i < paths.count; i++) { lua_pushstring(L, paths[i].UTF8String); lua_rawseti(L, -2, (lua_Integer)i + 1); }
	lua_objc_pcall(L, 1, 0, "open files");
	return YES;
}
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
	(void)application;
	NSMutableArray<NSString *> *paths = [NSMutableArray array];
	for (NSURL *url in urls) if (url.isFileURL && url.path.length) [paths addObject:url.path];
	if (![self deliver:paths]) [self.pendingPaths addObjectsFromArray:paths];
}
- (BOOL)acceptsPreviewPanelControl:(QLPreviewPanel *)panel { (void)panel; return self.previewItems.count > 0; }
- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel {
	panel.dataSource = self; panel.delegate = self;
	panel.currentPreviewItemIndex = self.previewIndex;
}
- (void)endPreviewPanelControl:(QLPreviewPanel *)panel { panel.dataSource = nil; panel.delegate = nil; }
- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel { (void)panel; return (NSInteger)self.previewItems.count; }
- (id<QLPreviewItem>)previewPanel:(QLPreviewPanel *)panel previewItemAtIndex:(NSInteger)index {
	(void)panel;
	return index >= 0 && index < (NSInteger)self.previewItems.count ? self.previewItems[(NSUInteger)index] : nil;
}
@end

static LuaApplicationDelegate *lua_objc_application_delegate(void) {
	static LuaApplicationDelegate *delegate;
	if (!delegate) {
		delegate = [LuaApplicationDelegate new];
		[NSApplication sharedApplication].delegate = delegate;
	}
	return delegate;
}

static NSArray<NSString *> *string_array(lua_State *L, int index) {
	luaL_checktype(L, index, LUA_TTABLE);
	NSMutableArray<NSString *> *strings = [NSMutableArray array];
	for (lua_Integer i = 1; ; i++) {
		lua_rawgeti(L, index, i);
		if (lua_isnil(L, -1)) { lua_pop(L, 1); break; }
		[strings addObject:[NSString stringWithUTF8String:luaL_checkstring(L, -1)]];
		lua_pop(L, 1);
	}
	return strings;
}

// _onOpenFiles(handler(paths) | nil): folders and files opened with the app.
static int bridge_on_open_files(lua_State *L) {
	LuaApplicationDelegate *delegate = lua_objc_application_delegate();
	[delegate.openHandler dispose];
	delegate.openHandler = lua_reg_opt_unscoped(L, 1);
	if (delegate.openHandler && delegate.pendingPaths.count) {
		// After the caller finishes setting up, as a launch-time open would.
		dispatch_async(dispatch_get_main_queue(), ^{
			NSArray<NSString *> *pending = delegate.pendingPaths.copy;
			if ([delegate deliver:pending]) [delegate.pendingPaths removeAllObjects];
		});
	}
	return 0;
}

// Test hook: _openFiles(paths) as if the Finder opened them with the app.
static int bridge_open_files(lua_State *L) {
	NSMutableArray<NSURL *> *urls = [NSMutableArray array];
	for (NSString *path in string_array(L, 1)) [urls addObject:[NSURL fileURLWithPath:path]];
	[lua_objc_application_delegate() application:NSApp openURLs:urls];
	return 0;
}

// _quickLook(paths, index): shows the items in the system Quick Look panel,
// starting at `index` (1-based); an empty list closes the panel. The panel
// is shown only while the event loop runs, so headless tests record the
// items without opening a window.
static int bridge_quick_look(lua_State *L) {
	LuaApplicationDelegate *delegate = lua_objc_application_delegate();
	NSMutableArray<NSURL *> *urls = [NSMutableArray array];
	for (NSString *path in string_array(L, 1)) [urls addObject:[NSURL fileURLWithPath:path]];
	lua_Integer index = luaL_optinteger(L, 2, 1);
	delegate.previewItems = urls;
	delegate.previewIndex = MAX(0, MIN((NSInteger)index - 1, (NSInteger)urls.count - 1));
	if (!NSApp.isRunning) return 0;
	QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
	if (!urls.count) { if (QLPreviewPanel.sharedPreviewPanelExists && panel.isVisible) [panel orderOut:nil]; return 0; }
	if (panel.isVisible && panel.currentController == delegate) {
		[panel reloadData];
		panel.currentPreviewItemIndex = delegate.previewIndex;
	} else {
		[panel updateController];
		[panel makeKeyAndOrderFront:nil];
	}
	return 0;
}

// Test hook: _quickLookItems() -> the paths Quick Look would show.
static int bridge_quick_look_items(lua_State *L) {
	NSArray<NSURL *> *items = lua_objc_application_delegate().previewItems ?: @[];
	lua_createtable(L, (int)items.count, 0);
	for (NSUInteger i = 0; i < items.count; i++) { lua_pushstring(L, items[i].path.UTF8String); lua_rawseti(L, -2, (lua_Integer)i + 1); }
	return 1;
}

#pragma mark - Moving items

// _moveItem(source, folder, completion(ok, message, destination)): moves a
// file or folder into `folder`, on another disk too (AppKit then copies and
// removes the original). It runs off the main thread, so a large move never
// stalls the window; an existing item of the same name is never replaced.
static int bridge_move_item(lua_State *L) {
	NSString *source = [NSString stringWithUTF8String:luaL_checkstring(L, 1)];
	NSString *folder = [NSString stringWithUTF8String:luaL_checkstring(L, 2)];
	LuaReg *completion = lua_reg_create(L, 3, NO);
	NSString *destination = [folder stringByAppendingPathComponent:source.lastPathComponent];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *error = nil;
		BOOL ok = NO;
		NSString *message = nil;
		if ([NSFileManager.defaultManager fileExistsAtPath:destination]) {
			message = [NSString stringWithFormat:@"An item named “%@” already exists in “%@”.", source.lastPathComponent, folder.lastPathComponent];
		} else {
			ok = [NSFileManager.defaultManager moveItemAtURL:[NSURL fileURLWithPath:source]
				toURL:[NSURL fileURLWithPath:destination] error:&error];
			if (!ok) message = error.localizedDescription ?: @"The item could not be moved.";
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			lua_State *state = lua_reg_live_state(completion);
			if (state && lua_reg_push(completion)) {
				lua_pushboolean(state, ok);
				if (message) lua_pushstring(state, message.UTF8String); else lua_pushnil(state);
				lua_pushstring(state, destination.UTF8String);
				lua_objc_pcall(state, 3, 0, "move item");
			}
			[completion dispose];
		});
	});
	return 0;
}

#pragma mark - Checks before moving

// _runningApplications() -> bundle identifiers of the running apps, so a
// cleanup can skip a cache while the app that writes it is open.
static int bridge_running_applications(lua_State *L) {
	NSArray<NSRunningApplication *> *apps = NSWorkspace.sharedWorkspace.runningApplications;
	lua_createtable(L, (int)apps.count, 0);
	lua_Integer index = 1;
	for (NSRunningApplication *app in apps) {
		if (!app.bundleIdentifier.length) continue;
		lua_pushstring(L, app.bundleIdentifier.UTF8String);
		lua_rawseti(L, -2, index++);
	}
	return 1;
}

// _applicationPath(bundleIdentifier) -> the installed app LaunchServices
// knows for it, wherever it lives, or nil.
static int bridge_application_path(lua_State *L) {
	NSString *identifier = [NSString stringWithUTF8String:luaL_checkstring(L, 1)];
	NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:identifier];
	if (url.path.length) lua_pushstring(L, url.path.UTF8String); else lua_pushnil(L);
	return 1;
}

// _codeSignatures(paths, completion(signatures)): each signed bundle's
// team identifier and app groups, keyed by path, read from its signature
// without validating it. A Group Container is named by an app group, so
// this is how a folder such as "UBF8T346G9.Office" finds its apps. Reading
// every app on a Mac takes seconds, so it runs off the main thread; an
// unsigned or unreadable bundle is left out.
static int bridge_code_signatures(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	NSMutableArray<NSString *> *paths = [NSMutableArray array];
	lua_Integer count = luaL_len(L, 1);
	for (lua_Integer i = 1; i <= count; i++) {
		lua_rawgeti(L, 1, i);
		if (lua_type(L, -1) == LUA_TSTRING) [paths addObject:[NSString stringWithUTF8String:lua_tostring(L, -1)]];
		lua_pop(L, 1);
	}
	LuaReg *completion = lua_reg_create(L, 2, NO);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSMutableDictionary<NSString *, NSDictionary *> *signatures = [NSMutableDictionary dictionary];
		for (NSString *path in paths) {
			SecStaticCodeRef code = NULL;
			if (SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:path], kSecCSDefaultFlags, &code) != errSecSuccess || !code) continue;
			CFDictionaryRef copied = NULL;
			OSStatus status = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &copied);
			CFRelease(code);
			if (status != errSecSuccess || !copied) continue;
			NSDictionary *information = (__bridge_transfer NSDictionary *)copied;
			NSString *team = information[(__bridge NSString *)kSecCodeInfoTeamIdentifier];
			id groups = [information[(__bridge NSString *)kSecCodeInfoEntitlementsDict] objectForKey:@"com.apple.security.application-groups"];
			NSMutableDictionary *signature = [NSMutableDictionary dictionary];
			if ([team isKindOfClass:NSString.class] && team.length) signature[@"team"] = team;
			if ([groups isKindOfClass:NSArray.class]) {
				NSMutableArray *names = [NSMutableArray array];
				for (id group in groups) if ([group isKindOfClass:NSString.class]) [names addObject:group];
				if (names.count) signature[@"groups"] = names;
			}
			if (signature.count) signatures[path] = signature;
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			lua_State *state = lua_reg_live_state(completion);
			if (state && lua_reg_push(completion)) {
				lua_createtable(state, 0, (int)signatures.count);
				[signatures enumerateKeysAndObjectsUsingBlock:^(NSString *path, NSDictionary *signature, BOOL *stop) {
					lua_createtable(state, 0, 2);
					if (signature[@"team"]) { lua_pushstring(state, [signature[@"team"] UTF8String]); lua_setfield(state, -2, "team"); }
					NSArray<NSString *> *groups = signature[@"groups"];
					if (groups) {
						lua_createtable(state, (int)groups.count, 0);
						for (NSUInteger i = 0; i < groups.count; i++) { lua_pushstring(state, groups[i].UTF8String); lua_rawseti(state, -2, (lua_Integer)i + 1); }
						lua_setfield(state, -2, "groups");
					}
					lua_setfield(state, -2, path.UTF8String);
				}];
				lua_objc_pcall(state, 1, 0, "code signatures");
			}
			[completion dispose];
		});
	});
	return 0;
}

// _fileIdentity(path) -> {inode, device, symlink} from lstat, or nil when
// the path is gone. A different inode at the same path is a different item.
static int bridge_file_identity(lua_State *L) {
	struct stat info;
	if (lstat(luaL_checkstring(L, 1), &info) != 0) { lua_pushnil(L); return 1; }
	lua_createtable(L, 0, 3);
	lua_pushnumber(L, (lua_Number)info.st_ino); lua_setfield(L, -2, "inode");
	lua_pushnumber(L, (lua_Number)info.st_dev); lua_setfield(L, -2, "device");
	lua_pushboolean(L, S_ISLNK(info.st_mode)); lua_setfield(L, -2, "symlink");
	return 1;
}

#pragma mark - Relaunching

// _relaunch(onFailure(message)): starts a new instance of this app, then
// quits once it is running, as macOS sometimes applies Full Disk Access
// only to a process started after it was granted. An app bundle reopens
// through Launch Services; a development binary restarts with its
// arguments. `onFailure` runs when the new instance could not start.
static int bridge_relaunch(lua_State *L) {
	LuaReg *failure = lua_reg_opt_unscoped(L, 1);
	void (^finish)(BOOL, NSString *) = ^(BOOL ok, NSString *message) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (ok) {
				[failure dispose];
				/* AppKit refuses to quit while a window shows a sheet, which
				 * left both instances running when Restart was clicked in a
				 * sheet. The new instance has everything; end them first. */
				for (NSWindow *window in NSApp.windows) {
					while (window.attachedSheet) [window endSheet:window.attachedSheet];
				}
				[NSApp terminate:nil];
				return;
			}
			lua_State *state = lua_reg_live_state(failure);
			if (state && lua_reg_push(failure)) {
				lua_pushstring(state, message.UTF8String ?: "");
				lua_objc_pcall(state, 1, 0, "relaunch");
			}
			[failure dispose];
		});
	};
	NSBundle *bundle = NSBundle.mainBundle;
	if ([bundle.bundlePath.pathExtension isEqualToString:@"app"]) {
		/* Quit on evidence, not on the completion handler alone: inside the
		 * App Sandbox Launch Services can start the new instance yet report
		 * an error, or report late, which left two copies running. The new
		 * instance appearing among this bundle's running applications is
		 * what counts; failure is reported only if none appears in time. */
		__block BOOL done = NO;
		void (^settle)(BOOL, NSString *) = ^(BOOL ok, NSString *message) {
			if (done) return;
			done = YES;
			finish(ok, message);
		};
		pid_t own = NSProcessInfo.processInfo.processIdentifier;
		NSString *identifier = bundle.bundleIdentifier;
		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:kRelaunchTimeout];
		[NSTimer scheduledTimerWithTimeInterval:kRelaunchPollInterval repeats:YES block:^(NSTimer *timer) {
			if (done) { [timer invalidate]; return; }
			for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:identifier]) {
				if (app.processIdentifier != own && !app.terminated) { [timer invalidate]; settle(YES, nil); return; }
			}
			if (deadline.timeIntervalSinceNow < 0) {
				[timer invalidate];
				settle(NO, @"The new instance did not start. Quit and open Diskmap again.");
			}
		}];
		NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
		configuration.createsNewApplicationInstance = YES;
		[NSWorkspace.sharedWorkspace openApplicationAtURL:bundle.bundleURL configuration:configuration
			completionHandler:^(NSRunningApplication *app, NSError *error) {
				(void)error;
				if (app) dispatch_async(dispatch_get_main_queue(), ^{ settle(YES, nil); });
			}];
		return 0;
	}
	NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
	NSTask *task = [NSTask new];
	task.executableURL = [NSURL fileURLWithPath:bundle.executablePath ?: arguments.firstObject];
	task.arguments = arguments.count > 1 ? [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)] : @[];
	task.currentDirectoryURL = [NSURL fileURLWithPath:NSFileManager.defaultManager.currentDirectoryPath];
	NSError *error = nil;
	BOOL launched = [task launchAndReturnError:&error];
	finish(launched, error.localizedDescription ?: @"The app could not start again.");
	return 0;
}
