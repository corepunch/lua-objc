#pragma mark - LuaToolbarFieldDelegate

static const char kToolbarFieldDelegateKey;
static const char kToolbarContentKey;
static void toolbar_size_content(NSView *view);

@interface LuaToolbarItem : NSToolbarItem
@end
@implementation LuaToolbarItem
- (void)setView:(NSView *)view {
	if (self.view) objc_setAssociatedObject(self.view, &kToolbarContentKey, nil, OBJC_ASSOCIATION_RETAIN);
	if (view) {
		objc_setAssociatedObject(view, &kToolbarContentKey, @YES, OBJC_ASSOCIATION_RETAIN);
		toolbar_size_content(view);
	}
	[super setView:view];
}
@end

@interface LuaToolbarFieldDelegate : NSObject <NSTextFieldDelegate>
@property (nonatomic, strong) LuaReg *submitReg;
@end

@implementation LuaToolbarFieldDelegate
- (void)dealloc { [_submitReg dispose]; }
- (BOOL)control:(NSControl *)control
	   textView:(NSTextView *)textView
doCommandBySelector:(SEL)selector
{
	if (selector != @selector(insertNewline:)) return NO;
	lua_State *L = lua_reg_live_state(self.submitReg);
	if (!L || !lua_reg_push(self.submitReg)) return NO;
	lua_pushstring(L, ((NSTextField *)control).stringValue.UTF8String);
	lua_objc_pcall(L, 1, 0, "toolbar field submit");
	return YES;
}
@end

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
	if ([identifier isEqualToString:@"flexibleSpace"])
		return NSToolbarFlexibleSpaceItemIdentifier;
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
	if ([identifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]) {
		return [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
	}

	for (NSDictionary *item in _items) {
		if ([toolbar_item_identifier(item[@"id"]) isEqualToString:identifier]) {
			NSToolbarItem *ti = [item[@"type"] isEqualToString:@"search"]
				? [[NSSearchToolbarItem alloc] initWithItemIdentifier:identifier]
				: [[LuaToolbarItem alloc] initWithItemIdentifier:identifier];
			ti.label = item[@"label"] ?: identifier;
			ti.paletteLabel = ti.label;
			ti.toolTip = item[@"tooltip"];
			ti.autovalidates = NO;
			ti.enabled = YES;
			if (item[@"visibilityPriority"])
				ti.visibilityPriority = [item[@"visibilityPriority"] integerValue];

			if ([ti isKindOfClass:NSSearchToolbarItem.class]) return ti;

			// ── Field item ────────────────────────────────────────────────
			if ([item[@"type"] isEqualToString:@"field"]) {
				LuaTextField *field = [[LuaTextField alloc] initWithFrame:NSZeroRect];
				((NSTextFieldCell *)field.cell).bezelStyle = NSTextFieldRoundedBezel;
				field.placeholderString = item[@"label"] ?: @"";
				field.stringValue       = item[@"value"] ?: @"";

				LuaReg *submitReg = item[@"submitReg"];
				if (submitReg) {
					LuaToolbarFieldDelegate *del = [LuaToolbarFieldDelegate new];
					del.submitReg = submitReg;
					field.delegate = del;
					objc_setAssociatedObject(field, &kToolbarFieldDelegateKey,
						del, OBJC_ASSOCIATION_RETAIN);
				}

				CGFloat minW = [item[@"minWidth"] doubleValue] ?: 200;
				field.translatesAutoresizingMaskIntoConstraints = NO;
				[field.widthAnchor constraintGreaterThanOrEqualToConstant:minW].active = YES;
				ti.view = field;
				return ti;
			}

			// ── Button / image item ───────────────────────────────────────
			NSImage *img = nil;
			if (item[@"icon"]) {
				img = [NSImage imageWithSystemSymbolName:item[@"icon"]
										accessibilityDescription:ti.label];
			}

			LuaReg *actionReg = item[@"actionReg"];
			if (actionReg) {
				lua_reg_store(ti, &kKeys[kCallbackKey], actionReg);
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
				lua_reg_store(btn, &kKeys[kCallbackKey], actionReg);
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
