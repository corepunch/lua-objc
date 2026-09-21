#pragma mark - Bridge functions

static int bridge_window(lua_State *L) {
@autoreleasepool {
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

	NSWindow *w = [[LuaWindow alloc] initWithContentRect:frame
											   styleMask:style
												 backing:NSBackingStoreBuffered
												   defer:NO];
	w.title = [NSString stringWithUTF8String:title];
	w.releasedWhenClosed = NO;

	if (transparent_titlebar) {
		w.titlebarAppearsTransparent = YES;
		w.movableByWindowBackground = YES;
	}
	if (hide_title) {
		w.titleVisibility = NSWindowTitleHidden;
	}

	[w center];

	[[NSNotificationCenter defaultCenter]
		addObserverForName:NSWindowWillCloseNotification
					object:w
					 queue:nil
				usingBlock:^(NSNotification *note) {
		@autoreleasepool {
			NSWindow *closing = note.object;
			LuaReg *closeReg = objc_getAssociatedObject(
				closing, &kKeys[kWindowCloseKey]);
			lua_State *callL = lua_reg_live_state(closeReg);
			if (callL && lua_reg_push(closeReg))
				lua_objc_pcall(callL, 0, 0, "window close");
			[closeReg dispose];
			objc_setAssociatedObject(closing, &kKeys[kWindowCloseKey], nil,
				OBJC_ASSOCIATION_ASSIGN);
			/* App:present replaces windows while the run loop is alive. Defer
			 * termination until the close has completed so the replacement
			 * window is visible before deciding that the app has no UI left. */
			dispatch_async(dispatch_get_main_queue(), ^{
				/* Headless tooling (tests, --dump-layout, --screenshot) never
				 * runs NSApp, so closing a window there must not terminate
				 * the process. Only quit when the real event loop is live
				 * and no visible window remains. */
				if (!NSApp.isRunning) return;
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
		}
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
				dict[@"actionReg"] = lua_reg_create(L, -1, YES);
			}
			lua_pop(L, 1);

			lua_getfield(L, -3, "type");
			const char *itype = lua_tostring(L, -1);
			if (itype) dict[@"type"] = [NSString stringWithUTF8String:itype];
			lua_pop(L, 1);

			lua_getfield(L, -3, "minWidth");
			if (lua_isnumber(L, -1)) dict[@"minWidth"] = @(lua_tonumber(L, -1));
			lua_pop(L, 1);

			lua_getfield(L, -3, "value");
			const char *ivalue = lua_tostring(L, -1);
			if (ivalue) dict[@"value"] = [NSString stringWithUTF8String:ivalue];
			lua_pop(L, 1);

			lua_getfield(L, -3, "onSubmit");
			if (lua_isfunction(L, -1))
				dict[@"submitReg"] = lua_reg_create(L, -1, YES);
			lua_pop(L, 1);

			[items addObject:dict];
			lua_pop(L, 3);
		}

		LuaToolbarDelegate *del = [[LuaToolbarDelegate alloc] initWithItems:items];
		/* Document tabs own independent tracking separators. A shared toolbar
		 * family identifier makes AppKit duplicate those non-repeatable items
		 * when a second document joins the native window tab group. */
		NSString *toolbarIdentifier = [NSString stringWithFormat:
			@"lua-objc.%@", NSUUID.UUID.UUIDString];
		NSToolbar *tb = [[NSToolbar alloc]
			initWithIdentifier:toolbarIdentifier];
		tb.displayMode = lua_toboolean(L, 7)
			? NSToolbarDisplayModeIconAndLabel : NSToolbarDisplayModeIconOnly;
		tb.delegate = del;
		w.toolbar = tb;
		w.toolbarStyle = NSWindowToolbarStyleUnified;
		objc_setAssociatedObject(w, &kKeys[kToolbarDelegateKey], del,
			OBJC_ASSOCIATION_RETAIN);
	}

	push_objc(L, w, "nswindow");
	return 1;
}
}

static int bridge_on_window_close(lua_State *L) {
	NSWindow *window = lua_objc_check_object(L, 1, [NSWindow class], "Window");
	lua_reg_store(window, &kKeys[kWindowCloseKey], lua_reg_opt_unscoped(L, 2));
	return 0;
}

static int bridge_NSWindow_addTabbedWindow_impl(lua_State *L) {
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

static NSViewController *workspace_pane_controller(
	NSView *content, BOOL followsSafeAreaLeading) {
	NSViewController *controller = [[NSViewController alloc] init];
	NSView *host = [[NSView alloc] initWithFrame:NSZeroRect];
	controller.view = host;

	content.translatesAutoresizingMaskIntoConstraints = NO;
	[host addSubview:content];
	NSLayoutXAxisAnchor *leadingAnchor = followsSafeAreaLeading
		? host.safeAreaLayoutGuide.leadingAnchor : host.leadingAnchor;
	[NSLayoutConstraint activateConstraints:@[
		[content.leadingAnchor constraintEqualToAnchor:leadingAnchor],
		[content.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
		[content.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
		[content.topAnchor
			constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor],
	]];
	// AppKit's content-list host includes the floating sidebar. Constrain the
	// actual safe-area content so a third pane cannot consume its minimum width.
	NSNumber *minimumWidth = objc_getAssociatedObject(content, &kKeys[kMinWidthKey]);
	if (minimumWidth.doubleValue > 0) {
		NSLayoutConstraint *minimum = [content.widthAnchor
			constraintGreaterThanOrEqualToConstant:minimumWidth.doubleValue];
		minimum.priority = NSLayoutPriorityDefaultHigh;
		minimum.active = YES;
	}
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
	CGFloat detailWidth = luaL_optnumber(L, 8, 0);

	/* Keep the semantic split items full height so AppKit owns their glass,
	 * but place app content below the current toolbar and tab-bar safe area.
	 * A shared host makes scroll views and plain preview canvases agree. */
	NSViewController *sidebarController =
		workspace_pane_controller(sidebar, NO);
	NSViewController *contentController =
		workspace_pane_controller(content, YES);
	NSViewController *detailController = detail
		? workspace_pane_controller(detail, NO)
		: nil;

	NSSplitViewController *splitController =
		[[NSSplitViewController alloc] init];
	splitController.splitView.vertical = YES;

	NSSplitViewItem *sidebarItem =
		[NSSplitViewItem sidebarWithViewController:sidebarController];
	sidebarItem.minimumThickness = kWorkspaceSidebarMinWidth;
	sidebarItem.maximumThickness = kWorkspaceSidebarMaxWidth;
	sidebarItem.preferredThicknessFraction =
		fmax(kWorkspaceSidebarMinWidth,
			 fmin(kWorkspaceSidebarMaxWidth, sidebarWidth))
		/ MAX(1, window.contentLayoutRect.size.width);
	sidebarItem.allowsFullHeightLayout = YES;

	NSSplitViewItem *contentItem = detail
		? [NSSplitViewItem
			contentListWithViewController:contentController]
		: [NSSplitViewItem
			contentListWithViewController:contentController];
	contentItem.automaticallyAdjustsSafeAreaInsets = YES;
	NSSplitViewItem *detailItem = detail
		? [NSSplitViewItem
			splitViewItemWithViewController:detailController]
		: nil;
	if (detailItem && detailWidth > 0) {
		CGFloat clampedDetailWidth =
			fmax(kWorkspaceDetailMinWidth,
				 fmin(kWorkspaceDetailMaxWidth, detailWidth));
		detailItem.minimumThickness = clampedDetailWidth;
		detailItem.maximumThickness = clampedDetailWidth;
		detailItem.preferredThicknessFraction =
			clampedDetailWidth / MAX(1, window.contentLayoutRect.size.width);
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

	/* preferredThicknessFraction only takes effect on double-click or
	 * fullscreen entry, not at construction.  Set the sidebar divider
	 * position directly so sidebarWidth takes immediate effect. */
	CGFloat clampedSidebarWidth =
		fmax(kWorkspaceSidebarMinWidth,
			 fmin(kWorkspaceSidebarMaxWidth, sidebarWidth));
	[splitController.splitView
		setPosition:clampedSidebarWidth
		ofDividerAtIndex:0];
	[splitController.view layoutSubtreeIfNeeded];
	if (detailItem && detailWidth > 0) {
		CGFloat clampedDetailWidth =
			fmax(kWorkspaceDetailMinWidth,
				 fmin(kWorkspaceDetailMaxWidth, detailWidth));
		[splitController.splitView
			setPosition:contentWidth - clampedDetailWidth
			ofDividerAtIndex:kWorkspaceContentDividerIndex];
		[splitController.view layoutSubtreeIfNeeded];
	}

	LuaToolbarDelegate *toolbarDelegate = objc_getAssociatedObject(
		window,
		&kKeys[kToolbarDelegateKey]);
	[toolbarDelegate
		installSidebarTrackingSeparatorForSplitView:splitController.splitView
										 inToolbar:window.toolbar];
	[content setNeedsLayout:YES];
	[content layoutSubtreeIfNeeded];

	observe_workspace_pane(sidebar);
	observe_workspace_pane(content);
	if (detail) {
		observe_workspace_pane(detail);
	}
	layout_recursive(sidebar, clampedSidebarWidth);
	layout_recursive(content, content.bounds.size.width);
	if (detail) {
		layout_recursive(detail, detail.bounds.size.width);
	}
	if (contentDividerAfter
		&& (detail || [content isKindOfClass:[NSSplitView class]])) {
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

static int bridge_NSWindow_workspaceState_impl(lua_State *L) {
	id obj = check_objc(L, 1);
	if (![obj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "workspaceState requires a window");
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
	BOOL hasSidebarToggle = NO;
	BOOL tracksSidebarDivider = NO;
	for (NSToolbarItem *toolbarItem in ((NSWindow *)obj).toolbar.items) {
		if ([toolbarItem.itemIdentifier
			isEqualToString:NSToolbarToggleSidebarItemIdentifier]) {
			hasSidebarToggle = YES;
		} else if ([toolbarItem.itemIdentifier
			isEqualToString:kSidebarTrackingSeparatorIdentifier]) {
			tracksSidebarDivider = YES;
		} else if ([toolbarItem
			isKindOfClass:[NSTrackingSeparatorToolbarItem class]]) {
			tracksContentDivider = YES;
		}
	}
	lua_pushboolean(L, tracksContentDivider);
	lua_setfield(L, -2, "tracksContentDivider");
	lua_pushboolean(L, hasSidebarToggle);
	lua_setfield(L, -2, "hasSidebarToggle");
	lua_pushboolean(L, tracksSidebarDivider);
	lua_setfield(L, -2, "tracksSidebarDivider");
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
		if (items.count >= 3) {
			lua_pushboolean(L, items.lastObject.isCollapsed);
			lua_setfield(L, -2, "detailCollapsed");
		}
		lua_pushinteger(
			L,
			(lua_Integer)contentItem
				.topAlignedAccessoryViewControllers.count);
		lua_setfield(L, -2, "topAccessoryCount");
	}
	return 1;
}

static int bridge_NSWindow_toggleSidebar_impl(lua_State *L) {
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
		sidebarItem.collapsed = !sidebarItem.isCollapsed;
	}
	return 0;
}

static int bridge_NSWindow_toggleDetail_impl(lua_State *L) {
	id obj = check_objc(L, 1);
	if (![obj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "toggleDetail requires a window");
	}
	NSViewController *controller = ((NSWindow *)obj).contentViewController;
	if (![controller isKindOfClass:[NSSplitViewController class]]) return 0;
	NSSplitViewController *splitController =
		(NSSplitViewController *)controller;
	if (splitController.splitViewItems.count < 3) return 0;
	NSSplitViewItem *detailItem = splitController.splitViewItems.lastObject;
	detailItem.collapsed = !detailItem.isCollapsed;
	return 0;
}

static int bridge_NSView_splitProportions_impl(lua_State *L) {
	NSView *view = check_view(L, 1);
	if (![view isKindOfClass:[NSSplitView class]]) {
		return luaL_error(L, "splitProportions requires an NSSplitView");
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
@property (nonatomic, strong) LuaReg *dropCallback;
@end

@implementation LuaImageViewerView

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		_zoomScale = kImageViewerDefaultZoomScale;
		_fitToWindow = NO;

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
	[_dropCallback dispose];
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
	lua_State *callL = lua_reg_live_state(_dropCallback);
	if (!callL || !lua_reg_push(_dropCallback)) return YES;
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

/* NSImageView has no aspect-fill scaling mode. Resize the native image's
 * logical drawing size and let NSImageView center and clip it; retain the
 * source so repeated resizing never compounds scale or resamples pixels. */
@interface LuaImageView : NSImageView
@property(nonatomic, strong) NSImage *sourceImage;
@property(nonatomic, copy) NSString *contentModeName;
@end
@implementation LuaImageView
- (void)updateImageLayout {
	NSImage *source = self.sourceImage;
	if (!source) return;
	self.imageAlignment = NSImageAlignCenter;
	if ([_contentModeName isEqualToString:@"fill"] && source.size.width > 0 && source.size.height > 0) {
		CGFloat scale = MAX(self.bounds.size.width / source.size.width, self.bounds.size.height / source.size.height);
		NSImage *drawing = [source copy];
		drawing.size = NSMakeSize(source.size.width * scale, source.size.height * scale);
		[super setImage:drawing];
		self.imageScaling = NSImageScaleNone;
		self.clipsToBounds = YES;
	} else {
		[super setImage:source];
		self.imageScaling = [_contentModeName isEqualToString:@"stretch"] ? NSImageScaleAxesIndependently
			: ([_contentModeName isEqualToString:@"center"] ? NSImageScaleNone : NSImageScaleProportionallyUpOrDown);
	}
}
- (void)setImage:(NSImage *)image {
	self.sourceImage = image;
	if (image) [self updateImageLayout];
	else [super setImage:nil];
}
- (void)setContentModeName:(NSString *)mode { _contentModeName = [mode copy]; [self updateImageLayout]; }
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; [self updateImageLayout]; }
@end

static int bridge_image(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	NSString *nsPath = [NSString stringWithUTF8String:path];
	CGFloat maxWidth = luaL_optnumber(L, 2, kDefaultImageMaxWidth);

	// File icons require NSWorkspace resolution, including custom Finder icons.
	NSImage *img = lua_toboolean(L, 3) ? [NSWorkspace.sharedWorkspace iconForFile:nsPath] : [[NSImage alloc] initWithContentsOfFile:nsPath];
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

	LuaImageView *iv = [[LuaImageView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
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

	LuaImageViewerView *viewer = [[LuaImageViewerView alloc]
		initWithFrame:NSMakeRect(0, 0, kImageViewerDefaultWidth, kImageViewerDefaultHeight)];
	viewer.dropCallback = lua_reg_opt(L, 2);
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

static const char kDoubleClickHandlerKey;

@interface LuaDoubleClickHandler : NSObject
@property (nonatomic) LuaReg *reg;
@end

@implementation LuaDoubleClickHandler
- (void)fire:(NSClickGestureRecognizer *)r {
	if (r.state != NSGestureRecognizerStateRecognized) return;
	lua_State *L = lua_reg_live_state(self.reg);
	if (L && lua_reg_push(self.reg))
		lua_objc_pcall(L, 0, 0, "double-click");
}
@end

static int bridge_add_double_click(lua_State *L) {
	NSView *view = check_view(L, 1);
	LuaReg *reg = lua_reg_opt(L, 2);
	if (!reg) return 0;
	LuaDoubleClickHandler *handler = [LuaDoubleClickHandler new];
	handler.reg = reg;
	objc_setAssociatedObject(view, &kDoubleClickHandlerKey, handler,
		OBJC_ASSOCIATION_RETAIN);
	NSClickGestureRecognizer *gr = [[NSClickGestureRecognizer alloc]
		initWithTarget:handler action:@selector(fire:)];
	gr.numberOfClicksRequired = 2;
	[view addGestureRecognizer:gr];
	return 0;
}

#pragma mark - Hover Tooltip (NSPopover)

#define kHoverTooltipMinWidth  60
#define kHoverTooltipDismissDelay 0.05

@interface LuaHoverTooltipVC : NSViewController
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *detailLabel;
@property (nonatomic, strong) NSStackView *stack;
@end

@implementation LuaHoverTooltipVC

- (void)loadView {
	_titleLabel = [NSTextField labelWithString:@""];
	_titleLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
	_titleLabel.textColor = NSColor.labelColor;
	_titleLabel.alignment = NSTextAlignmentCenter;
	[_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired
		forOrientation:NSLayoutConstraintOrientationHorizontal];

	_detailLabel = [NSTextField labelWithString:@""];
	_detailLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
	_detailLabel.textColor = NSColor.secondaryLabelColor;
	_detailLabel.alignment = NSTextAlignmentCenter;
	[_detailLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired
		forOrientation:NSLayoutConstraintOrientationHorizontal];

	_stack = [NSStackView stackViewWithViews:@[_titleLabel, _detailLabel]];
	_stack.orientation = NSUserInterfaceLayoutOrientationVertical;
	_stack.spacing = 1;
	_stack.edgeInsets = NSEdgeInsetsMake(4, 10, 4, 10);
	self.view = _stack;
}

- (void)updateTitle:(NSString *)title detail:(NSString *)detail {
	_titleLabel.stringValue = title;
	_detailLabel.stringValue = detail;
	_detailLabel.hidden = (detail.length == 0);
	[_stack layoutSubtreeIfNeeded];
	NSSize fitting = [_stack fittingSize];
	fitting.width = MAX(fitting.width, kHoverTooltipMinWidth);
	self.preferredContentSize = fitting;
}

@end

static NSPopover *sharedHoverPopover(void) {
	static NSPopover *popover;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		popover = [[NSPopover alloc] init];
		popover.behavior = NSPopoverBehaviorSemitransient;
		popover.animates = NO;
		popover.contentViewController = [[LuaHoverTooltipVC alloc] init];
	});
	return popover;
}

static dispatch_block_t sPendingDismiss;

static void cancelPendingDismiss(void) {
	if (sPendingDismiss) {
		dispatch_block_cancel(sPendingDismiss);
		sPendingDismiss = nil;
	}
}

static void scheduleDismiss(void) {
	cancelPendingDismiss();
	sPendingDismiss = dispatch_block_create(0, ^{
		sPendingDismiss = nil;
		NSPopover *popover = sharedHoverPopover();
		if (popover.isShown) [popover close];
	});
	dispatch_after(
		dispatch_time(DISPATCH_TIME_NOW,
			(int64_t)(kHoverTooltipDismissDelay * NSEC_PER_SEC)),
		dispatch_get_main_queue(), sPendingDismiss);
}

static const char kHoverTooltipTrackerKey;

@interface LuaHoverTooltipTracker : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, weak) NSView *trackedView;
@property (nonatomic, strong) NSTrackingArea *area;
@end

@implementation LuaHoverTooltipTracker

- (void)installOn:(NSView *)view {
	_trackedView = view;
	if (_area) [view removeTrackingArea:_area];
	_area = [[NSTrackingArea alloc]
		initWithRect:NSZeroRect
			options:(NSTrackingMouseEnteredAndExited
				| NSTrackingActiveInKeyWindow
				| NSTrackingInVisibleRect)
			  owner:self
		   userInfo:nil];
	[view addTrackingArea:_area];
}

- (void)mouseEntered:(NSEvent *)event {
	cancelPendingDismiss();
	NSView *view = _trackedView;
	if (!view || !view.window) return;
	NSPopover *popover = sharedHoverPopover();
	LuaHoverTooltipVC *vc = (LuaHoverTooltipVC *)popover.contentViewController;
	[vc updateTitle:_title detail:_detail];
	if (popover.isShown) [popover close];
	[popover showRelativeToRect:view.bounds
						 ofView:view
				  preferredEdge:NSMaxYEdge];
}

- (void)mouseExited:(NSEvent *)event {
	scheduleDismiss();
}

@end

static int bridge_add_hover_tooltip(lua_State *L) {
	NSView *view = check_view(L, 1);
	const char *title = luaL_checkstring(L, 2);
	const char *detail = luaL_optstring(L, 3, "");

	LuaHoverTooltipTracker *tracker = [LuaHoverTooltipTracker new];
	tracker.title = [NSString stringWithUTF8String:title];
	tracker.detail = [NSString stringWithUTF8String:detail];
	[tracker installOn:view];
	objc_setAssociatedObject(view, &kHoverTooltipTrackerKey, tracker,
		OBJC_ASSOCIATION_RETAIN);
	return 0;
}

static int bridge_NSView_clearContainer_impl(lua_State *L) {
@autoreleasepool {
	NSView *container = check_view(L, 1);
	for (NSView *sub in [container.subviews copy]) {
		[sub removeFromSuperview];
	}
	layout_recursive(container, container.bounds.size.width);
}
	return 0;
}
