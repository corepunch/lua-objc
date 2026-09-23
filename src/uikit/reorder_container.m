#pragma mark - Native drag-to-reorder for UIKit view containers

@interface LuaReorderContainer : NSObject <UIDragInteractionDelegate, UIDropInteractionDelegate>
@property(nonatomic, weak) UIView *container;
@property(nonatomic, copy) NSArray<UIView *> *items;
@property(nonatomic, strong) LuaReg *callback;
- (void)moveItemFrom:(NSUInteger)from to:(NSUInteger)to;
@end

@implementation LuaReorderContainer

- (NSArray<UIDragItem *> *)dragInteraction:(UIDragInteraction *)interaction
		itemsForBeginningSession:(id<UIDragSession>)session {
	(void)session;
	if (![self.items containsObject:interaction.view]) return @[];
	NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:@"lua-objc-reorder"];
	UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];
	item.localObject = interaction.view;
	return @[item];
}

- (UIDropProposal *)dropInteraction:(UIDropInteraction *)interaction
		sessionDidUpdate:(id<UIDropSession>)session {
	(void)interaction;
	UIView *source = session.items.firstObject.localObject;
	if (!session.localDragSession || session.items.count != 1 ||
		![self.items containsObject:source])
		return [[UIDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
	return [[UIDropProposal alloc] initWithDropOperation:UIDropOperationMove];
}

- (void)dropInteraction:(UIDropInteraction *)interaction
		performDrop:(id<UIDropSession>)session {
	(void)interaction;
	UIView *source = session.items.firstObject.localObject;
	NSUInteger from = [self.items indexOfObject:source];
	if (from == NSNotFound || !self.container) return;
	CGPoint location = [session locationInView:self.container];
	NSUInteger to = from;
	CGFloat nearest = CGFLOAT_MAX;
	for (NSUInteger index = 0; index < self.items.count; index++) {
		UIView *item = self.items[index];
		CGPoint center = [self.container convertPoint:
			CGPointMake(CGRectGetMidX(item.bounds), CGRectGetMidY(item.bounds)) fromView:item];
		CGFloat distance = hypot(location.x - center.x, location.y - center.y);
		if (distance < nearest) { nearest = distance; to = index; }
	}
	// Let UIKit finish the drop preview before the controller reconciles XML.
	dispatch_async(dispatch_get_main_queue(), ^{ [self moveItemFrom:from to:to]; });
}

- (void)moveItemFrom:(NSUInteger)from to:(NSUInteger)to {
	if (from == to || from >= self.items.count || to >= self.items.count) return;
	lua_State *callL = lua_reg_live_state(self.callback);
	if (!callL || !lua_reg_push(self.callback)) return;
	lua_pushinteger(callL, (lua_Integer)from + 1);
	lua_pushinteger(callL, (lua_Integer)to + 1);
	lua_objc_pcall(callL, 2, 0, "reorder container move");
}
@end

static char kReorderContainerKey;
static int bridge_UIKitReorder_attach(lua_State *L) {
	UIView *container = check_objc(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);
	LuaReg *callback = lua_reg_opt(L, 3);
	if (!callback) return luaL_error(L, "reorder container requires a callback");
	NSMutableArray<UIView *> *items = [NSMutableArray array];
	for (lua_Integer index = 1; index <= (lua_Integer)lua_rawlen(L, 2); index++) {
		lua_rawgeti(L, 2, index);
		UIView *item = check_objc(L, -1);
		lua_pop(L, 1);
		[items addObject:item];
	}
	LuaReorderContainer *delegate = [LuaReorderContainer new];
	delegate.container = container;
	delegate.items = items;
	delegate.callback = callback;
	for (UIView *item in items) {
		item.userInteractionEnabled = YES;
		[item addInteraction:[[UIDragInteraction alloc] initWithDelegate:delegate]];
	}
	[container addInteraction:[[UIDropInteraction alloc] initWithDelegate:delegate]];
	objc_setAssociatedObject(container, &kReorderContainerKey, delegate, OBJC_ASSOCIATION_RETAIN);
	return 0;
}

static int bridge_UIKitReorder_testMove(lua_State *L) {
	UIView *container = check_objc(L, 1);
	LuaReorderContainer *delegate = objc_getAssociatedObject(container, &kReorderContainerKey);
	if (!delegate) return luaL_error(L, "view has no reorder container");
	lua_Integer from = luaL_checkinteger(L, 2);
	lua_Integer to = luaL_checkinteger(L, 3);
	if (from < 1 || to < 1) return luaL_error(L, "reorder indexes start at one");
	[delegate moveItemFrom:(NSUInteger)from - 1 to:(NSUInteger)to - 1];
	return 0;
}
