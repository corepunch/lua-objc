#pragma mark - Lua helpers

static int bridge_tableview_add(lua_State *L);
static int bridge_tableview_remove(lua_State *L);
static int bridge_tableview_clear(lua_State *L);
static int bridge_add(lua_State *L);
static int bridge_layout(lua_State *L);
static int bridge_set_content_size(lua_State *L);
static int bridge_size_to_fit(lua_State *L);
static int bridge_show(lua_State *L);
static void layout_recursive(UIView *view, CGFloat width);

@interface UIView (LuaLayoutProperties)
@property(nonatomic) CGFloat padding;
@property(nonatomic) CGFloat paddingHorizontal;
@property(nonatomic) CGFloat paddingVertical;
@property(nonatomic, copy) NSString *alignment;
@property(nonatomic) CGFloat fixedWidth;
@property(nonatomic) CGFloat fixedHeight;
@property(nonatomic) CGFloat minWidth;
@property(nonatomic) CGFloat minHeight;
@property(nonatomic) NSNumber *maxWidth;
@property(nonatomic) NSNumber *maxHeight;
@property(nonatomic) CGFloat spacing;
@property(nonatomic) CGFloat flexGrow;
@property(nonatomic) CGFloat flexShrink;
@property(nonatomic) NSNumber *flexBasis;
@property(nonatomic) BOOL fillWidth;
@property(nonatomic) BOOL fillHeight;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic, copy) NSString *contentModeName;
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
- (CGFloat)paddingHorizontal { return [objc_getAssociatedObject(self, &kPaddingHorizontalKey) doubleValue]; }
- (void)setPaddingHorizontal:(CGFloat)value { objc_setAssociatedObject(self, &kPaddingHorizontalKey, @(MAX(0, value)), OBJC_ASSOCIATION_RETAIN); }
- (CGFloat)paddingVertical { return [objc_getAssociatedObject(self, &kPaddingVerticalKey) doubleValue]; }
- (void)setPaddingVertical:(CGFloat)value { objc_setAssociatedObject(self, &kPaddingVerticalKey, @(MAX(0, value)), OBJC_ASSOCIATION_RETAIN); }
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
- (CGFloat)minWidth { return [objc_getAssociatedObject(self, &kMinWidthKey) doubleValue]; }
- (void)setMinWidth:(CGFloat)value { objc_setAssociatedObject(self, &kMinWidthKey, @(MAX(0, value)), OBJC_ASSOCIATION_RETAIN); }
- (CGFloat)minHeight { return [objc_getAssociatedObject(self, &kMinHeightKey) doubleValue]; }
- (void)setMinHeight:(CGFloat)value { objc_setAssociatedObject(self, &kMinHeightKey, @(MAX(0, value)), OBJC_ASSOCIATION_RETAIN); }
- (NSNumber *)maxWidth { return objc_getAssociatedObject(self, &kMaxWidthKey); }
- (void)setMaxWidth:(NSNumber *)value { objc_setAssociatedObject(self, &kMaxWidthKey, value, OBJC_ASSOCIATION_RETAIN); }
- (NSNumber *)maxHeight { return objc_getAssociatedObject(self, &kMaxHeightKey); }
- (void)setMaxHeight:(NSNumber *)value { objc_setAssociatedObject(self, &kMaxHeightKey, value, OBJC_ASSOCIATION_RETAIN); }
- (CGFloat)spacing {
	NSNumber *value = objc_getAssociatedObject(self, &kSpacingKey);
	return value ? value.doubleValue : kStackSpacing;
}
- (void)setSpacing:(CGFloat)value {
	objc_setAssociatedObject(self, &kSpacingKey, @(MAX(0, value)),
		OBJC_ASSOCIATION_RETAIN);
}
- (CGFloat)flexGrow {
	return [objc_getAssociatedObject(self, &kFlexGrowKey) doubleValue];
}
- (void)setFlexGrow:(CGFloat)value {
	objc_setAssociatedObject(self, &kFlexGrowKey, @(MAX(0, value)),
		OBJC_ASSOCIATION_RETAIN);
}
- (CGFloat)flexShrink { NSNumber *v = objc_getAssociatedObject(self, &kFlexShrinkKey); return v ? v.doubleValue : 1; }
- (void)setFlexShrink:(CGFloat)value { objc_setAssociatedObject(self, &kFlexShrinkKey, @(MAX(0, value)), OBJC_ASSOCIATION_RETAIN); }
- (NSNumber *)flexBasis { return objc_getAssociatedObject(self, &kFlexBasisKey); }
- (void)setFlexBasis:(NSNumber *)value { objc_setAssociatedObject(self, &kFlexBasisKey, value, OBJC_ASSOCIATION_RETAIN); }
- (BOOL)fillWidth {
	return [objc_getAssociatedObject(self, &kFillWidthKey) boolValue];
}
- (void)setFillWidth:(BOOL)value {
	objc_setAssociatedObject(self, &kFillWidthKey, @(value),
		OBJC_ASSOCIATION_RETAIN);
}
- (BOOL)fillHeight { return [objc_getAssociatedObject(self, &kFillHeightKey) boolValue]; }
- (void)setFillHeight:(BOOL)value { objc_setAssociatedObject(self, &kFillHeightKey, @(value), OBJC_ASSOCIATION_RETAIN); }
- (CGFloat)cornerRadius { return [objc_getAssociatedObject(self, &kCornerRadiusKey) doubleValue]; }
- (void)setCornerRadius:(CGFloat)value {
	CGFloat radius = MAX(0, value);
	objc_setAssociatedObject(self, &kCornerRadiusKey, @(radius), OBJC_ASSOCIATION_RETAIN);
	self.layer.cornerRadius = radius;
	self.clipsToBounds = radius > 0;
}
- (NSString *)contentModeName { return @"fit"; }
- (void)setContentModeName:(NSString *)value {
	if (![self isKindOfClass:[UIImageView class]]) return;
	((UIImageView *)self).contentMode = [value isEqualToString:@"fill"]
		? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
}
@end

static id check_objc(lua_State *L, int idx) {
	ObjCRef *ref = lua_objc_test_ref(L, idx);
	if (ref) return (__bridge id)ref->ptr;
	luaL_typeerror(L, idx, "uiview, uiwindow, or uiviewcontroller");
	return nil;
}

static UIView *check_view(lua_State *L, int idx) {
	id obj = check_objc(L, idx);
	return (UIView *)obj;
}
