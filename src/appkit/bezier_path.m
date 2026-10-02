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
