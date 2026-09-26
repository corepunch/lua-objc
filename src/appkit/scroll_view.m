@interface LuaScrollView : NSScrollView
/* SwiftUI scrollTargetBehavior; recorded for parity, since Mac wheel and
 * trackpad scrolling stays continuous as it does in SwiftUI on macOS. */
@property(nonatomic, copy) NSString *scrollTargetBehavior;
@end
@implementation LuaScrollView
- (void)scrollWheel:(NSEvent *)event {
	NSScrollView *parent = self.enclosingScrollView;
	NSSize document = self.documentView.frame.size;
	NSSize viewport = self.contentView.bounds.size;
	BOOL vertical = event.scrollingDeltaY != 0;
	BOOL horizontal = event.scrollingDeltaX != 0;
	BOOL verticalRange = document.height > viewport.height;
	BOOL horizontalRange = document.width > viewport.width;
	BOOL canScroll = (vertical && verticalRange) || (horizontal && horizontalRange);
	// Phase-only events must also reach the parent for a fully fitted child.
	if (!vertical && !horizontal) canScroll = verticalRange || horizontalRange;
	// A content-sized list still owns an NSScrollView, which otherwise swallows
	// wheel input. Forward only when the requested axes have no scroll range;
	// a scrollable child keeps AppKit's normal edge and momentum behavior.
	if (parent && !canScroll) {
		[parent scrollWheel:event];
		return;
	}
	[super scrollWheel:event];
}
- (void)setFrameSize:(NSSize)size {
	// Unflipped stack documents read from the top. Preserve that reading position
	// across native viewport resizing before the declarative layout measures again.
	NSView *document = self.documentView;
	BOOL preserve = document && !document.isFlipped
		&& objc_getAssociatedObject(self, &kKeys[kScrollViewportSizeKey]);
	CGFloat distance = MAX(0, document.frame.size.height
		- self.contentView.bounds.origin.y - self.contentSize.height);
	[super setFrameSize:size];
	if (preserve) {
		[self tile];
		NSPoint origin = self.contentView.bounds.origin;
		origin.y = MAX(0, document.frame.size.height - self.contentSize.height - distance);
		[self.contentView scrollToPoint:origin];
	}
}
@end

// AppKit requires a window to animate wheel scrolling. For headless tests,
// dispatch a real event and record which scroller reaches AppKit's implementation.
static int bridge_test_scroll_wheel(lua_State *L) {
	NSView *view = check_view(L, 1);
	int32_t vertical = (int32_t)luaL_checkinteger(L, 2);
	int32_t horizontal = (int32_t)luaL_optinteger(L, 3, 0);
	CGScrollEventUnit unit = lua_toboolean(L, 4) ? kCGScrollEventUnitLine : kCGScrollEventUnitPixel;
	CGEventRef cgEvent = CGEventCreateScrollWheelEvent(NULL, unit,
		2, vertical, horizontal);
	NSEvent *event = [NSEvent eventWithCGEvent:cgEvent];
	CFRelease(cgEvent);
	__block NSScrollView *receiver = nil;
	Method method = class_getInstanceMethod(NSScrollView.class, @selector(scrollWheel:));
	IMP recorder = imp_implementationWithBlock(^(NSScrollView *scroll, NSEvent *wheel) {
		receiver = scroll;
	});
	IMP original = method_setImplementation(method, recorder);
	@try {
		[view scrollWheel:event];
	} @finally {
		method_setImplementation(method, original);
		imp_removeBlock(recorder);
	}
	push_objc(L, receiver, "nsview");
	return 1;
}
