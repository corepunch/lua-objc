#pragma mark - Lua helpers

static int bridge_tableview_add(lua_State *L);
static int bridge_tableview_remove(lua_State *L);
static int bridge_tableview_clear(lua_State *L);
static int bridge_add(lua_State *L);
static int bridge_layout(lua_State *L);
static int bridge_set_content_size(lua_State *L);
static int bridge_show(lua_State *L);
static void layout_recursive(UIView *view, CGFloat width);

@interface UIView (LuaLayoutProperties)
@property(nonatomic) CGFloat padding;
@property(nonatomic, copy) NSString *alignment;
@property(nonatomic) CGFloat fixedWidth;
@property(nonatomic) CGFloat fixedHeight;
@end

@implementation UIView (LuaLayoutProperties)
- (CGFloat)padding {
	NSNumber *value = objc_getAssociatedObject(self, &kPaddingKey);
	return value ? value.doubleValue : 12.0;
}
- (void)setPadding:(CGFloat)value {
	objc_setAssociatedObject(self, &kPaddingKey, @(value),
		OBJC_ASSOCIATION_RETAIN);
}
- (NSString *)alignment {
	return objc_getAssociatedObject(self, &kAlignmentKey) ?: @"center";
}
- (void)setAlignment:(NSString *)value {
	objc_setAssociatedObject(self, &kAlignmentKey, value,
		OBJC_ASSOCIATION_COPY);
}
- (CGFloat)fixedWidth {
	return [objc_getAssociatedObject(self, &kFixedWidthKey) doubleValue];
}
- (void)setFixedWidth:(CGFloat)value {
	objc_setAssociatedObject(self, &kFixedWidthKey, @(value),
		OBJC_ASSOCIATION_RETAIN);
}
- (CGFloat)fixedHeight {
	return [objc_getAssociatedObject(self, &kFixedHeightKey) doubleValue];
}
- (void)setFixedHeight:(CGFloat)value {
	objc_setAssociatedObject(self, &kFixedHeightKey, @(value),
		OBJC_ASSOCIATION_RETAIN);
}
@end

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
