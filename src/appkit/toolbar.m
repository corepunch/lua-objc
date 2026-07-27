#pragma mark - LuaToolbarDelegate

@interface LuaToolbarDelegate : NSObject <NSToolbarDelegate>
@property (nonatomic, strong) NSArray *items;
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
	for (NSDictionary *item in _items) {
		[ids addObject:item[@"id"]];
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

@end

