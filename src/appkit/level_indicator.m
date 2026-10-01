#pragma mark - LuaLevelIndicator

/* SwiftUI `Gauge` with `.linearCapacity`: AppKit's continuous capacity level
 * indicator, read-only and without warning thresholds.
 *
 * NSLevelIndicator reports a 16 pt intrinsic height, but its cell draws an
 * 18 pt capsule centred in the frame. Any shorter frame clips the capsule's
 * top edge, leaving rounded corners only at the bottom. Report the cell's own
 * size so layout never proposes a frame the native drawing does not fit. */
/* The capsule is drawn by the cell: NSLevelIndicator draws through its cell
 * whatever the view's drawRect: says. */
@interface LuaLevelIndicatorCell : NSLevelIndicatorCell
@property (nonatomic) CGFloat thickness;
@end

@implementation LuaLevelIndicatorCell

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
	if (self.thickness <= 0) {
		[super drawWithFrame:cellFrame inView:controlView];
		return;
	}
	CGFloat height = MIN(self.thickness, NSHeight(cellFrame));
	NSRect track = NSMakeRect(NSMinX(cellFrame), NSMidY(cellFrame) - height / 2, NSWidth(cellFrame), height);
	CGFloat radius = height / 2;
	NSBezierPath *capsule = [NSBezierPath bezierPathWithRoundedRect:track xRadius:radius yRadius:radius];
	[[NSColor tertiarySystemFillColor] setFill];
	[capsule fill];
	double span = self.maxValue - self.minValue;
	double fraction = span > 0 ? (self.doubleValue - self.minValue) / span : 0;
	if (!(fraction > 0)) return;
	/* The fill is a capsule of its own, at least as wide as it is tall, so a
	 * small value still reads as a rounded mark, clipped to the track. */
	CGFloat width = MAX(height, NSWidth(track) * MIN(1, fraction));
	NSRect fill = NSMakeRect(NSMinX(track), NSMinY(track), width, height);
	NSColor *tint = ((NSLevelIndicator *)controlView).fillColor ?: [NSColor controlAccentColor];
	if (!self.isEnabled) tint = [tint colorWithAlphaComponent:tint.alphaComponent * kGaugeDisabledFillAlpha];
	[NSGraphicsContext saveGraphicsState];
	[capsule addClip];
	[tint setFill];
	[[NSBezierPath bezierPathWithRoundedRect:fill xRadius:radius yRadius:radius] fill];
	[NSGraphicsContext restoreGraphicsState];
}

@end

@interface LuaLevelIndicator : NSLevelIndicator
/* 0 draws AppKit's own 18 pt capacity cell. A positive thickness draws the
 * bar the way SwiftUI's `.linearCapacity` Gauge does: a capsule track in the
 * system fill colour with a capsule fill in the tint, `thickness` points
 * tall. AppKit's cell has no thinner size at any control size, so the bar is
 * drawn here; the view stays an NSLevelIndicator, so its value, range and
 * accessibility role are unchanged. */
@property (nonatomic) CGFloat thickness;
@end

@implementation LuaLevelIndicator

+ (Class)cellClass {
	return [LuaLevelIndicatorCell class];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		self.levelIndicatorStyle = NSLevelIndicatorStyleContinuousCapacity;
		self.minValue = 0;
		self.maxValue = 1;
		self.warningValue = kGaugeNoThreshold;
		self.criticalValue = kGaugeNoThreshold;
		self.editable = NO;
	}
	return self;
}

/* A gauge shows what it is given: a value outside its range fills or
 * empties it, and one that is not a number is no value. */
- (void)setDoubleValue:(double)value {
	[super setDoubleValue:isfinite(value) ? MAX(self.minValue, MIN(self.maxValue, value)) : self.minValue];
}

- (NSSize)intrinsicContentSize {
	if (self.thickness > 0) return NSMakeSize(NSViewNoIntrinsicMetric, ceil(self.thickness));
	return NSMakeSize(NSViewNoIntrinsicMetric, ceil(self.cell.cellSize.height));
}

- (void)setThickness:(CGFloat)thickness {
	_thickness = MAX(0, thickness);
	if ([self.cell isKindOfClass:[LuaLevelIndicatorCell class]]) ((LuaLevelIndicatorCell *)self.cell).thickness = _thickness;
	[self invalidateIntrinsicContentSize];
	[self setNeedsDisplay:YES];
}

@end
