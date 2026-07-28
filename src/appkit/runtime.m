#pragma mark - Lua helpers

/* Forward declarations for table/outline and other hand-written functions
 * that runtime.m references directly. */
static int bridge_tableview_add(lua_State *L);
static int bridge_tableview_remove(lua_State *L);
static int bridge_tableview_clear(lua_State *L);
static int bridge_table_show_loading(lua_State *L);
static int bridge_table_hide_loading(lua_State *L);
static int bridge_table_column_widths(lua_State *L);
static int bridge_table_refresh(lua_State *L);
static int bridge_tableview_replace(lua_State *L);
static int bridge_table_select_row(lua_State *L);
static int bridge_table_activate_row(lua_State *L);
static int bridge_text_view(lua_State *L);
static int bridge_symbol_toggle(lua_State *L);
static int bridge_eval(lua_State *L);
static int bridge_outlineview(lua_State *L);
static int bridge_list_directory(lua_State *L);
static int bridge_tabview(lua_State *L);
static int bridge_segmented_control(lua_State *L);
static int bridge_panel(lua_State *L);
static int bridge_panel_style_state(lua_State *L);
static int bridge_menu_item(lua_State *L);
static int bridge_text_field_callbacks(lua_State *L);
static int bridge_text_field_test_input(lua_State *L);
static int bridge_text_field_test_command(lua_State *L);
static int bridge_object_add_impl(lua_State *L);
static int bridge_object_layout_impl(lua_State *L);
static int bridge_object_set_content_size_impl(lua_State *L);
/* Native bridge method forwards. */
#define GEN_CLASS_FORWARDS
#include "bindings.m"
#undef GEN_CLASS_FORWARDS
static void layout_recursive(NSView *view, CGFloat width);

/*
 * KVC is the property bridge. Framework-owned layout state lives on NSView
 * itself, so every native subclass inherits the same Lua-visible accessors.
 */
#define LUA_NUMBER_ACCESSORS(GETTER, SETTER, KEY, FALLBACK, EXPR) \
- (CGFloat)GETTER { \
	NSNumber *value = objc_getAssociatedObject(self, &kKeys[KEY]); \
	return value ? value.doubleValue : (FALLBACK); \
} \
- (void)SETTER:(CGFloat)value { \
	objc_setAssociatedObject(self, &kKeys[KEY], @(EXPR), \
		OBJC_ASSOCIATION_RETAIN); \
}

#define LUA_BOOL_ACCESSORS(GETTER, SETTER, KEY) \
- (BOOL)GETTER { \
	return [objc_getAssociatedObject(self, &kKeys[KEY]) boolValue]; \
} \
- (void)SETTER:(BOOL)value { \
	objc_setAssociatedObject(self, &kKeys[KEY], @(value), \
		OBJC_ASSOCIATION_RETAIN); \
}

@implementation NSView (LuaLayoutProperties)
LUA_NUMBER_ACCESSORS(padding, setPadding, kPaddingKey, 0, value)
LUA_NUMBER_ACCESSORS(paddingHorizontal, setPaddingHorizontal,
	kPaddingHorizontalKey, 0, value)
LUA_NUMBER_ACCESSORS(paddingVertical, setPaddingVertical,
	kPaddingVerticalKey, 0, value)
LUA_NUMBER_ACCESSORS(spacing, setSpacing, kSpacingKey,
	kStackSpacing, MAX(0, value))
LUA_NUMBER_ACCESSORS(fixedWidth, setFixedWidth, kFixedWidthKey, 0, value)
LUA_NUMBER_ACCESSORS(fixedHeight, setFixedHeight, kFixedHeightKey, 0, value)
LUA_NUMBER_ACCESSORS(minWidth, setMinWidth, kMinWidthKey, 0, value)
LUA_NUMBER_ACCESSORS(minHeight, setMinHeight, kMinHeightKey, 0, value)
LUA_NUMBER_ACCESSORS(flexGrow, setFlexGrow, kFlexGrowKey, 0, MAX(0, value))
LUA_NUMBER_ACCESSORS(flexShrink, setFlexShrink,
	kFlexShrinkKey, 1, MAX(0, value))
LUA_BOOL_ACCESSORS(fillWidth, setFillWidth, kFillWidthKey)
LUA_BOOL_ACCESSORS(fillHeight, setFillHeight, kFillHeightKey)

- (NSNumber *)maxWidth {
	return objc_getAssociatedObject(self, &kKeys[kMaxWidthKey]);
}
- (void)setMaxWidth:(NSNumber *)value {
	objc_setAssociatedObject(self, &kKeys[kMaxWidthKey], value,
		OBJC_ASSOCIATION_RETAIN);
}
- (NSNumber *)maxHeight {
	return objc_getAssociatedObject(self, &kKeys[kMaxHeightKey]);
}
- (void)setMaxHeight:(NSNumber *)value {
	objc_setAssociatedObject(self, &kKeys[kMaxHeightKey], value,
		OBJC_ASSOCIATION_RETAIN);
}
- (NSNumber *)flexBasis {
	return objc_getAssociatedObject(self, &kKeys[kFlexBasisKey]);
}
- (void)setFlexBasis:(NSNumber *)value {
	NSNumber *basis = value ? @(MAX(0, value.doubleValue)) : nil;
	objc_setAssociatedObject(self, &kKeys[kFlexBasisKey], basis,
		OBJC_ASSOCIATION_RETAIN);
}
- (NSString *)alignment {
	return objc_getAssociatedObject(self, &kKeys[kAlignmentKey]) ?: @"center";
}
- (void)setAlignment:(NSString *)value {
	objc_setAssociatedObject(self, &kKeys[kAlignmentKey], value,
		OBJC_ASSOCIATION_COPY);
}
- (NSSize)size {
	return self.frame.size;
}
- (void)setSize:(NSSize)value {
	self.frameSize = value;
}
- (NSRect)frameInWindow {
	return [self convertRect:self.bounds toView:nil];
}
@end

#undef LUA_BOOL_ACCESSORS
#undef LUA_NUMBER_ACCESSORS

@interface LuaTextField : NSTextField
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSString *placeholder;
@property(nonatomic) NSInteger lineLimit;
@end

@implementation LuaTextField
- (NSString *)text { return self.stringValue; }
- (void)setText:(NSString *)value { self.stringValue = value ?: @""; }
- (NSString *)placeholder { return self.placeholderString; }
- (void)setPlaceholder:(NSString *)value { self.placeholderString = value; }
- (NSInteger)lineLimit { return self.maximumNumberOfLines; }
- (void)setLineLimit:(NSInteger)value { self.maximumNumberOfLines = value; }
@end

@interface LuaWindow : NSWindow
@end
@implementation LuaWindow
@end

@implementation NSWindow (LuaProperties)
- (NSSize)size { return self.contentView.frame.size; }
- (void)setSize:(NSSize)value { [self setContentSize:value]; }
- (NSString *)tabbing {
	switch (self.tabbingMode) {
		case NSWindowTabbingModeDisallowed: return @"disallowed";
		case NSWindowTabbingModePreferred: return @"preferred";
		default: return @"automatic";
	}
}
- (void)setTabbing:(NSString *)value {
	if ([value isEqualToString:@"disallowed"]) {
		self.tabbingMode = NSWindowTabbingModeDisallowed;
	} else if ([value isEqualToString:@"preferred"]) {
		self.tabbingMode = NSWindowTabbingModePreferred;
	} else if ([value isEqualToString:@"automatic"]) {
		self.tabbingMode = NSWindowTabbingModeAutomatic;
	} else {
		[NSException raise:NSInvalidArgumentException
			format:@"unknown tabbing mode: %@", value];
	}
}
- (NSString *)appearanceStyle {
	if (!self.appearance) return @"system";
	return [self.appearance.name isEqualToString:NSAppearanceNameDarkAqua]
		? @"dark" : @"light";
}
- (void)setAppearanceStyle:(NSString *)value {
	if ([value isEqualToString:@"system"]) {
		self.appearance = nil;
	} else {
		self.appearance = [NSAppearance appearanceNamed:
			[value isEqualToString:@"dark"]
				? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
	}
}
@end

@interface LuaNativeTextView : NSTextView
@property(nonatomic, copy) NSString *text;
@end

@implementation LuaNativeTextView
- (NSString *)text { return self.string; }
- (void)setText:(NSString *)value { self.string = value ?: @""; }
@end

static id check_objc(lua_State *L, int idx) {
	ObjCRef *ref = lua_objc_test_ref(L, idx);
	if (ref) return (__bridge id)ref->ptr;
	luaL_typeerror(L, idx, "Objective-C object");
	return nil;
}

static NSView *check_view(lua_State *L, int idx) {
	id obj = check_objc(L, idx);
	if ([obj isKindOfClass:[NSWindow class]]) {
		return [(NSWindow *)obj contentView];
	}
	if (![obj isKindOfClass:[NSView class]]) {
		luaL_typeerror(L, idx, "NSView or NSWindow");
		return nil;
	}
	return (NSView *)obj;
}

/* Native value userdata helpers (NSSize, NSPoint, NSRect). */
#define GEN_STRUCT_HELPERS
#include "structs.m"
#undef GEN_STRUCT_HELPERS

static void push_kvc_value(lua_State *L, id value) {
	if ([value isKindOfClass:[NSValue class]]) {
		const char *type = ((NSValue *)value).objCType;
		if (strcmp(type, @encode(NSSize)) == 0) {
			push_NSSize(L, ((NSValue *)value).sizeValue);
			return;
		}
		if (strcmp(type, @encode(NSPoint)) == 0) {
			push_NSPoint(L, ((NSValue *)value).pointValue);
			return;
		}
		if (strcmp(type, @encode(NSRect)) == 0) {
			push_NSRect(L, ((NSValue *)value).rectValue);
			return;
		}
	}
	push_objc_value(L, value);
}

static id lua_to_kvc_value(lua_State *L, int idx) {
	NSSize *size = luaL_testudata(L, idx, "lua_objc.struct.NSSize");
	if (size) return [NSValue valueWithSize:*size];
	NSPoint *point = luaL_testudata(L, idx, "lua_objc.struct.NSPoint");
	if (point) return [NSValue valueWithPoint:*point];
	NSRect *rect = luaL_testudata(L, idx, "lua_objc.struct.NSRect");
	if (rect) return [NSValue valueWithRect:*rect];
	return lua_to_objc_value(L, idx);
}

/* Native class-binding wrapper functions (after check_view etc.) */
#define GEN_CLASS_WRAPPERS
#include "bindings.m"
#undef GEN_CLASS_WRAPPERS

/* Native class MethodEntry arrays. */
#define GEN_CLASS_ARRAYS
#include "bindings.m"
#undef GEN_CLASS_ARRAYS

static MethodEntry TableDataMethods[] = {
	{"addRow",       bridge_tableview_add},
	{"removeRow",    bridge_tableview_remove},
	{"clearRows",    bridge_tableview_clear},
	{"replaceRows",  bridge_tableview_replace},
	{"selectRow",    bridge_table_select_row},
	{"activateRow",  bridge_table_activate_row},
	{"rowCount",     NULL},
	{"showLoading",  bridge_table_show_loading},
	{"hideLoading",  bridge_table_hide_loading},
	{"refresh",      bridge_table_refresh},
	{NULL, NULL}
};

static int nsview_index(lua_State *L) {
	id obj = (__bridge id)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	const char *key = lua_tostring(L, 2);
	if (!key) { lua_pushnil(L); return 1; }

	/* Native class dispatch. */
#define GEN_CLASS_INDEX
#include "bindings.m"
#undef GEN_CLASS_INDEX

	NSString *kvcKey = [NSString stringWithUTF8String:key];
	@try {
		id value = [obj valueForKey:kvcKey];
		push_kvc_value(L, value);
		return 1;
	} @catch (NSException *exception) {
		(void)exception;
	}

	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (src) {
		if (strcmp(key, "rowCount") == 0) {
			if ([src isKindOfClass:[LuaOutlineViewSource class]]) {
				lua_pushinteger(L,
					(lua_Integer)[(LuaOutlineViewSource *)src rowCount]);
			} else {
				lua_pushinteger(L,
					(lua_Integer)((LuaTableViewSource *)src).rows.count);
			}
			return 1;
		}
		lua_CFunction method = lookupMethod(key, TableDataMethods);
		if (method) {
			lua_pushcfunction(L, method);
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

	NSString *kvcKey = [NSString stringWithUTF8String:key];
	id value = lua_to_kvc_value(L, 3);
	@try {
		[obj setValue:value forKey:kvcKey];
		return 0;
	} @catch (NSException *exception) {
		return luaL_error(L, "cannot set '%s' on %s: %s",
			key,
			NSStringFromClass([obj class]).UTF8String,
			exception.reason.UTF8String);
	}
}
