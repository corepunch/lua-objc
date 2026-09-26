#pragma mark - LuaPathView

@interface LuaPathView : NSView
@property (nonatomic, strong) NSBezierPath *path;
@property (nonatomic, strong) NSColor *strokeColor;
@property (nonatomic, strong) NSColor *fillColor;
@property (nonatomic) CGFloat lineWidth;
@property (nonatomic) NSSize pathSize;
@property (nonatomic) BOOL scalesToFit;
@property (nonatomic, readonly) BOOL closed;
@end

@implementation LuaPathView

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		_path = [[NSBezierPath alloc] init];
		_strokeColor = [NSColor controlAccentColor];
		_fillColor = nil;
		_lineWidth = 1.0;
		_pathSize = frameRect.size;
		_scalesToFit = NO;
	}
	return self;
}

- (void)drawRect:(NSRect)dirtyRect {
	[super drawRect:dirtyRect];
	NSBezierPath *drawPath = [_path copy];
	if (_scalesToFit && _pathSize.width > 0 && _pathSize.height > 0) {
		NSAffineTransform *transform = [NSAffineTransform transform];
		[transform scaleXBy:self.bounds.size.width / _pathSize.width
			yBy:self.bounds.size.height / _pathSize.height];
		[drawPath transformUsingAffineTransform:transform];
	}
	if (_fillColor) {
		[_fillColor setFill];
		[drawPath fill];
	}
	if (_strokeColor && _lineWidth > 0) {
		[_strokeColor setStroke];
		drawPath.lineWidth = _lineWidth;
		[drawPath stroke];
	}
}

- (BOOL)closed {
	if (_path.elementCount == 0) return NO;
	return [_path elementAtIndex:_path.elementCount - 1] == NSBezierPathElementClosePath;
}

- (BOOL)isFlipped {
	return YES;
}

@end

#include <math.h>

static void push_NSRect(lua_State *L, NSRect value);

/* Screen-clockwise degrees from east, in a y-down view. Equal endpoints
 * close the circle so a track can be one arc. */
static CGFloat arc_normalize_degrees(CGFloat degrees) {
	CGFloat wrapped = fmod(degrees, 360.0);
	if (wrapped < 0) wrapped += 360.0;
	return wrapped;
}

static void arc_add_clockwise(NSBezierPath *path, NSPoint center, CGFloat radius,
		CGFloat startDegrees, CGFloat sweepDegrees) {
	CGFloat angle = startDegrees;
	CGFloat remaining = sweepDegrees;
	BOOL moved = path.elementCount > 0;
	while (remaining > 0.01) {
		CGFloat step = MIN(90.0, remaining);
		CGFloat a1 = angle * M_PI / 180.0;
		CGFloat a2 = (angle + step) * M_PI / 180.0;
		CGFloat handle = (4.0 / 3.0) * tan((a2 - a1) / 4.0);
		NSPoint start = NSMakePoint(center.x + radius * cos(a1), center.y + radius * sin(a1));
		NSPoint end = NSMakePoint(center.x + radius * cos(a2), center.y + radius * sin(a2));
		NSPoint tangentStart = NSMakePoint(-sin(a1), cos(a1));
		NSPoint tangentEnd = NSMakePoint(-sin(a2), cos(a2));
		if (!moved) {
			[path moveToPoint:start];
			moved = YES;
		}
		[path curveToPoint:end
			controlPoint1:NSMakePoint(start.x + handle * radius * tangentStart.x,
				start.y + handle * radius * tangentStart.y)
			controlPoint2:NSMakePoint(end.x - handle * radius * tangentEnd.x,
				end.y - handle * radius * tangentEnd.y)];
		angle += step;
		remaining -= step;
	}
}

static NSColor *semantic_color(NSString *name);

@interface LuaArcView : NSView
@property(nonatomic) CGFloat startAngle;
@property(nonatomic) CGFloat endAngle;
@property(nonatomic) CGFloat lineWidth;
@property(nonatomic) CGFloat strokeAlpha;
@property(nonatomic, copy) NSString *stroke;
@property(nonatomic, copy) NSString *lineCap;
- (NSBezierPath *)arcPath;
@end

/* SwiftUI strokes a shape centered on its path and never clips it to the
 * frame, so an Arc stroke extends lineWidth/2 past its bounds. drawRect is
 * clipped to the view; its backing CAShapeLayer is not. */
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

- (NSBezierPath *)arcPath {
	NSRect bounds = self.bounds;
	NSPoint center = NSMakePoint(NSMidX(bounds), NSMidY(bounds));
	CGFloat radius = MIN(bounds.size.width, bounds.size.height) / 2.0;
	NSBezierPath *path = [NSBezierPath bezierPath];
	if (radius <= 0) return path;
	CGFloat start = arc_normalize_degrees(self.startAngle);
	CGFloat end = arc_normalize_degrees(self.endAngle);
	CGFloat sweep = end - start;
	if (sweep <= 0) sweep += 360.0;
	if (sweep >= kArcFullCircleDegrees) {
		[path appendBezierPathWithOvalInRect:NSMakeRect(
			center.x - radius, center.y - radius, radius * 2.0, radius * 2.0)];
	} else {
		arc_add_clockwise(path, center, radius, start, sweep);
	}
	path.lineWidth = self.lineWidth;
	path.lineCapStyle = [self.lineCap isEqualToString:@"round"]
		? NSLineCapStyleRound : NSLineCapStyleButt;
	return path;
}

- (void)updateShape {
	CAShapeLayer *shape = (CAShapeLayer *)self.layer;
	if (![shape isKindOfClass:CAShapeLayer.class]) return;
	// arcPath is in this flipped view's coordinates; match the layer's.
	CGPathRef path = self.arcPath.CGPath;
	if (!shape.geometryFlipped) {
		CGAffineTransform flip = CGAffineTransformMake(1, 0, 0, -1, 0, self.bounds.size.height);
		shape.path = CFAutorelease(CGPathCreateCopyByTransformingPath(path, &flip));
	} else {
		shape.path = path;
	}
	shape.fillColor = nil;
	shape.lineWidth = self.lineWidth;
	shape.lineCap = [self.lineCap isEqualToString:@"round"] ? kCALineCapRound : kCALineCapButt;
	shape.masksToBounds = NO;
	[self.effectiveAppearance performAsCurrentDrawingAppearance:^{
		// Label colors carry their own translucency (tertiary, quaternary);
		// strokeAlpha scales it rather than replacing it with opaque ink.
		NSColor *color = [semantic_color(self.stroke ?: @"accent")
			colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
		shape.strokeColor = [color colorWithAlphaComponent:
			color.alphaComponent * MIN(1, MAX(0, self.strokeAlpha))].CGColor;
	}];
}

- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; [self updateShape]; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self updateShape]; }
- (void)setStartAngle:(CGFloat)value { _startAngle = value; [self updateShape]; }
- (void)setEndAngle:(CGFloat)value { _endAngle = value; [self updateShape]; }
- (void)setLineWidth:(CGFloat)value { _lineWidth = value; [self updateShape]; }
- (void)setStrokeAlpha:(CGFloat)value { _strokeAlpha = value; [self updateShape]; }
- (void)setStroke:(NSString *)value { _stroke = [value copy]; [self updateShape]; }
- (void)setLineCap:(NSString *)value { _lineCap = [value copy]; [self updateShape]; }

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
		kCGImageAlphaPremultipliedLast);
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

static int bridge_LuaArcView_arcBounds(lua_State *L) {
	LuaArcView *view = lua_objc_check_object(L, 1, [LuaArcView class], "Arc");
	push_NSRect(L, view.arcPath.bounds);
	return 1;
}
