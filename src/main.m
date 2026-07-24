#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

static char kAxisKey;
static char kTableSourceKey;
static char kCallbackKey;
static const CGFloat kPadding = 12.0;
static lua_State *gL = NULL;

typedef struct {
	void *ptr;
} ObjCRef;

#pragma mark - LuaTableViewSource

@interface LuaTableViewSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSMutableArray *columns;
@property (nonatomic, weak) NSTableView *tableView;
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

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)column
				  row:(NSInteger)row
{
	NSDictionary *rowData = _rows[row];
	NSString *colId = column.identifier;
	id value = rowData[colId];
	NSString *text = value ? [value description] : @"";

	NSTextField *tf = [tableView makeViewWithIdentifier:@"cell" owner:self];
	if (!tf) {
		tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, column.width, 20)];
		tf.identifier = @"cell";
		tf.bezeled = NO;
		tf.drawsBackground = NO;
		tf.editable = NO;
		tf.selectable = NO;
	}
	tf.stringValue = text;
	return tf;
}

- (void)addRow:(NSDictionary *)row {
	[_rows addObject:row];
	NSInteger idx = (NSInteger)_rows.count - 1;
	[_tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:idx]
					  withAnimation:NSTableViewAnimationSlideDown];
}

- (void)removeRowAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_rows.count) return;
	[_rows removeObjectAtIndex:(NSUInteger)index];
	[_tableView removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:index]
					  withAnimation:NSTableViewAnimationSlideUp];
}

- (void)clearRows {
	[_rows removeAllObjects];
	[_tableView reloadData];
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

			NSNumber *refNum = item[@"actionRef"];
			if (refNum) {
				NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
				btn.title = ti.label;
				btn.bezelStyle = NSBezelStyleToolbar;
				[btn sizeToFit];
				ti.view = btn;

				objc_setAssociatedObject(btn, &kCallbackKey, refNum,
					OBJC_ASSOCIATION_RETAIN);
				btn.target = [LuaButtonTarget shared];
				btn.action = @selector(onAction:);
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
static int bridge_toggle_get_state(lua_State *L);
static int bridge_toggle_set_state(lua_State *L);

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

static int nsview_index(lua_State *L) {
	id obj = (__bridge id)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	const char *key = lua_tostring(L, 2);
	if (!key) { lua_pushnil(L); return 1; }

	if (strcmp(key, "set_text") == 0 && [obj isKindOfClass:[NSTextField class]]) {
		lua_pushcfunction(L, bridge_set_text);
		return 1;
	}
	if (strcmp(key, "get_state") == 0 && [obj isKindOfClass:[NSButton class]]) {
		lua_pushcfunction(L, bridge_toggle_get_state);
		return 1;
	}
	if (strcmp(key, "set_state") == 0 && [obj isKindOfClass:[NSButton class]]) {
		lua_pushcfunction(L, bridge_toggle_set_state);
		return 1;
	}

	id src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (!src) {
		lua_pushnil(L);
		return 1;
	}

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
	lua_pushnil(L);
	return 1;
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
			const char *iid = lua_tostring(L, -2);
			const char *ilabel = lua_tostring(L, -1);

			NSMutableDictionary *dict = [NSMutableDictionary dictionary];
			if (iid) dict[@"id"] = [NSString stringWithUTF8String:iid];
			if (ilabel) dict[@"label"] = [NSString stringWithUTF8String:ilabel];

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
		tb.displayMode = NSToolbarDisplayModeIconAndLabel;
		tb.delegate = del;
		w.toolbar = tb;
	}

	push_objc(L, w, "nswindow");
	return 1;
}

static int bridge_vstack(lua_State *L) {
	NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(v, &kAxisKey, @"vstack", OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "nsview");
	return 1;
}

static int bridge_hstack(lua_State *L) {
	NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(v, &kAxisKey, @"hstack", OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "nsview");
	return 1;
}

static int bridge_hsplit(lua_State *L) {
	NSSplitView *v = [[NSSplitView alloc] initWithFrame:NSZeroRect];
	v.vertical = YES;
	v.dividerStyle = NSSplitViewDividerStyleThin;
	objc_setAssociatedObject(v, &kAxisKey, @"hsplit", OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "nsview");
	return 1;
}

static int bridge_spacer(lua_State *L) {
	NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
	push_objc(L, v, "nsview");
	return 1;
}

static int bridge_text(lua_State *L) {
	const char *str = luaL_checkstring(L, 1);
	CGFloat fontSize = luaL_optnumber(L, 2, 0);
	const char *weightStr = luaL_optstring(L, 3, NULL);

	NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 22)];
	tf.stringValue = [NSString stringWithUTF8String:str];
	tf.bezeled = NO;
	tf.drawsBackground = NO;
	tf.editable = NO;
	tf.selectable = NO;

	if (fontSize > 0) {
		NSFontWeight w = NSFontWeightRegular;
		if (weightStr) {
			if (strcmp(weightStr, "bold") == 0) w = NSFontWeightBold;
			else if (strcmp(weightStr, "semibold") == 0) w = NSFontWeightSemibold;
			else if (strcmp(weightStr, "light") == 0) w = NSFontWeightLight;
			else if (strcmp(weightStr, "heavy") == 0) w = NSFontWeightHeavy;
		}
		tf.font = [NSFont systemFontOfSize:fontSize weight:w];
	}

	[tf sizeToFit];

	push_objc(L, tf, "nsview");
	return 1;
}

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
		container = [(NSWindow *)parent contentView];
	} else {
		container = (NSView *)parent;
	}

	[container addSubview:child];
	return 0;
}

static void layout_recursive(NSView *view, CGFloat width) {
	if (!view) return;

	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);

	if ([axis isEqualToString:@"vstack"]) {
		CGFloat y = kPadding;
		for (NSView *sv in view.subviews) {
			if ([sv respondsToSelector:@selector(sizeToFit)]) {
				[(id)sv sizeToFit];
			}
			NSRect f = sv.frame;
			CGFloat childW = f.size.width > 0 ? f.size.width : width - 2 * kPadding;
			CGFloat childH = f.size.height > 0 ? f.size.height : 22;
			sv.frame = NSMakeRect(kPadding, y, childW, childH);
			y += childH + kPadding;
			layout_recursive(sv, childW);
		}
		view.frame = NSMakeRect(0, 0, width, y);
	} else if ([axis isEqualToString:@"hstack"]) {
		CGFloat x = kPadding;
		CGFloat maxH = 0;
		for (NSView *sv in view.subviews) {
			if ([sv respondsToSelector:@selector(sizeToFit)]) {
				[(id)sv sizeToFit];
			}
			NSRect f = sv.frame;
			CGFloat childW = f.size.width > 0 ? f.size.width : 40;
			CGFloat childH = f.size.height > 0 ? f.size.height : 22;
			sv.frame = NSMakeRect(x, kPadding, childW, childH);
			if (childH > maxH) maxH = childH;
			x += childW + kPadding;
			layout_recursive(sv, childW);
		}
		view.frame = NSMakeRect(0, 0, x, maxH + 2 * kPadding);
	} else if ([axis isEqualToString:@"hsplit"]) {
		CGFloat n = (CGFloat)view.subviews.count;
		if (n == 0) return;
		CGFloat childW = (width - (n - 1) * kPadding) / n;
		CGFloat x = 0;
		for (NSView *sv in view.subviews) {
			sv.frame = NSMakeRect(x, 0, childW, view.frame.size.height);
			layout_recursive(sv, childW);
			x += childW + kPadding;
		}
	} else {
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

static int bridge_set_frame(lua_State *L) {
	NSView *view = check_view(L, 1);
	CGFloat x = luaL_checknumber(L, 2);
	CGFloat y = luaL_checknumber(L, 3);
	CGFloat w = luaL_checknumber(L, 4);
	CGFloat h = luaL_checknumber(L, 5);
	view.frame = NSMakeRect(x, y, w, h);
	return 0;
}

static int bridge_get_frame(lua_State *L) {
	NSView *view = check_view(L, 1);
	NSRect f = view.frame;
	lua_pushnumber(L, f.origin.x);
	lua_pushnumber(L, f.origin.y);
	lua_pushnumber(L, f.size.width);
	lua_pushnumber(L, f.size.height);
	return 4;
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
		[(NSTextField *)obj setStringValue:[NSString stringWithUTF8String:str]];
		[(NSTextField *)obj sizeToFit];
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

static int bridge_separator(lua_State *L) {
	NSBox *sep = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 200, 1)];
	sep.boxType = NSBoxSeparator;
	push_objc(L, sep, "nsview");
	return 1;
}

static int bridge_toggle_get_state(lua_State *L) {
	id obj = check_objc(L, 1);
	if ([obj isKindOfClass:[NSButton class]]) {
		lua_pushboolean(L, [(NSButton *)obj state] == NSControlStateValueOn);
		return 1;
	}
	lua_pushnil(L);
	return 1;
}

static int bridge_toggle_set_state(lua_State *L) {
	id obj = check_objc(L, 1);
	int is_on = lua_toboolean(L, 2);
	if ([obj isKindOfClass:[NSButton class]]) {
		[(NSButton *)obj setState:is_on ? NSControlStateValueOn : NSControlStateValueOff];
	}
	return 0;
}

#pragma mark - TableView bridge

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

	int ncols = (int)luaL_len(L, 1);

	NSTableView *tv = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	tv.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
	tv.headerView = [[NSTableHeaderView alloc] init];
	tv.usesAlternatingRowBackgroundColors = YES;

	CGFloat colW = ncols > 0 ? width / ncols : width;
	NSMutableArray *colSpecs = [NSMutableArray array];

	for (int i = 1; i <= ncols; i++) {
		lua_rawgeti(L, 1, i);
		lua_getfield(L, -1, "id");
		lua_getfield(L, -2, "title");
		const char *colId = lua_tostring(L, -2);
		const char *colTitle = lua_tostring(L, -1);

		if (!colId) {
			lua_pop(L, 3);
			continue;
		}

		NSString *nsId = [NSString stringWithUTF8String:colId];
		NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:nsId];
		col.title = [NSString stringWithUTF8String:colTitle ?: colId];
		col.width = colW;
		col.minWidth = 40;
		[tv addTableColumn:col];

		[colSpecs addObject:@{@"id": nsId, @"title": col.title}];

		lua_pop(L, 3);
	}

	LuaTableViewSource *src = [[LuaTableViewSource alloc] initWithTableView:tv
																   columns:colSpecs];

	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	sv.documentView = tv;
	sv.hasVerticalScroller = YES;
	sv.autohidesScrollers = YES;
	sv.borderType = NSBezelBorder;

	objc_setAssociatedObject(sv, &kTableSourceKey, src, OBJC_ASSOCIATION_RETAIN);

	push_objc(L, sv, "nsview");
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

static int bridge_spinner(lua_State *L) {
	NSProgressIndicator *p = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 22, 22)];
	p.style = NSProgressIndicatorStyleSpinning;
	p.displayedWhenStopped = NO;
	push_objc(L, p, "nsview");
	return 1;
}

static int bridge_spinner_start(lua_State *L) {
	NSView *view = check_view(L, 1);
	if ([view isKindOfClass:[NSProgressIndicator class]]) {
		[(NSProgressIndicator *)view startAnimation:nil];
	}
	return 0;
}

static int bridge_spinner_stop(lua_State *L) {
	NSView *view = check_view(L, 1);
	if ([view isKindOfClass:[NSProgressIndicator class]]) {
		[(NSProgressIndicator *)view stopAnimation:nil];
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
	{"_text",             bridge_text},
	{"_image",            bridge_image},
	{"_add",              bridge_add},
	{"_layout",           bridge_layout},
	{"_set_frame",        bridge_set_frame},
	{"_get_frame",        bridge_get_frame},
	{"_set_content_size", bridge_set_content_size},
	{"_tableview",        bridge_tableview},
	{"_button",           bridge_button},
	{"_toggle",           bridge_toggle},
	{"_separator",        bridge_separator},
	{"_toggle_get_state", bridge_toggle_get_state},
	{"_toggle_set_state", bridge_toggle_set_state},
	{"_timer_after",      bridge_timer_after},
	{"_spinner",          bridge_spinner},
	{"_spinner_start",    bridge_spinner_start},
	{"_spinner_stop",     bridge_spinner_stop},
	{"_show",             bridge_show},
	{NULL, NULL},
};

static void register_metatable(lua_State *L, const char *name) {
	luaL_newmetatable(L, name);
	lua_pushcfunction(L, gc_objc);
	lua_setfield(L, -2, "__gc");
	lua_pushcfunction(L, nsview_index);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);
}

int luaopen_bridge(lua_State *L) {
	register_metatable(L, "nsview");
	register_metatable(L, "nswindow");
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
