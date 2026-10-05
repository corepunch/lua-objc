#pragma mark - LuaArcView

static void push_NSRect(lua_State *L, NSRect value);
static NSColor *semantic_color(NSString *name);

/* An arc or sector as a filled CAShapeLayer path. Shape and color changes
 * apply immediately. The layer is not clipped: a stroke may extend beyond
 * the view's frame. */
@interface LuaArcView ()
@property(nonatomic) CGFloat startAngle;
@property(nonatomic) CGFloat endAngle;
@property(nonatomic) CGFloat lineWidth;
@property(nonatomic) CGFloat strokeAlpha;
@property(nonatomic, copy) NSString *stroke;
@property(nonatomic, copy) NSString *lineCap;
@property(nonatomic) CGFloat diameter;
@property(nonatomic) CGFloat fitDiameter;
@property(nonatomic) CGFloat inset;
@property(nonatomic) CGFloat cornerRadius;
- (ArcShape)shape;
@end

@implementation LuaArcView

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		_lineWidth = 1;
		_strokeAlpha = 1;
		_stroke = @"accent";
		_lineCap = @"butt";
		self.wantsLayer = YES;
		self.clipsToBounds = NO;
		[self updateShape];
	}
	return self;
}

- (CALayer *)makeBackingLayer { return [CAShapeLayer layer]; }
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }

- (ArcShape)shape {
	return (ArcShape){self.startAngle, self.endAngle, self.lineWidth, self.diameter, self.fitDiameter,
		self.inset, self.cornerRadius, [self.lineCap isEqualToString:@"round"]};
}

/* The path in the backing layer's coordinates, which are not flipped. */
- (CGPathRef)copyLayerPath:(ArcShape)shape {
	CGPathRef path = arc_path_create(self.bounds, shape);
	if (!path || ((CAShapeLayer *)self.layer).geometryFlipped) return path;
	CGAffineTransform flip = CGAffineTransformMake(1, 0, 0, -1, 0, self.bounds.size.height);
	CGPathRef flipped = CGPathCreateCopyByTransformingPath(path, &flip);
	CGPathRelease(path);
	return flipped;
}

- (void)updateShape {
	CAShapeLayer *layer = (CAShapeLayer *)self.layer;
	if (![layer isKindOfClass:CAShapeLayer.class]) return;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	ArcShape shape = self.shape;
	CGPathRef path = [self copyLayerPath:shape];
	layer.path = path;
	if (path) CGPathRelease(path);
	layer.fillRule = kCAFillRuleEvenOdd;
	layer.masksToBounds = NO;
	[self.effectiveAppearance performAsCurrentDrawingAppearance:^{
		// Label colors carry their own translucency (tertiary, quaternary);
		// strokeAlpha scales it rather than replacing it with opaque ink.
		NSColor *color = [semantic_color(self.stroke ?: @"accent")
			colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
		layer.fillColor = [color colorWithAlphaComponent:
			color.alphaComponent * MIN(1, MAX(0, self.strokeAlpha))].CGColor;
	}];
	[CATransaction commit];
}

- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; [self updateShape]; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self updateShape]; }
- (void)setStartAngle:(CGFloat)value { _startAngle = value; [self updateShape]; }
- (void)setEndAngle:(CGFloat)value { _endAngle = value; [self updateShape]; }
- (void)setLineWidth:(CGFloat)value { _lineWidth = value; [self updateShape]; }
- (void)setStrokeAlpha:(CGFloat)value { _strokeAlpha = value; [self updateShape]; }
- (void)setStroke:(NSString *)value { _stroke = [value copy]; [self updateShape]; }
- (void)setLineCap:(NSString *)value { _lineCap = [value copy]; [self updateShape]; }
- (void)setDiameter:(CGFloat)value { _diameter = value; [self updateShape]; }
- (void)setFitDiameter:(CGFloat)value { _fitDiameter = value; [self updateShape]; }
- (void)setInset:(CGFloat)value { _inset = value; [self updateShape]; }
- (void)setCornerRadius:(CGFloat)value { _cornerRadius = value; [self updateShape]; }

@end

// Test hook: ink bounds of the Arc's rendered layer in view coordinates
// (y down), on a canvas extended by `margin` so unclipped strokes show, and
// the peak ink alpha (0...1) so translucent strokes can be told from opaque.
static int bridge_arc_ink_bounds(lua_State *L) {
	LuaArcView *view = lua_objc_check_object(L, 1, [LuaArcView class], "Arc");
	CGFloat margin = luaL_optnumber(L, 2, 8);
	[view updateShape];
	NSInteger width = (NSInteger)ceil(view.bounds.size.width + margin * 2);
	NSInteger height = (NSInteger)ceil(view.bounds.size.height + margin * 2);
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
		(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(space);
	// Render the real backing layer, shifted by the margin, so clipping or a
	// wrong orientation shows up in the ink. Bitmap row 0 is the top.
	CGContextTranslateCTM(context, margin, margin);
	// renderInContext ignores the root layer's own geometryFlipped; apply it
	// so the ink matches what the window shows.
	if (view.layer.geometryFlipped) {
		CGContextTranslateCTM(context, 0, view.bounds.size.height);
		CGContextScaleCTM(context, 1, -1);
	}
	[view.layer renderInContext:context];
	const uint8_t *pixels = CGBitmapContextGetData(context);
	NSInteger minX = width, minY = height, maxX = -1, maxY = -1;
	uint8_t peak = 0;
	for (NSInteger y = 0; y < height; y++)
		for (NSInteger x = 0; x < width; x++) {
			uint8_t alpha = pixels[(y * width + x) * 4 + 3];
			peak = MAX(peak, alpha);
			if (alpha > 12) {
				minX = MIN(minX, x); maxX = MAX(maxX, x);
				minY = MIN(minY, y); maxY = MAX(maxY, y);
			}
		}
	CGContextRelease(context);
	if (maxX < 0) { lua_pushnil(L); return 1; }
	// Bitmap rows run top-down in memory; report y-down view coordinates.
	push_NSRect(L, NSMakeRect(minX - margin, minY - margin, maxX - minX + 1, maxY - minY + 1));
	lua_pushnumber(L, peak / 255.0);
	return 2;
}

static int bridge_arc(lua_State *L) {
	CGFloat width = (CGFloat)luaL_optnumber(L, 1, 48);
	CGFloat height = (CGFloat)luaL_optnumber(L, 2, width);
	LuaArcView *view = [[LuaArcView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	push_objc(L, view, "nsview");
	return 1;
}

// The drawn outline's bounds in view coordinates (y down).
static int bridge_LuaArcView_arcBounds(lua_State *L) {
	LuaArcView *view = lua_objc_check_object(L, 1, [LuaArcView class], "Arc");
	CGPathRef path = arc_path_create(view.bounds, view.shape);
	push_NSRect(L, path ? CGPathGetPathBoundingBox(path) : NSZeroRect);
	if (path) CGPathRelease(path);
	return 1;
}
