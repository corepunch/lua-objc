#pragma mark - Lua helpers

/* Forward declarations for table/outline and other hand-written functions
 * that runtime.m references directly. */
static int bridge_tableview_add(lua_State *L);
static int bridge_tableview_remove(lua_State *L);
static int bridge_tableview_clear(lua_State *L);
static int bridge_glass_effect(lua_State *L);
static int bridge_table_show_loading(lua_State *L);
static int bridge_table_hide_loading(lua_State *L);
static int bridge_table_column_widths(lua_State *L);
static int bridge_table_refresh(lua_State *L);
static int bridge_tableview_replace(lua_State *L);
static int bridge_table_select_row(lua_State *L);
static int bridge_table_activate_row(lua_State *L);
static int bridge_text_view(lua_State *L);
static int bridge_symbol_toggle(lua_State *L);
static int bridge_outlineview(lua_State *L);
static int bridge_list_directory(lua_State *L);
static int bridge_tabview(lua_State *L);
static int bridge_segmented_control(lua_State *L);
static int bridge_panel(lua_State *L);
static int bridge_panel_style_state(lua_State *L);
static int bridge_set_main_menu(lua_State *L);
static int bridge_main_menu_snapshot(lua_State *L);
static int bridge_perform_main_menu_item(lua_State *L);
static int bridge_search_help(lua_State *L);
static int bridge_text_field_callbacks(lua_State *L);
static int bridge_text_field_test_input(lua_State *L);
static int bridge_text_field_test_command(lua_State *L);
static int bridge_text_field_test_focus(lua_State *L);
static int bridge_NSScrollView_scrollTo(lua_State *L);
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

@interface NSView (LuaSurfaceProperties)
@property(nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic) BOOL clipsToBounds;
@end

@implementation NSView (LuaSurfaceProperties)
- (NSColor *)backgroundColor {
	return objc_getAssociatedObject(self, &kKeys[kBackgroundColorKey]);
}
- (void)setBackgroundColor:(NSColor *)value {
	objc_setAssociatedObject(self, &kKeys[kBackgroundColorKey], value,
		OBJC_ASSOCIATION_RETAIN);
	self.wantsLayer = YES;
	[self.effectiveAppearance performAsCurrentDrawingAppearance:^{ self.layer.backgroundColor = value.CGColor; }];
}
- (CGFloat)cornerRadius {
	return [objc_getAssociatedObject(self, &kKeys[kCornerRadiusKey]) doubleValue];
}
- (void)setCornerRadius:(CGFloat)value {
	CGFloat radius = MAX(0, value);
	objc_setAssociatedObject(self, &kKeys[kCornerRadiusKey], @(radius),
		OBJC_ASSOCIATION_RETAIN);
	self.wantsLayer = YES;
	self.layer.cornerRadius = radius;
	self.clipsToBounds = radius > 0;
}
- (BOOL)clipsToBounds {
	return [objc_getAssociatedObject(self, &kKeys[kClipsToBoundsKey]) boolValue];
}
- (void)setClipsToBounds:(BOOL)value {
	objc_setAssociatedObject(self, &kKeys[kClipsToBoundsKey], @(value),
		OBJC_ASSOCIATION_RETAIN);
	self.wantsLayer = YES;
	self.layer.masksToBounds = value;
}
@end

@implementation NSView (LuaLayoutProperties)
LUA_NUMBER_ACCESSORS(padding, setPadding, kPaddingKey, 0, value)
LUA_NUMBER_ACCESSORS(paddingHorizontal, setPaddingHorizontal,
	kPaddingHorizontalKey, 0, value)
LUA_NUMBER_ACCESSORS(paddingVertical, setPaddingVertical,
	kPaddingVerticalKey, 0, value)
LUA_NUMBER_ACCESSORS(paddingLeading, setPaddingLeading, kPaddingLeadingKey, 0, value)
LUA_NUMBER_ACCESSORS(paddingTrailing, setPaddingTrailing, kPaddingTrailingKey, 0, value)
LUA_NUMBER_ACCESSORS(paddingTop, setPaddingTop, kPaddingTopKey, 0, value)
LUA_NUMBER_ACCESSORS(paddingBottom, setPaddingBottom, kPaddingBottomKey, 0, value)
LUA_NUMBER_ACCESSORS(spacing, setSpacing, kSpacingKey,
	kStackSpacing, MAX(0, value))
LUA_NUMBER_ACCESSORS(maxRows, setMaxRows, kFlowMaxRowsKey, 0, MAX(0, floor(value)))
LUA_NUMBER_ACCESSORS(minWidth, setMinWidth, kMinWidthKey, 0, value)
LUA_NUMBER_ACCESSORS(minHeight, setMinHeight, kMinHeightKey, 0, value)
LUA_NUMBER_ACCESSORS(flexGrow, setFlexGrow, kFlexGrowKey, 0, MAX(0, value))
LUA_NUMBER_ACCESSORS(flexShrink, setFlexShrink,
	kFlexShrinkKey, 1, MAX(0, value))
LUA_BOOL_ACCESSORS(fillWidth, setFillWidth, kFillWidthKey)
LUA_NUMBER_ACCESSORS(containerRelativeWidth, setContainerRelativeWidth,
	kContainerRelativeWidthKey, 0, MAX(0, value))
LUA_BOOL_ACCESSORS(fillHeight, setFillHeight, kFillHeightKey)

/* A fixed dimension is optional, like a maximum: nil clears it, so a
 * reconciled template that drops `width` lets the view size itself again,
 * while 0 remains a real zero-point frame. */
- (NSNumber *)fixedWidth {
	return objc_getAssociatedObject(self, &kKeys[kFixedWidthKey]);
}
- (void)setFixedWidth:(NSNumber *)value {
	objc_setAssociatedObject(self, &kKeys[kFixedWidthKey], value,
		OBJC_ASSOCIATION_RETAIN);
}
- (NSNumber *)fixedHeight {
	return objc_getAssociatedObject(self, &kKeys[kFixedHeightKey]);
}
- (void)setFixedHeight:(NSNumber *)value {
	objc_setAssociatedObject(self, &kKeys[kFixedHeightKey], value,
		OBJC_ASSOCIATION_RETAIN);
}
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
- (NSString *)fixedSize {
	return objc_getAssociatedObject(self, &kKeys[kFixedSizeKey]);
}
- (void)setFixedSize:(NSString *)value {
	objc_setAssociatedObject(self, &kKeys[kFixedSizeKey], value.length ? value : nil,
		OBJC_ASSOCIATION_COPY);
}
/* SwiftUI `.ignoresSafeArea(edges:)`: "top", "bottom" or "all". A view that
 * touches its window's safe area on those edges extends to the window edge,
 * under a full-size-content title bar and toolbar. */
- (NSString *)ignoresSafeArea {
	return objc_getAssociatedObject(self, &kKeys[kIgnoresSafeAreaKey]);
}
- (void)setIgnoresSafeArea:(NSString *)value {
	objc_setAssociatedObject(self, &kKeys[kIgnoresSafeAreaKey], value.length ? value : nil,
		OBJC_ASSOCIATION_COPY);
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
@property(nonatomic) NSInteger textAlignment;
@end

@implementation LuaTextField
- (NSString *)text { return self.stringValue; }
- (void)setText:(NSString *)value { self.stringValue = value ?: @""; }
- (NSString *)placeholder { return self.placeholderString; }
- (void)setPlaceholder:(NSString *)value { self.placeholderString = value; }
- (NSInteger)lineLimit { return self.maximumNumberOfLines; }
- (void)setLineLimit:(NSInteger)value { self.maximumNumberOfLines = value; }
- (NSInteger)textAlignment { return self.alignment; }
- (void)setTextAlignment:(NSInteger)value { self.alignment = (NSTextAlignment)value; }
@end

/* Labels need paragraph metrics to survive text/font changes. KVC alone
 * cannot maintain attributed paragraph state when those native setters run. */
@interface LuaLabelCell : NSTextFieldCell
@end
@implementation LuaLabelCell
- (NSRect)drawingRectForBounds:(NSRect)bounds { return bounds; }
- (NSRect)titleRectForBounds:(NSRect)bounds { return bounds; }
@end

/* SwiftUI `.minimumScaleFactor`: offered less width than its text needs, a
 * label draws in a smaller size of its font, down to `minimumScaleFactor`
 * times the declared size. The declared font is kept, so wider proposals
 * bring the full size back. */
@interface LuaLabel : LuaTextField
@property(nonatomic) CGFloat minimumScaleFactor;
- (void)fitFontToWidth:(CGFloat)width;
@end

@implementation LuaLabel {
	NSLineBreakMode _paragraphBreakMode;
	NSFont *_declaredFont;
	BOOL _scalingFont;
}
+ (Class)cellClass { return LuaLabelCell.class; }
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) _minimumScaleFactor = 1;
	return self;
}
- (void)setMinimumScaleFactor:(CGFloat)value {
	_minimumScaleFactor = MAX(0.01, MIN(1, value));
	[self fitFontToWidth:CGFLOAT_MAX];
}
- (void)applyScaledFont:(NSFont *)font {
	_scalingFont = YES;
	self.font = font;
	_scalingFont = NO;
}
- (void)fitFontToWidth:(CGFloat)width {
	NSFont *declared = _declaredFont ?: self.font;
	if (!declared) return;
	if (self.font != declared) [self applyScaledFont:declared];
	if (_minimumScaleFactor >= 1 || width >= CGFLOAT_MAX / 2) return;
	CGFloat natural = self.fittingSize.width;
	if (natural <= width || natural <= 0) return;
	/* Glyph advances are not exactly linear in the point size, so step down
	 * from the proportional guess until the text fits or reaches the floor. */
	CGFloat floorSize = declared.pointSize * _minimumScaleFactor;
	CGFloat size = MAX(floorSize, floor(declared.pointSize * width / natural * 2) / 2);
	for (;;) {
		[self applyScaledFont:[NSFont fontWithDescriptor:declared.fontDescriptor size:size] ?: declared];
		if (size <= floorSize || self.fittingSize.width <= width) break;
		size = MAX(floorSize, size - 0.5);
	}
}
- (NSSize)intrinsicContentSize {
	NSSize size = [super intrinsicContentSize];
	// The attributed paragraph uses complete font metrics. Native single-line
	// field metrics can be shorter, clipping descenders with that paragraph.
	if (self.font) size.height = MAX(size.height, ceil(self.font.ascender - self.font.descender + self.font.leading));
	return size;
}
- (void)updateParagraphMetrics {
	if (!self.font) return;
	NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
	paragraph.alignment = self.alignment;
	paragraph.lineBreakMode = self.lineBreakMode;
	CGFloat lineHeight = ceil(self.font.ascender - self.font.descender + self.font.leading);
	paragraph.minimumLineHeight = lineHeight;
	paragraph.maximumLineHeight = lineHeight;
	self.attributedStringValue = [[NSAttributedString alloc] initWithString:self.stringValue attributes:@{
		NSFontAttributeName: self.font,
		NSForegroundColorAttributeName: self.textColor ?: NSColor.labelColor,
		NSParagraphStyleAttributeName: paragraph,
	}];
}
- (void)setStringValue:(NSString *)value { [super setStringValue:value]; [self updateParagraphMetrics]; }
- (void)setFont:(NSFont *)font {
	if (!_scalingFont) _declaredFont = font;
	[super setFont:font];
	[self updateParagraphMetrics];
}
- (void)setTextColor:(NSColor *)color { [super setTextColor:color]; [self updateParagraphMetrics]; }
- (void)setAlignment:(NSTextAlignment)value { [super setAlignment:value]; [self updateParagraphMetrics]; }
// Native single-line cell layout temporarily selects clipping. Keep the
// declared paragraph mode through later text mutations and wider/narrower passes.
- (NSLineBreakMode)lineBreakMode { return _paragraphBreakMode; }
- (void)setLineBreakMode:(NSLineBreakMode)value {
	_paragraphBreakMode = value;
	[super setLineBreakMode:value];
	[self updateParagraphMetrics];
}
@end

@interface LuaSecureTextField : NSSecureTextField
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSString *placeholder;
@property(nonatomic) NSInteger lineLimit;
@property(nonatomic) NSInteger textAlignment;
@end

@implementation LuaSecureTextField
- (NSString *)text { return self.stringValue; }
- (void)setText:(NSString *)value { self.stringValue = value ?: @""; }
- (NSString *)placeholder { return self.placeholderString; }
- (void)setPlaceholder:(NSString *)value { self.placeholderString = value; }
- (NSInteger)lineLimit { return self.maximumNumberOfLines; }
- (void)setLineLimit:(NSInteger)value { self.maximumNumberOfLines = value; }
- (NSInteger)textAlignment { return self.alignment; }
- (void)setTextAlignment:(NSInteger)value { self.alignment = (NSTextAlignment)value; }
@end

@interface LuaWindow : NSWindow
@end
@implementation LuaWindow
@end

/* AppKit lazily creates private helper windows (e.g. the text-input cursor
 * helper window) the first time a text view's selection changes. These can
 * appear in NSApp.windows ahead of the app's own window, so headless tooling
 * (--dump-layout, --screenshot) must look for an actual LuaWindow instance
 * rather than blindly taking NSApp.windows.firstObject. */
static NSWindow *lua_objc_app_window(void) {
	for (NSWindow *w in NSApp.windows) {
		if ([w isKindOfClass:[LuaWindow class]]) return w;
	}
	return NSApp.windows.firstObject;
}

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
/* SwiftUI `.windowLevel(.floating)`. A floating window also joins every
 * Space and floats over full-screen apps, as the system Picture in Picture
 * window does. */
- (NSString *)windowLevel {
	return self.level >= NSFloatingWindowLevel ? @"floating" : @"normal";
}
- (void)setWindowLevel:(NSString *)value {
	BOOL floating = [value isEqualToString:@"floating"];
	if (!floating && ![value isEqualToString:@"normal"]) {
		[NSException raise:NSInvalidArgumentException format:@"unknown window level: %@", value];
	}
	NSWindowCollectionBehavior joins = NSWindowCollectionBehaviorCanJoinAllSpaces
		| NSWindowCollectionBehaviorFullScreenAuxiliary;
	self.level = floating ? NSFloatingWindowLevel : NSNormalWindowLevel;
	self.collectionBehavior = floating ? (self.collectionBehavior | joins) : (self.collectionBehavior & ~joins);
}
/* Width over height kept while the user resizes; 0 resizes freely. */
- (CGFloat)aspectRatio {
	NSSize ratio = self.contentAspectRatio;
	return ratio.height > 0 ? ratio.width / ratio.height : 0;
}
- (void)setAspectRatio:(CGFloat)value {
	if (value > 0) {
		self.contentAspectRatio = NSMakeSize(value, 1);
	} else {
		self.contentResizeIncrements = NSMakeSize(1, 1);
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
	if (!ref) {
		luaL_typeerror(L, idx, "Objective-C object");
		return nil;
	}
	return lua_objc_live_ptr(L, idx, ref);
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

static void invalidate_layout(NSView *view);
static void flush_pending_layout(void);
static void motion_will_set(id object, const char *key);
static BOOL motion_intercept_hidden(id object, BOOL hidden);

/* SwiftUI `.scrollDisabled(true)`: the list keeps its rows in place and is
 * as tall as all of them, leaving overflow to a scrolling ancestor. */
static char kScrollDisabledKey;
@interface NSScrollView (LuaScrollDisabled)
@property(nonatomic) BOOL scrollDisabled;
@end
@implementation NSScrollView (LuaScrollDisabled)
- (BOOL)scrollDisabled {
	return [objc_getAssociatedObject(self, &kScrollDisabledKey) boolValue];
}
- (void)setScrollDisabled:(BOOL)value {
	objc_setAssociatedObject(self, &kScrollDisabledKey, @(value), OBJC_ASSOCIATION_RETAIN);
	if (value) self.hasVerticalScroller = NO;
}
@end

// Row count determines the height of a list that does not scroll.
static void table_rows_changed(id obj) {
	if ([obj isKindOfClass:NSScrollView.class] && ((NSScrollView *)obj).scrollDisabled)
		invalidate_layout((NSView *)obj);
}

static int nsview_index(lua_State *L) {
@autoreleasepool {
	id obj = lua_objc_live_ptr(L, 1, lua_touserdata(L, 1));
	const char *key = lua_tostring(L, 2);
	if (!key) { lua_pushnil(L); return 1; }

	/* Native class dispatch. */
#define GEN_CLASS_INDEX
#include "bindings.m"
#undef GEN_CLASS_INDEX

	if (lua_objc_key_reads_geometry(key)) flush_pending_layout();
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
}

static int nsview_newindex(lua_State *L) {
@autoreleasepool {
	id obj = lua_objc_live_ptr(L, 1, lua_touserdata(L, 1));
	const char *key = lua_tostring(L, 2);
	if (!key) return luaL_error(L, "invalid property name");

	NSString *kvcKey = [NSString stringWithUTF8String:key];
	id value = lua_to_kvc_value(L, 3);
	motion_will_set(obj, key);
	if (strcmp(key, "hidden") == 0 && motion_intercept_hidden(obj, lua_toboolean(L, 3))) {
		invalidate_layout((NSView *)obj);
		return 0;
	}
	@try {
		[obj setValue:value forKey:kvcKey];
		if ([obj isKindOfClass:NSView.class] && lua_objc_key_affects_layout(key))
			invalidate_layout((NSView *)obj);
		return 0;
	} @catch (NSException *exception) {
		return luaL_error(L, "cannot set '%s' on %s: %s",
			key,
			NSStringFromClass([obj class]).UTF8String,
			exception.reason.UTF8String);
	}
}
}
