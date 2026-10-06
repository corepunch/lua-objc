#pragma mark - Waveform view

#import <AVFAudio/AVFAudio.h>

/* A sound file drawn as its waveform under a tempo grid, with markers the
 * person places, selects and drags. The file is decoded once into a mono
 * copy; each draw reduces only the columns in the dirty rect to their
 * minimum and maximum, so a view inside a scroll view costs what is visible.
 * Marker placement snaps to the grid natively, while the drag is live; Lua
 * hears about a marker only when it is added, selected or dropped. */
@interface LuaWaveformView : LuaPointerView
@property (nonatomic, copy) NSString *source;
@property (nonatomic) double bpm;
@property (nonatomic) NSInteger beatsPerBar;
@property (nonatomic) NSInteger division;
@property (nonatomic) double gridOffset;
@property (nonatomic, copy) NSString *selectedId;
@property (nonatomic, readonly) double duration;
@property (nonatomic, strong) LuaReg *addReg;
@property (nonatomic, strong) LuaReg *selectReg;
@property (nonatomic, strong) LuaReg *moveReg;
@property (nonatomic, strong) LuaReg *zoomReg;
@property (nonatomic, strong) NSData *mono;
@property (nonatomic) double sampleRate;
@property (nonatomic, copy) NSArray<NSDictionary *> *markers;
@property (nonatomic, copy) NSString *draggingId;
@property (nonatomic) double dragTime;
@property (nonatomic) BOOL dragMoved;
/* Playback: the span being heard and "stopped", "playing" or "paused". */
@property (nonatomic) double playFrom;
@property (nonatomic) double playTo;
@property (nonatomic, copy) NSString *playState;
@property (nonatomic, strong) CALayer *playhead;
@property (nonatomic) double shownFrom;
@property (nonatomic) double shownTo;
@property (nonatomic, copy) NSString *shownState;
@property (nonatomic) double playElapsed;
@property (nonatomic) CFTimeInterval playResumedAt;
@end

@implementation LuaWaveformView
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) { _markers = @[]; _beatsPerBar = 4; _division = 4; _selectedId = @""; _playState = @"stopped"; _shownState = @"stopped"; }
	return self;
}
- (double)duration {
	return self.sampleRate > 0 ? (double)(self.mono.length / sizeof(float)) / self.sampleRate : 0;
}
- (void)setSource:(NSString *)source {
	if ([source isEqualToString:_source]) return;
	_source = [source copy];
	self.mono = nil;
	self.sampleRate = 0;
	if (source.length) [self load];
	[self setNeedsDisplay:YES];
}
/* Channels are averaged: the picture is for finding transients, and a mono
 * copy halves the memory of a stereo file. */
- (void)load {
	NSError *error = nil;
	AVAudioFile *file = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:self.source] error:&error];
	if (!file || file.length <= 0 || file.length > UINT32_MAX) return;
	AVAudioFormat *format = file.processingFormat;
	AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:(AVAudioFrameCount)file.length];
	if (!buffer || ![file readIntoBuffer:buffer error:&error] || !buffer.floatChannelData) return;
	AVAudioFrameCount frames = buffer.frameLength;
	NSUInteger channels = format.channelCount;
	NSMutableData *mono = [NSMutableData dataWithLength:frames * sizeof(float)];
	float *out = mono.mutableBytes;
	for (NSUInteger channel = 0; channel < channels; channel++) {
		const float *in = buffer.floatChannelData[channel];
		for (AVAudioFrameCount i = 0; i < frames; i++) out[i] += in[i] / channels;
	}
	self.mono = mono;
	self.sampleRate = format.sampleRate;
}
- (void)setBpm:(double)bpm { _bpm = bpm; [self setNeedsDisplay:YES]; }
- (void)setBeatsPerBar:(NSInteger)value { _beatsPerBar = MAX(1, value); [self setNeedsDisplay:YES]; }
- (void)setDivision:(NSInteger)value { _division = MAX(0, value); [self setNeedsDisplay:YES]; }
- (void)setGridOffset:(double)value { _gridOffset = value; [self setNeedsDisplay:YES]; }
/* Empty, never nil, when nothing is selected: a property that reads nil
 * looks absent to the template patcher. */
- (void)setSelectedId:(NSString *)value {
	_selectedId = [value copy] ?: @"";
	[self setNeedsDisplay:YES];
}
- (void)setMarkers:(NSArray<NSDictionary *> *)markers {
	_markers = [markers copy];
	[self setNeedsDisplay:YES];
	[self.window invalidateCursorRectsForView:self];
}
/* It has no natural width: it takes what it is offered (a fixed width when
 * zoomed). Without an intrinsic size the layout would read its last frame
 * back as its size, and a zoomed-in waveform could never fit again. */
- (NSSize)intrinsicContentSize { return NSMakeSize(0, kWaveformMinHeight); }
- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	[self.window invalidateCursorRectsForView:self];
}
- (void)viewDidChangeEffectiveAppearance {
	[super viewDidChangeEffectiveAppearance];
	[self setNeedsDisplay:YES];
	if (self.playhead) [self placePlayhead];
}

#pragma mark Playhead

/* The playhead is a layer that Core Animation moves from where playback is
 * to the span's end over the time left, so playing costs no timer and no
 * Lua. Each change of state, span or width places it again from the time
 * accumulated so far; pausing stops it where it is. */
- (void)setPlayFrom:(double)value { _playFrom = value; self.needsLayout = YES; }
- (void)setPlayTo:(double)value { _playTo = value; self.needsLayout = YES; }
- (void)setPlayState:(NSString *)value { _playState = value.length ? [value copy] : @"stopped"; self.needsLayout = YES; }
- (void)layout {
	[super layout];
	[self syncPlayhead];
}
- (double)playheadTime {
	double running = self.playResumedAt > 0 ? CACurrentMediaTime() - self.playResumedAt : 0;
	return self.playFrom + MIN(self.playElapsed + running, MAX(0, self.playTo - self.playFrom));
}
- (void)syncPlayhead {
	BOOL playing = [self.playState isEqualToString:@"playing"];
	BOOL paused = [self.playState isEqualToString:@"paused"];
	if ((!playing && !paused) || self.duration <= 0 || self.playTo <= self.playFrom) {
		[self.playhead removeFromSuperlayer];
		self.playhead = nil;
		self.shownState = @"stopped";
		self.playElapsed = 0;
		self.playResumedAt = 0;
		return;
	}
	BOOL sameRun = ![self.shownState isEqualToString:@"stopped"]
		&& self.shownFrom == self.playFrom && self.shownTo == self.playTo;
	if (sameRun) {
		self.playElapsed = [self playheadTime] - self.playFrom;
	} else {
		self.playElapsed = 0;
	}
	self.playResumedAt = playing ? CACurrentMediaTime() : 0;
	self.shownFrom = self.playFrom;
	self.shownTo = self.playTo;
	self.shownState = self.playState;
	[self placePlayhead];
}
- (void)placePlayhead {
	if (!self.playhead) {
		self.wantsLayer = YES;
		self.playhead = [CALayer layer];
		self.playhead.zPosition = 1;
		[self.layer addSublayer:self.playhead];
	}
	CGFloat height = self.bounds.size.height;
	CGFloat x = [self xAtTime:[self playheadTime]], end = [self xAtTime:self.playTo];
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	[self.playhead removeAllAnimations];
	[self.effectiveAppearance performAsCurrentDrawingAppearance:^{
		self.playhead.backgroundColor = NSColor.labelColor.CGColor;
	}];
	self.playhead.bounds = CGRectMake(0, 0, kWaveformPlayheadWidth, height);
	self.playhead.position = CGPointMake(x, height / 2);
	double remaining = self.playTo - [self playheadTime];
	if (self.playResumedAt > 0 && remaining > 0) {
		CABasicAnimation *move = [CABasicAnimation animationWithKeyPath:@"position.x"];
		move.fromValue = @(x);
		move.toValue = @(end);
		move.duration = remaining;
		move.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
		self.playhead.position = CGPointMake(end, height / 2);
		[self.playhead addAnimation:move forKey:@"play"];
	}
	[CATransaction commit];
}

#pragma mark Geometry

- (double)timeAtX:(CGFloat)x {
	double width = self.bounds.size.width;
	if (width <= 0 || self.duration <= 0) return 0;
	return MIN(MAX(x / width, 0), 1) * self.duration;
}
- (CGFloat)xAtTime:(double)time {
	return self.duration > 0 ? time / self.duration * self.bounds.size.width : 0;
}
/* The snap step is one grid division; a division of 0 places freely. */
- (double)snapStep {
	if (self.bpm <= 0 || self.division <= 0) return 0;
	return 60.0 / self.bpm / self.division;
}
- (double)snap:(double)time {
	double step = [self snapStep];
	if (step > 0) time = self.gridOffset + round((time - self.gridOffset) / step) * step;
	return MIN(MAX(time, 0), self.duration);
}
static double waveform_marker_time(NSDictionary *marker) {
	id value = marker[@"time"];
	return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
}
- (NSString *)markerIdAtX:(CGFloat)x {
	NSString *found = nil;
	CGFloat nearest = kWaveformMarkerHitWidth;
	for (NSDictionary *marker in self.markers) {
		CGFloat distance = fabs([self xAtTime:waveform_marker_time(marker)] - x);
		if (distance <= nearest) { nearest = distance; found = [marker[@"id"] description]; }
	}
	return found;
}
- (double)displayedTimeOf:(NSDictionary *)marker {
	if (self.draggingId && [[marker[@"id"] description] isEqualToString:self.draggingId]) return self.dragTime;
	return waveform_marker_time(marker);
}

#pragma mark Pointer

- (void)call:(LuaReg *)reg identifier:(NSString *)identifier time:(double)time context:(const char *)context {
	lua_State *L = lua_reg_live_state(reg);
	if (!L || !lua_reg_push(reg)) return;
	int count = 0;
	if (identifier) { lua_pushstring(L, identifier.UTF8String); count++; }
	if (!identifier || reg == self.moveReg) { lua_pushnumber(L, time); count++; }
	lua_objc_pcall(L, count, 0, context);
}
/* Pressing on a marker selects it and starts a drag; pressing anywhere else
 * adds a marker at the nearest grid line. */
- (void)pressAt:(CGFloat)x {
	self.draggingId = [self markerIdAtX:x];
	self.dragMoved = NO;
	if (self.draggingId) {
		for (NSDictionary *marker in self.markers)
			if ([[marker[@"id"] description] isEqualToString:self.draggingId]) self.dragTime = waveform_marker_time(marker);
		self.selectedId = self.draggingId;
		[self call:self.selectReg identifier:self.draggingId time:0 context:"waveform select"];
	} else if (self.duration > 0) {
		[self call:self.addReg identifier:nil time:[self snap:[self timeAtX:x]] context:"waveform add"];
	}
}
- (void)dragTo:(CGFloat)x {
	if (!self.draggingId) return;
	double time = [self snap:[self timeAtX:x]];
	if (time == self.dragTime) return;
	self.dragTime = time;
	self.dragMoved = YES;
	[self setNeedsDisplay:YES];
}
- (void)releaseAt:(CGFloat)x {
	(void)x;
	NSString *identifier = self.draggingId;
	self.draggingId = nil;
	if (identifier && self.dragMoved)
		[self call:self.moveReg identifier:identifier time:self.dragTime context:"waveform move"];
	[self setNeedsDisplay:YES];
}
- (void)mouseDown:(NSEvent *)event {
	if (self.keyReg) [self.window makeFirstResponder:self];
	[self pressAt:[self convertPoint:event.locationInWindow fromView:nil].x];
}
- (void)mouseDragged:(NSEvent *)event {
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	[self dragTo:point.x];
	[self autoscroll:event];
}
- (void)mouseUp:(NSEvent *)event {
	[self releaseAt:[self convertPoint:event.locationInWindow fromView:nil].x];
}
- (void)resetCursorRects {
	for (NSDictionary *marker in self.markers) {
		CGFloat x = [self xAtTime:waveform_marker_time(marker)];
		[self addCursorRect:NSMakeRect(x - kWaveformMarkerHitWidth, 0, 2 * kWaveformMarkerHitWidth, self.bounds.size.height)
			cursor:NSCursor.resizeLeftRightCursor];
	}
}

#pragma mark Zoom

/* A vertical wheel or a pinch zooms around the pointer; horizontal
 * scrolling stays the scroll view's. The width is the app's (it may fit
 * the window or stop at its closest zoom), so the view asks with
 * `onZoom(factor)`, lets the new width lay out, then scrolls so the time
 * under the pointer is under it again. */
- (void)zoomBy:(double)factor atX:(CGFloat)x {
	if (!self.zoomReg || self.duration <= 0 || factor <= 0 || factor == 1) return;
	NSClipView *clip = [self.superview isKindOfClass:NSClipView.class] ? (NSClipView *)self.superview : nil;
	double time = [self timeAtX:x];
	CGFloat offset = x - (clip ? clip.bounds.origin.x : 0);
	lua_State *L = lua_reg_live_state(self.zoomReg);
	if (!L || !lua_reg_push(self.zoomReg)) return;
	lua_pushnumber(L, factor);
	if (lua_objc_pcall(L, 1, 0, "waveform zoom") != LUA_OK) return;
	flush_pending_layout();
	if (!clip) return;
	CGFloat limit = MAX(0, self.frame.size.width - clip.bounds.size.width);
	CGFloat origin = MIN(MAX([self xAtTime:time] - offset, 0), limit);
	[clip scrollToPoint:NSMakePoint(origin, clip.bounds.origin.y)];
	[self.enclosingScrollView reflectScrolledClipView:clip];
}
- (void)scrollWheel:(NSEvent *)event {
	if (!self.zoomReg || fabs(event.scrollingDeltaY) <= fabs(event.scrollingDeltaX)) {
		[super scrollWheel:event];
		return;
	}
	// A notched wheel reports lines; a trackpad reports points.
	CGFloat delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : kWaveformZoomPointsPerLine);
	[self zoomBy:pow(kWaveformZoomPerPoint, delta) atX:[self convertPoint:event.locationInWindow fromView:nil].x];
}
- (void)magnifyWithEvent:(NSEvent *)event {
	[self zoomBy:1 + event.magnification atX:[self convertPoint:event.locationInWindow fromView:nil].x];
}

#pragma mark Drawing

- (void)drawGridIn:(NSRect)dirty height:(CGFloat)height {
	if (self.bpm <= 0 || self.duration <= 0) return;
	double beat = 60.0 / self.bpm;
	NSInteger perBeat = MAX(1, self.division);
	double step = beat / perBeat;
	double pointsPerSecond = self.bounds.size.width / self.duration;
	BOOL showSteps = step * pointsPerSecond >= kWaveformMinGridSpacing;
	BOOL showBeats = beat * pointsPerSecond >= kWaveformMinGridSpacing;
	BOOL showBarNumbers = beat * self.beatsPerBar * pointsPerSecond >= kWaveformMinBarLabelSpacing;
	NSDictionary *labelAttributes = @{
		NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:kWaveformLabelFontSize weight:NSFontWeightMedium],
		NSForegroundColorAttributeName: NSColor.secondaryLabelColor};
	NSInteger stepsPerBar = perBeat * self.beatsPerBar;
	long first = (long)floor(([self timeAtX:NSMinX(dirty) - kWaveformMinBarLabelSpacing] - self.gridOffset) / step);
	long last = (long)ceil(([self timeAtX:NSMaxX(dirty)] - self.gridOffset) / step);
	for (long index = MAX(first, (long)ceil(-self.gridOffset / step)); index <= last; index++) {
		CGFloat x = round([self xAtTime:self.gridOffset + index * step]) + 0.5;
		BOOL bar = index % stepsPerBar == 0;
		BOOL onBeat = index % perBeat == 0;
		if (!bar && !(onBeat ? showBeats : showSteps)) continue;
		CGFloat alpha = bar ? kWaveformBarLineAlpha : onBeat ? kWaveformBeatLineAlpha : kWaveformStepLineAlpha;
		[[NSColor.labelColor colorWithAlphaComponent:alpha] setFill];
		NSRectFillUsingOperation(NSMakeRect(x - 0.5, bar ? 0 : kWaveformRulerHeight, 1, height), NSCompositingOperationSourceOver);
		if (bar && showBarNumbers) {
			NSString *number = [NSString stringWithFormat:@"%ld", index / stepsPerBar + 1];
			[number drawAtPoint:NSMakePoint(x + kWaveformLabelInset, kWaveformLabelInset) withAttributes:labelAttributes];
		}
	}
}
- (void)drawSamplesIn:(NSRect)dirty top:(CGFloat)top height:(CGFloat)height {
	const float *samples = self.mono.bytes;
	NSUInteger frames = self.mono.length / sizeof(float);
	CGFloat width = self.bounds.size.width;
	if (!samples || !frames || width <= 0 || height <= 0) return;
	double framesPerPoint = frames / width;
	CGFloat middle = top + height / 2, half = height / 2;
	NSInteger from = MAX(0, (NSInteger)floor(NSMinX(dirty))), to = MIN((NSInteger)ceil(width), (NSInteger)ceil(NSMaxX(dirty)));
	if (to <= from) return;
	NSRect *rects = malloc(sizeof(NSRect) * (size_t)(to - from));
	NSInteger count = 0;
	for (NSInteger column = from; column < to; column++) {
		NSUInteger start = (NSUInteger)(column * framesPerPoint);
		NSUInteger end = MIN(frames, MAX(start + 1, (NSUInteger)((column + 1) * framesPerPoint)));
		if (start >= frames) break;
		float low = samples[start], high = samples[start];
		for (NSUInteger i = start + 1; i < end; i++) {
			if (samples[i] < low) low = samples[i];
			if (samples[i] > high) high = samples[i];
		}
		CGFloat y0 = middle - MIN(1, high) * half, y1 = middle - MAX(-1, low) * half;
		rects[count++] = NSMakeRect(column, y0, 1, MAX(kWaveformMinLineHeight, y1 - y0));
	}
	[[NSColor.secondaryLabelColor colorWithAlphaComponent:kWaveformSampleAlpha] setFill];
	NSRectFillListUsingOperation(rects, count, NSCompositingOperationSourceOver);
	free(rects);
}
- (void)drawRect:(NSRect)dirty {
	NSRect bounds = self.bounds;
	[NSColor.textBackgroundColor setFill];
	NSRectFill(dirty);
	if (self.duration <= 0) return;

	/* Every other slice is shaded, so the cuts read as pieces. */
	NSMutableArray<NSNumber *> *cuts = [NSMutableArray array];
	for (NSDictionary *marker in self.markers) [cuts addObject:@([self displayedTimeOf:marker])];
	[cuts sortUsingSelector:@selector(compare:)];
	[[NSColor.labelColor colorWithAlphaComponent:kWaveformSliceShadeAlpha] setFill];
	for (NSUInteger index = 0; index < cuts.count; index += 2) {
		CGFloat x0 = [self xAtTime:cuts[index].doubleValue];
		CGFloat x1 = index + 1 < cuts.count ? [self xAtTime:cuts[index + 1].doubleValue] : NSMaxX(bounds);
		NSRectFillUsingOperation(NSMakeRect(x0, kWaveformRulerHeight, x1 - x0, bounds.size.height - kWaveformRulerHeight),
			NSCompositingOperationSourceOver);
	}

	[self drawGridIn:dirty height:bounds.size.height];
	[NSColor.separatorColor setFill];
	NSRectFill(NSMakeRect(NSMinX(dirty), kWaveformRulerHeight - 1, dirty.size.width, 1));
	[self drawSamplesIn:dirty top:kWaveformRulerHeight + kWaveformVerticalInset
		height:bounds.size.height - kWaveformRulerHeight - 2 * kWaveformVerticalInset];

	NSDictionary *numberAttributes = @{
		NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:kWaveformLabelFontSize weight:NSFontWeightSemibold],
		NSForegroundColorAttributeName: NSColor.labelColor};
	/* Slice numbers match the exported files: a slice starts at the file's
	 * start and at every cut, and empty slices (two cuts on one grid line, a
	 * cut at either end) are skipped, as the export skips them. */
	NSMutableArray<NSNumber *> *starts = [NSMutableArray arrayWithObject:@0];
	for (NSNumber *cut in cuts)
		if (cut.doubleValue > starts.lastObject.doubleValue && cut.doubleValue < self.duration) [starts addObject:cut];
	for (NSUInteger index = 0; index < starts.count; index++) {
		CGFloat x = [self xAtTime:starts[index].doubleValue];
		NSString *label = [NSString stringWithFormat:@"%lu", (unsigned long)index + 1];
		NSSize size = [label sizeWithAttributes:numberAttributes];
		[label drawAtPoint:NSMakePoint(x + kWaveformLabelInset, NSMaxY(bounds) - size.height - kWaveformLabelInset)
			withAttributes:numberAttributes];
	}
	for (NSDictionary *marker in self.markers) {
		BOOL selected = [[marker[@"id"] description] isEqualToString:self.selectedId];
		CGFloat x = round([self xAtTime:[self displayedTimeOf:marker]]);
		CGFloat lineWidth = selected ? kWaveformSelectedMarkerWidth : kWaveformMarkerWidth;
		NSColor *color = selected ? NSColor.controlAccentColor : NSColor.systemOrangeColor;
		[color setFill];
		NSRectFill(NSMakeRect(x - lineWidth / 2, 0, lineWidth, bounds.size.height));
		NSBezierPath *handle = [NSBezierPath bezierPath];
		[handle moveToPoint:NSMakePoint(x - kWaveformHandleSize / 2, 0)];
		[handle lineToPoint:NSMakePoint(x + kWaveformHandleSize / 2, 0)];
		[handle lineToPoint:NSMakePoint(x, kWaveformHandleSize)];
		[handle closePath];
		[handle fill];
	}
}
@end

// _waveform(onAdd, onSelect, onMove, onKey, onZoom): onAdd(time),
// onSelect(id), onMove(id, time), onKey(view, key) -> handled, onZoom(factor).
static int bridge_waveform(lua_State *L) {
	LuaWaveformView *view = [[LuaWaveformView alloc] initWithFrame:NSZeroRect];
	view.addReg = lua_reg_opt(L, 1);
	view.selectReg = lua_reg_opt(L, 2);
	view.moveReg = lua_reg_opt(L, 3);
	view.keyReg = lua_reg_opt(L, 4);
	view.zoomReg = lua_reg_opt(L, 5);
	push_objc(L, view, "nsview");
	return 1;
}

// _waveformMarkers(view, {{id =, time =}, ...})
static int bridge_waveform_markers(lua_State *L) {
	LuaWaveformView *view = lua_objc_check_object(L, 1, [LuaWaveformView class], "waveform");
	id value = lua_to_objc_value(L, 2);
	view.markers = [value isKindOfClass:NSArray.class] ? value : @[];
	return 0;
}

// Test hook: _waveformSend(view, "press" | "drag" | "release", x),
// _waveformSend(view, "zoom", x, factor) and _waveformSend(view, "duration")
// -> seconds.
static int bridge_waveform_send(lua_State *L) {
	LuaWaveformView *view = lua_objc_check_object(L, 1, [LuaWaveformView class], "waveform");
	const char *kind = luaL_checkstring(L, 2);
	if (strcmp(kind, "duration") == 0) { lua_pushnumber(L, view.duration); return 1; }
	// "playhead" -> seconds where the playhead is (nil when hidden), moving
	if (strcmp(kind, "playhead") == 0) {
		[view syncPlayhead];
		if (view.playhead) lua_pushnumber(L, [view playheadTime]); else lua_pushnil(L);
		lua_pushboolean(L, view.playResumedAt > 0);
		return 2;
	}
	// "scrolled" -> the visible origin's x in a scroll view
	if (strcmp(kind, "scrolled") == 0) {
		NSClipView *clip = [view.superview isKindOfClass:NSClipView.class] ? (NSClipView *)view.superview : nil;
		lua_pushnumber(L, clip ? clip.bounds.origin.x : 0);
		return 1;
	}
	CGFloat x = luaL_checknumber(L, 3);
	if (strcmp(kind, "zoom") == 0) { [view zoomBy:luaL_checknumber(L, 4) atX:x]; return 0; }
	if (strcmp(kind, "press") == 0) [view pressAt:x];
	else if (strcmp(kind, "drag") == 0) [view dragTo:x];
	else if (strcmp(kind, "release") == 0) [view releaseAt:x];
	else return luaL_error(L, "unknown waveform event %s", kind);
	return 0;
}
