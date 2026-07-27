#pragma mark - Offscreen render

static NSData *offscreen_render(NSView *view, CGFloat width, CGFloat height) {
	view.frame = NSMakeRect(0, 0, width, height);

	/* Wrap in a borderless offscreen window so drawRect: has a valid window. */
	NSWindow *offscreen = [[NSWindow alloc]
		initWithContentRect:NSMakeRect(-10000, -10000, width, height)
				  styleMask:NSWindowStyleMaskBorderless
					backing:NSBackingStoreBuffered
					  defer:NO];
	offscreen.releasedWhenClosed = NO;
	[offscreen.contentView addSubview:view];
	[offscreen orderBack:nil];

	NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
	if (!rep) {
		[view removeFromSuperview];
		[offscreen close];
		return nil;
	}

	CGFloat scale = [NSScreen mainScreen]
		? [NSScreen mainScreen].backingScaleFactor : kFallbackBackingScale;
	(void)scale;

	[view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];

	NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG
									properties:@{}];

	[view removeFromSuperview];
	[offscreen close];
	return png;
}

static int bridge_render_to_png(lua_State *L) {
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

typedef struct {
	FSEventStreamRef stream;
	int luaRef;
} FileWatcherEntry;

static void file_watcher_callback(ConstFSEventStreamRef streamRef,
	void *clientCallBackInfo, size_t numEvents, void *eventPaths,
	const FSEventStreamEventFlags *eventFlags,
	const FSEventStreamEventId *eventIds)
{
	(void)streamRef; (void)numEvents; (void)eventPaths;
	(void)eventFlags; (void)eventIds;
	NSValue *boxed = (__bridge NSValue *)clientCallBackInfo;
	NSString *path = (__bridge NSString *)(void *)boxed.pointerValue;

	NSValue *entryBox = gFileWatchers[path];
	if (!entryBox || !gL) return;

	FileWatcherEntry entry;
	[entryBox getValue:&entry];
	if (entry.luaRef == LUA_NOREF) return;

	lua_rawgeti(gL, LUA_REGISTRYINDEX, entry.luaRef);
	lua_pushstring(gL, path.UTF8String);
	lua_objc_pcall(gL, 1, 0, "watchFile");
}

static int bridge_watch_file(lua_State *L) {
	const char *pathC = luaL_checkstring(L, 1);
	NSString *path = [NSString stringWithUTF8String:pathC];

	if (!gFileWatchers) {
		gFileWatchers = [NSMutableDictionary dictionary];
	}

	/* Cancel any existing watcher for this path. */
	NSValue *existing = gFileWatchers[path];
	if (existing) {
		FileWatcherEntry old;
		[existing getValue:&old];
		FSEventStreamStop(old.stream);
		FSEventStreamInvalidate(old.stream);
		FSEventStreamRelease(old.stream);
		if (old.luaRef != LUA_NOREF) {
			luaL_unref(gL, LUA_REGISTRYINDEX, old.luaRef);
		}
		[gFileWatchers removeObjectForKey:path];
	}

	/* nil callback = just cancel */
	if (lua_isnoneornil(L, 2)) return 0;

	luaL_checktype(L, 2, LUA_TFUNCTION);
	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);

	/* Use the path NSString pointer as stable context; kept alive by dict. */
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

	FileWatcherEntry entry = { .stream = stream, .luaRef = ref };
	[gFileWatchers setObject:[NSValue value:&entry
							withObjCType:@encode(FileWatcherEntry)]
					  forKey:path];
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
