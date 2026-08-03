#pragma mark - LuaToolbarDelegate

static NSToolbarItemIdentifier const kContentTrackingSeparatorIdentifier =
	@"lua-objc.contentTrackingSeparator";
static NSToolbarItemIdentifier const kSidebarTrackingSeparatorIdentifier =
	@"lua-objc.sidebarTrackingSeparator";
static NSString *const kToggleSidebarAlias = @"toggleSidebar";

static NSToolbarItemIdentifier toolbar_item_identifier(NSString *identifier) {
	if ([identifier isEqualToString:kToggleSidebarAlias]) {
		return NSToolbarToggleSidebarItemIdentifier;
	}
	return identifier;
}

@interface LuaToolbarDelegate : NSObject <NSToolbarDelegate>
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) NSSplitView *trackingSplitView;
@property (nonatomic, strong) NSSplitView *sidebarTrackingSplitView;
@property (nonatomic, copy) NSString *trackingAfterIdentifier;
@property (nonatomic) NSInteger trackingDividerIndex;
- (void)installSidebarTrackingSeparatorForSplitView:(NSSplitView *)splitView
										  inToolbar:(NSToolbar *)toolbar;
- (void)installTrackingSeparatorForSplitView:(NSSplitView *)splitView
								dividerIndex:(NSInteger)dividerIndex
								   inToolbar:(NSToolbar *)toolbar
							 afterIdentifier:(NSString *)itemIdentifier;
@end

@implementation LuaToolbarDelegate

- (instancetype)initWithItems:(NSArray *)items {
	self = [super init];
	if (self) {
		_items = [items copy];
	}
	return self;
}

- (NSArray<NSString *> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
	NSMutableArray *ids = [NSMutableArray array];
	BOOL insertedTrackingSeparator = NO;
	for (NSDictionary *item in _items) {
		NSString *identifier = item[@"id"];
		[ids addObject:toolbar_item_identifier(identifier)];
		if (_sidebarTrackingSplitView
			&& [identifier isEqualToString:kToggleSidebarAlias]) {
			[ids addObject:kSidebarTrackingSeparatorIdentifier];
		}
		if (_trackingSplitView
			&& [identifier isEqualToString:_trackingAfterIdentifier]) {
			[ids addObject:kContentTrackingSeparatorIdentifier];
			insertedTrackingSeparator = YES;
		}
	}
	if (_trackingSplitView && !insertedTrackingSeparator) {
		[ids addObject:kContentTrackingSeparatorIdentifier];
	}
	return ids;
}

- (NSArray<NSString *> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
	return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
	 itemForItemIdentifier:(NSString *)identifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
	if ([identifier isEqualToString:kSidebarTrackingSeparatorIdentifier]
		&& _sidebarTrackingSplitView) {
		return [NSTrackingSeparatorToolbarItem
			trackingSeparatorToolbarItemWithIdentifier:identifier
										 splitView:_sidebarTrackingSplitView
									  dividerIndex:kWorkspaceContentDividerIndex];
	}
	if ([identifier isEqualToString:kContentTrackingSeparatorIdentifier]
		&& _trackingSplitView) {
		return [NSTrackingSeparatorToolbarItem
			trackingSeparatorToolbarItemWithIdentifier:identifier
										 splitView:_trackingSplitView
									  dividerIndex:_trackingDividerIndex];
	}

	for (NSDictionary *item in _items) {
		if ([item[@"id"] isEqualToString:identifier]) {
			NSToolbarItem *ti = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
			ti.label = item[@"label"] ?: identifier;
			ti.paletteLabel = ti.label;
			ti.toolTip = item[@"tooltip"];
			ti.autovalidates = NO;
			ti.enabled = YES;

			NSImage *img = nil;
			if (item[@"icon"]) {
				img = [NSImage imageWithSystemSymbolName:item[@"icon"]
										accessibilityDescription:ti.label];
			}

			NSNumber *refNum = item[@"actionRef"];
			if (refNum) {
				objc_setAssociatedObject(ti, &kKeys[kCallbackKey], refNum,
					OBJC_ASSOCIATION_RETAIN);
				ti.target = [LuaButtonTarget shared];
				ti.action = @selector(onAction:);

				NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
				btn.bezelStyle = NSBezelStyleToolbar;
				btn.image = img;
				btn.imagePosition = img ? NSImageOnly : NSNoImage;
				btn.toolTip = ti.toolTip;
				[btn sizeToFit];
				btn.target = [LuaButtonTarget shared];
				btn.action = @selector(onAction:);
				objc_setAssociatedObject(btn, &kKeys[kCallbackKey], refNum,
					OBJC_ASSOCIATION_RETAIN);
				ti.view = btn;
			} else if (img) {
				ti.image = img;
			}

			return ti;
		}
	}
	return nil;
}

- (void)installSidebarTrackingSeparatorForSplitView:(NSSplitView *)splitView
										  inToolbar:(NSToolbar *)toolbar
{
	if (_sidebarTrackingSplitView || !splitView.isVertical) return;
	NSUInteger toggleIndex = NSNotFound;
	for (NSUInteger index = 0; index < toolbar.items.count; index++) {
		if ([toolbar.items[index].itemIdentifier
			isEqualToString:NSToolbarToggleSidebarItemIdentifier]) {
			toggleIndex = index;
			break;
		}
	}
	if (toggleIndex == NSNotFound) return;

	_sidebarTrackingSplitView = splitView;
	[toolbar insertItemWithItemIdentifier:kSidebarTrackingSeparatorIdentifier
								  atIndex:toggleIndex + 1];
}

- (void)installTrackingSeparatorForSplitView:(NSSplitView *)splitView
								dividerIndex:(NSInteger)dividerIndex
								   inToolbar:(NSToolbar *)toolbar
							 afterIdentifier:(NSString *)itemIdentifier
{
	if (_trackingSplitView || !splitView.isVertical) return;
	_trackingSplitView = splitView;
	_trackingDividerIndex = dividerIndex;
	_trackingAfterIdentifier = [itemIdentifier copy];
	NSString *resolvedIdentifier = toolbar_item_identifier(itemIdentifier);
	NSUInteger insertionIndex = toolbar.items.count;
	for (NSUInteger index = 0; index < toolbar.items.count; index++) {
		if ([toolbar.items[index].itemIdentifier
			isEqualToString:resolvedIdentifier]) {
			insertionIndex = index + 1;
			break;
		}
	}
	[toolbar insertItemWithItemIdentifier:kContentTrackingSeparatorIdentifier
								  atIndex:insertionIndex];
}

@end
