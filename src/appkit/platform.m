#pragma mark - Offscreen render

static NSData *offscreen_render(NSView *view, CGFloat width, CGFloat height) {
	NSAppearance *appearance = view.effectiveAppearance;
	view.frame = NSMakeRect(0, 0, width, height);

	/* Wrap in a borderless offscreen window so drawRect: has a valid window. */
	NSWindow *offscreen = [[NSWindow alloc]
		initWithContentRect:NSMakeRect(-10000, -10000, width, height)
				  styleMask:NSWindowStyleMaskBorderless
					backing:NSBackingStoreBuffered
					  defer:NO];
	offscreen.releasedWhenClosed = NO;
	offscreen.appearance = appearance;
	__block NSColor *background;
	[appearance performAsCurrentDrawingAppearance:^{
		background = [NSColor.windowBackgroundColor
			colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
	}];
	offscreen.backgroundColor = background;
	offscreen.opaque = YES;
	offscreen.contentView.wantsLayer = YES;
	offscreen.contentView.layer.backgroundColor = background.CGColor;
	[offscreen.contentView addSubview:view];
	[offscreen orderBack:nil];

	NSView *renderRoot = offscreen.contentView;
	NSBitmapImageRep *rep = [renderRoot
		bitmapImageRepForCachingDisplayInRect:renderRoot.bounds];
	if (!rep) {
		[view removeFromSuperview];
		[offscreen close];
		return nil;
	}

	CGFloat scale = [NSScreen mainScreen]
		? [NSScreen mainScreen].backingScaleFactor : kFallbackBackingScale;
	(void)scale;

	[renderRoot cacheDisplayInRect:renderRoot.bounds toBitmapImageRep:rep];

	NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG
									properties:@{}];

	[view removeFromSuperview];
	[offscreen close];
	return png;
}

static int bridge_NSView_renderToPNG_impl(lua_State *L) {
	NSView *view  = check_view(L, 1);
	CGFloat width  = luaL_optnumber(L, 2, kRenderDefaultWidth);
	CGFloat height = luaL_optnumber(L, 3, kRenderDefaultHeight);
	view.frame = NSMakeRect(0, 0, width, height);
	layout_recursive(view, width);
	NSData *png = offscreen_render(view, width, height);
	if (!png) { lua_pushnil(L); return 1; }
	lua_pushlstring(L, png.bytes, png.length);
	return 1;
}

#pragma mark - File system watcher

/* FSEvents for a file or a directory tree. Each watch is its own stream with
 * its own callback, stopped by `_unwatch(token)` or when its Scope closes;
 * the Lua handle in AppKit.watch owns that lifetime. `since` replays events
 * recorded after an earlier event ID, so a watcher can learn what changed
 * while the app was not running. */

@interface LuaWatcher : NSObject
@property (nonatomic) FSEventStreamRef stream;
@property (nonatomic, strong) LuaReg *reg;
@end

@implementation LuaWatcher
- (void)stop {
	if (_stream) {
		FSEventStreamStop(_stream);
		FSEventStreamInvalidate(_stream);
		FSEventStreamRelease(_stream);
		_stream = NULL;
	}
	[_reg dispose];
	_reg = nil;
}
- (void)dealloc { [self stop]; }
@end

static NSMutableDictionary<NSNumber *, LuaWatcher *> *gWatchers = nil;
static NSInteger gNextWatcher = 0;

static void watcher_callback(ConstFSEventStreamRef streamRef, void *info, size_t count, void *eventPaths,
	const FSEventStreamEventFlags *flags, const FSEventStreamEventId *ids) {
	(void)streamRef;
	LuaWatcher *watcher = gWatchers[@((NSInteger)(intptr_t)info)];
	lua_State *L = lua_reg_live_state(watcher.reg);
	if (!L || !lua_reg_push(watcher.reg)) return;
	char **paths = eventPaths;
	lua_createtable(L, (int)count, 0);
	for (size_t i = 0; i < count; i++) {
		FSEventStreamEventFlags f = flags[i];
		lua_createtable(L, 0, 9);
		lua_pushstring(L, paths[i]); lua_setfield(L, -2, "path");
		lua_pushnumber(L, (lua_Number)ids[i]); lua_setfield(L, -2, "id");
		lua_pushboolean(L, (f & kFSEventStreamEventFlagItemCreated) != 0); lua_setfield(L, -2, "created");
		lua_pushboolean(L, (f & kFSEventStreamEventFlagItemRemoved) != 0); lua_setfield(L, -2, "removed");
		lua_pushboolean(L, (f & kFSEventStreamEventFlagItemRenamed) != 0); lua_setfield(L, -2, "renamed");
		lua_pushboolean(L, (f & (kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemInodeMetaMod)) != 0); lua_setfield(L, -2, "modified");
		lua_pushboolean(L, (f & kFSEventStreamEventFlagItemIsDir) != 0); lua_setfield(L, -2, "directory");
		lua_pushboolean(L, (f & kFSEventStreamEventFlagMustScanSubDirs) != 0); lua_setfield(L, -2, "rescan");
		lua_pushboolean(L, (f & kFSEventStreamEventFlagHistoryDone) != 0); lua_setfield(L, -2, "historyDone");
		lua_rawseti(L, -2, (lua_Integer)i + 1);
	}
	lua_objc_pcall(L, 1, 0, "watch");
}

// _watch(paths, callback, since, latency) -> token. `since` is an event ID
// or nil for events from now on.
static int bridge_watch(lua_State *L) {
	NSMutableArray<NSString *> *paths = [NSMutableArray array];
	if (lua_istable(L, 1)) {
		for (lua_Integer i = 1; ; i++) {
			lua_rawgeti(L, 1, i);
			if (lua_isnil(L, -1)) { lua_pop(L, 1); break; }
			[paths addObject:[NSString stringWithUTF8String:luaL_checkstring(L, -1)]];
			lua_pop(L, 1);
		}
	} else {
		[paths addObject:[NSString stringWithUTF8String:luaL_checkstring(L, 1)]];
	}
	if (paths.count == 0) return luaL_error(L, "watch requires a path");
	luaL_checktype(L, 2, LUA_TFUNCTION);
	FSEventStreamEventId since = lua_isnumber(L, 3) ? (FSEventStreamEventId)lua_tonumber(L, 3) : kFSEventStreamEventIdSinceNow;
	CFTimeInterval latency = luaL_optnumber(L, 4, kFSWatcherLatency);
	if (!gWatchers) gWatchers = [NSMutableDictionary dictionary];
	NSInteger token = ++gNextWatcher;
	FSEventStreamContext ctx = {.version = 0, .info = (void *)(intptr_t)token};
	FSEventStreamRef stream = FSEventStreamCreate(NULL, watcher_callback, &ctx, (__bridge CFArrayRef)paths, since, latency,
		kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer);
	if (!stream) return luaL_error(L, "could not watch %s", paths.firstObject.UTF8String);
	LuaWatcher *watcher = [LuaWatcher new];
	watcher.stream = stream;
	watcher.reg = lua_reg_create(L, 2, NO);
	gWatchers[@(token)] = watcher;
	FSEventStreamSetDispatchQueue(stream, dispatch_get_main_queue());
	FSEventStreamStart(stream);
	lua_pushinteger(L, token);
	return 1;
}

static int bridge_unwatch(lua_State *L) {
	NSNumber *token = @(luaL_checkinteger(L, 1));
	[(LuaWatcher *)gWatchers[token] stop];
	[gWatchers removeObjectForKey:token];
	return 0;
}

// The newest event ID on this Mac: store it to ask later what changed since.
static int bridge_latest_event_id(lua_State *L) {
	lua_pushnumber(L, (lua_Number)FSEventsGetCurrentEventId());
	return 1;
}

static int bridge_pick_folder(lua_State *L) {
	const char *titleC = luaL_optstring(L, 1, "Open Folder");
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.canChooseFiles = NO;
	panel.canChooseDirectories = YES;
	panel.allowsMultipleSelection = NO;
	panel.canCreateDirectories = YES;
	panel.title = [NSString stringWithUTF8String:titleC];

	NSInteger response = [panel runModal];
	if (response != NSModalResponseOK || panel.URL == nil) {
		lua_pushnil(L);
		return 1;
	}

	lua_pushstring(L, panel.URL.path.UTF8String);
	return 1;
}

#pragma mark - Navigation gestures

/* Buttons 4 and 5 of a mouse (buttonNumber 3 and 4) and a two-finger swipe
 * are how a Mac user goes back and forward in any browsing window. The
 * monitor sees only events for its own window and ends with the window. */
static char kNavigationMonitorKey;

@interface LuaNavigationMonitor : NSObject
@property (nonatomic, strong) id monitor;
@property (nonatomic, strong) LuaReg *back;
@property (nonatomic, strong) LuaReg *forward;
@end
@implementation LuaNavigationMonitor
- (void)dealloc {
	if (_monitor) [NSEvent removeMonitor:_monitor];
	[_back dispose]; [_forward dispose];
}
- (BOOL)navigate:(BOOL)forward {
	LuaReg *reg = forward ? self.forward : self.back;
	lua_State *L = lua_reg_live_state(reg);
	if (!L || !lua_reg_push(reg)) return NO;
	lua_objc_pcall(L, 0, 0, forward ? "navigate forward" : "navigate back");
	return YES;
}
@end

// _onNavigationGesture(window, back, forward)
static int bridge_on_navigation_gesture(lua_State *L) {
	NSWindow *window = lua_objc_check_object(L, 1, [NSWindow class], "window");
	LuaNavigationMonitor *navigation = [LuaNavigationMonitor new];
	navigation.back = lua_reg_opt(L, 2);
	navigation.forward = lua_reg_opt(L, 3);
	__weak NSWindow *weakWindow = window;
	__weak LuaNavigationMonitor *weakNavigation = navigation;
	navigation.monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskOtherMouseDown | NSEventMaskSwipe
		handler:^NSEvent *(NSEvent *event) {
			if (event.window != weakWindow) return event;
			if (event.type == NSEventTypeOtherMouseDown && (event.buttonNumber == 3 || event.buttonNumber == 4))
				return [weakNavigation navigate:event.buttonNumber == 4] ? nil : event;
			if (event.type == NSEventTypeSwipe && event.deltaX != 0)
				return [weakNavigation navigate:event.deltaX < 0] ? nil : event;
			return event;
		}];
	objc_setAssociatedObject(window, &kNavigationMonitorKey, navigation, OBJC_ASSOCIATION_RETAIN);
	return 0;
}

// Test hook: _navigationGesture(window, "back" | "forward")
static int bridge_navigation_gesture(lua_State *L) {
	NSWindow *window = lua_objc_check_object(L, 1, [NSWindow class], "window");
	LuaNavigationMonitor *navigation = objc_getAssociatedObject(window, &kNavigationMonitorKey);
	lua_pushboolean(L, [navigation navigate:strcmp(luaL_checkstring(L, 2), "forward") == 0]);
	return 1;
}

#pragma mark - Security-scoped bookmarks

/* A folder the person chose stays reachable across launches, even in a
 * sandbox, through a security-scoped bookmark. `_bookmark(path)` returns the
 * bookmark as base64 text to store; `_resolveBookmark(text)` returns the path
 * (after moves and renames), whether the bookmark is stale and should be
 * recreated, and starts access for the rest of the process's life. */
static int bridge_bookmark(lua_State *L) {
	NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:luaL_checkstring(L, 1)]];
	NSError *error = nil;
	NSData *data = [url bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
		includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
	if (!data) { lua_pushnil(L); lua_pushstring(L, error.localizedDescription.UTF8String); return 2; }
	lua_pushstring(L, [data base64EncodedStringWithOptions:0].UTF8String);
	return 1;
}

static int bridge_resolve_bookmark(lua_State *L) {
	NSData *data = [[NSData alloc] initWithBase64EncodedString:[NSString stringWithUTF8String:luaL_checkstring(L, 1)] options:0];
	if (!data) { lua_pushnil(L); lua_pushboolean(L, 0); lua_pushstring(L, "Not a bookmark."); return 3; }
	BOOL stale = NO;
	NSError *error = nil;
	NSURL *url = [NSURL URLByResolvingBookmarkData:data options:NSURLBookmarkResolutionWithSecurityScope | NSURLBookmarkResolutionWithoutUI
		relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
	if (!url) { lua_pushnil(L); lua_pushboolean(L, 0); lua_pushstring(L, error.localizedDescription.UTF8String); return 3; }
	[url startAccessingSecurityScopedResource];
	lua_pushstring(L, url.path.UTF8String);
	lua_pushboolean(L, stale);
	return 2;
}

static int bridge_pick_file(lua_State *L) {
	const char *titleC = luaL_optstring(L, 1, "Open File");
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.canChooseFiles = YES;
	panel.canChooseDirectories = NO;
	panel.allowsMultipleSelection = NO;
	panel.canCreateDirectories = NO;
	panel.title = [NSString stringWithUTF8String:titleC];

	NSInteger response = [panel runModal];
	if (response != NSModalResponseOK || panel.URL == nil) {
		lua_pushnil(L);
		return 1;
	}

	lua_pushstring(L, panel.URL.path.UTF8String);
	return 1;
}

// _saveFile(title, defaultName) -> path or nil: the standard save panel.
static int bridge_save_file(lua_State *L) {
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.title = [NSString stringWithUTF8String:luaL_optstring(L, 1, "Save")];
	panel.nameFieldStringValue = [NSString stringWithUTF8String:luaL_optstring(L, 2, "Untitled")];
	panel.canCreateDirectories = YES;
	if ([panel runModal] != NSModalResponseOK || !panel.URL) { lua_pushnil(L); return 1; }
	lua_pushstring(L, panel.URL.path.UTF8String);
	return 1;
}

#pragma mark - Test support

/* Headless tests schedule real NSTimers but never run NSApp. Pumping the
 * current run loop lets a pending timer fire (or prove it was cancelled)
 * without showing a window. */
static int bridge_runloop_tick(lua_State *L) {
	double seconds = luaL_optnumber(L, 1, 0.05);
	[[NSRunLoop currentRunLoop]
		runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
	return 0;
}
