#pragma mark - Virtualized stack and grid backed by UICollectionView

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
- (void)layoutSubviews {
	if (self.lastLayoutWidth != self.bounds.size.width) {
		self.lastLayoutWidth = self.bounds.size.width;
		[self.collectionViewLayout invalidateLayout];
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

@interface LuaLazyCollectionSource : NSObject <UICollectionViewDataSource,
	UICollectionViewDelegate, UICollectionViewDragDelegate,
	UICollectionViewDropDelegate>
@property(nonatomic, strong) NSMutableArray<NSNumber *> *order;
@property(nonatomic, strong) LuaReg *factory;
@property(nonatomic, strong) LuaReg *moveCallback;
@end

@implementation LuaLazyCollectionSource
- (NSInteger)collectionView:(UICollectionView *)collectionView
		numberOfItemsInSection:(NSInteger)section {
	(void)collectionView; (void)section;
	return (NSInteger)self.order.count;
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
		cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	LuaLazyCollectionCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"lazy"
		forIndexPath:indexPath];
	lua_State *callL = lua_reg_live_state(self.factory);
	if (!callL || !lua_reg_push(self.factory)) { cell.hostedView = nil; return cell; }
	lua_pushinteger(callL, self.order[(NSUInteger)indexPath.item].integerValue + 1);
	if (lua_objc_pcall(callL, 1, 1, "lazy collection item") != LUA_OK) {
		cell.hostedView = nil;
		return cell;
	}
	UIView *view = check_objc(callL, -1);
	cell.hostedView = view;
	lua_pop(callL, 1);
	return cell;
}
- (NSArray<UIDragItem *> *)collectionView:(UICollectionView *)collectionView
		itemsForBeginningDragSession:(id<UIDragSession>)session
		atIndexPath:(NSIndexPath *)indexPath {
	(void)collectionView; (void)session;
	if (!lua_reg_live_state(self.moveCallback)) return @[];
	NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:@"lua-objc-lazy-item"];
	UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];
	item.localObject = self;
	return @[item];
}
- (UICollectionViewDropProposal *)collectionView:(UICollectionView *)collectionView
		dropSessionDidUpdate:(id<UIDropSession>)session
		withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
	(void)collectionView; (void)destinationIndexPath;
	if (!lua_reg_live_state(self.moveCallback) || !session.localDragSession ||
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
	NSNumber *moved = self.order[(NSUInteger)source.item];
	[self.order removeObjectAtIndex:(NSUInteger)source.item];
	[self.order insertObject:moved atIndex:(NSUInteger)to];
	NSIndexPath *destination = [NSIndexPath indexPathForItem:to inSection:0];
	[collectionView performBatchUpdates:^{
		[collectionView moveItemAtIndexPath:source toIndexPath:destination];
	} completion:nil];
	[coordinator dropItem:item.dragItem toItemAtIndexPath:destination];
	dispatch_async(dispatch_get_main_queue(), ^{
		lua_State *callL = lua_reg_live_state(self.moveCallback);
		if (!callL || !lua_reg_push(self.moveCallback)) return;
		lua_pushinteger(callL, source.item + 1);
		lua_pushinteger(callL, to + 1);
		lua_objc_pcall(callL, 2, 0, "lazy collection move");
	});
}
@end

static char kLazyCollectionSourceKey;
static int bridge_UIKitLazy_collection(lua_State *L) {
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
	LuaLazyFlowLayout *layout = [LuaLazyFlowLayout new];
	layout.columns = columns;
	layout.rowHeight = rowHeight;
	layout.itemSpacing = spacing;
	layout.minimumLineSpacing = spacing;
	layout.minimumInteritemSpacing = spacing;
	UICollectionView *view = [[LuaLazyCollectionView alloc] initWithFrame:
		CGRectMake(0, 0, kLazyCollectionWidth, kLazyCollectionHeight)
		collectionViewLayout:layout];
	// The containing XML view already applies safe-area geometry. Automatic
	// scroll insets would center a full-width cell past the visible leading edge.
	view.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
	view.backgroundColor = UIColor.systemBackgroundColor;
	[view registerClass:LuaLazyCollectionCell.class forCellWithReuseIdentifier:@"lazy"];
	LuaLazyCollectionSource *source = [LuaLazyCollectionSource new];
	source.factory = factory;
	source.moveCallback = moveCallback;
	source.order = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
	for (NSInteger index = 0; index < count; index++)
		[source.order addObject:@(index)];
	view.dataSource = source;
	view.delegate = source;
	if (moveCallback) {
		view.dragDelegate = source;
		view.dropDelegate = source;
		view.dragInteractionEnabled = YES;
	}
	objc_setAssociatedObject(view, &kLazyCollectionSourceKey, source,
		OBJC_ASSOCIATION_RETAIN);
	push_objc(L, view, "uiview");
	return 1;
}
