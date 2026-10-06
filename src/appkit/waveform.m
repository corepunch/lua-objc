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
@property (nonatomic, strong) NSData *mono;
@property (nonatomic) double sampleRate;
@property (nonatomic, copy) NSArray<NSDictionary *> *markers;
@property (nonatomic, copy) NSString *draggingId;
@property (nonatomic) double dragTime;
@property (nonatomic) BOOL dragMoved;
@end

@implementation LuaWaveformView
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) { _markers = @[]; _beatsPerBar = 4; _division = 4; _selectedId = @""; }
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

// _waveform(onAdd, onSelect, onMove, onKey): onAdd(time), onSelect(id),
// onMove(id, time), onKey(view, key) -> handled.
static int bridge_waveform(lua_State *L) {
	LuaWaveformView *view = [[LuaWaveformView alloc] initWithFrame:NSZeroRect];
	view.addReg = lua_reg_opt(L, 1);
	view.selectReg = lua_reg_opt(L, 2);
	view.moveReg = lua_reg_opt(L, 3);
	view.keyReg = lua_reg_opt(L, 4);
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

// Test hook: _waveformSend(view, "press" | "drag" | "release", x) and
// _waveformSend(view, "duration") -> seconds.
static int bridge_waveform_send(lua_State *L) {
	LuaWaveformView *view = lua_objc_check_object(L, 1, [LuaWaveformView class], "waveform");
	const char *kind = luaL_checkstring(L, 2);
	if (strcmp(kind, "duration") == 0) { lua_pushnumber(L, view.duration); return 1; }
	CGFloat x = luaL_checknumber(L, 3);
	if (strcmp(kind, "press") == 0) [view pressAt:x];
	else if (strcmp(kind, "drag") == 0) [view dragTo:x];
	else if (strcmp(kind, "release") == 0) [view releaseAt:x];
	else return luaL_error(L, "unknown waveform event %s", kind);
	return 0;
}
