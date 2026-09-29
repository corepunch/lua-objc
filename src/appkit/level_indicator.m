#pragma mark - LuaLevelIndicator

/* SwiftUI `Gauge` with `.linearCapacity`: AppKit's continuous capacity level
 * indicator, read-only and without warning thresholds.
 *
 * NSLevelIndicator reports a 16 pt intrinsic height, but its cell draws an
 * 18 pt capsule centred in the frame. Any shorter frame clips the capsule's
 * top edge, leaving rounded corners only at the bottom. Report the cell's own
 * size so layout never proposes a frame the native drawing does not fit. */
@interface LuaLevelIndicator : NSLevelIndicator
@end

@implementation LuaLevelIndicator

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
	return NSMakeSize(NSViewNoIntrinsicMetric, ceil(self.cell.cellSize.height));
}

@end
