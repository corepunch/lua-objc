#pragma mark - Native drag-to-reorder for AppKit stack containers

@interface LuaContainerReorder : NSObject <NSDraggingSource>
@property(nonatomic, weak) NSView *container;
@property(nonatomic, copy) NSArray<NSView *> *items;
@property(nonatomic, strong) LuaReg *callback;
- (void)moveItemFrom:(NSUInteger)from to:(NSUInteger)to;
- (NSDragOperation)validateDrag:(id<NSDraggingInfo>)info;
- (BOOL)acceptDrag:(id<NSDraggingInfo>)info;
@end

@implementation LuaContainerReorder

- (void)dragItem:(NSPanGestureRecognizer *)gesture {
	if (gesture.state != NSGestureRecognizerStateBegan || !self.container) return;
	NSView *view = gesture.view;
	NSUInteger index = [self.items indexOfObject:view];
	if (index == NSNotFound || !NSApp.currentEvent) return;
	NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
	if (!bitmap) return;
	[view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
	NSImage *image = [[NSImage alloc] initWithSize:view.bounds.size];
	[image addRepresentation:bitmap];
	NSPasteboardItem *pasteboard = [NSPasteboardItem new];
	[pasteboard setString:[NSString stringWithFormat:@"%lu", (unsigned long)index]
		forType:@"org.luaobjc.reorder-item"];
	NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter:pasteboard];
	[item setDraggingFrame:[self.container convertRect:view.bounds fromView:view] contents:image];
	NSDraggingSession *session = [self.container beginDraggingSessionWithItems:@[item]
		event:NSApp.currentEvent source:self];
	session.animatesToStartingPositionsOnCancelOrFail = YES;
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session
		sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
	(void)session;
	return context == NSDraggingContextWithinApplication ? NSDragOperationMove : NSDragOperationNone;
}

- (NSDragOperation)validateDrag:(id<NSDraggingInfo>)info {
	if (info.draggingSource != self || !self.container) return NSDragOperationNone;
	NSString *value = [info.draggingPasteboard stringForType:@"org.luaobjc.reorder-item"];
	NSInteger index = value.integerValue;
	return value && index >= 0 && index < (NSInteger)self.items.count
		? NSDragOperationMove : NSDragOperationNone;
}

- (BOOL)acceptDrag:(id<NSDraggingInfo>)info {
	if ([self validateDrag:info] != NSDragOperationMove) return NO;
	NSInteger from = [[info.draggingPasteboard stringForType:@"org.luaobjc.reorder-item"] integerValue];
	NSPoint location = [self.container convertPoint:info.draggingLocation fromView:nil];
	NSUInteger to = (NSUInteger)from;
	CGFloat nearest = CGFLOAT_MAX;
	for (NSUInteger index = 0; index < self.items.count; index++) {
		NSView *item = self.items[index];
		NSPoint center = [self.container convertPoint:
			NSMakePoint(NSMidX(item.bounds), NSMidY(item.bounds)) fromView:item];
		CGFloat distance = hypot(location.x - center.x, location.y - center.y);
		if (distance < nearest) { nearest = distance; to = index; }
	}
	// Finish the native drag session before replacing a retained template subtree.
	dispatch_async(dispatch_get_main_queue(), ^{
		[self moveItemFrom:(NSUInteger)from to:to];
	});
	return YES;
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

static char kAppKitReorderContainerKey;
@implementation LuaStackView (ReorderContainer)
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
	LuaContainerReorder *delegate = objc_getAssociatedObject(self, &kAppKitReorderContainerKey);
	return [delegate validateDrag:sender];
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
	LuaContainerReorder *delegate = objc_getAssociatedObject(self, &kAppKitReorderContainerKey);
	return [delegate validateDrag:sender];
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	LuaContainerReorder *delegate = objc_getAssociatedObject(self, &kAppKitReorderContainerKey);
	return [delegate acceptDrag:sender];
}
@end

static int bridge_AppKitReorder_attach(lua_State *L) {
	NSView *container = check_view(L, 1);
	if (![container isKindOfClass:LuaStackView.class])
		return luaL_error(L, "reorder container requires a stack-style native layout");
	luaL_checktype(L, 2, LUA_TTABLE);
	LuaReg *callback = lua_reg_opt(L, 3);
	if (!callback) return luaL_error(L, "reorder container requires a callback");
	NSMutableArray<NSView *> *items = [NSMutableArray array];
	for (lua_Integer index = 1; index <= (lua_Integer)lua_rawlen(L, 2); index++) {
		lua_rawgeti(L, 2, index);
		NSView *item = check_view(L, -1);
		lua_pop(L, 1);
		[items addObject:item];
	}
	LuaContainerReorder *delegate = [LuaContainerReorder new];
	delegate.container = container;
	delegate.items = items;
	delegate.callback = callback;
	for (NSView *item in items) {
		NSPanGestureRecognizer *gesture = [[NSPanGestureRecognizer alloc]
			initWithTarget:delegate action:@selector(dragItem:)];
		[item addGestureRecognizer:gesture];
	}
	[container registerForDraggedTypes:@[@"org.luaobjc.reorder-item"]];
	objc_setAssociatedObject(container, &kAppKitReorderContainerKey, delegate,
		OBJC_ASSOCIATION_RETAIN);
	return 0;
}

static int bridge_AppKitReorder_testMove(lua_State *L) {
	NSView *container = check_view(L, 1);
	LuaContainerReorder *delegate = objc_getAssociatedObject(container, &kAppKitReorderContainerKey);
	if (!delegate) return luaL_error(L, "view has no reorder container");
	lua_Integer from = luaL_checkinteger(L, 2);
	lua_Integer to = luaL_checkinteger(L, 3);
	if (from < 1 || to < 1) return luaL_error(L, "reorder indexes start at one");
	[delegate moveItemFrom:(NSUInteger)from - 1 to:(NSUInteger)to - 1];
	return 0;
}
