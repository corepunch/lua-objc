#pragma mark - LazyVStack and LazyVGrid

/* SwiftUI's lazy stacks: a virtualized collection that asks Lua for an
 * item's view only when the item scrolls into view, on NSCollectionView
 * (AppKit) and UICollectionView (UIKit). With a move callback items reorder
 * by dragging. The source (item factory, order, moves) is shared; the views
 * and drag and drop are each platform's. lua/ui/lazy.lua is the Lua side. */

/* Shared by both platforms' data sources: the items in their current order
 * (original indices), the Lua factory that builds an item's view, and the
 * callback told about moves. */
@interface LuaLazyCollectionSource : NSObject
@property(nonatomic, strong) NSMutableArray<NSNumber *> *order;
@property(nonatomic, strong) LuaReg *factory;
@property(nonatomic, strong) LuaReg *moveCallback;
@property(nonatomic) NSInteger columns;
@property(nonatomic) CGFloat rowHeight;
@property(nonatomic) CGFloat spacing;
@property(nonatomic) NSUInteger createdViews;
@end

@implementation LuaLazyCollectionSource
/* The view Lua builds for the item shown at `position`, or nil. */
- (id)viewForItemAt:(NSInteger)position {
	lua_State *L = lua_reg_live_state(self.factory);
	if (!L || !lua_reg_push(self.factory)) return nil;
	lua_pushinteger(L, self.order[(NSUInteger)position].integerValue + 1);
	if (lua_objc_pcall(L, 1, 1, "lazy collection item") != LUA_OK) return nil;
	id view = check_view(L, -1);
	lua_pop(L, 1);
	self.createdViews++;
	return view;
}
- (BOOL)reorders { return lua_reg_live_state(self.moveCallback) != NULL; }
/* Moves an item in the order and tells Lua, after the collection has
 * finished its own update. */
- (void)moveFrom:(NSInteger)from to:(NSInteger)to {
	NSNumber *moved = self.order[(NSUInteger)from];
	[self.order removeObjectAtIndex:(NSUInteger)from];
	[self.order insertObject:moved atIndex:(NSUInteger)to];
	dispatch_async(dispatch_get_main_queue(), ^{
		lua_State *L = lua_reg_live_state(self.moveCallback);
		if (!L || !lua_reg_push(self.moveCallback)) return;
		lua_pushinteger(L, from + 1);
		lua_pushinteger(L, to + 1);
		lua_objc_pcall(L, 2, 0, "lazy collection move");
	});
}
@end

#if TARGET_OS_IPHONE

@interface LuaLazyFlowLayout : UICollectionViewFlowLayout
@property(nonatomic) NSInteger columns;
@property(nonatomic) CGFloat rowHeight;
@property(nonatomic) CGFloat itemSpacing;
@end
@implementation LuaLazyFlowLayout
- (void)prepareLayout {
	CGFloat gaps = self.itemSpacing * (self.columns - 1);
	CGFloat scale = self.collectionView.traitCollection.displayScale ?: 1;
	CGFloat available = self.collectionView.bounds.size.width - gaps
		- kLazyLayoutGuardPixels / scale;
	CGFloat width = MAX(kLazyMinimumItemWidth,
		floor(MAX(0, available) * scale / self.columns) / scale);
	CGSize size = CGSizeMake(width, self.rowHeight);
	if (!CGSizeEqualToSize(self.itemSize, size)) self.itemSize = size;
	[super prepareLayout];
}
- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
	(void)newBounds;
	return YES;
}
@end

@interface LuaLazyCollectionView : UICollectionView
@property(nonatomic) CGFloat lastLayoutWidth;
@end
@implementation LuaLazyCollectionView
- (void)safeAreaInsetsDidChange {
	[super safeAreaInsetsDidChange];
	[self setNeedsLayout];
}
- (void)layoutSubviews {
	if (self.lastLayoutWidth != self.bounds.size.width) {
		self.lastLayoutWidth = self.bounds.size.width;
		[self.collectionViewLayout invalidateLayout];
	}
	// Only the bottom edge: horizontal safe-area geometry is already applied
	// by the containing view (see the constructor).
	CGFloat bottomInset = uikit_scroll_bottom_inset(self);
	if (self.contentInset.bottom != bottomInset) {
		self.contentInset = UIEdgeInsetsMake(0, 0, bottomInset, 0);
		self.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottomInset, 0);
	}
	[super layoutSubviews];
}
@end

@interface LuaLazyCollectionCell : UICollectionViewCell
@property(nonatomic, strong) UIView *hostedView;
@end
@implementation LuaLazyCollectionCell
- (void)setHostedView:(UIView *)view {
	[_hostedView removeFromSuperview];
	_hostedView = view;
	if (view) [self.contentView addSubview:view];
	[self setNeedsLayout];
}
- (void)layoutSubviews {
	[super layoutSubviews];
	if (!_hostedView) return;
	_hostedView.frame = self.contentView.bounds;
	layout_recursive(_hostedView, self.contentView.bounds.size.width);
}
@end

@interface LuaLazyUIKitSource : LuaLazyCollectionSource <UICollectionViewDataSource,
	UICollectionViewDelegate, UICollectionViewDragDelegate, UICollectionViewDropDelegate>
@end

@implementation LuaLazyUIKitSource
- (NSInteger)collectionView:(__unused UICollectionView *)collectionView
		numberOfItemsInSection:(__unused NSInteger)section {
	return (NSInteger)self.order.count;
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
		cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	LuaLazyCollectionCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"lazy"
		forIndexPath:indexPath];
	cell.hostedView = [self viewForItemAt:indexPath.item];
	return cell;
}
- (NSArray<UIDragItem *> *)collectionView:(__unused UICollectionView *)collectionView
		itemsForBeginningDragSession:(__unused id<UIDragSession>)session
		atIndexPath:(__unused NSIndexPath *)indexPath {
	if (!self.reorders) return @[];
	NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:@"lua-objc-lazy-item"];
	UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];
	item.localObject = self;
	return @[item];
}
- (UICollectionViewDropProposal *)collectionView:(__unused UICollectionView *)collectionView
		dropSessionDidUpdate:(id<UIDropSession>)session
		withDestinationIndexPath:(__unused NSIndexPath *)destinationIndexPath {
	if (!self.reorders || !session.localDragSession ||
		session.items.count != 1 || session.items.firstObject.localObject != self)
		return [[UICollectionViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
	return [[UICollectionViewDropProposal alloc] initWithDropOperation:UIDropOperationMove
		intent:UICollectionViewDropIntentInsertAtDestinationIndexPath];
}
- (void)collectionView:(UICollectionView *)collectionView
		performDropWithCoordinator:(id<UICollectionViewDropCoordinator>)coordinator {
	id<UICollectionViewDropItem> item = coordinator.items.firstObject;
	NSIndexPath *source = item.sourceIndexPath;
	if (!source || item.dragItem.localObject != self || self.order.count == 0) return;
	NSInteger to = coordinator.destinationIndexPath
		? coordinator.destinationIndexPath.item : (NSInteger)self.order.count - 1;
	to = MIN(MAX(to, 0), (NSInteger)self.order.count - 1);
	if (source.item == to) return;
	[self moveFrom:source.item to:to];
	NSIndexPath *destination = [NSIndexPath indexPathForItem:to inSection:0];
	[collectionView performBatchUpdates:^{
		[collectionView moveItemAtIndexPath:source toIndexPath:destination];
	} completion:nil];
	[coordinator dropItem:item.dragItem toItemAtIndexPath:destination];
}
@end

static UIView *lazy_collection_view(LuaLazyCollectionSource *base) {
	LuaLazyUIKitSource *source = (LuaLazyUIKitSource *)base;
	LuaLazyFlowLayout *layout = [LuaLazyFlowLayout new];
	layout.columns = source.columns;
	layout.rowHeight = source.rowHeight;
	layout.itemSpacing = source.spacing;
	layout.minimumLineSpacing = source.spacing;
	layout.minimumInteritemSpacing = source.spacing;
	UICollectionView *view = [[LuaLazyCollectionView alloc] initWithFrame:
		CGRectMake(0, 0, kLazyCollectionWidth, kLazyCollectionHeight)
		collectionViewLayout:layout];
	// The containing XML view already applies safe-area geometry. Automatic
	// scroll insets would center a full-width cell past the visible leading edge.
	view.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
	view.backgroundColor = UIColor.systemBackgroundColor;
	[view registerClass:LuaLazyCollectionCell.class forCellWithReuseIdentifier:@"lazy"];
	view.dataSource = source;
	view.delegate = source;
	if (source.moveCallback) {
		view.dragDelegate = source;
		view.dropDelegate = source;
		view.dragInteractionEnabled = YES;
	}
	return view;
}

#define LuaLazyPlatformSource LuaLazyUIKitSource

#else

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

@interface LuaLazyAppKitSource : LuaLazyCollectionSource <NSCollectionViewDataSource,
	NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout>
@property(nonatomic, weak) NSCollectionView *collection;
- (void)updateDocumentFrame;
@end

/* The scroll view sizes its collection to the rows whenever it lays out. */
@interface LuaLazyCollectionScroll : NSScrollView
@property(nonatomic, weak) LuaLazyAppKitSource *source;
@end
@implementation LuaLazyCollectionScroll
- (void)layout {
	[super layout];
	[self.source updateDocumentFrame];
}
@end

@implementation LuaLazyAppKitSource
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
- (NSInteger)collectionView:(__unused NSCollectionView *)collectionView
		numberOfItemsInSection:(__unused NSInteger)section {
	return (NSInteger)self.order.count;
}
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
		itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
	LuaLazyCollectionItem *item = [collectionView makeItemWithIdentifier:@"lazy"
		forIndexPath:indexPath];
	item.hostedView = [self viewForItemAt:indexPath.item];
	return item;
}
- (NSSize)collectionView:(NSCollectionView *)collectionView
		layout:(__unused NSCollectionViewLayout *)collectionViewLayout
		sizeForItemAtIndexPath:(__unused NSIndexPath *)indexPath {
	CGFloat gaps = self.spacing * (self.columns - 1);
	CGFloat width = MAX(kLazyMinimumItemWidth,
		(collectionView.bounds.size.width - gaps) / self.columns);
	return NSMakeSize(width, self.rowHeight);
}
- (CGFloat)collectionView:(__unused NSCollectionView *)collectionView
		layout:(__unused NSCollectionViewLayout *)collectionViewLayout
		minimumLineSpacingForSectionAtIndex:(__unused NSInteger)section {
	return self.spacing;
}
- (CGFloat)collectionView:(__unused NSCollectionView *)collectionView
		layout:(__unused NSCollectionViewLayout *)collectionViewLayout
		minimumInteritemSpacingForSectionAtIndex:(__unused NSInteger)section {
	return self.spacing;
}
- (id<NSPasteboardWriting>)collectionView:(__unused NSCollectionView *)collectionView
		pasteboardWriterForItemAtIndexPath:(NSIndexPath *)indexPath {
	if (!self.reorders) return nil;
	NSPasteboardItem *item = [NSPasteboardItem new];
	[item setString:[NSString stringWithFormat:@"%ld", (long)indexPath.item]
		forType:@"org.luaobjc.lazy-reorder"];
	return item;
}
- (NSDragOperation)collectionView:(NSCollectionView *)collectionView
		validateDrop:(id<NSDraggingInfo>)info
		proposedIndexPath:(__unused NSIndexPath **)indexPath
		dropOperation:(NSCollectionViewDropOperation *)operation {
	if (!self.reorders || info.draggingSource != collectionView) return NSDragOperationNone;
	*operation = NSCollectionViewDropBefore;
	return NSDragOperationMove;
}
- (BOOL)collectionView:(NSCollectionView *)collectionView
		acceptDrop:(id<NSDraggingInfo>)info indexPath:(NSIndexPath *)indexPath
		dropOperation:(__unused NSCollectionViewDropOperation)operation {
	if (info.draggingSource != collectionView || self.order.count == 0) return NO;
	NSString *value = [info.draggingPasteboard stringForType:@"org.luaobjc.lazy-reorder"];
	if (!value || !indexPath) return NO;
	NSInteger from = value.integerValue;
	NSInteger to = indexPath.item > from ? indexPath.item - 1 : indexPath.item;
	to = MIN(MAX(to, 0), (NSInteger)self.order.count - 1);
	if (from < 0 || from >= (NSInteger)self.order.count) return NO;
	if (from == to) return YES;
	[self moveFrom:from to:to];
	[collectionView moveItemAtIndexPath:[NSIndexPath indexPathForItem:from inSection:0]
		toIndexPath:[NSIndexPath indexPathForItem:to inSection:0]];
	return YES;
}
@end

static NSView *lazy_collection_view(LuaLazyCollectionSource *base) {
	LuaLazyAppKitSource *source = (LuaLazyAppKitSource *)base;
	NSCollectionView *collection = [[NSCollectionView alloc] initWithFrame:
		NSMakeRect(0, 0, kLazyCollectionWidth, kLazyCollectionHeight)];
	collection.collectionViewLayout = [NSCollectionViewFlowLayout new];
	[collection registerClass:LuaLazyCollectionItem.class forItemWithIdentifier:@"lazy"];
	source.collection = collection;
	collection.dataSource = source;
	collection.delegate = source;
	if (source.moveCallback) {
		[collection registerForDraggedTypes:@[@"org.luaobjc.lazy-reorder"]];
		[collection setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
	}
	LuaLazyCollectionScroll *scroll = [[LuaLazyCollectionScroll alloc] initWithFrame:
		NSMakeRect(0, 0, kLazyCollectionWidth, kLazyCollectionHeight)];
	scroll.hasVerticalScroller = YES;
	scroll.source = source;
	scroll.documentView = collection;
	return scroll;
}

#define LuaLazyPlatformSource LuaLazyAppKitSource

#endif

static char kLazyCollectionSourceKey;

// _lazyCollection(count, columns, rowHeight, spacing, factory, onMove, grid) -> view
static int bridge_lazy_collection(lua_State *L) {
	NSInteger count = luaL_checkinteger(L, 1);
	NSInteger columns = luaL_optinteger(L, 2,
		lua_toboolean(L, 7) ? kLazyGridColumns : kLazyStackColumns);
	CGFloat rowHeight = luaL_optnumber(L, 3, kLazyRowHeight);
	CGFloat spacing = luaL_optnumber(L, 4, kLazyItemSpacing);
	if (count < 0 || columns < 1 || rowHeight <= 0 || spacing < 0)
		return luaL_error(L, "invalid lazy collection dimensions");
	LuaReg *factory = lua_reg_opt(L, 5);
	if (!factory) return luaL_error(L, "lazy collection requires an item factory");
	LuaLazyCollectionSource *source = [LuaLazyPlatformSource new];
	source.factory = factory;
	source.moveCallback = lua_reg_opt(L, 6);
	source.columns = columns;
	source.rowHeight = rowHeight;
	source.spacing = spacing;
	source.order = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
	for (NSInteger index = 0; index < count; index++) [source.order addObject:@(index)];
	id view = lazy_collection_view(source);
	objc_setAssociatedObject(view, &kLazyCollectionSourceKey, source, OBJC_ASSOCIATION_RETAIN);
#if TARGET_OS_IPHONE
	push_objc(L, view, "uiview");
#else
	push_objc(L, view, "nsview");
#endif
	return 1;
}

// Test hook: _lazyCollectionStats(view) -> item count, views built so far
static int bridge_lazy_collection_stats(lua_State *L) {
	id view = check_view(L, 1);
	LuaLazyCollectionSource *source = objc_getAssociatedObject(view, &kLazyCollectionSourceKey);
	if (!source) return luaL_error(L, "view is not a lazy collection");
	lua_pushinteger(L, (lua_Integer)source.order.count);
	lua_pushinteger(L, (lua_Integer)source.createdViews);
	return 2;
}

#define LUA_OBJC_LAZY_COLLECTION_FUNCTIONS \
	{"_lazyCollection", bridge_lazy_collection}, \
	{"_lazyCollectionStats", bridge_lazy_collection_stats},
