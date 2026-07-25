#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

static char kAxisKey;
static char kFlexibleKey;
static char kTableSourceKey;
static char kCallbackKey;
static char kToolbarDelegateKey;
static char kColumnAlignmentKey;
static char kResizeObserverKey;
static char kPaddingKey;
static char kAlignmentKey;
static char kFixedWidthKey;
static char kFixedHeightKey;
static const CGFloat kStackSpacing = 8.0;
static lua_State *gL = NULL;

typedef struct {
	void *ptr;
} ObjCRef;

#pragma mark - LuaTableViewSource

@interface LuaTableViewSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSMutableArray *columns;
@property (nonatomic, weak) NSTableView *tableView;
- (void)updateTableFrame;
@end

@interface LuaTableCellView : NSTableCellView
@end

@implementation LuaTableCellView

- (void)layout {
	[super layout];
	NSTextField *text = self.textField;
	if (!text) return;
	CGFloat height = ceil(text.intrinsicContentSize.height);
	text.frame = NSMakeRect(
		6,
		floor((self.bounds.size.height - height) / 2),
		MAX(0, self.bounds.size.width - 12),
		height);
}

@end

@implementation LuaTableViewSource

- (instancetype)initWithTableView:(NSTableView *)tv columns:(NSArray *)cols {
	self = [super init];
	if (self) {
		_tableView = tv;
		_columns = [cols mutableCopy];
		_rows = [NSMutableArray array];
		tv.dataSource = self;
		tv.delegate = self;
	}
	return self;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return (NSInteger)_rows.count;
}

- (void)updateTableFrame {
	NSClipView *clipView = (NSClipView *)_tableView.superview;
	if (![clipView isKindOfClass:[NSClipView class]]) return;

	CGFloat headerHeight = _tableView.headerView
		? _tableView.headerView.frame.size.height : 0;
	CGFloat rowsHeight = _rows.count * _tableView.rowHeight + headerHeight;
	NSSize viewport = clipView.bounds.size;
	_tableView.frame = NSMakeRect(
		0, 0, viewport.width, MAX(viewport.height, rowsHeight));
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)column
				  row:(NSInteger)row
{
	NSDictionary *rowData = _rows[row];
	NSString *colId = column.identifier;
	id value = rowData[colId];
	NSString *text = value ? [value description] : @"";

	NSString *reuseId = [@"cell-" stringByAppendingString:column.identifier];
	NSTableCellView *cell = [tableView makeViewWithIdentifier:reuseId owner:self];
	if (!cell) {
		cell = [[LuaTableCellView alloc] initWithFrame:
			NSMakeRect(0, 0, column.width, tableView.rowHeight)];
		cell.identifier = reuseId;

		NSTextField *tf = [NSTextField labelWithString:@""];
		tf.bezeled = NO;
		tf.drawsBackground = NO;
		tf.editable = NO;
		tf.selectable = NO;
		tf.lineBreakMode = NSLineBreakByTruncatingTail;

		[cell addSubview:tf];
		cell.textField = tf;
	}
	cell.textField.stringValue = text;
	NSNumber *alignment = objc_getAssociatedObject(column, &kColumnAlignmentKey);
	cell.textField.alignment = alignment
		? (NSTextAlignment)alignment.integerValue : NSTextAlignmentLeft;
	[cell setNeedsLayout:YES];
	return cell;
}

- (void)addRow:(NSDictionary *)row {
	[_rows addObject:row];
	NSInteger idx = (NSInteger)_rows.count - 1;
	[_tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:idx]
					  withAnimation:NSTableViewAnimationSlideDown];
	[self updateTableFrame];
}

- (void)removeRowAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_rows.count) return;
	[_rows removeObjectAtIndex:(NSUInteger)index];
	[_tableView removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:index]
					  withAnimation:NSTableViewAnimationSlideUp];
	[self updateTableFrame];
}

- (void)clearRows {
	[_rows removeAllObjects];
	[_tableView reloadData];
	[self updateTableFrame];
}

@end

#pragma mark - LuaButtonTarget

@interface LuaButtonTarget : NSObject
+ (instancetype)shared;
@end

@implementation LuaButtonTarget

+ (instancetype)shared {
	static LuaButtonTarget *instance = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ instance = [[self alloc] init]; });
	return instance;
}

- (void)onAction:(id)sender {
	id refObj = objc_getAssociatedObject(sender, &kCallbackKey);
	if (!refObj || !gL) return;
	int ref = [refObj intValue];

	lua_rawgeti(gL, LUA_REGISTRYINDEX, ref);
	int status = lua_pcall(gL, 0, 0, 0);
	if (status != LUA_OK) {
		fprintf(stderr, "button error: %s\n", lua_tostring(gL, -1));
		lua_pop(gL, 1);
	}
}

@end

#pragma mark - LuaToolbarDelegate

@interface LuaToolbarDelegate : NSObject <NSToolbarDelegate>
@property (nonatomic, strong) NSArray *items;
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
	for (NSDictionary *item in _items) {
		[ids addObject:item[@"id"]];
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
	for (NSDictionary *item in _items) {
		if ([item[@"id"] isEqualToString:identifier]) {
			NSToolbarItem *ti = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
			ti.label = item[@"label"] ?: identifier;
			ti.paletteLabel = ti.label;
			ti.toolTip = item[@"tooltip"];
			ti.autovalidates = NO;
			ti.enabled = YES;

			if (item[@"icon"]) {
				NSImage *img = [NSImage imageWithSystemSymbolName:item[@"icon"]
										accessibilityDescription:ti.label];
				if (img) {
					ti.image = img;
				}
			}

			NSNumber *refNum = item[@"actionRef"];
			if (refNum) {
				objc_setAssociatedObject(ti, &kCallbackKey, refNum,
					OBJC_ASSOCIATION_RETAIN);
				ti.target = [LuaButtonTarget shared];
				ti.action = @selector(onAction:);
			}

			return ti;
		}
	}
	return nil;
}

@end

#pragma mark - Lua helpers

static int bridge_tableview_add(lua_State *L);
static int bridge_tableview_remove(lua_State *L);
static int bridge_tableview_clear(lua_State *L);
static int bridge_set_text(lua_State *L);
static void layout_recursive(NSView *view, CGFloat width);

static void push_objc(lua_State *L, id obj, const char *meta) {
	ObjCRef *ref = lua_newuserdata(L, sizeof(ObjCRef));
	ref->ptr = (void *)CFBridgingRetain(obj);
	luaL_setmetatable(L, meta);
}

static id check_objc(lua_State *L, int idx) {
	ObjCRef *ref = luaL_testudata(L, idx, "nsview");
	if (ref) return (__bridge id)ref->ptr;
	ref = luaL_testudata(L, idx, "nswindow");
	if (ref) return (__bridge id)ref->ptr;
	luaL_typeerror(L, idx, "nsview or nswindow");
	return nil;
}

static NSView *check_view(lua_State *L, int idx) {
	id obj = check_objc(L, idx);
	if ([obj isKindOfClass:[NSWindow class]]) {
		return [(NSWindow *)obj contentView];
	}
	return (NSView *)obj;
}

static int gc_objc(lua_State *L) {
	ObjCRef *ref = lua_touserdata(L, 1);
	if (ref->ptr) {
		CFRelease(ref->ptr);
		ref->ptr = NULL;
	}
	return 0;
}

static void push_objc_value(lua_State *L, id value) {
	if (!value || value == [NSNull null]) {
		lua_pushnil(L);
	} else if ([value isKindOfClass:[NSString class]]) {
		lua_pushstring(L, [(NSString *)value UTF8String]);
	} else if ([value isKindOfClass:[NSNumber class]]) {
		NSNumber *num = (NSNumber *)value;
		NSString *typeStr = [NSString stringWithUTF8String:num.objCType];
		if ([typeStr isEqualToString:@"c"] || [typeStr isEqualToString:@"B"]) {
			lua_pushboolean(L, num.boolValue);
		} else {
			lua_pushnumber(L, num.doubleValue);
		}
	} else if ([value isKindOfClass:[NSView class]]) {
		push_objc(L, value, "nsview");
	} else if ([value isKindOfClass:[NSWindow class]]) {
		push_objc(L, value, "nswindow");
	} else if ([value isKindOfClass:[NSObject class]]) {
		push_objc(L, value, "nsobject");
	} else {
		lua_pushstring(L, [[value description] UTF8String]);
	}
}

static id lua_to_objc_value(lua_State *L, int idx) {
	ObjCRef *ref = luaL_testudata(L, idx, "nsview");
	if (!ref) ref = luaL_testudata(L, idx, "nswindow");
	if (!ref) ref = luaL_testudata(L, idx, "nsobject");
	if (ref) return (__bridge id)ref->ptr;

	switch (lua_type(L, idx)) {
		case LUA_TNIL:
			return nil;
		case LUA_TBOOLEAN:
			return @(lua_toboolean(L, idx));
		case LUA_TNUMBER: {
			double d = lua_tonumber(L, idx);
			if (d == floor(d) && d <= (double)NSIntegerMax && d >= (double)NSIntegerMin)
				return @((NSInteger)d);
			return @(d);
		}
		case LUA_TSTRING:
			return [NSString stringWithUTF8String:lua_tostring(L, idx)];
		default:
			return nil;
	}
}

static int nsview_index(lua_State *L) {
	id obj = (__bridge id)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	const char *key = lua_tostring(L, 2);
	if (!key) { lua_pushnil(L); return 1; }

	if (strcmp(key, "padding") == 0) {
		NSNumber *p = objc_getAssociatedObject(obj, &kPaddingKey);
		lua_pushnumber(L, p ? p.doubleValue : 0);
		return 1;
	}
	if (strcmp(key, "alignment") == 0) {
		NSString *a = objc_getAssociatedObject(obj, &kAlignmentKey);
		lua_pushstring(L, a ? a.UTF8String : "center");
		return 1;
	}
	if (strcmp(key, "fixed_width") == 0) {
		NSNumber *w = objc_getAssociatedObject(obj, &kFixedWidthKey);
		lua_pushnumber(L, w ? w.doubleValue : 0);
		return 1;
	}
	if (strcmp(key, "fixed_height") == 0) {
		NSNumber *h = objc_getAssociatedObject(obj, &kFixedHeightKey);
		lua_pushnumber(L, h ? h.doubleValue : 0);
		return 1;
	}

	if (strcmp(key, "set_text") == 0 && [obj isKindOfClass:[NSTextField class]]) {
		lua_pushcfunction(L, bridge_set_text);
		return 1;
	}

	NSString *kvcKey = [NSString stringWithUTF8String:key];
	@try {
		id value = [obj valueForKey:kvcKey];
		push_objc_value(L, value);
		return 1;
	} @catch (NSException *e) {
	}

	id src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (src) {
		if (strcmp(key, "add_row") == 0) {
			lua_pushcfunction(L, bridge_tableview_add);
			return 1;
		}
		if (strcmp(key, "remove_row") == 0) {
			lua_pushcfunction(L, bridge_tableview_remove);
			return 1;
		}
		if (strcmp(key, "clear_rows") == 0) {
			lua_pushcfunction(L, bridge_tableview_clear);
			return 1;
		}
		if (strcmp(key, "row_count") == 0) {
			lua_pushinteger(L, (lua_Integer)((LuaTableViewSource *)src).rows.count);
			return 1;
		}
	}

	lua_pushnil(L);
	return 1;
}

static int nsview_newindex(lua_State *L) {
	id obj = (__bridge id)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	const char *key = lua_tostring(L, 2);
	if (!key) return luaL_error(L, "invalid property name");

	if (strcmp(key, "padding") == 0) {
		double val = luaL_checknumber(L, 3);
		objc_setAssociatedObject(obj, &kPaddingKey, @(val), OBJC_ASSOCIATION_RETAIN);
		return 0;
	}
	if (strcmp(key, "alignment") == 0) {
		const char *val = luaL_checkstring(L, 3);
		objc_setAssociatedObject(obj, &kAlignmentKey,
			[NSString stringWithUTF8String:val], OBJC_ASSOCIATION_RETAIN);
		return 0;
	}
	if (strcmp(key, "fixed_width") == 0) {
		double val = luaL_checknumber(L, 3);
		objc_setAssociatedObject(obj, &kFixedWidthKey, @(val), OBJC_ASSOCIATION_RETAIN);
		return 0;
	}
	if (strcmp(key, "fixed_height") == 0) {
		double val = luaL_checknumber(L, 3);
		objc_setAssociatedObject(obj, &kFixedHeightKey, @(val), OBJC_ASSOCIATION_RETAIN);
		return 0;
	}

	NSString *kvcKey = [NSString stringWithUTF8String:key];
	id value = lua_to_objc_value(L, 3);

	@try {
		[obj setValue:value forKey:kvcKey];
	} @catch (NSException *e) {
		return luaL_error(L, "cannot set '%s': %s", key, e.description.UTF8String);
	}

	return 0;
}

#pragma mark - Bridge functions

static int bridge_window(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);
	int transparent_titlebar = lua_toboolean(L, 4);
	int hide_title = lua_toboolean(L, 5);

	NSRect frame = NSMakeRect(0, 0, width, height);
	NSUInteger style = NSWindowStyleMaskTitled
					 | NSWindowStyleMaskClosable
					 | NSWindowStyleMaskMiniaturizable
					 | NSWindowStyleMaskResizable;

	if (transparent_titlebar) {
		style |= NSWindowStyleMaskFullSizeContentView;
	}

	NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
											   styleMask:style
												 backing:NSBackingStoreBuffered
												   defer:NO];
	w.title = [NSString stringWithUTF8String:title];
	w.releasedWhenClosed = NO;

	if (transparent_titlebar) {
		w.titlebarAppearsTransparent = YES;
		if (hide_title) {
			w.titleVisibility = NSWindowTitleHidden;
		}
		w.movableByWindowBackground = YES;
	}

	[w center];

	[[NSNotificationCenter defaultCenter]
		addObserverForName:NSWindowWillCloseNotification
					object:w
					 queue:nil
				usingBlock:^(NSNotification *note) {
					[NSApp terminate:nil];
				}];

	if (!lua_isnoneornil(L, 6)) {
		luaL_checktype(L, 6, LUA_TTABLE);
		int n = (int)luaL_len(L, 6);
		NSMutableArray *items = [NSMutableArray array];
		for (int i = 1; i <= n; i++) {
			lua_rawgeti(L, 6, i);
			lua_getfield(L, -1, "id");
			lua_getfield(L, -2, "label");
			lua_getfield(L, -3, "icon");
			const char *iid = lua_tostring(L, -3);
			const char *ilabel = lua_tostring(L, -2);
			const char *iicon = lua_tostring(L, -1);

			NSMutableDictionary *dict = [NSMutableDictionary dictionary];
			if (iid) dict[@"id"] = [NSString stringWithUTF8String:iid];
			if (ilabel) dict[@"label"] = [NSString stringWithUTF8String:ilabel];
			if (iicon) dict[@"icon"] = [NSString stringWithUTF8String:iicon];

			lua_pop(L, 1);

			lua_getfield(L, -3, "tooltip");
			const char *tooltip = lua_tostring(L, -1);
			if (tooltip) {
				dict[@"tooltip"] = [NSString stringWithUTF8String:tooltip];
			}
			lua_pop(L, 1);

			lua_getfield(L, -3, "action");
			if (lua_isfunction(L, -1)) {
				lua_pushvalue(L, -1);
				int ref = luaL_ref(L, LUA_REGISTRYINDEX);
				dict[@"actionRef"] = @(ref);
			}
			lua_pop(L, 1);

			[items addObject:dict];
			lua_pop(L, 3);
		}

		LuaToolbarDelegate *del = [[LuaToolbarDelegate alloc] initWithItems:items];
		NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"main"];
		tb.displayMode = lua_toboolean(L, 7)
			? NSToolbarDisplayModeIconAndLabel : NSToolbarDisplayModeIconOnly;
		tb.delegate = del;
		w.toolbar = tb;
		objc_setAssociatedObject(w, &kToolbarDelegateKey, del,
			OBJC_ASSOCIATION_RETAIN);
	}

	push_objc(L, w, "nswindow");
	return 1;
}

static int bridge_vstack(lua_State *L) {
	NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(v, &kAxisKey, @"vstack", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "nsview");
	return 1;
}

static int bridge_hstack(lua_State *L) {
	NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(v, &kAxisKey, @"hstack", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "nsview");
	return 1;
}

static int bridge_hsplit(lua_State *L) {
	NSSplitView *v = [[NSSplitView alloc] initWithFrame:NSZeroRect];
	v.vertical = YES;
	v.dividerStyle = NSSplitViewDividerStyleThin;
	objc_setAssociatedObject(v, &kAxisKey, @"hsplit", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "nsview");
	return 1;
}

static int bridge_spacer(lua_State *L) {
	NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
	objc_setAssociatedObject(v, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "nsview");
	return 1;
}

#pragma mark - Text update

#pragma mark - Image

static int bridge_image(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	NSString *nsPath = [NSString stringWithUTF8String:path];

	NSImage *img = [[NSImage alloc] initWithContentsOfFile:nsPath];
	if (!img) {
		img = [NSImage imageNamed:nsPath];
	}
	if (!img) {
		return luaL_error(L, "failed to load image: %s", path);
	}

	NSSize size = img.size;
	if (size.width > 400) {
		CGFloat ratio = 400.0 / size.width;
		size.width = 400;
		size.height *= ratio;
	}

	NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
	iv.image = img;
	iv.imageScaling = NSImageScaleProportionallyUpOrDown;

	push_objc(L, iv, "nsview");
	return 1;
}

static int bridge_add(lua_State *L) {
	id parent = check_objc(L, 1);
	NSView *child = check_view(L, 2);

	NSView *container;
	if ([parent isKindOfClass:[NSWindow class]]) {
		NSWindow *window = (NSWindow *)parent;
		container = window.contentView;
		child.frame = container.bounds;
		child.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

		if (!objc_getAssociatedObject(window, &kResizeObserverKey)) {
			__weak NSView *weakChild = child;
			id observer = [[NSNotificationCenter defaultCenter]
				addObserverForName:NSWindowDidResizeNotification
							object:window
							 queue:nil
						usingBlock:^(NSNotification *note) {
							NSView *root = weakChild;
							if (!root) return;
							root.frame = ((NSWindow *)note.object).contentView.bounds;
							layout_recursive(root, root.bounds.size.width);
						}];
			objc_setAssociatedObject(window, &kResizeObserverKey, observer,
				OBJC_ASSOCIATION_RETAIN);
		}
	} else {
		container = (NSView *)parent;
	}

	[container addSubview:child];
	return 0;
}

static BOOL is_flexible(NSView *view) {
	return [objc_getAssociatedObject(view, &kFlexibleKey) boolValue];
}

static BOOL is_flexible_width(NSView *view) {
	return is_flexible(view);
}

static BOOL is_flexible_height(NSView *view) {
	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);
	if ([axis isEqualToString:@"hstack"]) return NO;
	return is_flexible(view);
}

static CGFloat view_padding(NSView *view) {
	NSNumber *p = objc_getAssociatedObject(view, &kPaddingKey);
	return p ? p.doubleValue : 0;
}

static NSString *view_alignment(NSView *view) {
	return objc_getAssociatedObject(view, &kAlignmentKey) ?: @"center";
}

static CGFloat view_fixed_width(NSView *view) {
	NSNumber *w = objc_getAssociatedObject(view, &kFixedWidthKey);
	return w ? w.doubleValue : 0;
}

static CGFloat view_fixed_height(NSView *view) {
	NSNumber *h = objc_getAssociatedObject(view, &kFixedHeightKey);
	return h ? h.doubleValue : 0;
}

static void size_to_fit_if_needed(NSView *view) {
	if (!is_flexible_width(view) && !is_flexible_height(view) &&
		[view respondsToSelector:@selector(sizeToFit)]) {
		[(id)view sizeToFit];
	}
}

static CGFloat preferred_height(NSView *view) {
	CGFloat fixed = view_fixed_height(view);
	if (fixed > 0) return fixed;

	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);
	if ([axis isEqualToString:@"hstack"]) {
		CGFloat maxHeight = 0;
		for (NSView *child in view.subviews) {
			size_to_fit_if_needed(child);
			CGFloat childHeight = preferred_height(child);
			if (childHeight > maxHeight) maxHeight = childHeight;
		}
		return maxHeight + 2 * view_padding(view);
	}

	size_to_fit_if_needed(view);
	return view.frame.size.height > 0 ? view.frame.size.height : 22;
}

static void layout_recursive(NSView *view, CGFloat width) {
	if (!view) return;

	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);
	CGFloat availableWidth = view.bounds.size.width > 0
		? view.bounds.size.width : width;
	CGFloat availableHeight = view.bounds.size.height;

	if ([axis isEqualToString:@"vstack"] || [axis isEqualToString:@"hstack"] ||
		[axis isEqualToString:@"hsplit"]) {

		CGFloat pad = view_padding(view);
		CGFloat contentW = availableWidth - 2 * pad;
		CGFloat contentH = availableHeight - 2 * pad;
		NSString *alignment = view_alignment(view);

		if ([axis isEqualToString:@"vstack"]) {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			CGFloat fixedHeight = 0;
			NSUInteger flexibleCount = 0;
			for (NSView *sv in view.subviews) {
				size_to_fit_if_needed(sv);
				CGFloat fh = view_fixed_height(sv);
				if (fh > 0) {
					fixedHeight += fh;
				} else if (is_flexible_height(sv)) {
					flexibleCount++;
				} else {
					fixedHeight += preferred_height(sv);
				}
			}

			CGFloat spacing = count > 1 ? (count - 1) * kStackSpacing : 0;
			CGFloat flexibleHeight = flexibleCount > 0
				? MAX(0, (contentH - fixedHeight - spacing) / flexibleCount)
				: 0;
			CGFloat top = pad + contentH;

			for (NSView *sv in view.subviews) {
				CGFloat fh = view_fixed_height(sv);
				CGFloat childH = fh > 0 ? fh
					: (is_flexible_height(sv) ? flexibleHeight : preferred_height(sv));
				CGFloat fw = view_fixed_width(sv);
				CGFloat childW = fw > 0 ? fw
					: (is_flexible_width(sv) ? contentW
						: MIN(sv.frame.size.width, contentW));
				top -= childH;
				CGFloat childX = pad;
				if ([alignment isEqualToString:@"center"]) {
					childX = pad + (contentW - childW) / 2;
				} else if ([alignment isEqualToString:@"trailing"]) {
					childX = pad + contentW - childW;
				}
				sv.frame = NSMakeRect(childX, top, childW, childH);
				layout_recursive(sv, childW);
				top -= kStackSpacing;
			}
		} else if ([axis isEqualToString:@"hstack"]) {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			CGFloat fixedWidth = 0;
			NSUInteger flexibleCount = 0;
			for (NSView *sv in view.subviews) {
				size_to_fit_if_needed(sv);
				CGFloat fw = view_fixed_width(sv);
				if (fw > 0) {
					fixedWidth += fw;
				} else if (is_flexible_width(sv)) {
					flexibleCount++;
				} else {
					fixedWidth += sv.frame.size.width > 0
						? sv.frame.size.width : 40;
				}
			}

			CGFloat spacing = count > 1 ? (count - 1) * kStackSpacing : 0;
			CGFloat flexibleWidth = flexibleCount > 0
				? MAX(0, (contentW - fixedWidth - spacing) / flexibleCount)
				: 0;
			CGFloat x = pad;

			for (NSView *sv in view.subviews) {
				CGFloat fw = view_fixed_width(sv);
				CGFloat childW = fw > 0 ? fw
					: (is_flexible_width(sv) ? flexibleWidth
						: (sv.frame.size.width > 0 ? sv.frame.size.width : 40));
				CGFloat fh = view_fixed_height(sv);
				CGFloat childH = fh > 0 ? fh
					: (is_flexible_height(sv) ? contentH
						: MIN(preferred_height(sv), contentH));
				CGFloat childY = pad;
				if ([alignment isEqualToString:@"center"]) {
					childY = pad + (contentH - childH) / 2;
				} else if ([alignment isEqualToString:@"bottom"]) {
					childY = pad + contentH - childH;
				}
				sv.frame = NSMakeRect(x, childY, childW, childH);
				layout_recursive(sv, childW);
				x += childW + kStackSpacing;
			}
		} else if ([axis isEqualToString:@"hsplit"]) {
			CGFloat n = (CGFloat)view.subviews.count;
			if (n == 0) return;
			CGFloat divider = [(NSSplitView *)view dividerThickness];
			CGFloat childW = (contentW - (n - 1) * divider) / n;
			CGFloat x = pad;
			for (NSView *sv in view.subviews) {
				sv.frame = NSMakeRect(x, pad, childW, contentH);
				layout_recursive(sv, childW);
				x += childW + divider;
			}
		}
	} else {
		if ([view isKindOfClass:[NSScrollView class]]) {
			LuaTableViewSource *source =
				objc_getAssociatedObject(view, &kTableSourceKey);
			[source updateTableFrame];
		}
		for (NSView *sv in view.subviews) {
			if (objc_getAssociatedObject(sv, &kAxisKey)) {
				layout_recursive(sv, width);
			}
		}
	}
}

static int bridge_layout(lua_State *L) {
	id obj = check_objc(L, 1);
	CGFloat width = luaL_optnumber(L, 2, 400);

	NSView *view;
	if ([obj isKindOfClass:[NSWindow class]]) {
		view = [(NSWindow *)obj contentView];
	} else {
		view = (NSView *)obj;
	}

	layout_recursive(view, width);
	return 0;
}

static int bridge_set_content_size(lua_State *L) {
	id obj = check_objc(L, 1);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);

	if ([obj isKindOfClass:[NSWindow class]]) {
		NSWindow *w = (NSWindow *)obj;
		NSRect frame = w.frame;
		NSRect contentRect = [w contentRectForFrameRect:frame];
		contentRect.size = NSMakeSize(width, height);
		NSRect newFrame = [w frameRectForContentRect:contentRect];
		[w setFrame:newFrame display:YES animate:NO];
	} else {
		NSView *v = (NSView *)obj;
		v.frame = NSMakeRect(v.frame.origin.x, v.frame.origin.y, width, height);
	}
	return 0;
}

#pragma mark - Text update

static int bridge_set_text(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *str = luaL_checkstring(L, 2);
	if ([obj isKindOfClass:[NSTextField class]]) {
		NSTextField *textField = (NSTextField *)obj;
		[textField setStringValue:[NSString stringWithUTF8String:str]];
		[textField sizeToFit];

		NSView *layoutRoot = nil;
		for (NSView *ancestor = textField.superview;
			 ancestor != nil; ancestor = ancestor.superview) {
			if (objc_getAssociatedObject(ancestor, &kAxisKey)) {
				layoutRoot = ancestor;
			}
		}
		if (layoutRoot) {
			layout_recursive(layoutRoot, layoutRoot.bounds.size.width);
		}
	}
	return 0;
}

#pragma mark - Button, toggle, separator

static int bridge_button(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	int has_action = !lua_isnoneornil(L, 2);
	int ref = LUA_NOREF;
	if (has_action) {
		luaL_checktype(L, 2, LUA_TFUNCTION);
		lua_pushvalue(L, 2);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
	btn.title = [NSString stringWithUTF8String:title];
	btn.bezelStyle = NSBezelStyleRounded;
	[btn sizeToFit];

	if (has_action) {
		objc_setAssociatedObject(btn, &kCallbackKey, @(ref),
			OBJC_ASSOCIATION_RETAIN);
		btn.target = [LuaButtonTarget shared];
		btn.action = @selector(onAction:);
	}

	push_objc(L, btn, "nsview");
	return 1;
}

static int bridge_toggle(lua_State *L) {
	const char *label = luaL_checkstring(L, 1);
	int is_on = lua_toboolean(L, 2);
	int has_action = !lua_isnoneornil(L, 3);
	int ref = LUA_NOREF;
	if (has_action) {
		luaL_checktype(L, 3, LUA_TFUNCTION);
		lua_pushvalue(L, 3);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	NSButton *btn = [NSButton checkboxWithTitle:[NSString stringWithUTF8String:label]
										 target:nil action:nil];
	btn.state = is_on ? NSControlStateValueOn : NSControlStateValueOff;
	[btn sizeToFit];

	if (has_action) {
		objc_setAssociatedObject(btn, &kCallbackKey, @(ref),
			OBJC_ASSOCIATION_RETAIN);
		btn.target = [LuaButtonTarget shared];
		btn.action = @selector(onAction:);
	}

	push_objc(L, btn, "nsview");
	return 1;
}

#pragma mark - Timer & spinner

static NSMutableDictionary *lua_table_to_dict(lua_State *L, int idx) {
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	lua_pushnil(L);
	while (lua_next(L, idx) != 0) {
		if (lua_type(L, -2) == LUA_TSTRING) {
			const char *key = lua_tostring(L, -2);
			const char *val = lua_tostring(L, -1);
			if (key) {
				dict[[NSString stringWithUTF8String:key]] =
					[NSString stringWithUTF8String:val ?: ""];
			}
		}
		lua_pop(L, 1);
	}
	return dict;
}

static int bridge_tableview(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);
	BOOL showsHeader = YES;
	BOOL bordered = NO;
	if (lua_istable(L, 4)) {
		lua_getfield(L, 4, "header");
		if (!lua_isnil(L, -1)) showsHeader = lua_toboolean(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, 4, "bordered");
		if (!lua_isnil(L, -1)) bordered = lua_toboolean(L, -1);
		lua_pop(L, 1);
	}

	int ncols = (int)luaL_len(L, 1);

	NSTableView *tv = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	tv.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;
	tv.headerView = showsHeader ? [[NSTableHeaderView alloc] init] : nil;
	tv.usesAlternatingRowBackgroundColors = YES;

	CGFloat colW = ncols > 0 ? width / ncols : width;
	NSMutableArray *colSpecs = [NSMutableArray array];

	for (int i = 1; i <= ncols; i++) {
		lua_rawgeti(L, 1, i);
		lua_getfield(L, -1, "id");
		lua_getfield(L, -2, "title");
		lua_getfield(L, -3, "alignment");
		lua_getfield(L, -4, "width");
		const char *colId = lua_tostring(L, -4);
		const char *colTitle = lua_tostring(L, -3);
		const char *colAlignment = lua_tostring(L, -2);
		CGFloat requestedWidth = lua_isnumber(L, -1)
			? lua_tonumber(L, -1) : colW;

		if (!colId) {
			lua_pop(L, 5);
			continue;
		}

		NSString *nsId = [NSString stringWithUTF8String:colId];
		NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:nsId];
		col.title = [NSString stringWithUTF8String:colTitle ?: colId];
		col.width = requestedWidth;
		col.minWidth = 40;
		NSTextAlignment alignment = NSTextAlignmentLeft;
		if (colAlignment && strcmp(colAlignment, "trailing") == 0) {
			alignment = NSTextAlignmentRight;
		} else if (colAlignment && strcmp(colAlignment, "center") == 0) {
			alignment = NSTextAlignmentCenter;
		}
		col.headerCell.alignment = NSTextAlignmentLeft;
		objc_setAssociatedObject(col, &kColumnAlignmentKey, @(alignment),
			OBJC_ASSOCIATION_RETAIN);
		[tv addTableColumn:col];

		[colSpecs addObject:@{@"id": nsId, @"title": col.title}];

		lua_pop(L, 5);
	}
	tv.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;

	LuaTableViewSource *src = [[LuaTableViewSource alloc] initWithTableView:tv
																   columns:colSpecs];

	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	sv.documentView = tv;
	sv.hasVerticalScroller = YES;
	sv.autohidesScrollers = YES;
	sv.borderType = bordered ? NSBezelBorder : NSNoBorder;
	objc_setAssociatedObject(sv, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);

	objc_setAssociatedObject(sv, &kTableSourceKey, src, OBJC_ASSOCIATION_RETAIN);

	push_objc(L, sv, "nsview");
	return 1;
}

static int bridge_toolbar_item(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *identifier = luaL_checkstring(L, 2);
	if (![obj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "ToolbarItem requires a window");
	}

	NSString *wanted = [NSString stringWithUTF8String:identifier];
	for (NSToolbarItem *item in ((NSWindow *)obj).toolbar.items) {
		if ([item.itemIdentifier isEqualToString:wanted]) {
			push_objc(L, item, "nsobject");
			return 1;
		}
	}

	lua_pushnil(L);
	return 1;
}

static int bridge_tableview_add(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (!src) return luaL_error(L, "not a table view");

	luaL_checktype(L, 2, LUA_TTABLE);
	NSMutableDictionary *row = lua_table_to_dict(L, 2);
	[src addRow:row];
	return 0;
}

static int bridge_tableview_remove(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (!src) return luaL_error(L, "not a table view");

	int idx = (int)luaL_checkinteger(L, 2);
	[src removeRowAtIndex:(NSInteger)idx];
	return 0;
}

static int bridge_tableview_clear(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (!src) return luaL_error(L, "not a table view");

	[src clearRows];
	return 0;
}

#pragma mark - Env & show

static int ui_env_index(lua_State *L) {
	lua_getfield(L, LUA_REGISTRYINDEX, "ui_module");
	lua_pushvalue(L, 2);
	lua_gettable(L, -2);
	if (!lua_isnil(L, -1)) return 1;
	lua_pop(L, 2);

	lua_getglobal(L, lua_tostring(L, 2));
	return 1;
}

static int bridge_show(lua_State *L) {
	NSWindow *w = (__bridge NSWindow *)((ObjCRef *)lua_touserdata(L, 1))->ptr;

	[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
	[NSApp activateIgnoringOtherApps:YES];
	[w makeKeyAndOrderFront:nil];

	return 0;
}

#pragma mark - Timer & spinner

static int bridge_timer_after(lua_State *L) {
	double delay = luaL_checknumber(L, 1);
	luaL_checktype(L, 2, LUA_TFUNCTION);
	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);

	lua_getfield(L, LUA_REGISTRYINDEX, "bridge_main");
	lua_State *mainL = (lua_State *)lua_touserdata(L, -1);
	lua_pop(L, 1);

	[NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(NSTimer *t) {
		lua_rawgeti(mainL, LUA_REGISTRYINDEX, ref);
		if (lua_pcall(mainL, 0, 0, 0) != LUA_OK) {
			fprintf(stderr, "timer error: %s\n", lua_tostring(mainL, -1));
			lua_pop(mainL, 1);
		}
		luaL_unref(mainL, LUA_REGISTRYINDEX, ref);
	}];

	return 0;
}

#pragma mark - Generic bridge (_create, _font, _perform, _callback)

static int bridge_create(lua_State *L) {
	const char *className = luaL_checkstring(L, 1);
	Class cls = NSClassFromString([NSString stringWithUTF8String:className]);
	if (!cls) return luaL_error(L, "unknown class: %s", className);

	id obj = [[cls alloc] init];
	push_objc(L, obj, [obj isKindOfClass:[NSWindow class]] ? "nswindow" : "nsview");
	return 1;
}

static int bridge_font(lua_State *L) {
	CGFloat size = luaL_checknumber(L, 1);
	const char *weightStr = luaL_optstring(L, 2, NULL);

	NSFontWeight w = NSFontWeightRegular;
	if (weightStr) {
		if (strcmp(weightStr, "bold") == 0) w = NSFontWeightBold;
		else if (strcmp(weightStr, "semibold") == 0) w = NSFontWeightSemibold;
		else if (strcmp(weightStr, "light") == 0) w = NSFontWeightLight;
		else if (strcmp(weightStr, "heavy") == 0) w = NSFontWeightHeavy;
	}

	NSFont *font = [NSFont systemFontOfSize:size weight:w];
	push_objc(L, font, "nsobject");
	return 1;
}

static int bridge_perform(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *selName = luaL_checkstring(L, 2);
	SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
	if (![obj respondsToSelector:sel]) return 0;

	id arg = nil;
	if (!lua_isnoneornil(L, 3)) {
		arg = lua_to_objc_value(L, 3);
	}

	NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
	if (!sig) return 0;

	NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
	inv.target = obj;
	inv.selector = sel;
	if (sig.numberOfArguments > 2) {
		[inv setArgument:&arg atIndex:2];
	}
	[inv invoke];

	if (sig.methodReturnLength > 0) {
		const char *retType = sig.methodReturnType;
		if (strcmp(retType, @encode(BOOL)) == 0 || strcmp(retType, "B") == 0 || strcmp(retType, "c") == 0) {
			BOOL val = NO;
			[inv getReturnValue:&val];
			lua_pushboolean(L, val);
		} else if (strcmp(retType, @encode(NSInteger)) == 0 || strcmp(retType, "q") == 0) {
			NSInteger val = 0;
			[inv getReturnValue:&val];
			lua_pushinteger(L, (lua_Integer)val);
		} else if (strcmp(retType, @encode(CGFloat)) == 0 || strcmp(retType, "d") == 0) {
			CGFloat val = 0;
			[inv getReturnValue:&val];
			lua_pushnumber(L, val);
		} else if (strcmp(retType, "@") == 0) {
			__unsafe_unretained id val = nil;
			[inv getReturnValue:&val];
			push_objc_value(L, val);
		} else {
			lua_pushnil(L);
		}
		return 1;
	}
	return 0;
}

static int bridge_callback(lua_State *L) {
	id obj = check_objc(L, 1);
	luaL_checktype(L, 2, LUA_TFUNCTION);
	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);

	objc_setAssociatedObject(obj, &kCallbackKey, @(ref), OBJC_ASSOCIATION_RETAIN);
	if ([obj respondsToSelector:@selector(setTarget:)]) {
		[obj setTarget:[LuaButtonTarget shared]];
	}
	if ([obj respondsToSelector:@selector(setAction:)]) {
		[obj setAction:@selector(onAction:)];
	}

	return 0;
}

#pragma mark - Module registration

static const luaL_Reg bridge_lib[] = {
	{"_window",           bridge_window},
	{"_vstack",           bridge_vstack},
	{"_hstack",           bridge_hstack},
	{"_hsplit",           bridge_hsplit},
	{"_spacer",           bridge_spacer},
	{"_image",            bridge_image},
	{"_add",              bridge_add},
	{"_layout",           bridge_layout},
	{"_set_content_size", bridge_set_content_size},
	{"_tableview",        bridge_tableview},
	{"_toolbar_item",     bridge_toolbar_item},
	{"_button",           bridge_button},
	{"_toggle",           bridge_toggle},
	{"_timer_after",      bridge_timer_after},
	{"_show",             bridge_show},
	{"_create",           bridge_create},
	{"_font",             bridge_font},
	{"_perform",          bridge_perform},
	{"_callback",         bridge_callback},
	{NULL, NULL},
};

static void register_metatable(lua_State *L, const char *name) {
	luaL_newmetatable(L, name);
	lua_pushcfunction(L, gc_objc);
	lua_setfield(L, -2, "__gc");
	lua_pushcfunction(L, nsview_index);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, nsview_newindex);
	lua_setfield(L, -2, "__newindex");
	lua_pop(L, 1);
}

int luaopen_bridge(lua_State *L) {
	register_metatable(L, "nsview");
	register_metatable(L, "nswindow");
	register_metatable(L, "nsobject");
	luaL_newlib(L, bridge_lib);
	return 1;
}

#pragma mark - Main

int main(int argc, char *argv[]) {
	[NSApplication sharedApplication];

	lua_State *L = luaL_newstate();
	gL = L;
	luaL_openlibs(L);

	lua_pushlightuserdata(L, L);
	lua_setfield(L, LUA_REGISTRYINDEX, "bridge_main");

	luaL_requiref(L, "bridge", luaopen_bridge, 1);
	lua_pop(L, 1);

	char cwd[4096];
	if (getcwd(cwd, sizeof(cwd))) {
		lua_getglobal(L, "package");
		lua_getfield(L, -1, "path");
		const char *defpath = lua_tostring(L, -1);
		char newpath[8192];
		snprintf(newpath, sizeof(newpath), "%s;%s/?.lua;%s/lua/?.lua", defpath, cwd, cwd);
		lua_pushstring(L, newpath);
		lua_setfield(L, -3, "path");
		lua_pop(L, 2);
	}

	lua_getglobal(L, "require");
	lua_pushstring(L, "luaui");
	if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
		fprintf(stderr, "error loading UI: %s\n", lua_tostring(L, -1));
		lua_close(L);
		return 1;
	}
	lua_setfield(L, LUA_REGISTRYINDEX, "ui_module");

	lua_newtable(L);
	lua_newtable(L);
	lua_pushcfunction(L, ui_env_index);
	lua_setfield(L, -2, "__index");
	lua_setmetatable(L, -2);

	const char *script = argc > 1 ? argv[1] : "examples/hello.lua";
	if (luaL_loadfile(L, script) != LUA_OK) {
		fprintf(stderr, "error: %s\n", lua_tostring(L, -1));
		lua_close(L);
		return 1;
	}

	lua_insert(L, -2);

	if (lua_setupvalue(L, -2, 1) == NULL) {
		lua_pop(L, 1);
		fprintf(stderr,
			"error: script has no _ENV upvalue (require Lua 5.2+)\n");
		lua_close(L);
		return 1;
	}

	if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
		fprintf(stderr, "error: %s\n", lua_tostring(L, -1));
		lua_close(L);
		return 1;
	}

	[NSApp run];

	lua_close(L);
	return 0;
}
