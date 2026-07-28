#pragma mark - LuaToolbarDelegate

static NSToolbarItemIdentifier const kContentTrackingSeparatorIdentifier =
	@"lua-objc.contentTrackingSeparator";

@interface LuaToolbarDelegate : NSObject <NSToolbarDelegate>
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) NSSplitView *trackingSplitView;
@property (nonatomic, copy) NSString *trackingAfterIdentifier;
@property (nonatomic) NSInteger trackingDividerIndex;
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
		[ids addObject:item[@"id"]];
		if (_trackingSplitView
			&& [item[@"id"] isEqualToString:_trackingAfterIdentifier]) {
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

- (void)installTrackingSeparatorForSplitView:(NSSplitView *)splitView
								dividerIndex:(NSInteger)dividerIndex
								   inToolbar:(NSToolbar *)toolbar
							 afterIdentifier:(NSString *)itemIdentifier
{
	if (_trackingSplitView || !splitView.isVertical) return;
	_trackingSplitView = splitView;
	_trackingDividerIndex = dividerIndex;
	_trackingAfterIdentifier = [itemIdentifier copy];
	NSUInteger insertionIndex = toolbar.items.count;
	for (NSUInteger index = 0; index < toolbar.items.count; index++) {
		if ([toolbar.items[index].itemIdentifier
			isEqualToString:itemIdentifier]) {
			insertionIndex = index + 1;
			break;
		}
	}
	[toolbar insertItemWithItemIdentifier:kContentTrackingSeparatorIdentifier
								  atIndex:insertionIndex];
}

@end
