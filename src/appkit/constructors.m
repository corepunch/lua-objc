/* Native constructors exported by the AppKit module. */
#import <QuartzCore/QuartzCore.h>

/* A stack is the drag destination for both of its drag features: files
 * dropped on it (`onDrop`) and its own items dragged to reorder
 * (reorder_container.m). AppKit sends one set of NSDraggingDestination
 * messages per view, so the stack implements them once and routes each drag
 * by its payload. A category method with the same selector would silently
 * replace these, which is how file drops once stopped reaching `onDrop`. */
@protocol LuaStackReorder <NSObject>
- (NSDragOperation)validateDrag:(id<NSDraggingInfo>)info;
- (BOOL)acceptDrag:(id<NSDraggingInfo>)info;
@end

/* AppKit has no KVC property to exclude a container subtree from hit testing.
 * Keep the native NSView traversal and opt out before it visits descendants. */
@interface LuaStackView : NSView
@property(nonatomic) BOOL allowsHitTesting;
// SwiftUI `.dropDestination(for: URL.self)`: files dropped on the stack go to
// `onDrop(paths)`, which returns whether it took them.
@property(nonatomic, strong) LuaReg *dropReg;
@property(nonatomic) BOOL dropTargeted;
// Accept only drags from other applications: a drag that starts in this
// app has a dragging source, one from the Finder has none.
@property(nonatomic) BOOL dropExternalOnly;
// Moves the stack's own items when one is dragged within it.
@property(nonatomic, strong) id<LuaStackReorder> reorder;
@end
@implementation LuaStackView
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) _allowsHitTesting = YES;
	return self;
}
// Publish the same content measurement used by the stack layout engine to
// native hosts such as NSToolbar, which ask for intrinsic/fitting geometry.
- (NSSize)intrinsicContentSize {
	if (!objc_getAssociatedObject(self, &kToolbarContentKey) || layout_axis(self) == LayoutAxisNone) return [super intrinsicContentSize];
	return measure_view(self, (LuaLayoutConstraint){
		.widthMode = LuaMeasureUndefined, .heightMode = LuaMeasureUndefined });
}
- (NSSize)fittingSize {
	return objc_getAssociatedObject(self, &kToolbarContentKey) ? self.intrinsicContentSize : [super fittingSize];
}
- (void)layout {
	[super layout];
	layout_from_appkit();
}
- (NSView *)hitTest:(NSPoint)point { return _allowsHitTesting ? [super hitTest:point] : nil; }
static NSArray<NSString *> *stack_drop_paths(id<NSDraggingInfo> info) {
	NSArray<NSURL *> *urls = [info.draggingPasteboard readObjectsForClasses:@[NSURL.class]
		options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
	NSMutableArray *paths = [NSMutableArray array];
	for (NSURL *url in urls) if (url.path.length) [paths addObject:url.path];
	return paths;
}
// Types the stack takes: file URLs for `onDrop`, its item type for reorder.
static void stack_register_drag_types(LuaStackView *view) {
	NSMutableArray *types = [NSMutableArray array];
	if (view.dropReg) [types addObject:NSPasteboardTypeFileURL];
	if (view.reorder) [types addObject:@"org.luaobjc.reorder-item"];
	if (types.count) [view registerForDraggedTypes:types];
	else [view unregisterDraggedTypes];
}
// While files hover over it, the stack shows the system focus indicator.
- (void)setDropTargeted:(BOOL)targeted {
	_dropTargeted = targeted;
	self.wantsLayer = YES;
	self.layer.borderWidth = targeted ? kDropHighlightWidth : 0;
	self.layer.borderColor = NSColor.keyboardFocusIndicatorColor.CGColor;
}
- (BOOL)acceptsFileDrag:(id<NSDraggingInfo>)sender {
	return self.dropReg && (!self.dropExternalOnly || sender.draggingSource == nil)
		&& stack_drop_paths(sender).count > 0;
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
	NSDragOperation reorder = [self.reorder validateDrag:sender];
	if (reorder != NSDragOperationNone) return reorder;
	self.dropTargeted = [self acceptsFileDrag:sender];
	return self.dropTargeted ? NSDragOperationCopy : NSDragOperationNone;
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
	NSDragOperation reorder = [self.reorder validateDrag:sender];
	if (reorder != NSDragOperationNone) return reorder;
	return self.dropTargeted ? NSDragOperationCopy : NSDragOperationNone;
}
- (void)draggingExited:(id<NSDraggingInfo>)sender { (void)sender; self.dropTargeted = NO; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	self.dropTargeted = NO;
	if ([self.reorder validateDrag:sender] != NSDragOperationNone) return [self.reorder acceptDrag:sender];
	if (![self acceptsFileDrag:sender]) return NO;
	return stack_perform_drop(self, stack_drop_paths(sender));
}
static BOOL stack_perform_drop(LuaStackView *view, NSArray<NSString *> *paths) {
	lua_State *L = lua_reg_live_state(view.dropReg);
	if (!L || !paths.count || !lua_reg_push(view.dropReg)) return NO;
	lua_createtable(L, (int)paths.count, 0);
	for (NSUInteger i = 0; i < paths.count; i++) { lua_pushstring(L, paths[i].UTF8String); lua_rawseti(L, -2, (lua_Integer)i + 1); }
	if (lua_objc_pcall(L, 1, 1, "drop") != LUA_OK) return NO;
	BOOL accepted = lua_toboolean(L, -1);
	lua_pop(L, 1);
	return accepted;
}
- (void)viewDidChangeEffectiveAppearance {
	[super viewDidChangeEffectiveAppearance];
	NSColor *color = self.backgroundColor;
	if (color) self.backgroundColor = color;
}
@end

// _setDropHandler(stack, onDrop | nil, externalOnly)
static int bridge_set_drop_handler(lua_State *L) {
	LuaStackView *view = lua_objc_check_object(L, 1, [LuaStackView class], "stack");
	view.dropReg = lua_reg_opt(L, 2);
	view.dropExternalOnly = lua_toboolean(L, 3);
	stack_register_drag_types(view);
	return 0;
}

/* The drag a test hook hands to a stack: files on a private pasteboard, from
 * the Finder (no source) or from inside this app. Only the NSDraggingInfo
 * members the stack reads are implemented. */
@interface LuaTestFileDrag : NSObject
@property(nonatomic, strong) NSPasteboard *draggingPasteboard;
@property(nonatomic, strong) id draggingSource;
@end
@implementation LuaTestFileDrag
@end

// Test hook: _dropFiles(stack, paths[, fromThisApp]) delivers the drop
// through the stack's own NSDraggingDestination methods, as AppKit does.
static int bridge_drop_files(lua_State *L) {
	LuaStackView *view = lua_objc_check_object(L, 1, [LuaStackView class], "stack");
	luaL_checktype(L, 2, LUA_TTABLE);
	NSMutableArray<NSURL *> *urls = [NSMutableArray array];
	for (lua_Integer i = 1; ; i++) {
		lua_rawgeti(L, 2, i);
		if (lua_isnil(L, -1)) { lua_pop(L, 1); break; }
		[urls addObject:[NSURL fileURLWithPath:[NSString stringWithUTF8String:luaL_checkstring(L, -1)]]];
		lua_pop(L, 1);
	}
	LuaTestFileDrag *drag = [LuaTestFileDrag new];
	drag.draggingPasteboard = [NSPasteboard pasteboardWithUniqueName];
	[drag.draggingPasteboard clearContents];
	[drag.draggingPasteboard writeObjects:urls];
	if (lua_toboolean(L, 3)) drag.draggingSource = view;
	id<NSDraggingInfo> info = (id<NSDraggingInfo>)drag;
	BOOL accepted = [view draggingEntered:info] != NSDragOperationNone && [view performDragOperation:info];
	[drag.draggingPasteboard releaseGlobally];
	lua_pushboolean(L, accepted);
	return 1;
}

static int bridge_hit_test_target(lua_State *L) {
	NSView *view = check_view(L, 1);
	NSView *target = check_view(L, 2);
	NSPoint point = NSMakePoint(luaL_checknumber(L, 3), luaL_checknumber(L, 4));
	lua_pushboolean(L, [view hitTest:point] == target);
	return 1;
}

static int bridge_AppKitControls_vstack(lua_State *L) {

	NSView *obj = [[LuaStackView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisVStack), OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_hstack(lua_State *L) {

	NSView *obj = [[LuaStackView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisHStack), OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_flowStack(lua_State *L) {

	NSView *obj = [[LuaStackView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisFlow), OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_zstack(lua_State *L) {
	NSView *obj = [[LuaStackView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisZStack), OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

@interface NSScrollView (LuaKeyboardScroll)
@property(nonatomic) BOOL scrollOnKeyboard;
@end
@implementation NSScrollView (LuaKeyboardScroll)
- (BOOL)scrollOnKeyboard {
	return [objc_getAssociatedObject(self, &kKeys[kScrollOnKeyboardKey]) boolValue];
}
- (void)setScrollOnKeyboard:(BOOL)value {
	objc_setAssociatedObject(self, &kKeys[kScrollOnKeyboardKey], @(value),
		OBJC_ASSOCIATION_RETAIN);
}
@end

static int bridge_AppKitControls_scrollView(lua_State *L) {
	NSView *content = check_view(L, 1);
	CGFloat contentWidth = (CGFloat)luaL_optnumber(L, 2, 0);
	CGFloat contentHeight = (CGFloat)luaL_optnumber(L, 3, 0);

	NSScrollView *obj = [[LuaScrollView alloc] initWithFrame:NSZeroRect];
	obj.clipsToBounds = YES;
	obj.contentView.clipsToBounds = YES;
	obj.autohidesScrollers = YES;
	obj.borderType = NSNoBorder;
	obj.drawsBackground = NO;
	obj.documentView = content;
	objc_setAssociatedObject(obj, &kKeys[kScrollContentKey], content, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	/* Assigning documentView can restore AppKit's default vertical scroller;
	 * apply the requested axis policy after the document is installed. */
	obj.hasHorizontalScroller = YES;
	obj.hasVerticalScroller = NO;
	if (contentWidth > 0 || contentHeight > 0) {
		NSRect frame = content.frame;
		frame.size.width = contentWidth > 0 ? contentWidth : frame.size.width;
		frame.size.height = contentHeight > 0 ? contentHeight : frame.size.height;
		content.frame = frame;
		layout_recursive(content, frame.size.width);
	}
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_hsplit(lua_State *L) {

	NSSplitView *obj = [[NSSplitView alloc] initWithFrame:NSZeroRect];
	obj.vertical = YES;
	obj.dividerStyle = NSSplitViewDividerStyleThin;
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisHSplit), OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_vsplit(lua_State *L) {

	NSSplitView *obj = [[NSSplitView alloc] initWithFrame:NSZeroRect];
	obj.vertical = NO;
	obj.dividerStyle = NSSplitViewDividerStyleThin;
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisVSplit), OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_separator(lua_State *L) {

	NSBox *obj = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, kSeparatorSize, kSeparatorSize)];
	obj.boxType = NSBoxSeparator;
	objc_setAssociatedObject(obj, &kKeys[kFixedHeightKey], @(kSeparatorSize), OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFillWidthKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_spacer(lua_State *L) {

	NSView *obj = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSpacerSize, kSpacerSize)];
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexBasisKey], @0, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

@interface LuaGradientView : NSView
@property(nonatomic, strong) CAGradientLayer *gradient;
/* Semantic stops, kept so the layer's CGColors follow the appearance. */
@property(nonatomic, copy) NSArray<NSColor *> *colors;
- (void)resolveColors;
@end

@implementation LuaGradientView
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.wantsLayer = YES;
		self.layer = [CALayer layer];
		self.layer.masksToBounds = YES;
	}
	return self;
}
- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	self.gradient.frame = self.bounds;
}
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)resolveColors {
	if (!self.colors) return;
	NSMutableArray *resolved = [NSMutableArray arrayWithCapacity:self.colors.count];
	[self.effectiveAppearance performAsCurrentDrawingAppearance:^{
		for (NSColor *color in self.colors) [resolved addObject:(id)color.CGColor];
	}];
	self.gradient.colors = resolved;
}
- (void)viewDidChangeEffectiveAppearance {
	[super viewDidChangeEffectiveAppearance];
	[self resolveColors];
}
@end

/* SwiftUI LinearGradient(colors:startPoint:endPoint:): evenly spaced semantic
 * stops between two unit points. Unit points have a top-left origin; the
 * layer of an unflipped NSView has its origin at the bottom, so y inverts. */
static int bridge_AppKitControls_linearGradientColors(lua_State *L) {
	LuaGradientView *view = (LuaGradientView *)check_view(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);
	NSMutableArray<NSColor *> *colors = [NSMutableArray array];
	lua_Integer count = luaL_len(L, 2);
	if (count < 2) return luaL_error(L, "LinearGradient colors needs at least two colors");
	for (lua_Integer index = 1; index <= count; index++) {
		lua_geti(L, 2, index);
		[colors addObject:semantic_color([NSString stringWithUTF8String:luaL_checkstring(L, -1)])];
		lua_pop(L, 1);
	}
	view.colors = colors;
	view.gradient.locations = nil;
	view.gradient.startPoint = CGPointMake(luaL_checknumber(L, 3), 1 - luaL_checknumber(L, 4));
	view.gradient.endPoint = CGPointMake(luaL_checknumber(L, 5), 1 - luaL_checknumber(L, 6));
	[view resolveColors];
	return 0;
}

static int bridge_AppKitControls_linearGradient(lua_State *L) {
	CGFloat topAlpha = (CGFloat)luaL_optnumber(L, 1, 0);
	CGFloat middleAlpha = (CGFloat)luaL_optnumber(L, 2, 0.5);
	CGFloat middleLocation = (CGFloat)luaL_optnumber(L, 3, 0.6);
	CGFloat bottomAlpha = (CGFloat)luaL_optnumber(L, 4, 0.82);
	LuaGradientView *view = [[LuaGradientView alloc] initWithFrame:NSZeroRect];
	CAGradientLayer *gradient = [CAGradientLayer layer];
	gradient.colors = @[(id)[NSColor colorWithWhite:0 alpha:topAlpha].CGColor,
		(id)[NSColor colorWithWhite:0 alpha:topAlpha].CGColor,
		(id)[NSColor colorWithWhite:0 alpha:middleAlpha].CGColor,
		(id)[NSColor colorWithWhite:0 alpha:bottomAlpha].CGColor];
	gradient.locations = @[@0.0, @0.3, @(middleLocation), @1.0];
	gradient.startPoint = CGPointMake(0.5, 1);
	gradient.endPoint = CGPointMake(0.5, 0);
	view.gradient = gradient;
	[view.layer addSublayer:gradient];
	push_objc(L, view, "nsview");
	return 1;
}

static int bridge_AppKitControls_label(lua_State *L) {
	push_objc(L, [LuaLabel wrappingLabelWithString:@""], "nsview");
	return 1;
}

static int bridge_AppKitControls_textField(lua_State *L) {

	LuaTextField *obj = [[LuaTextField alloc] initWithFrame:NSZeroRect];
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_secureTextField(lua_State *L) {
	LuaSecureTextField *obj = [[LuaSecureTextField alloc]
		initWithFrame:NSZeroRect];
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_searchField(lua_State *L) {
	NSSearchField *obj = [[NSSearchField alloc] initWithFrame:NSZeroRect];
	obj.bezelStyle = NSTextFieldRoundedBezel;
	obj.bezeled = YES;
	obj.drawsBackground = YES;
	[obj sizeToFit];
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_box(lua_State *L) {

	NSBox *obj = [[NSBox alloc] initWithFrame:NSZeroRect];
	push_objc(L, obj, "nsview");
	return 1;
}

/* SwiftUI's ProgressView() spins from the moment it appears. An
 * indeterminate indicator that hides while stopped would otherwise never be
 * seen, so it animates while it is shown in a window and stops when it
 * leaves or hides.
 * `spinning` reports that state to headless tests. */
@interface LuaProgressIndicator : NSProgressIndicator
@property(nonatomic, readonly) BOOL spinning;
@end

@implementation LuaProgressIndicator
- (void)viewDidMoveToWindow {
	[super viewDidMoveToWindow];
	[self updateSpinning];
}
- (void)setIndeterminate:(BOOL)indeterminate {
	[super setIndeterminate:indeterminate];
	[self updateSpinning];
}
- (void)setHidden:(BOOL)hidden {
	[super setHidden:hidden];
	[self updateSpinning];
}
- (void)updateSpinning {
	BOOL spin = self.isIndeterminate && self.window != nil && !self.hidden;
	if (spin == _spinning) return;
	_spinning = spin;
	if (spin) [self startAnimation:nil]; else [self stopAnimation:nil];
}
@end

static int bridge_AppKitControls_progressIndicator(lua_State *L) {

	NSProgressIndicator *obj = [[LuaProgressIndicator alloc] initWithFrame:NSZeroRect];
	push_objc(L, obj, "nsview");
	return 1;
}

// SwiftUI `Gauge` with the linear capacity style.
static int bridge_AppKitControls_levelIndicator(lua_State *L) {

	LuaLevelIndicator *obj = [[LuaLevelIndicator alloc] initWithFrame:NSZeroRect];
	[obj sizeToFit];
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_tableCellView(lua_State *L) {

	NSTableCellView *obj = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_popUpButton(lua_State *L) {

	NSPopUpButton *obj = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
	push_objc(L, obj, "nsview");
	return 1;
}

@interface LuaPopupMenuTarget : NSObject
@property(nonatomic, strong) NSArray *callbacks;
@end

@implementation LuaPopupMenuTarget
- (void)onAction:(NSPopUpButton *)sender {
	NSInteger index = sender.indexOfSelectedItem;
	if (index <= 0 || index > (NSInteger)self.callbacks.count) return;
	id callback = self.callbacks[index - 1];
	if (![callback isKindOfClass:LuaReg.class]) return;
	lua_State *L = lua_reg_live_state(callback);
	if (L && lua_reg_push(callback))
		lua_objc_pcall(L, 0, 0, "menu");
}
- (void)dealloc {
	for (id callback in _callbacks)
		if ([callback isKindOfClass:LuaReg.class]) [callback dispose];
}
@end

static int bridge_AppKitControls_menu(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	const char *title = luaL_optstring(L, 2, "Menu");
	const char *systemImage = luaL_optstring(L, 3, "");
	CGFloat symbolSize = (CGFloat)luaL_optnumber(L, 4, kDefaultSymbolPointSize);
	const char *imagePath = luaL_optstring(L, 5, "");
	if (symbolSize <= 0) return luaL_error(L, "menu symbolSize must be positive");
	NSPopUpButton *button = [[NSPopUpButton alloc]
		initWithFrame:NSZeroRect pullsDown:YES];
	button.bordered = NO;
	[button removeAllItems];
	[button addItemWithTitle:[NSString stringWithUTF8String:title]];
	NSImage *buttonImage = imagePath[0]
		? [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String:imagePath]] : nil;
	if (buttonImage) buttonImage.size = NSMakeSize(symbolSize, symbolSize);
	if (!buttonImage && systemImage[0]) {
		buttonImage = [NSImage imageWithSystemSymbolName:
			[NSString stringWithUTF8String:systemImage] accessibilityDescription:nil];
		buttonImage = [buttonImage imageWithSymbolConfiguration:
			[NSImageSymbolConfiguration configurationWithPointSize:symbolSize
				weight:NSFontWeightRegular]];
	}
	[button itemAtIndex:0].image = buttonImage;
	NSMutableArray *callbacks = [NSMutableArray array];
	NSInteger count = (NSInteger)luaL_len(L, 1);
	for (NSInteger index = 1; index <= count; index++) {
		lua_rawgeti(L, 1, index);
		lua_getfield(L, -1, "separator");
		BOOL separator = lua_toboolean(L, -1);
		lua_pop(L, 1);
		if (separator) {
			// Callbacks stay indexed by menu item, so a separator holds a slot.
			[button.menu addItem:[NSMenuItem separatorItem]];
			[callbacks addObject:NSNull.null];
			lua_pop(L, 1);
			continue;
		}
		lua_getfield(L, -1, "title");
		const char *itemTitle = luaL_optstring(L, -1, "");
		lua_pop(L, 1);
		// addItemWithTitle: replaces an existing item of the same title; a
		// menu may repeat titles across sections, so append the item directly.
		NSMenuItem *item = [[NSMenuItem alloc]
			initWithTitle:[NSString stringWithUTF8String:itemTitle] action:NULL keyEquivalent:@""];
		[button.menu addItem:item];
		lua_getfield(L, -1, "checked");
		if (lua_toboolean(L, -1)) item.state = NSControlStateValueOn;
		lua_pop(L, 1);
		lua_getfield(L, -1, "systemImage");
		const char *itemSymbol = luaL_optstring(L, -1, "");
		if (itemSymbol[0]) item.image = [NSImage imageWithSystemSymbolName:
			[NSString stringWithUTF8String:itemSymbol] accessibilityDescription:nil];
		lua_pop(L, 1);
		lua_getfield(L, -1, "imagePath");
		const char *imagePath = luaL_optstring(L, -1, "");
		if (imagePath[0]) {
			NSImage *image = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String:imagePath]];
			if (image) {
				image.size = NSMakeSize(symbolSize, symbolSize);
				item.image = image;
			}
		}
		lua_pop(L, 1);
		lua_getfield(L, -1, "action");
		LuaReg *callback = lua_reg_opt(L, -1);
		[callbacks addObject:callback ?: NSNull.null];
		if (!callback) item.enabled = NO;
		lua_pop(L, 2);
	}
	LuaPopupMenuTarget *target = [[LuaPopupMenuTarget alloc] init];
	target.callbacks = callbacks;
	button.target = target;
	button.action = @selector(onAction:);
	objc_setAssociatedObject(button, &kKeys[kCallbackKey], target,
		OBJC_ASSOCIATION_RETAIN);
	[button sizeToFit];
	push_objc(L, button, "nsview");
	return 1;
}

static void configure_control_callback(
	NSControl *control, lua_State *L, int callbackIndex
) {
	LuaReg *reg = lua_reg_opt(L, callbackIndex);
	if (!reg) return;
	lua_reg_store(control, &kKeys[kCallbackKey], reg);
	control.target = [LuaButtonTarget shared];
	control.action = @selector(onAction:);
}

static int bridge_AppKitControls_slider(lua_State *L) {
	CGFloat minimum = (CGFloat)luaL_optnumber(L, 1, 0);
	CGFloat maximum = (CGFloat)luaL_optnumber(L, 2, 1);
	CGFloat value = (CGFloat)luaL_optnumber(L, 3, minimum);
	if (maximum < minimum) {
		return luaL_error(L, "Slider maximum must be greater than or equal to minimum");
	}

	const char *style = luaL_optstring(L, 5, "");

	/* `level`: an editable continuous capacity indicator, AppKit's native
	 * fill bar. Dragging or clicking sets the value, like a drum machine's
	 * level fader. */
	if (strcmp(style, "level") == 0) {
		LuaLevelIndicator *level = [[LuaLevelIndicator alloc] initWithFrame:NSZeroRect];
		level.minValue = minimum;
		level.maxValue = maximum;
		level.doubleValue = MIN(MAX(value, minimum), maximum);
		level.editable = YES;
		level.continuous = YES;
		configure_control_callback(level, L, 4);
		push_objc(L, level, "nsview");
		return 1;
	}
	NSSlider *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
	slider.minValue = minimum;
	slider.maxValue = maximum;
	slider.doubleValue = MIN(MAX(value, minimum), maximum);
	if (style[0]) return luaL_error(L, "Slider style must be level");
	configure_control_callback(slider, L, 4);
	push_objc(L, slider, "nsview");
	return 1;
}

static int bridge_AppKitControls_stepper(lua_State *L) {
	CGFloat minimum = (CGFloat)luaL_optnumber(L, 1, 0);
	CGFloat maximum = (CGFloat)luaL_optnumber(L, 2, 100);
	CGFloat increment = (CGFloat)luaL_optnumber(L, 3, 1);
	CGFloat value = (CGFloat)luaL_optnumber(L, 4, minimum);
	if (maximum < minimum || increment <= 0) {
		return luaL_error(L, "Stepper requires maximum >= minimum and increment > 0");
	}

	NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
	stepper.minValue = minimum;
	stepper.maxValue = maximum;
	stepper.increment = increment;
	stepper.doubleValue = MIN(MAX(value, minimum), maximum);
	configure_control_callback(stepper, L, 5);
	push_objc(L, stepper, "nsview");
	return 1;
}

static int bridge_AppKitControls_picker(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	NSInteger selectedIndex = (NSInteger)luaL_optinteger(L, 2, 0);
	id titles = lua_to_objc_value(L, 1);
	if (![titles isKindOfClass:[NSArray class]]) {
		return luaL_error(L, "Picker options must be an array");
	}

	NSPopUpButton *picker = [[NSPopUpButton alloc]
		initWithFrame:NSZeroRect pullsDown:NO];
	[picker addItemsWithTitles:titles];
	if (selectedIndex >= 0 && selectedIndex < picker.numberOfItems) {
		[picker selectItemAtIndex:selectedIndex];
	}
	configure_control_callback(picker, L, 3);
	push_objc(L, picker, "nsview");
	return 1;
}

// SwiftUI `.pickerStyle(.segmented)`: one labelled segment per option,
// selecting exactly one, with the same callback wiring as the pop-up picker.
static int bridge_AppKitControls_segmentedPicker(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	NSInteger selectedIndex = (NSInteger)luaL_optinteger(L, 2, 0);
	id titles = lua_to_objc_value(L, 1);
	if (![titles isKindOfClass:[NSArray class]]) {
		return luaL_error(L, "Picker options must be an array");
	}
	NSSegmentedControl *control = [NSSegmentedControl
		segmentedControlWithLabels:titles
		trackingMode:NSSegmentSwitchTrackingSelectOne
		target:nil action:nil];
	if (selectedIndex >= 0 && selectedIndex < control.segmentCount) {
		control.selectedSegment = selectedIndex;
	}
	configure_control_callback(control, L, 3);
	[control sizeToFit];
	push_objc(L, control, "nsview");
	return 1;
}

static int bridge_AppKitControls_datePicker(lua_State *L) {
	NSDatePicker *picker = [[NSDatePicker alloc] initWithFrame:NSZeroRect];
	picker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
	picker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
	if (!lua_isnoneornil(L, 1))
		picker.dateValue = [NSDate dateWithTimeIntervalSince1970:luaL_checknumber(L, 1)];
	configure_control_callback(picker, L, 2);
	[picker sizeToFit];
	push_objc(L, picker, "nsview");
	return 1;
}

static int bridge_AppKitControls_colorPicker(lua_State *L) {
	NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSZeroRect];
	if (!lua_isnoneornil(L, 1))
		well.color = semantic_color([NSString stringWithUTF8String:luaL_checkstring(L, 1)]);
	configure_control_callback(well, L, 2);
	[well sizeToFit];
	push_objc(L, well, "nsview");
	return 1;
}

// NSButton owns tracking, keyboard activation, focus, and accessibility. Its
// declarative label must not intercept the native control's mouse events.
@interface LuaContentButton : NSButton
@end
@implementation LuaContentButton
- (NSView *)hitTest:(NSPoint)point { return [super hitTest:point] ? self : nil; }
@end

static int bridge_AppKitControls_button(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	NSView *content = lua_isnoneornil(L, 3) ? nil : check_view(L, 3);
	NSButton *obj = content ? [[LuaContentButton alloc] initWithFrame:NSZeroRect]
		: [[NSButton alloc] initWithFrame:NSZeroRect];
	obj.title = [NSString stringWithUTF8String:title];
	obj.bezelStyle = NSBezelStyleRounded;
	[obj sizeToFit];
	configure_control_callback(obj, L, 2);
	if (content) {
		[obj addSubview:content];
		objc_setAssociatedObject(obj, &kKeys[kButtonContentKey], content, OBJC_ASSOCIATION_RETAIN);
	}
	push_objc(L, obj, "nsview");
	return 1;
}

/* NSButtonCell centres an image-above-title stack on the title's line box,
 * which includes the descender, so the glyphs read high in a tall bezel —
 * visibly so on a drum pad. Centring the ink (image top to baseline) is what
 * SwiftUI's button toggle shows; the bezel is untouched. */
@interface LuaToggleButtonCell : NSButtonCell
@end
@implementation LuaToggleButtonCell
- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
	CGFloat shift = self.image && self.imagePosition == NSImageAbove ? -self.font.descender / 2 : 0;
	if (!view.isFlipped) shift = -shift;
	[super drawInteriorWithFrame:NSOffsetRect(frame, 0, shift) inView:view];
}
@end
@interface LuaToggleButton : NSButton
@end
@implementation LuaToggleButton
+ (Class)cellClass { return LuaToggleButtonCell.class; }
@end

static int bridge_AppKitControls_toggle(lua_State *L) {
	const char *label = luaL_checkstring(L, 1);
	BOOL is_on = (BOOL)lua_toboolean(L, 2);
	const char *style = luaL_optstring(L, 4, "");

	/* System Settings rows use NSSwitch. A titled checkbox remains the default. */
	if (strcmp(style, "switch") == 0) {
		NSSwitch *control = [[NSSwitch alloc] initWithFrame:NSZeroRect];
		control.state = is_on ? NSControlStateValueOn : NSControlStateValueOff;
		if (label[0]) control.accessibilityLabel = [NSString stringWithUTF8String:label];
		[control sizeToFit];
		configure_control_callback(control, L, 3);
		push_objc(L, control, "nsview");
		return 1;
	}

	/* SwiftUI `.toggleStyle(.button)`: a push-on/push-off button whose bezel
	 * fills with the tint while on, like a lit drum-machine pad. */
	if (strcmp(style, "button") == 0) {
		NSButton *pad = [[LuaToggleButton alloc] initWithFrame:NSZeroRect];
		pad.title = [NSString stringWithUTF8String:label];
		[pad setButtonType:NSButtonTypePushOnPushOff];
		pad.bezelStyle = NSBezelStyleFlexiblePush;
		const char *symbol = luaL_optstring(L, 5, "");
		if (symbol[0]) {
			NSImage *image = [NSImage imageWithSystemSymbolName:[NSString stringWithUTF8String:symbol]
				accessibilityDescription:nil];
			/* Without a size the symbol follows the button font, as in SwiftUI. */
			if (!lua_isnoneornil(L, 6)) {
				CGFloat symbolSize = (CGFloat)luaL_checknumber(L, 6);
				if (symbolSize <= 0) return luaL_error(L, "toggle symbolSize must be positive");
				image = [image imageWithSymbolConfiguration:
					[NSImageSymbolConfiguration configurationWithPointSize:symbolSize weight:NSFontWeightRegular]];
			}
			pad.image = image;
			pad.imagePosition = NSImageAbove;
			pad.imageHugsTitle = YES;
		}
		pad.state = is_on ? NSControlStateValueOn : NSControlStateValueOff;
		[pad sizeToFit];
		configure_control_callback(pad, L, 3);
		push_objc(L, pad, "nsview");
		return 1;
	}

	NSButton *obj = [NSButton checkboxWithTitle:[NSString stringWithUTF8String:label] target:nil action:nil];
	obj.state = is_on ? NSControlStateValueOn : NSControlStateValueOff;
	[obj sizeToFit];
	configure_control_callback(obj, L, 3);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_NSScrollView_onRefresh(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");
	bridge_set_optional_callback(L, obj, &kKeys[kTableRefreshKey], 2);
	return 0;
}

static int bridge_NSScrollView_onRowSelect(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");
	bridge_set_optional_callback(L, table_scrollview(obj), &kKeys[kTableSelectionKey], 2);
	return 0;
}

static int bridge_NSScrollView_onRowMove(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (![src isKindOfClass:[LuaTableViewSource class]])
		return luaL_error(L, "onRowMove requires a table view");
	NSScrollView *scroll = table_scrollview(obj);
	bridge_set_optional_callback(L, scroll, &kKeys[kTableMoveKey], 2);
	if (!lua_isnoneornil(L, 2)) {
		NSTableView *table = (NSTableView *)scroll.documentView;
		[table registerForDraggedTypes:@[NSPasteboardTypeString]];
		[table setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
	}
	return 0;
}

// setDragKey(key | nil): rows drag as the file at row[key].
static int bridge_NSScrollView_setDragKey(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *source = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (![source isKindOfClass:[LuaTableViewSource class]]) return luaL_error(L, "setDragKey requires a table view");
	const char *key = luaL_optstring(L, 2, NULL);
	source.dragKey = key ? [NSString stringWithUTF8String:key] : nil;
	NSTableView *table = (NSTableView *)table_scrollview(obj).documentView;
	[table setDraggingSourceOperationMask:key ? NSDragOperationCopy | NSDragOperationGeneric : NSDragOperationNone forLocal:NO];
	return 0;
}

// Test hook: _tableDragPath(list, row) → the path row `row` (1-based) drags.
static int bridge_table_drag_path(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *source = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	NSTableView *table = (NSTableView *)table_scrollview(obj).documentView;
	id writer = [source tableView:table pasteboardWriterForRow:(NSInteger)luaL_checkinteger(L, 2) - 1];
	if ([writer isKindOfClass:NSURL.class]) lua_pushstring(L, ((NSURL *)writer).path.UTF8String); else lua_pushnil(L);
	return 1;
}

static int bridge_NSScrollView_onRowSwipe(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *source = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!source) return luaL_error(L, "onRowSwipe requires a table view");
	const char *edge = luaL_checkstring(L, 2);
	NSString *title = [NSString stringWithUTF8String:luaL_checkstring(L, 3)];
	BOOL destructive = strcmp(luaL_optstring(L, 4, "normal"), "destructive") == 0;
	(void)lua_toboolean(L, 5); // AppKit owns the row action's full-swipe behavior.
	LuaReg *callback = lua_reg_opt(L, 6);
	if (strcmp(edge, "leading") == 0) {
		source.leadingSwipeReg = callback;
		source.leadingSwipeTitle = title;
		source.leadingSwipeDestructive = destructive;
	} else if (strcmp(edge, "trailing") == 0) {
		source.trailingSwipeReg = callback;
		source.trailingSwipeTitle = title;
		source.trailingSwipeDestructive = destructive;
	} else return luaL_error(L, "swipe edge must be leading or trailing");
	return 0;
}

static int bridge_test_row_swipe(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *source = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!source) return luaL_error(L, "row swipe test requires a table view");
	NSInteger row = (NSInteger)luaL_checkinteger(L, 2) - 1;
	const char *edge = luaL_checkstring(L, 3);
	if (strcmp(edge, "leading") != 0 && strcmp(edge, "trailing") != 0)
		return luaL_error(L, "swipe edge must be leading or trailing");
	lua_pushboolean(L, [source invokeSwipeAtRow:row leading:strcmp(edge, "leading") == 0]);
	return 1;
}

static int bridge_NSScrollView_onColumnButton(lua_State *L) {
	id obj = check_objc(L, 1);
	if (!objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]))
		return luaL_error(L, "not a table view");
	bridge_set_optional_callback(L, table_scrollview(obj), &kKeys[kTableColumnButtonKey], 2);
	return 0;
}

static const char kTableRowMenuDelegateKey;
static int bridge_NSScrollView_onRowMenu(lua_State *L) {
	id obj = check_objc(L, 1);
	if (!objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]))
		return luaL_error(L, "not a table view");
	NSScrollView *scroll = table_scrollview(obj);
	NSTableView *table = (NSTableView *)scroll.documentView;
	bridge_set_optional_callback(L, scroll, &kKeys[kTableRowMenuKey], 2);
	LuaTableRowMenuDelegate *delegate = nil;
	if (!lua_isnoneornil(L, 2)) {
		delegate = [LuaTableRowMenuDelegate new];
		delegate.scroll = scroll;
	}
	NSMenu *menu = nil;
	if (delegate) {
		menu = [[NSMenu alloc] init];
		menu.autoenablesItems = NO;
		menu.delegate = delegate;
	}
	table.menu = menu;
	objc_setAssociatedObject(table, &kTableRowMenuDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN);
	return 0;
}

/* Headless tests read a row menu exactly as AppKit would build it, then
 * perform one item, without opening a menu. Indices are 1-based. */
static int bridge_table_row_menu(lua_State *L) {
	id obj = check_objc(L, 1);
	if (!objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]))
		return luaL_error(L, "not a table view");
	NSMenu *menu = [[NSMenu alloc] init];
	table_row_menu_fill(table_scrollview(obj), menu, (NSInteger)luaL_checkinteger(L, 2) - 1);
	NSInteger perform = (NSInteger)luaL_optinteger(L, 3, 0);
	if (perform > 0) {
		if (perform > menu.numberOfItems) return luaL_error(L, "row menu has no item %d", (int)perform);
		NSMenuItem *item = [menu itemAtIndex:perform - 1];
		if (!item.enabled || !item.action) return luaL_error(L, "row menu item %d is not enabled", (int)perform);
		[NSApp sendAction:item.action to:item.target from:item];
		return 0;
	}
	lua_createtable(L, (int)menu.numberOfItems, 0);
	for (NSInteger index = 0; index < menu.numberOfItems; index++) {
		NSMenuItem *item = [menu itemAtIndex:index];
		lua_newtable(L);
		if (item.separatorItem) {
			lua_pushboolean(L, 1); lua_setfield(L, -2, "separator");
		} else {
			lua_pushstring(L, item.title.UTF8String); lua_setfield(L, -2, "title");
			lua_pushboolean(L, !item.enabled); lua_setfield(L, -2, "disabled");
		}
		lua_rawseti(L, -2, index + 1);
	}
	return 1;
}

static int bridge_NSScrollView_onColumnSort(lua_State *L) {
	id obj = check_objc(L, 1);
	if (!objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]))
		return luaL_error(L, "not a table view");
	bridge_set_optional_callback(L, table_scrollview(obj), &kKeys[kTableSortKey], 2);
	return 0;
}

static int bridge_NSScrollView_setSortIndicator(lua_State *L) {
	id obj = check_objc(L, 1);
	if (!objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]))
		return luaL_error(L, "not a table view");
	NSScrollView *scroll = table_scrollview(obj);
	NSTableView *table = (NSTableView *)scroll.documentView;
	NSString *identifier = [NSString stringWithUTF8String:luaL_checkstring(L, 2)];
	BOOL ascending = lua_toboolean(L, 3);
	NSTableColumn *target = nil;
	for (NSTableColumn *column in table.tableColumns) {
		[table setIndicatorImage:nil inTableColumn:column];
		if ([column.identifier isEqualToString:identifier]) target = column;
	}
	if (target) {
		NSString *name = ascending ? @"NSAscendingSortIndicator" : @"NSDescendingSortIndicator";
		[table setIndicatorImage:[NSImage imageNamed:name] inTableColumn:target];
	}
	return 0;
}

static int bridge_pathView(lua_State *L) {
	CGFloat w = (CGFloat)luaL_optnumber(L, 1, 100);
	CGFloat h = (CGFloat)luaL_optnumber(L, 2, 100);
	LuaPathView *obj = [[LuaPathView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_NSScrollView_onRowActivate(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table or outline view");
	NSScrollView *sv = table_scrollview(obj);
	NSTableView *table = (NSTableView *)sv.documentView;
	BOOL hasCallback = !lua_isnoneornil(L, 2);
	table.target = hasCallback ? src : nil;
	table.doubleAction = hasCallback ? @selector(activateSelectedRow:) : nil;
	bridge_set_optional_callback(L, sv, &kKeys[kTableActivationKey], 2);
	return 0;
}

#pragma mark - Page control

/* `_pageControl(numberOfPages, currentPage, onChange(page))`: the page dots
 * of UIPageControl, which has no AppKit class. Each dot is a borderless SF
 * Symbol button, so it takes clicks and VoiceOver reads it as a page; the
 * current one uses the label color and the others the tertiary one, as
 * UIPageControl's defaults do. `currentPage` is zero-based like UIKit's and
 * is set through KVC; a click sets it and calls `onChange` with it. */
@interface LuaPageControl : NSView
@property(nonatomic) NSInteger numberOfPages;
@property(nonatomic) NSInteger currentPage;
@property(nonatomic, strong) LuaReg *onChange;
@end

@implementation LuaPageControl
- (void)dealloc { [_onChange dispose]; }
- (BOOL)isFlipped { return YES; }
- (NSSize)intrinsicContentSize {
	NSInteger count = MAX(0, self.numberOfPages);
	return NSMakeSize(count * kPageControlDotSize + MAX(0, count - 1) * kPageControlDotSpacing, kPageControlDotSize);
}
- (void)setNumberOfPages:(NSInteger)numberOfPages {
	_numberOfPages = MAX(0, numberOfPages);
	for (NSView *dot in self.subviews.copy) [dot removeFromSuperview];
	NSImageSymbolConfiguration *size = [NSImageSymbolConfiguration configurationWithPointSize:kPageControlDotPointSize weight:NSFontWeightRegular];
	NSImage *image = [[NSImage imageWithSystemSymbolName:@"circle.fill" accessibilityDescription:nil] imageWithSymbolConfiguration:size];
	for (NSInteger page = 0; page < _numberOfPages; page++) {
		NSButton *dot = [NSButton buttonWithImage:image target:self action:@selector(selectPage:)];
		dot.bordered = NO;
		dot.tag = page;
		dot.accessibilityLabel = [NSString stringWithFormat:@"Page %ld of %ld", (long)page + 1, (long)_numberOfPages];
		[self addSubview:dot];
	}
	[self updateDots];
	[self invalidateIntrinsicContentSize];
	self.needsLayout = YES;
}
- (void)setCurrentPage:(NSInteger)currentPage {
	_currentPage = MIN(MAX(0, currentPage), MAX(0, self.numberOfPages - 1));
	[self updateDots];
}
- (void)updateDots {
	for (NSButton *dot in self.subviews) {
		BOOL current = dot.tag == self.currentPage;
		dot.contentTintColor = current ? NSColor.labelColor : NSColor.tertiaryLabelColor;
		dot.accessibilityValue = current ? @"Current page" : nil;
	}
}
- (void)layout {
	[super layout];
	NSSize size = self.intrinsicContentSize;
	CGFloat x = floor((self.bounds.size.width - size.width) / 2);
	CGFloat y = floor((self.bounds.size.height - kPageControlDotSize) / 2);
	for (NSButton *dot in self.subviews) {
		dot.frame = NSMakeRect(x + dot.tag * (kPageControlDotSize + kPageControlDotSpacing), y, kPageControlDotSize, kPageControlDotSize);
	}
}
- (void)selectPage:(NSButton *)sender {
	self.currentPage = sender.tag;
	lua_State *callL = lua_reg_live_state(_onChange);
	if (!callL || !lua_reg_push(_onChange)) return;
	lua_pushinteger(callL, sender.tag);
	lua_objc_pcall(callL, 1, 0, "page control");
}
@end

static int bridge_page_control(lua_State *L) {
	LuaPageControl *control = [[LuaPageControl alloc] initWithFrame:NSZeroRect];
	control.numberOfPages = (NSInteger)luaL_optinteger(L, 1, 0);
	control.currentPage = (NSInteger)luaL_optinteger(L, 2, 0);
	control.onChange = lua_reg_opt(L, 3);
	control.accessibilityRole = NSAccessibilityGroupRole;
	control.accessibilityLabel = @"Pages";
	[control setFrameSize:control.intrinsicContentSize];
	push_objc(L, control, "nsview");
	return 1;
}
