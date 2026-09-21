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

#pragma mark - File watcher

static NSMutableDictionary *gFileWatchers = nil;

@interface LuaFileWatcher : NSObject
@property (nonatomic) FSEventStreamRef stream;
@property (nonatomic, strong) LuaReg *reg;
@property (nonatomic, copy) NSString *path;
@end

@implementation LuaFileWatcher
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
- (void)dealloc {
	[self stop];
}
@end

static void file_watcher_callback(ConstFSEventStreamRef streamRef,
	void *clientCallBackInfo, size_t numEvents, void *eventPaths,
	const FSEventStreamEventFlags *eventFlags,
	const FSEventStreamEventId *eventIds)
{
	(void)streamRef; (void)numEvents; (void)eventPaths;
	(void)eventFlags; (void)eventIds;
	NSValue *boxed = (__bridge NSValue *)clientCallBackInfo;
	NSString *path = (__bridge NSString *)(void *)boxed.pointerValue;

	LuaFileWatcher *watcher = gFileWatchers[path];
	lua_State *L = lua_reg_live_state(watcher.reg);
	if (!L || !lua_reg_push(watcher.reg)) return;
	lua_pushstring(L, path.UTF8String);
	lua_objc_pcall(L, 1, 0, "watchFile");
}

static int bridge_watch_file(lua_State *L) {
	const char *pathC = luaL_checkstring(L, 1);
	NSString *path = [NSString stringWithUTF8String:pathC];

	if (!gFileWatchers) {
		gFileWatchers = [NSMutableDictionary dictionary];
	}

	LuaFileWatcher *existing = gFileWatchers[path];
	if (existing) {
		[existing stop];
		[gFileWatchers removeObjectForKey:path];
	}

	if (lua_isnoneornil(L, 2)) return 0;

	LuaReg *reg = lua_reg_create(L, 2, YES);

	FSEventStreamContext ctx = {
		.version = 0,
		.info = (__bridge void *)([NSValue valueWithPointer:(__bridge void *)path]),
		.retain = NULL,
		.release = NULL,
		.copyDescription = NULL,
	};

	CFArrayRef paths = (__bridge CFArrayRef)@[path];
	FSEventStreamRef stream = FSEventStreamCreate(
		NULL, file_watcher_callback, &ctx,
		paths, kFSEventStreamEventIdSinceNow, kFSWatcherLatency,
		kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer);
	FSEventStreamSetDispatchQueue(stream, dispatch_get_main_queue());
	FSEventStreamStart(stream);

	LuaFileWatcher *watcher = [[LuaFileWatcher alloc] init];
	watcher.stream = stream;
	watcher.reg = reg;
	watcher.path = path;
	gFileWatchers[path] = watcher;
	return 0;
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
