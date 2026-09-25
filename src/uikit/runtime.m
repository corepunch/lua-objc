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
@property(nonatomic) CGFloat paddingLeading;
@property(nonatomic) CGFloat paddingTrailing;
@property(nonatomic) CGFloat paddingVertical;
@property(nonatomic) CGFloat paddingTop;
@property(nonatomic) CGFloat paddingBottom;
@property(nonatomic, copy) NSString *alignment;
@property(nonatomic) CGFloat fixedWidth;
@property(nonatomic) CGFloat fixedHeight;
@property(nonatomic) CGFloat minWidth;
@property(nonatomic) CGFloat minHeight;
@property(nonatomic) NSNumber *maxWidth;
@property(nonatomic) NSNumber *maxHeight;
@property(nonatomic) CGFloat spacing;
@property(nonatomic) NSInteger maxRows;
@property(nonatomic) CGFloat flexGrow;
@property(nonatomic) CGFloat flexShrink;
@property(nonatomic) NSNumber *flexBasis;
@property(nonatomic) BOOL fillWidth;
@property(nonatomic) BOOL allowsHitTesting;
@property(nonatomic) BOOL fillHeight;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic, copy) NSString *ignoresSafeArea;
@property(nonatomic, copy) NSString *contentModeName;
@property(nonatomic) BOOL safeAreaInsetBottom;
@property(nonatomic) CGFloat minimumBottomInset;
@property(nonatomic) CGFloat offsetX;
@property(nonatomic) CGFloat offsetY;
@end

@implementation UIView (LuaLayoutProperties)
- (BOOL)allowsHitTesting { return self.userInteractionEnabled; }
- (void)setAllowsHitTesting:(BOOL)value { self.userInteractionEnabled = value; }
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
- (CGFloat)paddingLeading { return [objc_getAssociatedObject(self, &kPaddingLeadingKey) doubleValue]; }
- (void)setPaddingLeading:(CGFloat)value { objc_setAssociatedObject(self, &kPaddingLeadingKey, @(MAX(0, value)), OBJC_ASSOCIATION_RETAIN); }
- (CGFloat)paddingTrailing { return [objc_getAssociatedObject(self, &kPaddingTrailingKey) doubleValue]; }
- (void)setPaddingTrailing:(CGFloat)value { objc_setAssociatedObject(self, &kPaddingTrailingKey, @(MAX(0, value)), OBJC_ASSOCIATION_RETAIN); }
- (CGFloat)paddingTop { return [objc_getAssociatedObject(self, &kPaddingTopKey) doubleValue]; }
- (void)setPaddingTop:(CGFloat)value { objc_setAssociatedObject(self, &kPaddingTopKey, @(MAX(0, value)), OBJC_ASSOCIATION_RETAIN); }
- (CGFloat)paddingBottom { return [objc_getAssociatedObject(self, &kPaddingBottomKey) doubleValue]; }
- (void)setPaddingBottom:(CGFloat)value { objc_setAssociatedObject(self, &kPaddingBottomKey, @(MAX(0, value)), OBJC_ASSOCIATION_RETAIN); }
- (BOOL)safeAreaInsetBottom { return [objc_getAssociatedObject(self, &kSafeAreaInsetBottomKey) boolValue]; }
- (void)setSafeAreaInsetBottom:(BOOL)value { objc_setAssociatedObject(self, &kSafeAreaInsetBottomKey, @(value), OBJC_ASSOCIATION_RETAIN); }
- (CGFloat)minimumBottomInset { return [objc_getAssociatedObject(self, &kMinimumBottomInsetKey) doubleValue]; }
- (void)setMinimumBottomInset:(CGFloat)value { objc_setAssociatedObject(self, &kMinimumBottomInsetKey, @(MAX(0, value)), OBJC_ASSOCIATION_RETAIN); }
- (CGFloat)offsetX { return self.transform.tx; }
- (void)setOffsetX:(CGFloat)value {
	CGAffineTransform transform = self.transform;
	transform.tx = value;
	self.transform = transform;
}
- (CGFloat)offsetY { return self.transform.ty; }
- (void)setOffsetY:(CGFloat)value {
	CGAffineTransform transform = self.transform;
	transform.ty = value;
	self.transform = transform;
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
- (NSInteger)maxRows { return [objc_getAssociatedObject(self, &kFlowMaxRowsKey) integerValue]; }
- (void)setMaxRows:(NSInteger)value { objc_setAssociatedObject(self, &kFlowMaxRowsKey, @(MAX(0, value)), OBJC_ASSOCIATION_RETAIN); }
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
- (NSString *)ignoresSafeArea { return objc_getAssociatedObject(self, &kIgnoresSafeAreaKey); }
- (void)setIgnoresSafeArea:(NSString *)value {
	objc_setAssociatedObject(self, &kIgnoresSafeAreaKey, value, OBJC_ASSOCIATION_COPY);
}
- (NSString *)contentModeName {
	switch (self.contentMode) {
		case UIViewContentModeScaleAspectFill: return @"fill";
		case UIViewContentModeScaleToFill: return @"stretch";
		case UIViewContentModeCenter: return @"center";
		default: return @"fit";
	}
}
- (void)setContentModeName:(NSString *)value {
	if (![self isKindOfClass:UIImageView.class]) return;
	self.contentMode = [value isEqualToString:@"fill"] ? UIViewContentModeScaleAspectFill
		: ([value isEqualToString:@"stretch"] ? UIViewContentModeScaleToFill
		: ([value isEqualToString:@"center"] ? UIViewContentModeCenter : UIViewContentModeScaleAspectFit));
}
@end

static id check_objc(lua_State *L, int idx) {
	ObjCRef *ref = lua_objc_test_ref(L, idx);
	if (!ref) {
		luaL_typeerror(L, idx, "uiview, uiwindow, or uiviewcontroller");
		return nil;
	}
	return lua_objc_live_ptr(L, idx, ref);
}

static UIView *check_view(lua_State *L, int idx) {
	id obj = check_objc(L, idx);
	return (UIView *)obj;
}

/* Native value userdata helpers (CGSize, CGPoint, CGRect). */
#define GEN_STRUCT_HELPERS
#include "structs.m"
#undef GEN_STRUCT_HELPERS

static void push_kvc_value(lua_State *L, id value) {
	if ([value isKindOfClass:[NSValue class]]) {
		const char *type = ((NSValue *)value).objCType;
		if (strcmp(type, @encode(CGSize)) == 0) {
			push_CGSize(L, ((NSValue *)value).CGSizeValue);
			return;
		}
		if (strcmp(type, @encode(CGPoint)) == 0) {
			push_CGPoint(L, ((NSValue *)value).CGPointValue);
			return;
		}
		if (strcmp(type, @encode(CGRect)) == 0) {
			push_CGRect(L, ((NSValue *)value).CGRectValue);
			return;
		}
	}
	push_objc_value(L, value);
}

static id lua_to_kvc_value(lua_State *L, int idx) {
	CGSize *size = luaL_testudata(L, idx, "lua_objc.struct.CGSize");
	if (size) return [NSValue valueWithCGSize:*size];
	CGPoint *point = luaL_testudata(L, idx, "lua_objc.struct.CGPoint");
	if (point) return [NSValue valueWithCGPoint:*point];
	CGRect *rect = luaL_testudata(L, idx, "lua_objc.struct.CGRect");
	if (rect) return [NSValue valueWithCGRect:*rect];
	return lua_to_objc_value(L, idx);
}
