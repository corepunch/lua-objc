#pragma mark - LuaPathView

@interface LuaPathView : NSView
@property (nonatomic, strong) NSBezierPath *path;
@property (nonatomic, strong) NSColor *strokeColor;
@property (nonatomic, strong) NSColor *fillColor;
@property (nonatomic) CGFloat lineWidth;
@end

@implementation LuaPathView

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		_path = [[NSBezierPath alloc] init];
		_strokeColor = [NSColor controlAccentColor];
		_fillColor = nil;
		_lineWidth = 1.0;
	}
	return self;
}

- (void)drawRect:(NSRect)dirtyRect {
	[super drawRect:dirtyRect];
	if (_fillColor) {
		[_fillColor setFill];
		[_path fill];
	}
	if (_strokeColor && _lineWidth > 0) {
		[_strokeColor setStroke];
		_path.lineWidth = _lineWidth;
		[_path stroke];
	}
}

- (BOOL)isFlipped {
	return YES;
}

@end
