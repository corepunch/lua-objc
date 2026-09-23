#pragma mark - Virtualized stack and grid backed by NSCollectionView

@interface LuaLazyCollectionItem : NSCollectionViewItem
@property(nonatomic, strong) NSView *hostedView;
@end
@implementation LuaLazyCollectionItem
- (void)loadView { self.view = [[NSView alloc] initWithFrame:NSZeroRect]; }
- (void)setHostedView:(NSView *)view {
	[_hostedView removeFromSuperview];
	_hostedView = view;
	if (view) [self.view addSubview:view];
	[self.view setNeedsLayout:YES];
}
- (void)viewDidLayout {
	[super viewDidLayout];
	if (!_hostedView) return;
	_hostedView.frame = self.view.bounds;
	layout_recursive(_hostedView, self.view.bounds.size.width);
}
@end

@interface LuaLazyCollectionSource : NSObject <NSCollectionViewDataSource,
	NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout>
@property(nonatomic, weak) NSCollectionView *collection;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *order;
@property(nonatomic, strong) LuaReg *factory;
@property(nonatomic, strong) LuaReg *moveCallback;
@property(nonatomic) NSInteger columns;
@property(nonatomic) CGFloat rowHeight;
@property(nonatomic) CGFloat spacing;
@property(nonatomic) NSUInteger createdViews;
- (void)updateDocumentFrame;
@end

@interface LuaLazyCollectionScroll : NSScrollView
@property(nonatomic, weak) LuaLazyCollectionSource *source;
@end
@implementation LuaLazyCollectionScroll
- (void)layout {
	[super layout];
	[self.source updateDocumentFrame];
}
@end

@implementation LuaLazyCollectionSource
- (void)updateDocumentFrame {
	NSScrollView *scroll = self.collection.enclosingScrollView;
	if (!scroll) return;
	CGFloat width = scroll.contentSize.width;
	NSInteger rows = (self.order.count + self.columns - 1) / self.columns;
	CGFloat height = rows * self.rowHeight + MAX(0, rows - 1) * self.spacing;
	NSSize size = NSMakeSize(MAX(width, kLazyMinimumItemWidth),
		MAX(height, scroll.contentSize.height));
	if (!NSEqualSizes(self.collection.frame.size, size)) {
		[self.collection setFrameSize:size];
		[self.collection.collectionViewLayout invalidateLayout];
	}
}
- (NSInteger)collectionView:(NSCollectionView *)collectionView
		numberOfItemsInSection:(NSInteger)section {
	(void)collectionView; (void)section;
	return (NSInteger)self.order.count;
}
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
		itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
	LuaLazyCollectionItem *item = [collectionView makeItemWithIdentifier:@"lazy"
		forIndexPath:indexPath];
	lua_State *callL = lua_reg_live_state(self.factory);
	if (!callL || !lua_reg_push(self.factory)) { item.hostedView = nil; return item; }
	lua_pushinteger(callL, self.order[(NSUInteger)indexPath.item].integerValue + 1);
	if (lua_objc_pcall(callL, 1, 1, "lazy collection item") != LUA_OK) {
		item.hostedView = nil;
		return item;
	}
	NSView *view = check_view(callL, -1);
	item.hostedView = view;
	self.createdViews++;
	lua_pop(callL, 1);
	return item;
}
- (NSSize)collectionView:(NSCollectionView *)collectionView
		layout:(NSCollectionViewLayout *)collectionViewLayout
		sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	(void)collectionViewLayout; (void)indexPath;
	CGFloat gaps = self.spacing * (self.columns - 1);
	CGFloat width = MAX(kLazyMinimumItemWidth,
		(collectionView.bounds.size.width - gaps) / self.columns);
	return NSMakeSize(width, self.rowHeight);
}
- (CGFloat)collectionView:(NSCollectionView *)collectionView
		layout:(NSCollectionViewLayout *)collectionViewLayout
		minimumLineSpacingForSectionAtIndex:(NSInteger)section {
	(void)collectionView; (void)collectionViewLayout; (void)section;
	return self.spacing;
}
- (CGFloat)collectionView:(NSCollectionView *)collectionView
		layout:(NSCollectionViewLayout *)collectionViewLayout
		minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
	(void)collectionView; (void)collectionViewLayout; (void)section;
	return self.spacing;
}
- (id<NSPasteboardWriting>)collectionView:(NSCollectionView *)collectionView
		pasteboardWriterForItemAtIndexPath:(NSIndexPath *)indexPath {
	(void)collectionView;
	if (!lua_reg_live_state(self.moveCallback)) return nil;
	NSPasteboardItem *item = [NSPasteboardItem new];
	[item setString:[NSString stringWithFormat:@"%ld", (long)indexPath.item]
		forType:@"org.luaobjc.lazy-reorder"];
	return item;
}
- (NSDragOperation)collectionView:(NSCollectionView *)collectionView
		validateDrop:(id<NSDraggingInfo>)info
		proposedIndexPath:(NSIndexPath **)indexPath
		dropOperation:(NSCollectionViewDropOperation *)operation {
	(void)indexPath;
	if (!lua_reg_live_state(self.moveCallback) || info.draggingSource != collectionView)
		return NSDragOperationNone;
	*operation = NSCollectionViewDropBefore;
	return NSDragOperationMove;
}
- (BOOL)collectionView:(NSCollectionView *)collectionView
		acceptDrop:(id<NSDraggingInfo>)info indexPath:(NSIndexPath *)indexPath
		dropOperation:(NSCollectionViewDropOperation)operation {
	(void)operation;
	if (info.draggingSource != collectionView || self.order.count == 0) return NO;
	NSString *value = [info.draggingPasteboard stringForType:@"org.luaobjc.lazy-reorder"];
	if (!value || !indexPath) return NO;
	NSInteger from = value.integerValue;
	NSInteger to = indexPath.item > from ? indexPath.item - 1 : indexPath.item;
	to = MIN(MAX(to, 0), (NSInteger)self.order.count - 1);
	if (from < 0 || from >= (NSInteger)self.order.count) return NO;
	if (from == to) return YES;
	NSNumber *moved = self.order[(NSUInteger)from];
	[self.order removeObjectAtIndex:(NSUInteger)from];
	[self.order insertObject:moved atIndex:(NSUInteger)to];
	[collectionView moveItemAtIndexPath:[NSIndexPath indexPathForItem:from inSection:0]
		toIndexPath:[NSIndexPath indexPathForItem:to inSection:0]];
	dispatch_async(dispatch_get_main_queue(), ^{
		lua_State *callL = lua_reg_live_state(self.moveCallback);
		if (!callL || !lua_reg_push(self.moveCallback)) return;
		lua_pushinteger(callL, from + 1);
		lua_pushinteger(callL, to + 1);
		lua_objc_pcall(callL, 2, 0, "lazy collection move");
	});
	return YES;
}
@end

static char kLazyCollectionSourceKey;
static int bridge_AppKitLazy_collection(lua_State *L) {
	NSInteger count = luaL_checkinteger(L, 1);
	NSInteger columns = luaL_optinteger(L, 2,
		lua_toboolean(L, 7) ? kLazyGridColumns : kLazyStackColumns);
	CGFloat rowHeight = luaL_optnumber(L, 3, kLazyRowHeight);
	CGFloat spacing = luaL_optnumber(L, 4, kLazyItemSpacing);
	if (count < 0 || columns < 1 || rowHeight <= 0 || spacing < 0)
		return luaL_error(L, "invalid lazy collection dimensions");
	LuaReg *factory = lua_reg_opt(L, 5);
	if (!factory) return luaL_error(L, "lazy collection requires an item factory");
	LuaReg *moveCallback = lua_reg_opt(L, 6);
	NSCollectionViewFlowLayout *layout = [NSCollectionViewFlowLayout new];
	NSCollectionView *collection = [[NSCollectionView alloc] initWithFrame:
		NSMakeRect(0, 0, kLazyCollectionWidth, kLazyCollectionHeight)];
	collection.collectionViewLayout = layout;
	[collection registerClass:LuaLazyCollectionItem.class forItemWithIdentifier:@"lazy"];
	LuaLazyCollectionSource *source = [LuaLazyCollectionSource new];
	source.collection = collection;
	source.factory = factory;
	source.moveCallback = moveCallback;
	source.columns = columns;
	source.rowHeight = rowHeight;
	source.spacing = spacing;
	source.order = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
	for (NSInteger index = 0; index < count; index++)
		[source.order addObject:@(index)];
	collection.dataSource = source;
	collection.delegate = source;
	if (moveCallback) {
		[collection registerForDraggedTypes:@[@"org.luaobjc.lazy-reorder"]];
		[collection setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
	}
	LuaLazyCollectionScroll *scroll = [[LuaLazyCollectionScroll alloc] initWithFrame:
		NSMakeRect(0, 0, kLazyCollectionWidth, kLazyCollectionHeight)];
	scroll.hasVerticalScroller = YES;
	scroll.source = source;
	scroll.documentView = collection;
	objc_setAssociatedObject(scroll, &kLazyCollectionSourceKey, source,
		OBJC_ASSOCIATION_RETAIN);
	push_objc(L, scroll, "nsview");
	return 1;
}

static int bridge_AppKitLazy_stats(lua_State *L) {
	NSView *view = check_view(L, 1);
	LuaLazyCollectionSource *source = objc_getAssociatedObject(view, &kLazyCollectionSourceKey);
	if (!source) return luaL_error(L, "view is not a lazy collection");
	lua_pushinteger(L, (lua_Integer)source.order.count);
	lua_pushinteger(L, (lua_Integer)source.createdViews);
	return 2;
}
