#pragma mark - Bridge functions

static int bridge_window(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);
	int transparent_titlebar = lua_toboolean(L, 4);
	int hide_title = lua_toboolean(L, 5);

	NSRect frame = NSMakeRect(0, 0, width, height);
	NSUInteger style = NSWindowStyleMaskTitled
					 | NSWindowStyleMaskClosable
					 | NSWindowStyleMaskMiniaturizable
					 | NSWindowStyleMaskResizable;

	if (transparent_titlebar) {
		style |= NSWindowStyleMaskFullSizeContentView;
	}

	NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
											   styleMask:style
												 backing:NSBackingStoreBuffered
												   defer:NO];
	w.title = [NSString stringWithUTF8String:title];
	w.releasedWhenClosed = NO;

	if (transparent_titlebar) {
		w.titlebarAppearsTransparent = YES;
		if (hide_title) {
			w.titleVisibility = NSWindowTitleHidden;
		}
		w.movableByWindowBackground = YES;
	}

	[w center];

	[[NSNotificationCenter defaultCenter]
		addObserverForName:NSWindowWillCloseNotification
					object:w
					 queue:nil
				usingBlock:^(NSNotification *note) {
			/* App:present replaces windows while the run loop is alive. Defer
			 * termination until the close has completed so the replacement
			 * window is visible before deciding that the app has no UI left. */
			dispatch_async(dispatch_get_main_queue(), ^{
				BOOL hasVisibleWindow = NO;
				for (NSWindow *window in NSApp.windows) {
					if (window.isVisible) {
						hasVisibleWindow = YES;
						break;
					}
				}
				if (!hasVisibleWindow) {
					[NSApp terminate:nil];
				}
			});
		}];

	if (!lua_isnoneornil(L, 6)) {
		luaL_checktype(L, 6, LUA_TTABLE);
		int n = (int)luaL_len(L, 6);
		NSMutableArray *items = [NSMutableArray array];
		for (int i = 1; i <= n; i++) {
			lua_rawgeti(L, 6, i);
			lua_getfield(L, -1, "id");
			lua_getfield(L, -2, "label");
			lua_getfield(L, -3, "icon");
			const char *iid = lua_tostring(L, -3);
			const char *ilabel = lua_tostring(L, -2);
			const char *iicon = lua_tostring(L, -1);

			NSMutableDictionary *dict = [NSMutableDictionary dictionary];
			if (iid) dict[@"id"] = [NSString stringWithUTF8String:iid];
			if (ilabel) dict[@"label"] = [NSString stringWithUTF8String:ilabel];
			if (iicon) dict[@"icon"] = [NSString stringWithUTF8String:iicon];

			lua_pop(L, 1);

			lua_getfield(L, -3, "tooltip");
			const char *tooltip = lua_tostring(L, -1);
			if (tooltip) {
				dict[@"tooltip"] = [NSString stringWithUTF8String:tooltip];
			}
			lua_pop(L, 1);

			lua_getfield(L, -3, "action");
			if (lua_isfunction(L, -1)) {
				lua_pushvalue(L, -1);
				int ref = luaL_ref(L, LUA_REGISTRYINDEX);
				dict[@"actionRef"] = @(ref);
			}
			lua_pop(L, 1);

			[items addObject:dict];
			lua_pop(L, 3);
		}

		LuaToolbarDelegate *del = [[LuaToolbarDelegate alloc] initWithItems:items];
		NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"main"];
		tb.displayMode = lua_toboolean(L, 7)
			? NSToolbarDisplayModeIconAndLabel : NSToolbarDisplayModeIconOnly;
		tb.delegate = del;
		w.toolbar = tb;
		objc_setAssociatedObject(w, &kKeys[kToolbarDelegateKey], del,
			OBJC_ASSOCIATION_RETAIN);
	}

	push_objc(L, w, "nswindow");
	return 1;
}

static int bridge_set_window_tabbing(lua_State *L) {
	id obj = check_objc(L, 1);
	if (![obj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "setWindowTabbing requires a window");
	}

	const char *mode = luaL_checkstring(L, 2);
	NSWindowTabbingMode tabbingMode;
	if (strcmp(mode, "automatic") == 0) {
		tabbingMode = NSWindowTabbingModeAutomatic;
	} else if (strcmp(mode, "preferred") == 0) {
		tabbingMode = NSWindowTabbingModePreferred;
	} else if (strcmp(mode, "disallowed") == 0) {
		tabbingMode = NSWindowTabbingModeDisallowed;
	} else {
		return luaL_error(L,
			"tabbingMode must be 'automatic', 'preferred', or 'disallowed'");
	}

	NSWindow *window = (NSWindow *)obj;
	window.tabbingMode = tabbingMode;
	if (!lua_isnoneornil(L, 3)) {
		window.tabbingIdentifier = [NSString stringWithUTF8String:
			luaL_checkstring(L, 3)];
	}
	return 0;
}

static int bridge_add_tabbed_window(lua_State *L) {
	id parentObj = check_objc(L, 1);
	id childObj = check_objc(L, 2);
	if (![parentObj isKindOfClass:[NSWindow class]]
		|| ![childObj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "addTabbedWindow requires two windows");
	}

	const char *order = luaL_optstring(L, 3, "above");
	NSWindowOrderingMode orderingMode;
	if (strcmp(order, "above") == 0) {
		orderingMode = NSWindowAbove;
	} else if (strcmp(order, "below") == 0) {
		orderingMode = NSWindowBelow;
	} else {
		return luaL_error(L, "tab order must be 'above' or 'below'");
	}

	NSWindow *parent = (NSWindow *)parentObj;
	NSWindow *child = (NSWindow *)childObj;
	[parent addTabbedWindow:child ordered:orderingMode];
	if (parent.isVisible) {
		[child makeKeyAndOrderFront:nil];
	}
	return 0;
}

static int bridge_window_tab_count(lua_State *L) {
	id obj = check_objc(L, 1);
	if (![obj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "windowTabCount requires a window");
	}
	lua_pushinteger(L, (lua_Integer)((NSWindow *)obj).tabbedWindows.count);
	return 1;
}

static int bridge_select_window_tab(lua_State *L) {
	id obj = check_objc(L, 1);
	if (![obj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "selectWindowTab requires a window");
	}
	NSWindow *window = obj;
	if (window.tabGroup) {
		window.tabGroup.selectedWindow = window;
	}
	if (window.isVisible) {
		[window makeKeyAndOrderFront:nil];
	}
	return 0;
}

static void observe_workspace_pane(NSView *pane) {
	if (objc_getAssociatedObject(
			pane, &kKeys[kSplitPaneFrameObserverKey])) {
		return;
	}
	pane.postsFrameChangedNotifications = YES;
	__weak NSView *weakPane = pane;
	id observer = [[NSNotificationCenter defaultCenter]
		addObserverForName:NSViewFrameDidChangeNotification
					object:pane
					 queue:nil
				usingBlock:^(NSNotification *note) {
					NSView *resizedPane = weakPane;
					if (!resizedPane) return;
					layout_recursive(
						resizedPane,
						resizedPane.bounds.size.width);
				}];
	objc_setAssociatedObject(
		pane,
		&kKeys[kSplitPaneFrameObserverKey],
		observer,
		OBJC_ASSOCIATION_RETAIN);
}

static NSViewController *workspace_pane_controller(NSView *content) {
	NSViewController *controller = [[NSViewController alloc] init];
	NSView *host = [[NSView alloc] initWithFrame:NSZeroRect];
	controller.view = host;

	content.translatesAutoresizingMaskIntoConstraints = NO;
	[host addSubview:content];
	[NSLayoutConstraint activateConstraints:@[
		[content.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
		[content.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
		[content.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
		[content.topAnchor
			constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor],
	]];
	objc_setAssociatedObject(
		host,
		&kKeys[kWorkspaceSafeAreaContentKey],
		@YES,
		OBJC_ASSOCIATION_RETAIN);
	return controller;
}

static int bridge_set_window_workspace(lua_State *L) {
	id obj = check_objc(L, 1);
	if (![obj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "setWindowWorkspace requires a window");
	}
	NSWindow *window = obj;
	NSView *sidebar = check_view(L, 2);
	NSView *content = check_view(L, 3);
	NSView *accessory = lua_isnoneornil(L, 4)
		? nil : check_view(L, 4);
	CGFloat sidebarWidth = luaL_optnumber(
		L, 5, kWorkspaceSidebarWidth);
	NSString *contentDividerAfter = lua_isnoneornil(L, 6)
		? nil
		: [NSString stringWithUTF8String:luaL_checkstring(L, 6)];
	NSView *detail = lua_isnoneornil(L, 7)
		? nil : check_view(L, 7);

	/* Keep the semantic split items full height so AppKit owns their glass,
	 * but place app content below the current toolbar and tab-bar safe area.
	 * A shared host makes scroll views and plain preview canvases agree. */
	NSViewController *sidebarController =
		workspace_pane_controller(sidebar);
	NSViewController *contentController =
		workspace_pane_controller(content);
	NSViewController *detailController = detail
		? workspace_pane_controller(detail)
		: nil;

	NSSplitViewController *splitController =
		[[NSSplitViewController alloc] init];
	splitController.splitView.vertical = YES;

	NSSplitViewItem *sidebarItem =
		[NSSplitViewItem sidebarWithViewController:sidebarController];
	sidebarItem.minimumThickness = kWorkspaceSidebarMinWidth;
	sidebarItem.maximumThickness = kWorkspaceSidebarMaxWidth;
	sidebarItem.preferredThicknessFraction = MAX(
		kWorkspaceSidebarMinWidth,
		MIN(kWorkspaceSidebarMaxWidth, sidebarWidth))
		/ MAX(1, window.contentLayoutRect.size.width);
	sidebarItem.allowsFullHeightLayout = YES;

	NSSplitViewItem *contentItem = detail
		? [NSSplitViewItem
			contentListWithViewController:contentController]
		: [NSSplitViewItem
			splitViewItemWithViewController:contentController];
	contentItem.automaticallyAdjustsSafeAreaInsets = YES;
	NSSplitViewItem *detailItem = detail
		? [NSSplitViewItem
			splitViewItemWithViewController:detailController]
		: nil;
	if (detail) {
		contentItem.holdingPriority = NSLayoutPriorityDefaultLow;
		detailItem.holdingPriority = NSLayoutPriorityDefaultLow;
	}

	if (accessory) {
		NSSplitViewItemAccessoryViewController *accessoryController =
			[[NSSplitViewItemAccessoryViewController alloc] init];
		accessoryController.view = accessory;
		accessoryController.automaticallyAppliesContentInsets = YES;
		[contentItem addTopAlignedAccessoryViewController:
			accessoryController];
	}

	[splitController addSplitViewItem:sidebarItem];
	[splitController addSplitViewItem:contentItem];
	if (detailItem) {
		[splitController addSplitViewItem:detailItem];
	}
	CGFloat contentWidth = window.contentLayoutRect.size.width;
	CGFloat contentHeight = window.contentLayoutRect.size.height;
	window.styleMask |= NSWindowStyleMaskFullSizeContentView;
	window.titlebarAppearsTransparent = YES;
	/* Tahoe gives toolbar windows the large concentric frame that lets the
	 * semantic sidebar surround the traffic lights. A workspace without
	 * actions still needs an empty native toolbar to opt into that chrome. */
	if (!window.toolbar) {
		window.toolbar = [[NSToolbar alloc]
			initWithIdentifier:@"workspace"];
	}
	window.toolbarStyle = NSWindowToolbarStyleUnified;
	window.contentViewController = splitController;
	NSRect restoredFrame = [window
		frameRectForContentRect:NSMakeRect(0, 0, contentWidth, contentHeight)];
	CGFloat topEdge = NSMaxY(window.frame);
	restoredFrame.origin.x = window.frame.origin.x;
	restoredFrame.origin.y = topEdge - restoredFrame.size.height;
	[window setFrame:restoredFrame display:NO animate:NO];
	splitController.view.frame = window.contentView.bounds;
	[splitController.view layoutSubtreeIfNeeded];
	[content setNeedsLayout:YES];
	[content layoutSubtreeIfNeeded];

	observe_workspace_pane(sidebar);
	observe_workspace_pane(content);
	if (detail) {
		observe_workspace_pane(detail);
	}
	layout_recursive(sidebar, sidebar.bounds.size.width);
	layout_recursive(content, content.bounds.size.width);
	if (detail) {
		layout_recursive(detail, detail.bounds.size.width);
		CGFloat totalWidth = splitController.splitView.bounds.size.width;
		CGFloat sidebarEnd = sidebar.bounds.size.width;
		[splitController.splitView
			setPosition:sidebarEnd + (totalWidth - sidebarEnd) / 2.0
		 ofDividerAtIndex:kWorkspaceDetailDividerIndex];
	}
	if (contentDividerAfter
		&& (detail || [content isKindOfClass:[NSSplitView class]])) {
		LuaToolbarDelegate *toolbarDelegate = objc_getAssociatedObject(
			window,
			&kKeys[kToolbarDelegateKey]);
		NSSplitView *trackedSplitView = detail
			? splitController.splitView
			: (NSSplitView *)content;
		NSInteger trackedDividerIndex = detail
			? kWorkspaceDetailDividerIndex
			: kWorkspaceContentDividerIndex;
		[toolbarDelegate
			installTrackingSeparatorForSplitView:trackedSplitView
									 dividerIndex:trackedDividerIndex
									  inToolbar:window.toolbar
								afterIdentifier:contentDividerAfter];
	}
	return 0;
}

static int bridge_window_workspace_state(lua_State *L) {
	id obj = check_objc(L, 1);
	if (![obj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "windowWorkspaceState requires a window");
	}
	NSViewController *controller = ((NSWindow *)obj).contentViewController;
	if (![controller isKindOfClass:[NSSplitViewController class]]) {
		lua_pushnil(L);
		return 1;
	}

	NSSplitViewController *splitController =
		(NSSplitViewController *)controller;
	NSArray<NSSplitViewItem *> *items = splitController.splitViewItems;
	lua_newtable(L);
	lua_pushstring(L, controller.className.UTF8String);
	lua_setfield(L, -2, "controllerClass");
	lua_pushinteger(L, (lua_Integer)items.count);
	lua_setfield(L, -2, "itemCount");
	lua_pushboolean(L, ((NSWindow *)obj).toolbar != nil);
	lua_setfield(L, -2, "hasToolbar");
	lua_pushboolean(
		L,
		((NSWindow *)obj).toolbarStyle == NSWindowToolbarStyleUnified);
	lua_setfield(L, -2, "usesUnifiedToolbar");
	BOOL tracksContentDivider = NO;
	for (NSToolbarItem *toolbarItem in ((NSWindow *)obj).toolbar.items) {
		if ([toolbarItem
			isKindOfClass:[NSTrackingSeparatorToolbarItem class]]) {
			tracksContentDivider = YES;
			break;
		}
	}
	lua_pushboolean(L, tracksContentDivider);
	lua_setfield(L, -2, "tracksContentDivider");
	if (items.count >= 2) {
		NSSplitViewItem *sidebarItem = items[0];
		NSSplitViewItem *contentItem = items[1];
		BOOL safeAreaPaneHosts =
			[objc_getAssociatedObject(
				sidebarItem.viewController.view,
				&kKeys[kWorkspaceSafeAreaContentKey]) boolValue]
			&& [objc_getAssociatedObject(
				contentItem.viewController.view,
				&kKeys[kWorkspaceSafeAreaContentKey]) boolValue];
		if (items.count >= 3) {
			safeAreaPaneHosts = safeAreaPaneHosts
				&& [objc_getAssociatedObject(
					items[2].viewController.view,
					&kKeys[kWorkspaceSafeAreaContentKey]) boolValue];
		}
		lua_pushboolean(L, safeAreaPaneHosts);
		lua_setfield(L, -2, "safeAreaPaneHosts");
		lua_pushboolean(
			L, sidebarItem.behavior == NSSplitViewItemBehaviorSidebar);
		lua_setfield(L, -2, "nativeSidebar");
		lua_pushboolean(L, sidebarItem.allowsFullHeightLayout);
		lua_setfield(L, -2, "fullHeightSidebar");
		lua_pushboolean(
			L, contentItem.automaticallyAdjustsSafeAreaInsets);
		lua_setfield(L, -2, "contentUsesSafeArea");
		lua_pushinteger(
			L,
			(lua_Integer)contentItem
				.topAlignedAccessoryViewControllers.count);
		lua_setfield(L, -2, "topAccessoryCount");
	}
	return 1;
}

static int bridge_toggle_sidebar(lua_State *L) {
	id obj = check_objc(L, 1);
	if (![obj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "toggleSidebar requires a window");
	}
	NSWindow *window = obj;
	NSViewController *controller = window.contentViewController;
	if (![controller isKindOfClass:[NSSplitViewController class]]) {
		return 0;
	}
	NSSplitViewController *splitController =
		(NSSplitViewController *)controller;
	NSSplitViewItem *sidebarItem = splitController.splitViewItems.firstObject;
	if (sidebarItem.behavior == NSSplitViewItemBehaviorSidebar) {
		sidebarItem.animator.collapsed = !sidebarItem.isCollapsed;
	}
	return 0;
}

static int bridge_split_set_proportions(lua_State *L) {
	NSView *view = check_view(L, 1);
	if (![view isKindOfClass:[NSSplitView class]]) {
		return luaL_error(L, "splitSetProportions requires an NSSplitView");
	}
	luaL_checktype(L, 2, LUA_TTABLE);

	NSMutableArray<NSNumber *> *proportions = [NSMutableArray array];
	lua_Integer count = luaL_len(L, 2);
	for (lua_Integer i = 1; i <= count; i++) {
		lua_rawgeti(L, 2, i);
		CGFloat value = luaL_checknumber(L, -1);
		lua_pop(L, 1);
		if (value <= 0) {
			return luaL_error(L, "split proportions must be positive");
		}
		[proportions addObject:@(value)];
	}
	objc_setAssociatedObject(
		view, &kKeys[kSplitProportionsKey], proportions,
		OBJC_ASSOCIATION_RETAIN);
	return 0;
}


#pragma mark - Text update

#pragma mark - Image

@interface LuaImageViewerView : NSView <NSDraggingDestination>
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSView *documentView;
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) NSImage *sourceImage;
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic) CGFloat zoomScale;
@property (nonatomic) BOOL fitToWindow;
@property (nonatomic) int dropCallbackRef;
@end

@implementation LuaImageViewerView

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		_zoomScale = kImageViewerDefaultZoomScale;
		_fitToWindow = NO;
		_dropCallbackRef = LUA_NOREF;

		_scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
		_scrollView.hasVerticalScroller = YES;
		_scrollView.hasHorizontalScroller = YES;
		_scrollView.autohidesScrollers = YES;
		_scrollView.borderType = NSNoBorder;
		_scrollView.drawsBackground = NO;

		_documentView = [[NSView alloc] initWithFrame:NSZeroRect];
		_imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
		_imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
		_imageView.imageAlignment = NSImageAlignCenter;
		[_documentView addSubview:_imageView];
		_scrollView.documentView = _documentView;
		[self addSubview:_scrollView];
		[self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
	}
	return self;
}

- (void)dealloc {
	if (_dropCallbackRef != LUA_NOREF && gL) {
		luaL_unref(gL, LUA_REGISTRYINDEX, _dropCallbackRef);
	}
}

- (BOOL)acceptsFirstResponder {
	return YES;
}

- (void)setFrame:(NSRect)frameRect {
	[super setFrame:frameRect];
	[self updateLayout];
}

- (void)layout {
	[super layout];
	[self updateLayout];
}

- (void)setImagePath:(NSString *)imagePath {
	_imagePath = [imagePath copy];
	NSString *path = _imagePath;
	NSImage *image = nil;
	if (path.length > 0) {
		image = [[NSImage alloc] initWithContentsOfFile:path];
		if (!image) {
			image = [NSImage imageNamed:path];
		}
	}
	_sourceImage = image;
	_imageView.image = image;
	[self updateLayout];
}

- (void)setZoomScale:(CGFloat)zoomScale {
	_zoomScale = MAX(kImageViewerMinZoomScale, zoomScale);
	if (!_fitToWindow) {
		[self updateLayout];
	}
}

- (void)setFitToWindow:(BOOL)fitToWindow {
	_fitToWindow = fitToWindow;
	[self updateLayout];
}

- (NSArray<NSString *> *)dropPathsFromPasteboard:(NSPasteboard *)pasteboard {
	NSArray<NSURL *> *urls = [pasteboard readObjectsForClasses:@[[NSURL class]]
		options:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }];
	NSMutableArray<NSString *> *paths = [NSMutableArray array];
	for (NSURL *url in urls) {
		if (url.isFileURL && url.path.length > 0) {
			[paths addObject:url.path];
		}
	}
	return paths;
}

- (BOOL)hasFileDrop:(id<NSDraggingInfo>)sender {
	return [self dropPathsFromPasteboard:sender.draggingPasteboard].count > 0;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
	return [self hasFileDrop:sender] ? NSDragOperationCopy : NSDragOperationNone;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
	return [self hasFileDrop:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	NSArray<NSString *> *paths = [self dropPathsFromPasteboard:sender.draggingPasteboard];
	if (paths.count == 0) return NO;
	if (_dropCallbackRef == LUA_NOREF || !gL) return YES;

	lua_State *callL = gL;
	lua_rawgeti(callL, LUA_REGISTRYINDEX, _dropCallbackRef);
	lua_newtable(callL);
	for (NSUInteger i = 0; i < paths.count; i++) {
		lua_pushstring(callL, paths[i].UTF8String);
		lua_rawseti(callL, -2, (lua_Integer)(i + 1));
	}
	lua_objc_pcall(callL, 1, 0, "image drop");
	return YES;
}

- (void)updateLayout {
	self.scrollView.frame = self.bounds;
	NSImage *image = self.sourceImage;
	if (!image) {
		self.documentView.frame = self.scrollView.bounds;
		self.imageView.frame = NSZeroRect;
		return;
	}

	NSSize source = image.size;
	if (source.width <= 0 || source.height <= 0) {
		source = NSMakeSize(kMinLeafWidth, kMinLeafHeight);
	}

	NSSize viewport = self.scrollView.contentSize;
	CGFloat scale = self.fitToWindow
		? MIN(viewport.width / source.width, viewport.height / source.height)
		: self.zoomScale;
	if (!isfinite(scale) || scale <= 0) {
		scale = kImageViewerDefaultZoomScale;
	}
	CGFloat imageWidth = MAX(kMinLeafWidth, round(source.width * scale));
	CGFloat imageHeight = MAX(kMinLeafHeight, round(source.height * scale));
	CGFloat docWidth = MAX(viewport.width, imageWidth);
	CGFloat docHeight = MAX(viewport.height, imageHeight);

	self.documentView.frame = NSMakeRect(0, 0, docWidth, docHeight);
	self.imageView.frame = NSMakeRect(
		floor((docWidth - imageWidth) / 2.0),
		floor((docHeight - imageHeight) / 2.0),
		imageWidth,
		imageHeight);
	self.scrollView.hasHorizontalScroller = docWidth > viewport.width;
	self.scrollView.hasVerticalScroller = docHeight > viewport.height;
}

@end

static int bridge_image(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	NSString *nsPath = [NSString stringWithUTF8String:path];
	CGFloat maxWidth = luaL_optnumber(L, 2, kDefaultImageMaxWidth);

	NSImage *img = [[NSImage alloc] initWithContentsOfFile:nsPath];
	if (!img) {
		img = [NSImage imageNamed:nsPath];
	}
	if (!img) {
		return luaL_error(L, "failed to load image: %s", path);
	}

	NSSize size = img.size;
	if (maxWidth > 0 && size.width > maxWidth) {
		CGFloat ratio = maxWidth / size.width;
		size.width = maxWidth;
		size.height *= ratio;
	}

	NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
	iv.image = img;
	iv.imageScaling = NSImageScaleProportionallyUpOrDown;
	// NSImageView reports the source bitmap's intrinsic dimensions even when
	// the bridge has capped its display frame. Preserve the intended display
	// size so stack measurement does not reserve space for the original image.
	objc_setAssociatedObject(iv, &kKeys[kImageLayoutSizeKey],
		[NSValue valueWithSize:size], OBJC_ASSOCIATION_RETAIN);

	push_objc(L, iv, "nsview");
	return 1;
}

static int bridge_image_viewer(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	int ref = LUA_NOREF;
	if (!lua_isnoneornil(L, 2)) {
		luaL_checktype(L, 2, LUA_TFUNCTION);
		lua_pushvalue(L, 2);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	LuaImageViewerView *viewer = [[LuaImageViewerView alloc]
		initWithFrame:NSMakeRect(0, 0, kImageViewerDefaultWidth, kImageViewerDefaultHeight)];
	viewer.dropCallbackRef = ref;
	viewer.imagePath = [NSString stringWithUTF8String:path];

	push_objc(L, viewer, "nsview");
	return 1;
}

static int bridge_system_image(lua_State *L) {
	const char *symbol = luaL_checkstring(L, 1);
	const char *description = luaL_optstring(L, 2, symbol);
	CGFloat pointSize = luaL_optnumber(L, 3, kDefaultSymbolPointSize);
	const char *weightName = luaL_optstring(L, 4, "regular");
	const char *colorName = luaL_optstring(L, 5, "accent");

	NSFontWeight weight = lookupFontWeight([NSString stringWithUTF8String:weightName]);

	NSString *name = [NSString stringWithUTF8String:symbol];
	NSString *accessibilityDescription =
		[NSString stringWithUTF8String:description];
	NSImage *image = [NSImage imageWithSystemSymbolName:name
		accessibilityDescription:accessibilityDescription];
	if (!image) return luaL_error(L, "unknown SF Symbol: %s", symbol);

	NSImageSymbolConfiguration *configuration =
		[NSImageSymbolConfiguration configurationWithPointSize:pointSize
													   weight:weight];
	image = [image imageWithSymbolConfiguration:configuration];
	NSImageView *view = [[NSImageView alloc]
		initWithFrame:NSMakeRect(0, 0, pointSize, pointSize)];
	view.image = image;
	view.imageScaling = NSImageScaleProportionallyDown;
	view.contentTintColor = semantic_color(
		[NSString stringWithUTF8String:colorName]);
	view.accessibilityLabel = accessibilityDescription;
	push_objc(L, view, "nsview");
	return 1;
}

static int bridge_system_color(lua_State *L) {
	const char *name = luaL_checkstring(L, 1);
	NSColor *color = semantic_color([NSString stringWithUTF8String:name]);
	push_objc(L, color, "nsobject");
	return 1;
}
