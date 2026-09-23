/* Device-only benchmark probe: drive native scrolling and report display cadence. */
#import <mach/mach.h>

@interface LuaBenchmarkScroll : NSObject
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, strong) CADisplayLink *link;
@property(nonatomic, weak) UIScrollView *scroll;
@property(nonatomic, copy) NSString *kind;
@property(nonatomic) NSInteger rowCount;
@property(nonatomic) CFTimeInterval createdAt;
@property(nonatomic) CFTimeInterval firstFrameAt;
@property(nonatomic) CFTimeInterval previousFrameAt;
@property(nonatomic) NSUInteger frames;
@property(nonatomic) NSUInteger hitches;
@property(nonatomic) double longestFrame;
@property(nonatomic) uint64_t peakFootprint;
@property(nonatomic) BOOL reported;
- (void)tick:(CADisplayLink *)link;
@end

static UIScrollView *benchmark_scroll_view(UIView *view) {
	if ([view isKindOfClass:UIScrollView.class]) {
		UIScrollView *scroll = (UIScrollView *)view;
		if (scroll.contentSize.height > scroll.bounds.size.height) return scroll;
	}
	for (UIView *child in view.subviews) {
		UIScrollView *found = benchmark_scroll_view(child);
		if (found) return found;
	}
	return nil;
}

static uint64_t benchmark_footprint(void) {
	task_vm_info_data_t info;
	mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
	if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS)
		return 0;
	return info.phys_footprint;
}

static CFTimeInterval gBenchmarkStart;
static uint64_t gBenchmarkStartFootprint;

static int bridge_UIKitBenchmark_start(lua_State *L) {
	(void)L;
	gBenchmarkStart = CACurrentMediaTime();
	gBenchmarkStartFootprint = benchmark_footprint();
	return 0;
}

@implementation LuaBenchmarkScroll
- (void)tick:(CADisplayLink *)link {
	CFTimeInterval now = CACurrentMediaTime();
	if (!self.scroll) self.scroll = benchmark_scroll_view(self.window);
	if (!self.scroll) return;
	if (!self.firstFrameAt) self.firstFrameAt = now;
	CGFloat maximum = MAX(0, self.scroll.contentSize.height - self.scroll.bounds.size.height);
	CFTimeInterval elapsed = now - self.firstFrameAt;
	CGFloat travel = elapsed * kBenchmarkScrollPointsPerSecond;
	if (maximum > 0) {
		CGFloat cycle = fmod(travel, maximum * 2);
		CGFloat offset = cycle <= maximum ? cycle : maximum * 2 - cycle;
		[self.scroll setContentOffset:CGPointMake(0, offset) animated:NO];
	}
	double targetFPS = self.window.windowScene.screen.maximumFramesPerSecond;
	if (targetFPS <= 0) targetFPS = kBenchmarkPreferredFrameRate;
	if (self.previousFrameAt) {
		double gap = now - self.previousFrameAt;
		self.longestFrame = MAX(self.longestFrame, gap);
		if (gap > kBenchmarkHitchFrameCount / targetFPS) self.hitches++;
	}
	self.previousFrameAt = now;
	self.frames++;
	self.peakFootprint = MAX(self.peakFootprint, benchmark_footprint());
	if (!self.reported && elapsed >= kBenchmarkDuration) {
		self.reported = YES;
		NSLog(@"BENCH_RESULT kind=%@ rows=%ld firstFrameMs=%.1f fps=%.1f hitches=%lu longestFrameMs=%.1f peakFootprintMiB=%.1f displayHz=%.0f",
			self.kind, (long)self.rowCount, (self.firstFrameAt - self.createdAt) * 1000,
			self.frames / elapsed, (unsigned long)self.hitches, self.longestFrame * 1000,
			self.peakFootprint / (1024.0 * 1024.0), targetFPS);
	}
	if (elapsed >= kBenchmarkTraceDuration) {
		[link invalidate];
		self.link = nil;
	}
}
@end

static char kBenchmarkScrollKey;
static int bridge_UIKitBenchmark_scroll(lua_State *L) {
	UIWindow *window = (UIWindow *)check_objc(L, 1);
	LuaBenchmarkScroll *probe = [LuaBenchmarkScroll new];
	probe.window = window;
	probe.kind = [NSString stringWithUTF8String:luaL_checkstring(L, 2)];
	probe.rowCount = luaL_checkinteger(L, 3);
	probe.createdAt = gBenchmarkStart ?: CACurrentMediaTime();
	probe.peakFootprint = MAX(gBenchmarkStartFootprint, benchmark_footprint());
	probe.link = [CADisplayLink displayLinkWithTarget:probe selector:@selector(tick:)];
	probe.link.preferredFrameRateRange = CAFrameRateRangeMake(
		kBenchmarkMinimumFrameRate, kBenchmarkPreferredFrameRate,
		kBenchmarkPreferredFrameRate);
	[probe.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
	objc_setAssociatedObject(window, &kBenchmarkScrollKey, probe, OBJC_ASSOCIATION_RETAIN);
	return 0;
}
