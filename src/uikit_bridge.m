#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

static char kAxisKey;
static char kFlexibleKey;
static char kTableSourceKey;
static char kCallbackKey;
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

/* Protected callbacks must remain non-fatal without hiding Lua failures. */
static void report_lua_error(lua_State *L, const char *context) {
	const char *message = lua_tostring(L, -1);
	if (message) {
		fprintf(stderr, "%s error: %s\n", context, message);
	} else {
		fprintf(stderr, "%s error: <%s>\n", context, luaL_typename(L, -1));
	}
	fflush(stderr);
}

#pragma mark - LuaTableViewSource (iOS UITableView)

@interface LuaTableViewSource : NSObject <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSMutableArray *columns;
@property (nonatomic, weak) UITableView *tableView;
@end

@implementation LuaTableViewSource

- (instancetype)initWithTableView:(UITableView *)tv columns:(NSArray *)cols {
	self = [super init];
	if (self) {
		_tableView = tv;
		_columns = [cols mutableCopy];
		_rows = [NSMutableArray array];
		tv.dataSource = self;
		tv.delegate = self;
		[tv registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
	}
	return self;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)_rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSDictionary *rowData = _rows[indexPath.row];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"
														   forIndexPath:indexPath];

	NSArray *keys = [_columns valueForKey:@"id"];
	NSMutableArray *values = [NSMutableArray array];
	for (NSString *key in keys) {
		id val = rowData[key];
		[values addObject:val ? [val description] : @""];
	}
	cell.textLabel.text = [values componentsJoinedByString:@"  "];
	return cell;
}

- (void)addRow:(NSDictionary *)row {
	[_rows addObject:row];
	NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)_rows.count - 1 inSection:0];
	[_tableView insertRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)removeRowAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_rows.count) return;
	[_rows removeObjectAtIndex:(NSUInteger)index];
	NSIndexPath *ip = [NSIndexPath indexPathForRow:index inSection:0];
	[_tableView deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
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
		report_lua_error(gL, "button");
		lua_pop(gL, 1);
	}
}

@end

#pragma mark - Lua helpers

static int bridge_tableview_add(lua_State *L);
static int bridge_tableview_remove(lua_State *L);
static int bridge_tableview_clear(lua_State *L);
static int bridge_set_text(lua_State *L);
static void layout_recursive(UIView *view, CGFloat width);

static void push_objc(lua_State *L, id obj, const char *meta) {
	ObjCRef *ref = lua_newuserdata(L, sizeof(ObjCRef));
	ref->ptr = (void *)CFBridgingRetain(obj);
	luaL_setmetatable(L, meta);
}

static id check_objc(lua_State *L, int idx) {
	ObjCRef *ref = luaL_testudata(L, idx, "uiview");
	if (ref) return (__bridge id)ref->ptr;
	ref = luaL_testudata(L, idx, "uiwindow");
	if (ref) return (__bridge id)ref->ptr;
	luaL_typeerror(L, idx, "uiview or uiwindow");
	return nil;
}

static UIView *check_view(lua_State *L, int idx) {
	id obj = check_objc(L, idx);
	return (UIView *)obj;
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
	} else if ([value isKindOfClass:[UIView class]]) {
		push_objc(L, value, "uiview");
	} else if ([value isKindOfClass:[UIWindow class]]) {
		push_objc(L, value, "uiwindow");
	} else if ([value isKindOfClass:[NSObject class]]) {
		push_objc(L, value, "nsobject");
	} else {
		lua_pushstring(L, [[value description] UTF8String]);
	}
}

static id lua_to_objc_value(lua_State *L, int idx) {
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

#pragma mark - Layout helpers

static BOOL is_flexible(UIView *view) {
	return [objc_getAssociatedObject(view, &kFlexibleKey) boolValue];
}

static CGFloat view_padding(UIView *view) {
	NSNumber *p = objc_getAssociatedObject(view, &kPaddingKey);
	return p ? p.doubleValue : 12.0;
}

static NSString *view_alignment(UIView *view) {
	return objc_getAssociatedObject(view, &kAlignmentKey) ?: @"center";
}

static CGFloat view_fixed_width(UIView *view) {
	NSNumber *w = objc_getAssociatedObject(view, &kFixedWidthKey);
	return w ? w.doubleValue : 0;
}

static CGFloat view_fixed_height(UIView *view) {
	NSNumber *h = objc_getAssociatedObject(view, &kFixedHeightKey);
	return h ? h.doubleValue : 0;
}

static void size_to_fit_if_needed(UIView *view) {
	if (!is_flexible(view)) {
		[view sizeToFit];
	}
}

static void layout_recursive(UIView *view, CGFloat width) {
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
			for (UIView *sv in view.subviews) {
				size_to_fit_if_needed(sv);
				CGFloat fh = view_fixed_height(sv);
				if (is_flexible(sv)) {
					flexibleCount++;
				} else if (fh > 0) {
					fixedHeight += fh;
				} else {
					fixedHeight += sv.frame.size.height > 0
						? sv.frame.size.height : 22;
				}
			}

			CGFloat spacing = count > 1 ? (count - 1) * kStackSpacing : 0;
			CGFloat flexibleHeight = flexibleCount > 0
				? MAX(0, (contentH - fixedHeight - spacing) / flexibleCount)
				: 0;
			CGFloat top = pad + contentH;

			for (UIView *sv in view.subviews) {
				CGFloat fh = view_fixed_height(sv);
				CGFloat childH = is_flexible(sv) ? flexibleHeight
					: (fh > 0 ? fh : (sv.frame.size.height > 0 ? sv.frame.size.height : 22));
				CGFloat fw = view_fixed_width(sv);
				CGFloat childW = is_flexible(sv) ? contentW
					: (fw > 0 ? fw : MIN(sv.frame.size.width, contentW));
				top -= childH;
				CGFloat childX = pad;
				if ([alignment isEqualToString:@"center"]) {
					childX = pad + (contentW - childW) / 2;
				} else if ([alignment isEqualToString:@"trailing"]) {
					childX = pad + contentW - childW;
				}
				sv.frame = CGRectMake(childX, top, childW, childH);
				layout_recursive(sv, childW);
				top -= kStackSpacing;
			}
		} else if ([axis isEqualToString:@"hstack"]) {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			CGFloat fixedWidth = 0;
			NSUInteger flexibleCount = 0;
			for (UIView *sv in view.subviews) {
				size_to_fit_if_needed(sv);
				CGFloat fw = view_fixed_width(sv);
				if (is_flexible(sv)) {
					flexibleCount++;
				} else if (fw > 0) {
					fixedWidth += fw;
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

			for (UIView *sv in view.subviews) {
				CGFloat fw = view_fixed_width(sv);
				CGFloat childW = is_flexible(sv) ? flexibleWidth
					: (fw > 0 ? fw : (sv.frame.size.width > 0 ? sv.frame.size.width : 40));
				CGFloat fh = view_fixed_height(sv);
				CGFloat childH = is_flexible(sv) ? contentH
					: (fh > 0 ? fh : MIN(sv.frame.size.height, contentH));
				CGFloat childY = pad;
				if ([alignment isEqualToString:@"center"]) {
					childY = pad + (contentH - childH) / 2;
				} else if ([alignment isEqualToString:@"bottom"]) {
					childY = pad + contentH - childH;
				}
				sv.frame = CGRectMake(x, childY, childW, childH);
				layout_recursive(sv, childW);
				x += childW + kStackSpacing;
			}
		} else if ([axis isEqualToString:@"hsplit"]) {
			CGFloat n = (CGFloat)view.subviews.count;
			if (n == 0) return;
			CGFloat childW = contentW / n;
			CGFloat x = pad;
			for (UIView *sv in view.subviews) {
				sv.frame = CGRectMake(x, pad, childW, contentH);
				layout_recursive(sv, childW);
				x += childW;
			}
		}
	} else {
		for (UIView *sv in view.subviews) {
			if (objc_getAssociatedObject(sv, &kAxisKey)) {
				layout_recursive(sv, width);
			}
		}
	}
}

#pragma mark - nsview metatable (UIKit uses "uiview")

static int nsview_index(lua_State *L) {
	id obj = (__bridge id)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	const char *key = lua_tostring(L, 2);
	if (!key) { lua_pushnil(L); return 1; }

	if (strcmp(key, "padding") == 0) {
		NSNumber *p = objc_getAssociatedObject(obj, &kPaddingKey);
		lua_pushnumber(L, p ? p.doubleValue : 12.0);
		return 1;
	}
	if (strcmp(key, "alignment") == 0) {
		NSString *a = objc_getAssociatedObject(obj, &kAlignmentKey);
		lua_pushstring(L, a ? a.UTF8String : "center");
		return 1;
	}
	if (strcmp(key, "fixedWidth") == 0) {
		NSNumber *w = objc_getAssociatedObject(obj, &kFixedWidthKey);
		lua_pushnumber(L, w ? w.doubleValue : 0);
		return 1;
	}
	if (strcmp(key, "fixedHeight") == 0) {
		NSNumber *h = objc_getAssociatedObject(obj, &kFixedHeightKey);
		lua_pushnumber(L, h ? h.doubleValue : 0);
		return 1;
	}

	if (strcmp(key, "setText") == 0 && [obj isKindOfClass:[UILabel class]]) {
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
		if (strcmp(key, "addRow") == 0) {
			lua_pushcfunction(L, bridge_tableview_add);
			return 1;
		}
		if (strcmp(key, "removeRow") == 0) {
			lua_pushcfunction(L, bridge_tableview_remove);
			return 1;
		}
		if (strcmp(key, "clearRows") == 0) {
			lua_pushcfunction(L, bridge_tableview_clear);
			return 1;
		}
		if (strcmp(key, "rowCount") == 0) {
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
	if (strcmp(key, "fixedWidth") == 0) {
		double val = luaL_checknumber(L, 3);
		objc_setAssociatedObject(obj, &kFixedWidthKey, @(val), OBJC_ASSOCIATION_RETAIN);
		return 0;
	}
	if (strcmp(key, "fixedHeight") == 0) {
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

#pragma mark - Bridge functions (UIKit)

static int bridge_window(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);

	CGRect frame = CGRectMake(0, 0, width, height);
	UIWindow *w = [[UIWindow alloc] initWithFrame:frame];
	w.backgroundColor = [UIColor whiteColor];

	push_objc(L, w, "uiwindow");
	return 1;
}

static int bridge_vstack(lua_State *L) {
	UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(v, &kAxisKey, @"vstack", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "uiview");
	return 1;
}

static int bridge_hstack(lua_State *L) {
	UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(v, &kAxisKey, @"hstack", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "uiview");
	return 1;
}

static int bridge_hsplit(lua_State *L) {
	UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(v, &kAxisKey, @"hsplit", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "uiview");
	return 1;
}

static int bridge_spacer(lua_State *L) {
	UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
	objc_setAssociatedObject(v, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "uiview");
	return 1;
}

static int bridge_image(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	NSString *nsPath = [NSString stringWithUTF8String:path];

	UIImage *img = [UIImage imageWithContentsOfFile:nsPath];
	if (!img) img = [UIImage imageNamed:nsPath];
	if (!img) return luaL_error(L, "failed to load image: %s", path);

	CGSize size = img.size;
	if (size.width > 400) {
		CGFloat ratio = 400.0 / size.width;
		size.width = 400;
		size.height *= ratio;
	}

	UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
	iv.image = img;
	iv.contentMode = UIViewContentModeScaleAspectFit;

	push_objc(L, iv, "uiview");
	return 1;
}

static int bridge_add(lua_State *L) {
	id parent = check_objc(L, 1);
	UIView *child = check_view(L, 2);

	if ([parent isKindOfClass:[UIWindow class]]) {
		UIWindow *window = (UIWindow *)parent;
		[window addSubview:child];
		child.frame = window.bounds;
		child.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	} else {
		UIView *container = (UIView *)parent;
		[container addSubview:child];
	}

	return 0;
}

static int bridge_layout(lua_State *L) {
	id obj = check_objc(L, 1);
	CGFloat width = luaL_optnumber(L, 2, 400);

	UIView *view = (UIView *)obj;
	layout_recursive(view, width);
	return 0;
}

static int bridge_set_content_size(lua_State *L) {
	id obj = check_objc(L, 1);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);

	UIView *v = (UIView *)obj;
	v.frame = CGRectMake(v.frame.origin.x, v.frame.origin.y, width, height);
	return 0;
}

#pragma mark - Text update

static int bridge_set_text(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *str = luaL_checkstring(L, 2);
	if ([obj isKindOfClass:[UILabel class]]) {
		[(UILabel *)obj setText:[NSString stringWithUTF8String:str]];
		[(UILabel *)obj sizeToFit];
	}
	return 0;
}

#pragma mark - Button, toggle

static int bridge_button(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	int has_action = !lua_isnoneornil(L, 2);
	int ref = LUA_NOREF;
	if (has_action) {
		luaL_checktype(L, 2, LUA_TFUNCTION);
		lua_pushvalue(L, 2);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
	[btn setTitle:[NSString stringWithUTF8String:title] forState:UIControlStateNormal];
	[btn sizeToFit];

	if (has_action) {
		objc_setAssociatedObject(btn, &kCallbackKey, @(ref), OBJC_ASSOCIATION_RETAIN);
		[btn addTarget:[LuaButtonTarget shared] action:@selector(onAction:)
	  forControlEvents:UIControlEventTouchUpInside];
	}

	push_objc(L, btn, "uiview");
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

	UISwitch *sw = [[UISwitch alloc] init];
	sw.on = is_on;
	[sw sizeToFit];

	if (has_action) {
		objc_setAssociatedObject(sw, &kCallbackKey, @(ref), OBJC_ASSOCIATION_RETAIN);
		[sw addTarget:[LuaButtonTarget shared] action:@selector(onAction:)
	forControlEvents:UIControlEventValueChanged];
	}

	push_objc(L, sw, "uiview");
	return 1;
}

#pragma mark - TableView bridge (UITableView)

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

	UITableView *tv = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, width, height)
													style:UITableViewStylePlain];

	NSMutableArray *colSpecs = [NSMutableArray array];
	int ncols = (int)luaL_len(L, 1);
	for (int i = 1; i <= ncols; i++) {
		lua_rawgeti(L, 1, i);
		lua_getfield(L, -1, "id");
		lua_getfield(L, -2, "title");
		const char *colId = lua_tostring(L, -2);
		const char *colTitle = lua_tostring(L, -1);
		if (colId) {
			[colSpecs addObject:@{@"id": [NSString stringWithUTF8String:colId],
								  @"title": [NSString stringWithUTF8String:colTitle ?: colId]}];
		}
		lua_pop(L, 3);
	}

	LuaTableViewSource *src = [[LuaTableViewSource alloc] initWithTableView:tv
																   columns:colSpecs];

	objc_setAssociatedObject(tv, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(tv, &kTableSourceKey, src, OBJC_ASSOCIATION_RETAIN);

	push_objc(L, tv, "uiview");
	return 1;
}

static int bridge_tableview_add(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (!src) return luaL_error(L, "not a table view");
	luaL_checktype(L, 2, LUA_TTABLE);
	[src addRow:lua_table_to_dict(L, 2)];
	return 0;
}

static int bridge_tableview_remove(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (!src) return luaL_error(L, "not a table view");
	[src removeRowAtIndex:(NSInteger)luaL_checkinteger(L, 2)];
	return 0;
}

static int bridge_tableview_clear(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (!src) return luaL_error(L, "not a table view");
	[src clearRows];
	return 0;
}

#pragma mark - Show

static int bridge_show(lua_State *L) {
	UIWindow *w = (__bridge UIWindow *)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	[w makeKeyAndVisible];
	return 0;
}

#pragma mark - Timer

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
			report_lua_error(mainL, "timer");
			lua_pop(mainL, 1);
		}
		luaL_unref(mainL, LUA_REGISTRYINDEX, ref);
	}];

	return 0;
}

#pragma mark - Generic bridge

static int bridge_create(lua_State *L) {
	const char *className = luaL_checkstring(L, 1);
	Class cls = NSClassFromString([NSString stringWithUTF8String:className]);
	if (!cls) return luaL_error(L, "unknown class: %s", className);

	id obj = [[cls alloc] init];
	push_objc(L, obj, [obj isKindOfClass:[UIWindow class]] ? "uiwindow" : "uiview");
	return 1;
}

static int bridge_font(lua_State *L) {
	CGFloat size = luaL_checknumber(L, 1);
	const char *weightStr = luaL_optstring(L, 2, NULL);

	UIFontWeight w = UIFontWeightRegular;
	if (weightStr) {
		if (strcmp(weightStr, "bold") == 0) w = UIFontWeightBold;
		else if (strcmp(weightStr, "semibold") == 0) w = UIFontWeightSemibold;
		else if (strcmp(weightStr, "light") == 0) w = UIFontWeightLight;
		else if (strcmp(weightStr, "heavy") == 0) w = UIFontWeightHeavy;
	}

	UIFont *font = [UIFont systemFontOfSize:size weight:w];
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
	if ([obj respondsToSelector:@selector(addTarget:action:forControlEvents:)]) {
		[obj addTarget:[LuaButtonTarget shared] action:@selector(onAction:)
		forControlEvents:UIControlEventTouchUpInside];
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
	{"_setContentSize",   bridge_set_content_size},
	{"_tableview",        bridge_tableview},
	{"_button",           bridge_button},
	{"_toggle",           bridge_toggle},
	{"_timerAfter",       bridge_timer_after},
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

int luaopen_UIKitNative(lua_State *L) {
	gL = L;

	lua_pushlightuserdata(L, L);
	lua_setfield(L, LUA_REGISTRYINDEX, "bridge_main");

	register_metatable(L, "uiview");
	register_metatable(L, "uiwindow");
	register_metatable(L, "nsobject");
	luaL_newlib(L, bridge_lib);
	return 1;
}
