#pragma mark - Pointer view (click and hover coordinates)

/* A transparent view that reports clicks and hover positions in its own
 * top-left coordinates. Charts use it to map a point to a mark in Lua, so
 * geometry and hit testing share one tested implementation. */
@interface LuaPointerView : NSView <NSDraggingSource>
@property (nonatomic, strong) LuaReg *clickReg;
@property (nonatomic, strong) LuaReg *hoverReg;
@property (nonatomic, strong) LuaReg *dragReg;
@property (nonatomic, strong) LuaReg *keyReg;
@property (nonatomic, strong) NSTrackingArea *pointerTracking;
@property (nonatomic) NSPoint pressPoint;
@property (nonatomic) BOOL dragStarted;
@end

@implementation LuaPointerView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
- (void)updateTrackingAreas {
	[super updateTrackingAreas];
	if (self.pointerTracking) [self removeTrackingArea:self.pointerTracking];
	self.pointerTracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
		options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited
			| NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
		owner:self userInfo:nil];
	[self addTrackingArea:self.pointerTracking];
}
- (void)send:(LuaReg *)reg point:(NSPoint)point inside:(BOOL)inside count:(NSInteger)count context:(const char *)context {
	lua_State *L = lua_reg_live_state(reg);
	if (!L || !lua_reg_push(reg)) return;
	push_objc(L, self, "nsview");
	if (inside) { lua_pushnumber(L, point.x); lua_pushnumber(L, point.y); }
	else { lua_pushnil(L); lua_pushnil(L); }
	lua_pushinteger(L, count);
	lua_objc_pcall(L, 4, 0, context);
}
- (void)mouseDown:(NSEvent *)event {
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	self.pressPoint = point;
	self.dragStarted = NO;
	if (self.keyReg) [self.window makeFirstResponder:self];
	[self send:self.clickReg point:point inside:YES count:event.clickCount context:"pointer click"];
}
/* Dragging a mark drags the file it stands for, as a Finder item: into the
 * Finder, the Trash or any drop target that takes files. `onDrag(view, x, y)`
 * returns the path under the pointer, or nil. */
- (NSString *)dragPathAt:(NSPoint)point {
	lua_State *L = lua_reg_live_state(self.dragReg);
	if (!L || !lua_reg_push(self.dragReg)) return nil;
	push_objc(L, self, "nsview");
	lua_pushnumber(L, point.x); lua_pushnumber(L, point.y);
	if (lua_objc_pcall(L, 3, 1, "pointer drag") != LUA_OK) return nil;
	NSString *path = lua_isstring(L, -1) ? [NSString stringWithUTF8String:lua_tostring(L, -1)] : nil;
	lua_pop(L, 1);
	return path;
}
- (void)mouseDragged:(NSEvent *)event {
	if (!self.dragReg || self.dragStarted) return;
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	if (hypot(point.x - self.pressPoint.x, point.y - self.pressPoint.y) < kPointerDragThreshold) return;
	self.dragStarted = YES;
	NSString *path = [self dragPathAt:self.pressPoint];
	if (!path.length) return;
	NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter:[NSURL fileURLWithPath:path]];
	NSImage *icon = [NSWorkspace.sharedWorkspace iconForFile:path];
	NSRect frame = NSMakeRect(self.pressPoint.x - kPointerDragIconSize / 2, self.pressPoint.y - kPointerDragIconSize / 2,
		kPointerDragIconSize, kPointerDragIconSize);
	[item setDraggingFrame:frame contents:icon];
	[self beginDraggingSessionWithItems:@[item] event:event source:self];
}
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
	(void)session; (void)context;
	return NSDragOperationCopy | NSDragOperationGeneric;
}
/* Keyboard: `onKey(view, key)` gets "left", "right", "up", "down", "tab",
 * "backtab", "return", "delete", "escape" or the typed characters, and
 * returns true when it handled the key. */
- (BOOL)acceptsFirstResponder { return self.keyReg != nil; }
- (BOOL)becomeFirstResponder { [self setKeyboardFocusRingNeedsDisplayInRect:self.bounds]; return YES; }
- (BOOL)resignFirstResponder { [self setKeyboardFocusRingNeedsDisplayInRect:self.bounds]; return YES; }
- (void)keyDown:(NSEvent *)event {
	NSString *key = nil;
	switch (event.keyCode) {
		case 123: key = @"left"; break;
		case 124: key = @"right"; break;
		case 125: key = @"down"; break;
		case 126: key = @"up"; break;
		case 48: key = (event.modifierFlags & NSEventModifierFlagShift) ? @"backtab" : @"tab"; break;
		case 36: case 76: key = @"return"; break;
		case 51: case 117: key = @"delete"; break;
		case 53: key = @"escape"; break;
		default: key = event.characters; break;
	}
	lua_State *L = lua_reg_live_state(self.keyReg);
	BOOL handled = NO;
	if (key.length && L && lua_reg_push(self.keyReg)) {
		push_objc(L, self, "nsview");
		lua_pushstring(L, key.UTF8String);
		if (lua_objc_pcall(L, 2, 1, "pointer key") == LUA_OK) { handled = lua_toboolean(L, -1); lua_pop(L, 1); }
	}
	if (!handled) [super keyDown:event];
}
- (void)mouseMoved:(NSEvent *)event {
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	[self send:self.hoverReg point:point inside:YES count:0 context:"pointer hover"];
}
- (void)mouseExited:(NSEvent *)event {
	(void)event;
	[self send:self.hoverReg point:NSZeroPoint inside:NO count:0 context:"pointer hover"];
}
@end

// _pointerView(onClick, onHover, onDrag, onKey)
static int bridge_pointer_view(lua_State *L) {
	LuaPointerView *view = [[LuaPointerView alloc] initWithFrame:NSZeroRect];
	view.clickReg = lua_reg_opt(L, 1);
	view.hoverReg = lua_reg_opt(L, 2);
	view.dragReg = lua_reg_opt(L, 3);
	view.keyReg = lua_reg_opt(L, 4);
	push_objc(L, view, "nsview");
	return 1;
}

// Test hook: deliver a click or hover at a point without a window or events.
static int bridge_pointer_send(lua_State *L) {
	LuaPointerView *view = lua_objc_check_object(L, 1, [LuaPointerView class], "pointer view");
	const char *kind = luaL_checkstring(L, 2);
	if (strcmp(kind, "drag") == 0) {
		NSString *path = [view dragPathAt:NSMakePoint(luaL_checknumber(L, 3), luaL_checknumber(L, 4))];
		if (path) lua_pushstring(L, path.UTF8String); else lua_pushnil(L);
		return 1;
	}
	if (strcmp(kind, "key") == 0) {
		lua_State *state = lua_reg_live_state(view.keyReg);
		if (!state || !lua_reg_push(view.keyReg)) { lua_pushboolean(L, 0); return 1; }
		push_objc(state, view, "nsview");
		lua_pushstring(state, luaL_checkstring(L, 3));
		BOOL handled = lua_objc_pcall(state, 2, 1, "pointer key test") == LUA_OK && lua_toboolean(state, -1);
		lua_pop(state, 1);
		lua_pushboolean(L, handled);
		return 1;
	}
	BOOL inside = !lua_isnoneornil(L, 3);
	NSPoint point = inside ? NSMakePoint(luaL_checknumber(L, 3), luaL_checknumber(L, 4)) : NSZeroPoint;
	BOOL click = strcmp(kind, "click") == 0;
	[view send:click ? view.clickReg : view.hoverReg point:point inside:inside
		count:click ? luaL_optinteger(L, 5, 1) : 0 context:"pointer test"];
	return 0;
}

#pragma mark - Treemap view

/* Draws cells computed by a Lua layout function whenever its size changes.
 * The squarified layout lives in lua/ui/treemap.lua so it is shared and unit
 * tested; this view only paints: muted semantic colors that lighten with
 * depth, a hairline gap, diagonal hatching for reclaimable cells, and an
 * accent outline for the highlighted or selected cell. */
@interface LuaTreemapView : LuaPointerView
@property (nonatomic, strong) LuaReg *layoutReg;
@property (nonatomic, copy) NSArray<NSDictionary *> *cells;
@property (nonatomic, copy) NSString *highlightedId;
@property (nonatomic, copy) NSString *selectedId;
@end

@implementation LuaTreemapView
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) { _cells = @[]; self.wantsLayer = YES; }
	return self;
}
- (void)setFrameSize:(NSSize)size {
	BOOL changed = !NSEqualSizes(size, self.frame.size);
	[super setFrameSize:size];
	if (changed) [self relayoutCells];
}
- (void)relayoutCells {
	NSSize size = self.bounds.size;
	lua_State *L = lua_reg_live_state(self.layoutReg);
	if (size.width <= 0 || size.height <= 0 || !L || !lua_reg_push(self.layoutReg)) {
		self.cells = @[];
		[self setNeedsDisplay:YES];
		return;
	}
	lua_pushnumber(L, size.width);
	lua_pushnumber(L, size.height);
	if (lua_objc_pcall(L, 2, 1, "treemap layout") != LUA_OK) return;
	id value = lua_to_objc_value(L, -1);
	lua_pop(L, 1);
	self.cells = [value isKindOfClass:NSArray.class] ? value : @[];
	[self setNeedsDisplay:YES];
}
- (void)setHighlightedId:(NSString *)value { _highlightedId = [value copy]; [self setNeedsDisplay:YES]; }
- (void)setSelectedId:(NSString *)value { _selectedId = [value copy]; [self setNeedsDisplay:YES]; }
- (void)viewDidChangeEffectiveAppearance {
	[super viewDidChangeEffectiveAppearance];
	[self setNeedsDisplay:YES];
}
static CGFloat treemap_number(NSDictionary *cell, NSString *key) {
	id value = cell[key];
	return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
}
- (void)drawRect:(NSRect)dirty {
	NSDictionary *nameAttributes = @{
		NSFontAttributeName: [NSFont systemFontOfSize:kTreemapLabelFontSize weight:NSFontWeightSemibold],
		NSForegroundColorAttributeName: NSColor.labelColor};
	NSDictionary *detailAttributes = @{
		NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:kTreemapLabelFontSize weight:NSFontWeightRegular],
		NSForegroundColorAttributeName: NSColor.secondaryLabelColor};
	for (NSDictionary *cell in self.cells) {
		NSRect rect = NSMakeRect(treemap_number(cell, @"x"), treemap_number(cell, @"y"),
			treemap_number(cell, @"w"), treemap_number(cell, @"h"));
		rect = NSInsetRect(rect, kTreemapGap / 2, kTreemapGap / 2);
		if (rect.size.width <= 0 || rect.size.height <= 0 || !NSIntersectsRect(rect, dirty)) continue;
		NSString *colorName = [cell[@"color"] isKindOfClass:NSString.class] ? cell[@"color"] : @"systemGray";
		CGFloat depth = treemap_number(cell, @"depth");
		CGFloat alpha = MAX(kTreemapMinAlpha, kTreemapBaseAlpha - depth * kTreemapDepthFade);
		// Cells that do not match the typed filter recede.
		if ([cell[@"dimmed"] respondsToSelector:@selector(boolValue)] && [cell[@"dimmed"] boolValue]) alpha *= kTreemapDimmedAlpha;
		NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:rect
			xRadius:kTreemapCornerRadius yRadius:kTreemapCornerRadius];
		[[semantic_color(colorName) colorWithAlphaComponent:alpha] setFill];
		[shape fill];
		if ([cell[@"hatched"] respondsToSelector:@selector(boolValue)] && [cell[@"hatched"] boolValue]) {
			[NSGraphicsContext saveGraphicsState];
			[shape addClip];
			NSBezierPath *hatch = [NSBezierPath bezierPath];
			CGFloat span = rect.size.width + rect.size.height;
			for (CGFloat offset = 0; offset < span; offset += kTreemapHatchSpacing) {
				[hatch moveToPoint:NSMakePoint(NSMinX(rect) + offset, NSMinY(rect))];
				[hatch lineToPoint:NSMakePoint(NSMinX(rect) + offset - rect.size.height, NSMaxY(rect))];
			}
			hatch.lineWidth = kTreemapHatchWidth;
			[[NSColor.labelColor colorWithAlphaComponent:kTreemapHatchAlpha] setStroke];
			[hatch stroke];
			[NSGraphicsContext restoreGraphicsState];
		}
		NSString *identifier = [cell[@"id"] description];
		if ((self.selectedId && [identifier isEqualToString:self.selectedId])
			|| (self.highlightedId && [identifier isEqualToString:self.highlightedId])) {
			NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 1, 1)
				xRadius:kTreemapCornerRadius yRadius:kTreemapCornerRadius];
			outline.lineWidth = [identifier isEqualToString:self.selectedId] ? kTreemapSelectionWidth : 1;
			[NSColor.controlAccentColor setStroke];
			[outline stroke];
		}
		NSString *label = [cell[@"label"] isKindOfClass:NSString.class] ? cell[@"label"] : nil;
		if (label.length && rect.size.width >= kTreemapLabelMinWidth && rect.size.height >= kTreemapLabelMinHeight) {
			NSRect text = NSInsetRect(rect, kTreemapLabelInset, kTreemapLabelInset);
			NSStringDrawingOptions options = NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine;
			[label drawWithRect:NSMakeRect(NSMinX(text), NSMinY(text), text.size.width, kTreemapLabelLineHeight)
				options:options attributes:nameAttributes context:nil];
			NSString *detail = [cell[@"detail"] isKindOfClass:NSString.class] ? cell[@"detail"] : nil;
			if (detail.length && text.size.height >= 2 * kTreemapLabelLineHeight) {
				[detail drawWithRect:NSMakeRect(NSMinX(text), NSMinY(text) + kTreemapLabelLineHeight,
					text.size.width, kTreemapLabelLineHeight) options:options attributes:detailAttributes context:nil];
			}
		}
	}
}
@end

// _treemapRefresh(view): asks the layout function for cells again, after
// something it reads (a filter, a focus) changed.
static int bridge_treemap_refresh(lua_State *L) {
	LuaTreemapView *view = lua_objc_check_object(L, 1, [LuaTreemapView class], "treemap");
	[view relayoutCells];
	return 0;
}

// _treemap(layout, onClick, onHover, onDrag, onKey): layout(width, height)
// returns cells.
static int bridge_treemap(lua_State *L) {
	LuaTreemapView *view = [[LuaTreemapView alloc] initWithFrame:NSZeroRect];
	view.layoutReg = lua_reg_opt(L, 1);
	view.clickReg = lua_reg_opt(L, 2);
	view.hoverReg = lua_reg_opt(L, 3);
	view.dragReg = lua_reg_opt(L, 4);
	view.keyReg = lua_reg_opt(L, 5);
	push_objc(L, view, "nsview");
	return 1;
}

