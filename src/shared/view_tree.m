#pragma mark - View tree edits and offsets (shared by AppKit and UIKit)

/*
 * Declarative templates insert, move and remove views by position. None of
 * it animates: the platform's own containers (and `ArcView`'s own path
 * animation) are the only motion in the runtime.
 */

#if TARGET_OS_IPHONE
#define TreeView UIView
static void uikit_invalidate_layout(UIView *view);
#define tree_invalidate_layout(view) uikit_invalidate_layout(view)
#else
#define TreeView NSView
#define tree_invalidate_layout(view) invalidate_layout(view)
#endif

static BOOL reduce_motion_enabled(void) {
#if TARGET_OS_IPHONE
	return UIAccessibilityIsReduceMotionEnabled();
#else
	return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
#endif
}

/* Inserts `child` into `container` before its index-th child, or last. A
 * child already in the container moves. */
static void tree_insert(TreeView *container, TreeView *child, NSInteger index) {
	NSMutableArray<TreeView *> *present = [NSMutableArray array];
	for (TreeView *view in container.subviews) {
		if (view != child) [present addObject:view];
	}
	TreeView *before = index >= 0 && index < (NSInteger)present.count ? present[(NSUInteger)index] : nil;
	if (child.superview == container) {
		NSUInteger current = [container.subviews indexOfObject:child];
		NSUInteger target = before ? [container.subviews indexOfObject:before] : container.subviews.count;
		if (current + 1 == target || (!before && current == container.subviews.count - 1)) return;
	}
	if (child.superview && child.superview != container) [child removeFromSuperview];
#if TARGET_OS_IPHONE
	if (before) [container insertSubview:child belowSubview:before];
	else [container addSubview:child];
#else
	if (before) [container addSubview:child positioned:NSWindowBelow relativeTo:before];
	else [container addSubview:child];
#endif
	tree_invalidate_layout(container);
}

// _insertSubview(container, child, index): 1-based position among the children.
static int bridge_insert_subview(lua_State *L) {
	TreeView *container = check_view(L, 1);
	TreeView *child = check_view(L, 2);
	tree_insert(container, child, (NSInteger)luaL_optinteger(L, 3, 0) - 1);
	return 0;
}

// _removeSubview(view): removes the view from its container.
static int bridge_remove_subview(lua_State *L) {
	TreeView *view = check_view(L, 1);
	TreeView *container = view.superview;
	if (!container) return 0;
	[view removeFromSuperview];
	tree_invalidate_layout(container);
	return 0;
}

// _pushTransition(view, "leading" | "trailing"): the system's push transition
// for the next change to `view`'s contents, which enter from that edge. Core
// Animation's own CATransition does the work; nothing is snapshotted here.
static int bridge_push_transition(lua_State *L) {
	TreeView *view = check_view(L, 1);
	BOOL trailing = strcmp(luaL_checkstring(L, 2), "trailing") == 0;
	if (reduce_motion_enabled()) return 0;
#if !TARGET_OS_IPHONE
	view.wantsLayer = YES;
#endif
	CATransition *transition = [CATransition animation];
	transition.type = kCATransitionPush;
	transition.subtype = trailing ? kCATransitionFromRight : kCATransitionFromLeft;
	transition.duration = kPushTransitionDuration;
	transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
	[view.layer addAnimation:transition forKey:@"push"];
	return 0;
}

/* SwiftUI `.opacity` and `.offset(x:y:)`: offset moves a view's drawing without changing layout,
 * for a view that follows a drag. A layer translation; y grows downward. */
@interface TreeView (LuaOffset)
@property(nonatomic) CGFloat opacity;
@property(nonatomic) CGFloat offsetX;
@property(nonatomic) CGFloat offsetY;
@end

static char kOffsetKey;

static void tree_apply_offset(TreeView *view, CGFloat x, CGFloat y) {
#if !TARGET_OS_IPHONE
	view.wantsLayer = YES;
	CGFloat down = view.superview.isFlipped ? 1 : -1;
	view.layer.transform = CATransform3DMakeTranslation(x, y * down, 0);
#else
	view.layer.transform = CATransform3DMakeTranslation(x, y, 0);
#endif
	objc_setAssociatedObject(view, &kOffsetKey, @[@(x), @(y)], OBJC_ASSOCIATION_RETAIN);
}

static CGPoint tree_offset(TreeView *view) {
	NSArray<NSNumber *> *value = objc_getAssociatedObject(view, &kOffsetKey);
	return value ? CGPointMake(value[0].doubleValue, value[1].doubleValue) : CGPointZero;
}

@implementation TreeView (LuaOffset)
- (CGFloat)opacity {
#if TARGET_OS_IPHONE
	return self.alpha;
#else
	return self.alphaValue;
#endif
}
- (void)setOpacity:(CGFloat)value {
	CGFloat clamped = MIN(1, MAX(0, value));
#if TARGET_OS_IPHONE
	self.alpha = clamped;
#else
	self.alphaValue = clamped;
#endif
}
- (CGFloat)offsetX { return tree_offset(self).x; }
- (void)setOffsetX:(CGFloat)value { tree_apply_offset(self, value, tree_offset(self).y); }
- (CGFloat)offsetY { return tree_offset(self).y; }
- (void)setOffsetY:(CGFloat)value { tree_apply_offset(self, tree_offset(self).x, value); }
@end

#define LUA_OBJC_VIEW_TREE_FUNCTIONS \
	{"_insertSubview", bridge_insert_subview}, \
	{"_removeSubview", bridge_remove_subview}, \
	{"_pushTransition", bridge_push_transition},
