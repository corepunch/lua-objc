#pragma mark - Motion (SwiftUI transactions, animations and transitions)

/*
 * SwiftUI animates the difference a state change makes: `withAnimation`
 * opens a transaction, the body changes state, and every view whose frame,
 * opacity or transform differs afterwards animates from its old value to
 * its new one with the transaction's animation. Views inserted by the change
 * play their insertion transition and removed views play their removal
 * transition before they leave.
 *
 * This engine does the same on Core Animation, for NSView and UIView alike:
 *
 *   1. A transaction snapshots only what its body touches. A Lua property
 *      write snapshots the view's paint state (opacity, transform, colour,
 *      corner radius, content) and, when the write affects layout, the
 *      geometry of its whole layout owner's subtree, before the write lands.
 *      Structural edits (insert, remove) snapshot their container the same way.
 *   2. The body runs with implicit layer actions disabled.
 *   3. Commit flushes layout, then compares: changed layers receive explicit
 *      animations from the old value (or the value on screen, when an earlier
 *      animation is still running, so interruptions retarget smoothly) to
 *      the new model value. Model values are never changed by animation, so
 *      a skipped, interrupted or reduced animation always ends exactly where
 *      layout put the view.
 *
 * Springs use CASpringAnimation with SwiftUI's parameters (mass, stiffness,
 * damping, initial velocity); curves use CAMediaTimingFunction. Reduce Motion
 * keeps opacity and colour changes but makes geometry immediate, and turns
 * moving transitions into fades, as Apple's guidelines ask.
 */

#if TARGET_OS_IPHONE
#define MotionView UIView
#define MotionColor UIColor
#define motion_is_descendant(view, ancestor) [(view) isDescendantOfView:(ancestor)]
#define motion_point_value(point) [NSValue valueWithCGPoint:(point)]
#define motion_rect_value(rect) [NSValue valueWithCGRect:(rect)]
#define motion_value_point(value) [(value) CGPointValue]
#define motion_value_rect(value) [(value) CGRectValue]
#else
#define MotionView NSView
#define MotionColor NSColor
#define motion_is_descendant(view, ancestor) [(view) isDescendantOf:(ancestor)]
#define motion_point_value(point) [NSValue valueWithPoint:(point)]
#define motion_rect_value(rect) [NSValue valueWithRect:(rect)]
#define motion_value_point(value) [(value) pointValue]
#define motion_value_rect(value) [(value) rectValue]
#endif

/* ----- Animation values ----- */

typedef struct {
	BOOL spring;
	CGFloat x1, y1, x2, y2;          // cubic timing curve control points
	CGFloat duration;                // curve duration; springs settle on their own
	CGFloat mass, stiffness, damping, velocity;
	CGFloat delay, speed;
	float repeatCount;               // 0 once, HUGE_VALF forever
	BOOL autoreverses;
} MotionSpec;

static double motion_field(lua_State *L, int idx, const char *name, double fallback) {
	lua_getfield(L, idx, name);
	double value = lua_isnumber(L, -1) ? lua_tonumber(L, -1) : fallback;
	lua_pop(L, 1);
	return value;
}

static BOOL motion_bool_field(lua_State *L, int idx, const char *name) {
	lua_getfield(L, idx, name);
	BOOL value = lua_toboolean(L, -1);
	lua_pop(L, 1);
	return value;
}

/* Reads a native animation spec produced by ui/animation.lua. */
static MotionSpec motion_check_spec(lua_State *L, int idx) {
	idx = lua_absindex(L, idx);
	luaL_checktype(L, idx, LUA_TTABLE);
	MotionSpec spec = {0};
	lua_getfield(L, idx, "kind");
	const char *kind = luaL_optstring(L, -1, "timing");
	lua_pop(L, 1);
	if (strcmp(kind, "spring") == 0) spec.spring = YES;
	else if (strcmp(kind, "timing") != 0) luaL_error(L, "unknown animation kind '%s'", kind);
	spec.x1 = motion_field(L, idx, "x1", 0.42);
	spec.y1 = motion_field(L, idx, "y1", 0);
	spec.x2 = motion_field(L, idx, "x2", 0.58);
	spec.y2 = motion_field(L, idx, "y2", 1);
	spec.duration = MAX(0, motion_field(L, idx, "duration", kMotionDefaultDuration));
	spec.mass = MAX(0.0001, motion_field(L, idx, "mass", 1));
	spec.stiffness = MAX(0.0001, motion_field(L, idx, "stiffness", 100));
	spec.damping = MAX(0, motion_field(L, idx, "damping", 20));
	spec.velocity = motion_field(L, idx, "initialVelocity", 0);
	spec.delay = MAX(0, motion_field(L, idx, "delay", 0));
	spec.speed = MAX(0.0001, motion_field(L, idx, "speed", 1));
	double repeat = motion_field(L, idx, "repeatCount", 0);
	spec.repeatCount = repeat < 0 ? HUGE_VALF : (float)repeat;
	spec.autoreverses = motion_bool_field(L, idx, "autoreverses");
	return spec;
}

static BOOL motion_reduce_motion(void) {
#if TARGET_OS_IPHONE
	return UIAccessibilityIsReduceMotionEnabled();
#else
	return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
#endif
}

/* Test hook: Reduce Motion as the engine sees it. nil follows the system. */
static NSNumber *motionReduceOverride;
static BOOL motion_reduced(void) {
	return motionReduceOverride ? motionReduceOverride.boolValue : motion_reduce_motion();
}

static CAMediaTimingFunction *motion_timing(MotionSpec spec) {
	return [CAMediaTimingFunction functionWithControlPoints:(float)spec.x1 :(float)spec.y1
		:(float)spec.x2 :(float)spec.y2];
}

/* One property animation with the spec's curve, delay, speed and repetition.
 * Delayed animations hold their start value until they begin. */
static CABasicAnimation *motion_animation(MotionSpec spec, NSString *keyPath, id from, id to, CALayer *layer) {
	CABasicAnimation *animation;
	if (spec.spring) {
		CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:keyPath];
		spring.mass = spec.mass;
		spring.stiffness = spec.stiffness;
		spring.damping = spec.damping;
		spring.initialVelocity = spec.velocity;
		spring.duration = spring.settlingDuration;
		animation = spring;
	} else {
		animation = [CABasicAnimation animationWithKeyPath:keyPath];
		animation.duration = spec.duration;
		animation.timingFunction = motion_timing(spec);
	}
	animation.fromValue = from;
	animation.toValue = to;
	animation.speed = spec.speed;
	animation.repeatCount = spec.repeatCount;
	animation.autoreverses = spec.autoreverses;
	if (spec.delay > 0) {
		animation.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] + spec.delay;
		animation.fillMode = kCAFillModeBackwards;
	}
	return animation;
}

/* ----- Custom animators ----- */

/* A view whose content Core Animation cannot tween (SceneKit geometry, for
 * one) animates itself inside a transaction as an animator: it takes the
 * transaction's animation from motion_animate, steps itself with
 * motion_progress, and reports the end with motion_animator_finished. The
 * transaction's completion waits for it, and _motionSettle ends it. A
 * platform without such a view leaves these unused. */
@protocol LuaMotionAnimator <NSObject>
/* Jump to the final state now, then report motion_animator_finished. */
- (void)motionSettle;
@end

/* Seconds the animation runs once it has begun, at its speed. */
__unused static CFTimeInterval motion_duration(MotionSpec spec) {
	CFTimeInterval duration = spec.duration;
	if (spec.spring) {
		CASpringAnimation *spring = [CASpringAnimation animation];
		spring.mass = spec.mass;
		spring.stiffness = spec.stiffness;
		spring.damping = spec.damping;
		spring.initialVelocity = spec.velocity;
		duration = spring.settlingDuration;
	}
	return duration / spec.speed;
}

/* Bisection steps that solve a timing curve to well under a pixel. */
static const int kMotionBezierSteps = 40;

/* A cubic timing curve's y at x, as CAMediaTimingFunction evaluates it. */
static CGFloat motion_bezier(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat x) {
	if (x <= 0) return 0;
	if (x >= 1) return 1;
	CGFloat low = 0, high = 1, t = x;
	for (int step = 0; step < kMotionBezierSteps; step++) {
		CGFloat current = 3 * x1 * (1 - t) * (1 - t) * t + 3 * x2 * (1 - t) * t * t + t * t * t;
		if (fabs(current - x) < 1e-7) break;
		if (current < x) low = t; else high = t;
		t = (low + high) / 2;
	}
	return 3 * y1 * (1 - t) * (1 - t) * t + 3 * y2 * (1 - t) * t * t + t * t * t;
}

/* Progress (0 at the start value, 1 at the end value; a spring may pass 1)
 * `elapsed` seconds after the animation was added, as the same spec animates
 * a layer: held through the delay, then the curve or the spring's step
 * response. Repeats are for layer animations only. */
__unused static CGFloat motion_progress(MotionSpec spec, CFTimeInterval elapsed) {
	CFTimeInterval t = (elapsed - spec.delay) * spec.speed;
	if (t <= 0) return 0;
	if (!spec.spring) return spec.duration > 0 ? motion_bezier(spec.x1, spec.y1, spec.x2, spec.y2, t / spec.duration) : 1;
	CGFloat omega = sqrt(spec.stiffness / spec.mass);
	CGFloat zeta = spec.damping / (2 * sqrt(spec.stiffness * spec.mass));
	CGFloat velocity = -spec.velocity;
	if (zeta < 1) {
		CGFloat damped = omega * sqrt(1 - zeta * zeta);
		return 1 - exp(-zeta * omega * t) * (cos(damped * t) + (zeta * omega - velocity) / damped * sin(damped * t));
	}
	return 1 - exp(-omega * t) * (1 + (omega - velocity) * t);
}

/* ----- View effects: opacity, scale, rotation and offset ----- */

/* SwiftUI's scaleEffect and rotationEffect pivot on the view's centre, and
 * offset moves it without changing layout. They compose into one layer
 * transform. UIKit layers anchor at their centre; AppKit's backing layers
 * anchor at their origin, so the pivot is applied explicitly and refreshed
 * whenever layout changes the view's size. */
@interface LuaMotionEffects : NSObject
@property(nonatomic) CGFloat scale;
@property(nonatomic) CGFloat rotation;   // degrees, clockwise as in SwiftUI
@property(nonatomic) CGFloat offsetX;
@property(nonatomic) CGFloat offsetY;    // positive moves down, as in SwiftUI
@property(nonatomic, strong) id frameObserver;
@end

@implementation LuaMotionEffects
- (instancetype)init {
	self = [super init];
	if (self) _scale = 1;
	return self;
}
- (void)dealloc {
	if (_frameObserver) [NSNotificationCenter.defaultCenter removeObserver:_frameObserver];
}
@end

static char kMotionEffectsKey;
static char kMotionInsertionKey;
static char kMotionRemovalKey;
static char kMotionLeavingKey;
static char kMotionMatchedKey;
static char kMotionContentTransitionKey;

static LuaMotionEffects *motion_effects(MotionView *view, BOOL create) {
	LuaMotionEffects *effects = objc_getAssociatedObject(view, &kMotionEffectsKey);
	if (!effects && create) {
		effects = [LuaMotionEffects new];
		objc_setAssociatedObject(view, &kMotionEffectsKey, effects, OBJC_ASSOCIATION_RETAIN);
	}
	return effects;
}

static CALayer *motion_layer(MotionView *view) {
#if !TARGET_OS_IPHONE
	view.wantsLayer = YES;
#endif
	return view.layer;
}

/* The direction "down" takes in the view's layer space: +1 in a flipped
 * (top-left origin) space, -1 in AppKit's default bottom-left space. */
static CGFloat motion_down(MotionView *view) {
#if TARGET_OS_IPHONE
	(void)view;
	return 1;
#else
	return view.superview.isFlipped ? 1 : -1;
#endif
}

/* The layer transform for scale, clockwise rotation in degrees and an offset
 * in SwiftUI's top-left coordinates, pivoting on the view's centre. */
static CATransform3D motion_compose(MotionView *view, CGFloat scale, CGFloat rotation, CGFloat offsetX, CGFloat offsetY) {
	CGFloat down = motion_down(view);
	CGFloat angle = rotation * M_PI / 180.0 * down;
#if TARGET_OS_IPHONE
	CATransform3D transform = CATransform3DMakeTranslation(offsetX, offsetY, 0);
	transform = CATransform3DRotate(transform, angle, 0, 0, 1);
	return CATransform3DScale(transform, scale, scale, 1);
#else
	CGSize size = view.bounds.size;
	CGFloat cx = size.width / 2, cy = size.height / 2;
	CATransform3D transform = CATransform3DMakeTranslation(cx + offsetX, cy + offsetY * down, 0);
	transform = CATransform3DRotate(transform, angle, 0, 0, 1);
	transform = CATransform3DScale(transform, scale, scale, 1);
	return CATransform3DTranslate(transform, -cx, -cy, 0);
#endif
}

static CATransform3D motion_effects_transform(MotionView *view, LuaMotionEffects *effects) {
	if (!effects) return CATransform3DIdentity;
	return motion_compose(view, effects.scale, effects.rotation, effects.offsetX, effects.offsetY);
}

static void motion_apply_effects(MotionView *view) {
	LuaMotionEffects *effects = motion_effects(view, NO);
	CALayer *layer = motion_layer(view);
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	layer.transform = motion_effects_transform(view, effects);
	[CATransaction commit];
#if !TARGET_OS_IPHONE
	// The pivot depends on the size; follow layout's size changes.
	BOOL pivots = effects && (effects.scale != 1 || effects.rotation != 0);
	if (pivots && !effects.frameObserver) {
		view.postsFrameChangedNotifications = YES;
		__weak NSView *weakView = view;
		effects.frameObserver = [NSNotificationCenter.defaultCenter
			addObserverForName:NSViewFrameDidChangeNotification object:view queue:nil
			usingBlock:^(NSNotification *note) {
				(void)note;
				NSView *strong = weakView;
				if (!strong) return;
				LuaMotionEffects *current = motion_effects(strong, NO);
				[CATransaction begin];
				[CATransaction setDisableActions:YES];
				strong.layer.transform = motion_effects_transform(strong, current);
				[CATransaction commit];
			}];
	}
#endif
}

/* ----- Transactions ----- */

@interface LuaMotionState : NSObject
@property(nonatomic, weak) MotionView *superview;
@property(nonatomic) CGPoint position;
@property(nonatomic) CGRect bounds;
@property(nonatomic) float opacity;
@property(nonatomic) CATransform3D transform;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic, strong) id backgroundColor;
@property(nonatomic) BOOL hidden;
@property(nonatomic) CGRect windowRect;
@property(nonatomic, strong) id content;
@end
@implementation LuaMotionState
@end

@interface LuaMotionTransaction : NSObject
@property(nonatomic) MotionSpec spec;
@property(nonatomic) BOOL disabled;
@property(nonatomic, strong) NSMapTable<MotionView *, LuaMotionState *> *states;
@property(nonatomic, strong) NSHashTable<MotionView *> *owners;
@property(nonatomic, strong) NSHashTable<MotionView *> *claimed;
@property(nonatomic, strong) NSHashTable<MotionView *> *appearing;
@property(nonatomic, strong) NSMutableArray<MotionView *> *removals;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *matchedSources;
@property(nonatomic, strong) NSMutableArray<id<LuaMotionAnimator>> *animators;
@end
@implementation LuaMotionTransaction
- (instancetype)init {
	self = [super init];
	if (self) {
		_states = [NSMapTable weakToStrongObjectsMapTable];
		_owners = [NSHashTable weakObjectsHashTable];
		_claimed = [NSHashTable weakObjectsHashTable];
		_appearing = [NSHashTable weakObjectsHashTable];
		_removals = [NSMutableArray array];
		_matchedSources = [NSMutableDictionary dictionary];
		_animators = [NSMutableArray array];
	}
	return self;
}
@end

/* Animations still running, so tests (and teardown) can settle them. Each
 * batch finishes once its CATransaction has completed and its animators
 * have ended. */
@interface LuaMotionBatch : NSObject
@property(nonatomic, strong) NSHashTable<CALayer *> *layers;
@property(nonatomic, strong) NSMutableArray<id<LuaMotionAnimator>> *animators;
@property(nonatomic, strong) NSMutableArray<dispatch_block_t> *completions;
@property(nonatomic) BOOL layersFinished;
@property(nonatomic) BOOL finished;
@end
@implementation LuaMotionBatch
- (instancetype)init {
	self = [super init];
	if (self) {
		_layers = [NSHashTable weakObjectsHashTable];
		_animators = [NSMutableArray array];
		_completions = [NSMutableArray array];
	}
	return self;
}
- (void)finish {
	if (self.finished) return;
	self.finished = YES;
	for (dispatch_block_t block in self.completions) block();
	[self.completions removeAllObjects];
}
@end

static NSMutableArray<LuaMotionTransaction *> *motionStack;
static NSMutableArray<LuaMotionBatch *> *motionBatches;
static NSString *const kMotionKeyPrefix = @"lua.motion.";

static void motion_batch_advance(LuaMotionBatch *batch) {
	if (!batch.layersFinished || batch.animators.count > 0) return;
	[motionBatches removeObject:batch];
	[batch finish];
}

static LuaMotionTransaction *motion_current(void);

/* Joins `animator` to the open transaction and hands it that transaction's
 * animation. Returns NO, starting nothing, outside a transaction, in one
 * that disables animation, and under Reduce Motion: the animator then shows
 * its final state at once. */
__unused static BOOL motion_animate(id<LuaMotionAnimator> animator, MotionSpec *spec) {
	LuaMotionTransaction *txn = motion_current();
	if (!txn || txn.disabled || motion_reduced()) return NO;
	[txn.animators addObject:animator];
	*spec = txn.spec;
	return YES;
}

__unused static void motion_animator_finished(id<LuaMotionAnimator> animator) {
	for (LuaMotionTransaction *txn in motionStack) [txn.animators removeObjectIdenticalTo:animator];
	for (LuaMotionBatch *batch in [motionBatches copy]) {
		if ([batch.animators indexOfObjectIdenticalTo:animator] == NSNotFound) continue;
		[batch.animators removeObjectIdenticalTo:animator];
		motion_batch_advance(batch);
	}
}

static LuaMotionTransaction *motion_current(void) {
	return motionStack.lastObject;
}

static MotionView *motion_layout_owner(MotionView *view);
static void motion_flush_layout(NSArray<MotionView *> *owners);
/* Lays out everything still pending from writes made outside a transaction,
 * so a transaction's snapshot starts from the committed layout. */
static void motion_settle_layout(void);
/* Structural changes move siblings like any layout-affecting write: the
 * container is laid out in the next pass, before the frame is drawn. */
static void motion_invalidate_layout(MotionView *view);

/* Content a contentTransition cross-fades or rolls: text, titles, images. */
static id motion_content(MotionView *view) {
	for (NSString *key in @[@"text", @"stringValue", @"title", @"image"]) {
		if ([view respondsToSelector:NSSelectorFromString(key)]) {
			@try { return [view valueForKey:key]; } @catch (NSException *e) { (void)e; }
		}
	}
	return nil;
}

/* The layer geometry and opacity a view's model implies. AppKit applies
 * frame and alpha writes to a backing layer lazily once the view has been
 * displayed, so the view, not its layer, is the source of truth; the layer's
 * frame equals the view's frame in the superview's coordinates. */
static void motion_geometry(MotionView *view, CGPoint *position, CGRect *bounds) {
#if TARGET_OS_IPHONE
	*position = view.center;
	*bounds = view.bounds;
#else
	CALayer *layer = motion_layer(view);
	CGRect frame = view.frame;
	CGPoint anchor = layer.anchorPoint;
	*position = CGPointMake(frame.origin.x + anchor.x * frame.size.width, frame.origin.y + anchor.y * frame.size.height);
	*bounds = CGRectMake(layer.bounds.origin.x, layer.bounds.origin.y, frame.size.width, frame.size.height);
#endif
}

static float motion_alpha(MotionView *view) {
#if TARGET_OS_IPHONE
	return (float)view.alpha;
#else
	return (float)view.alphaValue;
#endif
}

static LuaMotionState *motion_capture(MotionView *view) {
	CALayer *layer = motion_layer(view);
	LuaMotionState *state = [LuaMotionState new];
	state.superview = view.superview;
	CGPoint position; CGRect bounds;
	motion_geometry(view, &position, &bounds);
	state.position = position;
	state.bounds = bounds;
	state.opacity = motion_alpha(view);
	state.transform = layer.transform;
	state.cornerRadius = layer.cornerRadius;
	state.backgroundColor = (__bridge id)layer.backgroundColor;
	state.hidden = view.hidden || objc_getAssociatedObject(view, &kMotionLeavingKey) != nil;
	if (objc_getAssociatedObject(view, &kMotionContentTransitionKey)) state.content = motion_content(view);
	if (objc_getAssociatedObject(view, &kMotionMatchedKey) && view.window) {
#if TARGET_OS_IPHONE
		state.windowRect = [view convertRect:view.bounds toView:nil];
#else
		state.windowRect = [view convertRect:view.bounds toView:nil];
#endif
	}
	return state;
}

/* Tables own their rows; their cells are reused, never animated here. */
static BOOL motion_is_opaque_container(MotionView *view) {
#if TARGET_OS_IPHONE
	return [view isKindOfClass:UITableView.class] || [view isKindOfClass:UICollectionView.class];
#else
	return [view isKindOfClass:NSTableView.class];
#endif
}

static void motion_snapshot_view(LuaMotionTransaction *txn, MotionView *view) {
	if (![txn.states objectForKey:view]) [txn.states setObject:motion_capture(view) forKey:view];
}

static void motion_snapshot_tree(LuaMotionTransaction *txn, MotionView *root) {
	motion_snapshot_view(txn, root);
	if (motion_is_opaque_container(root)) return;
	for (MotionView *child in root.subviews) motion_snapshot_tree(txn, child);
}

/* Called before a Lua write or structural edit changes `view`. Geometry is
 * captured for the layout region the change can move. */
static void motion_will_change(MotionView *view, BOOL affectsLayout) {
	LuaMotionTransaction *txn = motion_current();
	// A view being built has no superview yet: it has no old state to
	// animate from, and must not be mistaken for one when it is inserted.
	if (!txn || !view || !view.superview) return;
	motion_snapshot_view(txn, view);
	if (!affectsLayout) return;
	MotionView *owner = motion_layout_owner(view);
	for (MotionView *covered in txn.owners) {
		if (covered == owner || motion_is_descendant(owner, covered)) return;
	}
	motion_snapshot_tree(txn, owner);
	[txn.owners addObject:owner];
}

static BOOL motion_is_leaving(MotionView *view) {
	return objc_getAssociatedObject(view, &kMotionLeavingKey) != nil;
}

/* ----- Transitions ----- */

/* A transition state: how an inserted view starts or a removed view ends,
 * relative to its laid-out state. Keys: opacity, scale, rotation, offsetX,
 * offsetY, edge (leading, trailing, top, bottom: a move by the view's own
 * size), strokeEnd (arcs draw on, staggered by `stagger`). */
static CGFloat motion_state_number(NSDictionary *state, NSString *key, CGFloat fallback) {
	id value = state[key];
	return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}

static BOOL motion_state_moves(NSDictionary *state) {
	return state[@"scale"] || state[@"rotation"] || state[@"offsetX"] || state[@"offsetY"] || state[@"edge"];
}

static CATransform3D motion_state_transform(MotionView *view, NSDictionary *state) {
	LuaMotionEffects *effects = motion_effects(view, NO);
	CGFloat scale = (effects ? effects.scale : 1) * motion_state_number(state, @"scale", 1);
	CGFloat rotation = (effects ? effects.rotation : 0) + motion_state_number(state, @"rotation", 0);
	CGFloat x = (effects ? effects.offsetX : 0) + motion_state_number(state, @"offsetX", 0);
	CGFloat y = (effects ? effects.offsetY : 0) + motion_state_number(state, @"offsetY", 0);
	NSString *edge = [state[@"edge"] isKindOfClass:NSString.class] ? state[@"edge"] : nil;
	CGSize size = view.bounds.size;
	if ([edge isEqualToString:@"leading"]) x -= size.width;
	else if ([edge isEqualToString:@"trailing"]) x += size.width;
	else if ([edge isEqualToString:@"top"]) y -= size.height;
	else if ([edge isEqualToString:@"bottom"]) y += size.height;
	return motion_compose(view, scale, rotation, x, y);
}

/* Animations this engine added: its prefixed keys, and the content
 * transition Core Animation stores under kCATransition. */
static BOOL motion_owns_key(NSString *key) {
	return [key hasPrefix:kMotionKeyPrefix] || [key isEqualToString:kCATransition];
}

static void motion_remove_animations(CALayer *layer) {
	for (NSString *key in layer.animationKeys) {
		if (motion_owns_key(key)) [layer removeAnimationForKey:key];
	}
}

static NSString *motion_key(NSString *keyPath) {
	return [kMotionKeyPrefix stringByAppendingString:keyPath];
}

static void motion_add(LuaMotionBatch *batch, CALayer *layer, CABasicAnimation *animation) {
	[layer addAnimation:animation forKey:motion_key(animation.keyPath)];
	[batch.layers addObject:layer];
}

/* The value a layer shows now: its presentation value while one of our
 * animations runs on that key, else the given model value. */
static id motion_from(CALayer *layer, NSString *keyPath, id model) {
	if ([layer animationForKey:motion_key(keyPath)] && layer.presentationLayer) {
		id value = [layer.presentationLayer valueForKeyPath:keyPath];
		if (value) return value;
	}
	return model;
}

/* Arcs inside a view, for the draw-on transition. */
static void motion_shape_layers(MotionView *view, NSMutableArray<CAShapeLayer *> *found) {
	CALayer *layer = view.layer;
	if ([layer isKindOfClass:CAShapeLayer.class]) { [found addObject:(CAShapeLayer *)layer]; return; }
	for (MotionView *child in view.subviews) motion_shape_layers(child, found);
}

/* Plays a transition state on `view`: insertion from the state to the view's
 * current values, removal from its current values to the state. Reduce
 * Motion keeps only the fade. Returns how many animations were added. */
static NSInteger motion_play_transition(LuaMotionTransaction *txn, LuaMotionBatch *batch, MotionView *view,
	NSDictionary *state, BOOL insertion) {
	if (!state.count) return 0;
	MotionSpec spec = txn.spec;
	CALayer *layer = motion_layer(view);
	BOOL reduced = motion_reduced();
	NSInteger added = 0;
	CGFloat fade = motion_state_number(state, @"opacity", reduced && motion_state_moves(state) ? 0 : 1);
	if (fade != 1) {
		float alpha = motion_alpha(view);
		NSNumber *current = @(alpha), *edge = @(alpha * fade);
		CABasicAnimation *animation = motion_animation(spec, @"opacity",
			insertion ? edge : motion_from(layer, @"opacity", current), insertion ? current : edge, layer);
		if (!insertion) { animation.fillMode = kCAFillModeForwards; animation.removedOnCompletion = NO; }
		motion_add(batch, layer, animation);
		added++;
	}
	if (!reduced && motion_state_moves(state)) {
		NSValue *current = [NSValue valueWithCATransform3D:layer.transform];
		NSValue *edge = [NSValue valueWithCATransform3D:motion_state_transform(view, state)];
		CABasicAnimation *animation = motion_animation(spec, @"transform",
			insertion ? edge : motion_from(layer, @"transform", current), insertion ? current : edge, layer);
		if (!insertion) { animation.fillMode = kCAFillModeForwards; animation.removedOnCompletion = NO; }
		motion_add(batch, layer, animation);
		added++;
	}
	if (state[@"strokeEnd"]) {
		NSMutableArray<CAShapeLayer *> *shapes = [NSMutableArray array];
		motion_shape_layers(view, shapes);
		CGFloat stagger = reduced ? 0 : motion_state_number(state, @"stagger", 0);
		CGFloat target = motion_state_number(state, @"strokeEnd", 0);
		[shapes enumerateObjectsUsingBlock:^(CAShapeLayer *shape, NSUInteger index, BOOL *stop) {
			(void)stop;
			MotionSpec staggered = spec;
			staggered.delay += stagger * index;
			CABasicAnimation *animation = motion_animation(staggered, @"strokeEnd",
				insertion ? @(target) : @(shape.strokeEnd), insertion ? @(shape.strokeEnd) : @(target), shape);
			if (!insertion) { animation.fillMode = kCAFillModeForwards; animation.removedOnCompletion = NO; }
			motion_add(batch, shape, animation);
		}];
		added += (NSInteger)shapes.count;
	}
	return added;
}

/* ----- Commit ----- */

static BOOL motion_rect_equal(CGRect a, CGRect b) {
	return fabs(a.origin.x - b.origin.x) < 0.01 && fabs(a.origin.y - b.origin.y) < 0.01
		&& fabs(a.size.width - b.size.width) < 0.01 && fabs(a.size.height - b.size.height) < 0.01;
}

static BOOL motion_point_equal(CGPoint a, CGPoint b) {
	return fabs(a.x - b.x) < 0.01 && fabs(a.y - b.y) < 0.01;
}

/* Frames animate for layers without drawn content (stacks, backgrounds,
 * shapes); a drawn layer takes its new size at once and moves, since
 * stretching drawn text or controls would distort them. */
static BOOL motion_resizes_smoothly(MotionView *view, CALayer *layer) {
	return layer.contents == nil || view.subviews.count > 0;
}

static void motion_diff_view(LuaMotionTransaction *txn, LuaMotionBatch *batch, MotionView *view, LuaMotionState *state) {
	CALayer *layer = motion_layer(view);
	MotionSpec spec = txn.spec;
	BOOL reduced = motion_reduced();
	CGPoint position; CGRect bounds;
	motion_geometry(view, &position, &bounds);
	if (!reduced && state.superview == view.superview) {
		if (!motion_point_equal(state.position, position)) {
			motion_add(batch, layer, motion_animation(spec, @"position",
				motion_from(layer, @"position", motion_point_value(state.position)),
				motion_point_value(position), layer));
		}
		if (!motion_rect_equal(state.bounds, bounds) && motion_resizes_smoothly(view, layer)) {
			motion_add(batch, layer, motion_animation(spec, @"bounds",
				motion_from(layer, @"bounds", motion_rect_value(state.bounds)),
				motion_rect_value(bounds), layer));
		}
	}
	if (!reduced && !CATransform3DEqualToTransform(state.transform, layer.transform)) {
		motion_add(batch, layer, motion_animation(spec, @"transform",
			motion_from(layer, @"transform", [NSValue valueWithCATransform3D:state.transform]),
			[NSValue valueWithCATransform3D:layer.transform], layer));
	}
	float alpha = motion_alpha(view);
	if (fabsf(state.opacity - alpha) > 0.001f) {
		motion_add(batch, layer, motion_animation(spec, @"opacity",
			motion_from(layer, @"opacity", @(state.opacity)), @(alpha), layer));
	}
	if (fabs(state.cornerRadius - layer.cornerRadius) > 0.01) {
		motion_add(batch, layer, motion_animation(spec, @"cornerRadius",
			motion_from(layer, @"cornerRadius", @(state.cornerRadius)), @(layer.cornerRadius), layer));
	}
	id color = (__bridge id)layer.backgroundColor;
	if (state.backgroundColor != color && !(state.backgroundColor && color
		&& CGColorEqualToColor((__bridge CGColorRef)state.backgroundColor, (__bridge CGColorRef)color))) {
		id from = state.backgroundColor ?: (__bridge id)[MotionColor clearColor].CGColor;
		id to = color ?: (__bridge id)[MotionColor clearColor].CGColor;
		motion_add(batch, layer, motion_animation(spec, @"backgroundColor", from, to, layer));
	}
	NSString *content = objc_getAssociatedObject(view, &kMotionContentTransitionKey);
	if (content && ![content isEqualToString:@"identity"]) {
		id now = motion_content(view);
		if (!(now == state.content || [now isEqual:state.content])) {
			CATransition *transition = [CATransition animation];
			transition.duration = spec.spring ? MIN(kMotionContentMaxDuration, spec.duration) : spec.duration;
			transition.timingFunction = motion_timing(spec);
			transition.type = kCATransitionFade;
			if ([content isEqualToString:@"numericText"] && !reduced) {
				// Digits roll up as a number grows and down as it shrinks.
				double before = [state.content respondsToSelector:@selector(doubleValue)] ? [state.content doubleValue] : 0;
				double after = [now respondsToSelector:@selector(doubleValue)] ? [now doubleValue] : 0;
				BOOL up = after >= before;
				transition.type = kCATransitionPush;
#if TARGET_OS_IPHONE
				transition.subtype = up ? kCATransitionFromTop : kCATransitionFromBottom;
#else
				transition.subtype = (up == view.isFlipped) ? kCATransitionFromTop : kCATransitionFromBottom;
#endif
			}
			// Core Animation files every transition under kCATransition.
			[layer addAnimation:transition forKey:kCATransition];
			[batch.layers addObject:layer];
		}
	}
	if (state.hidden && !view.hidden && !motion_is_leaving(view)) [txn.appearing addObject:view];
}

/* A view with a matchedGeometry id that appears where another view with the
 * same id was: it grows or shrinks from that view's frame (FLIP). */
static void motion_match(LuaMotionTransaction *txn, LuaMotionBatch *batch, MotionView *view, NSString *matched) {
	NSArray *sources = txn.matchedSources[matched];
	if (!sources.count || !view.window || motion_reduced()) return;
	CGRect from = motion_value_rect(sources.firstObject);
	CGRect to = [view convertRect:view.bounds toView:nil];
	if (to.size.width <= 0 || to.size.height <= 0) return;
	CGFloat sx = from.size.width / to.size.width, sy = from.size.height / to.size.height;
	CGFloat dx = CGRectGetMidX(from) - CGRectGetMidX(to), dy = CGRectGetMidY(from) - CGRectGetMidY(to);
	CALayer *layer = motion_layer(view);
#if TARGET_OS_IPHONE
	// UIKit layers pivot on their centre and window coordinates grow down.
	CATransform3D start = CATransform3DConcat(CATransform3DMakeScale(sx, sy, 1), CATransform3DMakeTranslation(dx, dy, 0));
#else
	// Window coordinates grow upward; the layer pivots on its origin and its
	// parent's space may be flipped.
	CGSize size = view.bounds.size;
	CGFloat ty = motion_down(view) > 0 ? -dy : dy;
	CATransform3D start = CATransform3DMakeTranslation(size.width / 2 + dx, size.height / 2 + ty, 0);
	start = CATransform3DScale(start, sx, sy, 1);
	start = CATransform3DTranslate(start, -size.width / 2, -size.height / 2, 0);
#endif
	start = CATransform3DConcat(layer.transform, start);
	motion_add(batch, layer, motion_animation(txn.spec, @"transform",
		[NSValue valueWithCATransform3D:start], [NSValue valueWithCATransform3D:layer.transform], layer));
}

static void motion_insert_tree(LuaMotionTransaction *txn, LuaMotionBatch *batch, MotionView *view) {
	if (view.hidden) return;
	NSDictionary *insertion = objc_getAssociatedObject(view, &kMotionInsertionKey);
	if (insertion) motion_play_transition(txn, batch, view, insertion, YES);
	NSString *matched = objc_getAssociatedObject(view, &kMotionMatchedKey);
	if (matched) motion_match(txn, batch, view, matched);
	if (motion_is_opaque_container(view)) return;
	for (MotionView *child in view.subviews) motion_insert_tree(txn, batch, child);
}

static void motion_walk(LuaMotionTransaction *txn, LuaMotionBatch *batch, MotionView *view, NSHashTable *visited) {
	[visited addObject:view];
	LuaMotionState *state = [txn.states objectForKey:view];
	if (!state) { motion_insert_tree(txn, batch, view); return; }
	if (view.hidden) return;
	if (![txn.claimed containsObject:view]) motion_diff_view(txn, batch, view, state);
	if (motion_is_opaque_container(view)) return;
	for (MotionView *child in view.subviews) motion_walk(txn, batch, child, visited);
}

static void motion_finish_removal(MotionView *view) {
	if (!motion_is_leaving(view)) return;
	objc_setAssociatedObject(view, &kMotionLeavingKey, nil, OBJC_ASSOCIATION_RETAIN);
	motion_remove_animations(view.layer);
	MotionView *container = view.superview;
	[view removeFromSuperview];
	motion_invalidate_layout(container);
}

static void motion_finish_hide(MotionView *view) {
	if (!motion_is_leaving(view)) return;
	objc_setAssociatedObject(view, &kMotionLeavingKey, nil, OBJC_ASSOCIATION_RETAIN);
	motion_remove_animations(view.layer);
	view.hidden = YES;
}

static char kMotionHidesKey;

/* Commits the transaction's differences as animations. `completion` runs
 * once every animation added here has finished, or on the next turn of the
 * run loop when nothing animated. */
/* Runs `add` inside a Core Animation transaction whose completion finishes
 * `batch`. The completion block is installed before any animation is added,
 * as CATransaction requires; a batch with nothing animated finishes on the
 * next turn of the run loop, like SwiftUI's completion. */
static void motion_run_batch(LuaMotionBatch *batch, dispatch_block_t add) {
	if (!motionBatches) motionBatches = [NSMutableArray array];
	[motionBatches addObject:batch];
	[CATransaction begin];
	__weak LuaMotionBatch *weakBatch = batch;
	[CATransaction setCompletionBlock:^{
		LuaMotionBatch *strong = weakBatch;
		if (!strong) return;
		strong.layersFinished = YES;
		motion_batch_advance(strong);
	}];
	add();
	[CATransaction commit];

	if (batch.layers.count == 0) {
		dispatch_async(dispatch_get_main_queue(), ^{
			batch.layersFinished = YES;
			motion_batch_advance(batch);
		});
	}
}

/* Commits the transaction's differences as animations. `completion` runs
 * once every animation added here has finished. */
static void motion_commit(LuaMotionTransaction *txn, dispatch_block_t completion) {
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	motion_flush_layout(txn.owners.allObjects);
	[CATransaction commit];
	LuaMotionBatch *batch = [LuaMotionBatch new];
	if (completion) [batch.completions addObject:completion];
	[batch.animators addObjectsFromArray:txn.animators];
	motion_run_batch(batch, ^{
		if (txn.disabled) return;
		// Matched sources: views with a matched id that are gone or hidden.
		for (MotionView *view in txn.states.keyEnumerator) {
			NSString *matched = objc_getAssociatedObject(view, &kMotionMatchedKey);
			LuaMotionState *state = [txn.states objectForKey:view];
			if (!matched || state.hidden || CGRectIsEmpty(state.windowRect)) continue;
			if (view.window && !view.hidden && !motion_is_leaving(view)) continue;
			NSMutableArray *list = txn.matchedSources[matched] ?: [NSMutableArray array];
			[list addObject:motion_rect_value(state.windowRect)];
			txn.matchedSources[matched] = list;
		}
		NSHashTable *visited = [NSHashTable weakObjectsHashTable];
		for (MotionView *owner in txn.owners) motion_walk(txn, batch, owner, visited);
		for (MotionView *view in txn.states.keyEnumerator) {
			if ([visited containsObject:view] || [txn.claimed containsObject:view]) continue;
			if (!view.hidden) motion_diff_view(txn, batch, view, [txn.states objectForKey:view]);
		}
		for (MotionView *view in txn.appearing) {
			NSDictionary *insertion = objc_getAssociatedObject(view, &kMotionInsertionKey);
			if (insertion) motion_play_transition(txn, batch, view, insertion, YES);
		}
		for (MotionView *view in txn.removals) {
			NSDictionary *removal = objc_getAssociatedObject(view, &kMotionRemovalKey);
			BOOL hides = objc_getAssociatedObject(view, &kMotionHidesKey) != nil;
			objc_setAssociatedObject(view, &kMotionHidesKey, nil, OBJC_ASSOCIATION_RETAIN);
			motion_play_transition(txn, batch, view, removal, NO);
			[batch.completions insertObject:^{ if (hides) motion_finish_hide(view); else motion_finish_removal(view); } atIndex:0];
		}
	});
	// An enclosing transaction must not animate what this one handled.
	LuaMotionTransaction *parent = motion_current();
	if (parent) {
		for (MotionView *view in txn.states.keyEnumerator) [parent.claimed addObject:view];
	}
}

/* ----- Hooks for property writes and structural edits ----- */

static BOOL motion_has_transition(MotionView *view) {
	return objc_getAssociatedObject(view, &kMotionInsertionKey) || objc_getAssociatedObject(view, &kMotionRemovalKey);
}

/* Called by the Lua metatable before `key` is written on `view`. */
static void motion_will_set(id object, const char *key) {
	if (!motion_current() || ![object isKindOfClass:MotionView.class]) return;
	motion_will_change((MotionView *)object, lua_objc_key_affects_layout(key));
}

/* A hidden write inside an animated transaction on a view with a transition
 * behaves like SwiftUI's conditional insertion and removal: showing plays the
 * insertion transition; hiding keeps the view on screen, out of layout,
 * while its removal transition plays, and hides it afterwards. Returns YES
 * when the write was handled. */
static BOOL motion_intercept_hidden(id object, BOOL hidden) {
	LuaMotionTransaction *txn = motion_current();
	if (!txn || txn.disabled || ![object isKindOfClass:MotionView.class]) return NO;
	MotionView *view = (MotionView *)object;
	if (!motion_has_transition(view)) return NO;
	if (hidden) {
		if (view.hidden || motion_is_leaving(view)) return YES;
		objc_setAssociatedObject(view, &kMotionLeavingKey, @YES, OBJC_ASSOCIATION_RETAIN);
		objc_setAssociatedObject(view, &kMotionHidesKey, @YES, OBJC_ASSOCIATION_RETAIN);
		[txn.removals addObject:view];
		return YES;
	}
	if (motion_is_leaving(view)) {
		// Shown again while leaving: stop leaving where it stands.
		objc_setAssociatedObject(view, &kMotionLeavingKey, nil, OBJC_ASSOCIATION_RETAIN);
		objc_setAssociatedObject(view, &kMotionHidesKey, nil, OBJC_ASSOCIATION_RETAIN);
		[txn.removals removeObject:view];
	}
	view.hidden = NO;
	[txn.appearing addObject:view];
	return YES;
}

/* Removes `view` from its container, playing its removal transition first
 * when a transaction is animating. The view leaves layout at once. */
static void motion_remove(MotionView *view) {
	if (!view.superview) return;
	LuaMotionTransaction *txn = motion_current();
	motion_will_change(view.superview, YES);
	NSDictionary *removal = objc_getAssociatedObject(view, &kMotionRemovalKey);
	if (!txn || txn.disabled || !removal.count || view.hidden) {
		MotionView *container = view.superview;
		[view removeFromSuperview];
		motion_invalidate_layout(container);
		return;
	}
	objc_setAssociatedObject(view, &kMotionLeavingKey, @YES, OBJC_ASSOCIATION_RETAIN);
	[txn.removals addObject:view];
}

/* Inserts `child` into `container` before the index-th child that is not
 * leaving, or last. An existing child moves. */
static void motion_insert(MotionView *container, MotionView *child, NSInteger index) {
	motion_will_change(container, YES);
	NSMutableArray<MotionView *> *present = [NSMutableArray array];
	for (MotionView *view in container.subviews) {
		if (view != child && !motion_is_leaving(view)) [present addObject:view];
	}
	MotionView *before = index >= 0 && index < (NSInteger)present.count ? present[(NSUInteger)index] : nil;
	if (child.superview == container) {
		NSUInteger current = [container.subviews indexOfObject:child];
		NSUInteger target = before ? [container.subviews indexOfObject:before] : container.subviews.count;
		if (current + 1 == target || (!before && current == container.subviews.count - 1)) return;
	}
	if (child.superview && child.superview != container) [child removeFromSuperview];
#if TARGET_OS_IPHONE
	if (before) [container insertSubview:child belowSubview:before];
	else [container addSubview:child];
#else
	if (before) [container addSubview:child positioned:NSWindowBelow relativeTo:before];
	else [container addSubview:child];
#endif
	motion_invalidate_layout(container);
}

/* ----- Lua bindings ----- */

static BOOL motion_callback(LuaReg *reg, const char *context) {
	lua_State *L = lua_reg_live_state(reg);
	if (!L || !lua_reg_push(reg)) return NO;
	return lua_objc_pcall(L, 0, 0, context) == LUA_OK;
}

// _motionTransaction(spec | nil, body, completion): runs body in a transaction.
// A nil spec disables animation for the body (Transaction.disablesAnimations).
static int bridge_motion_transaction(lua_State *L) {
	lua_settop(L, 3);
	BOOL disabled = lua_isnil(L, 1);
	MotionSpec spec = disabled ? (MotionSpec){0} : motion_check_spec(L, 1);
	luaL_checktype(L, 2, LUA_TFUNCTION);
	LuaReg *completion = lua_isfunction(L, 3) ? lua_reg_opt_unscoped(L, 3) : nil;
	LuaMotionTransaction *txn = [LuaMotionTransaction new];
	txn.spec = spec;
	txn.disabled = disabled;
	if (!motionStack) motionStack = [NSMutableArray array];
	// Writes made before the transaction are not part of it: a page mounted
	// outside any transaction has its views in the hierarchy but not laid
	// out yet. Snapshotting those unlaid frames would animate the page in
	// from its zero-sized origin, so settle pending layout first, as SwiftUI
	// commits an unanimated update before the next transaction's body runs.
	if (motionStack.count == 0) motion_settle_layout();
	[motionStack addObject:txn];
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	lua_pushvalue(L, 2);
	int status = lua_pcall(L, 0, LUA_MULTRET, 0);
	[CATransaction commit];
	[motionStack removeLastObject];
	if (status != LUA_OK) return lua_error(L);
	int results = lua_gettop(L) - 3;
	motion_commit(txn, completion ? ^{ motion_callback(completion, "withAnimation completion"); } : nil);
	return results;
}

// _motionSetTransition(view, insertion, removal): transition states or nil.
static int bridge_motion_set_transition(lua_State *L) {
	MotionView *view = check_view(L, 1);
	id insertion = lua_istable(L, 2) ? lua_to_objc_value(L, 2) : nil;
	id removal = lua_istable(L, 3) ? lua_to_objc_value(L, 3) : nil;
	objc_setAssociatedObject(view, &kMotionInsertionKey, [insertion isKindOfClass:NSDictionary.class] ? insertion : nil, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(view, &kMotionRemovalKey, [removal isKindOfClass:NSDictionary.class] ? removal : nil, OBJC_ASSOCIATION_RETAIN);
	return 0;
}

// _motionSetMatched(view, "namespace/id" | nil)
static int bridge_motion_set_matched(lua_State *L) {
	MotionView *view = check_view(L, 1);
	const char *key = luaL_optstring(L, 2, NULL);
	objc_setAssociatedObject(view, &kMotionMatchedKey, key ? [NSString stringWithUTF8String:key] : nil, OBJC_ASSOCIATION_COPY);
	return 0;
}

// _motionSetContentTransition(view, "opacity" | "numericText" | "interpolate" | "identity" | nil)
static int bridge_motion_set_content_transition(lua_State *L) {
	MotionView *view = check_view(L, 1);
	const char *kind = luaL_optstring(L, 2, NULL);
	if (kind && strcmp(kind, "opacity") && strcmp(kind, "numericText") && strcmp(kind, "interpolate") && strcmp(kind, "identity"))
		return luaL_error(L, "unknown content transition '%s'", kind);
	objc_setAssociatedObject(view, &kMotionContentTransitionKey, kind ? [NSString stringWithUTF8String:kind] : nil, OBJC_ASSOCIATION_COPY);
	return 0;
}

// _motionInsert(container, child, index): 1-based index among present children.
static int bridge_motion_insert(lua_State *L) {
	MotionView *container = check_view(L, 1);
	MotionView *child = check_view(L, 2);
	NSInteger index = (NSInteger)luaL_optinteger(L, 3, 0) - 1;
	motion_insert(container, child, index);
	return 0;
}

// _motionRemove(view): removes with the view's removal transition when animating.
static int bridge_motion_remove(lua_State *L) {
	motion_remove(check_view(L, 1));
	return 0;
}

// _keyframeAnimation(view, {duration, repeatCount, autoreverses, count,
//   opacity = {...}, scaleEffect = {...}, rotationEffect = {...},
//   offsetX = {...}, offsetY = {...}}): plays sampled keyframe tracks.
// Samples are evenly spaced over the duration; transforms pivot on the
// view's centre on both platforms.
static NSArray<NSNumber *> *motion_samples(lua_State *L, int idx, const char *name, NSInteger count) {
	lua_getfield(L, idx, name);
	if (!lua_istable(L, -1)) { lua_pop(L, 1); return nil; }
	NSMutableArray *values = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
	for (NSInteger i = 1; i <= count; i++) {
		lua_rawgeti(L, -1, i);
		[values addObject:@(lua_tonumber(L, -1))];
		lua_pop(L, 1);
	}
	lua_pop(L, 1);
	return values;
}

static int bridge_keyframe_animation(lua_State *L) {
	MotionView *view = check_view(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);
	NSInteger count = (NSInteger)motion_field(L, 2, "count", 0);
	if (count < 2) return luaL_error(L, "keyframe animation needs at least two samples");
	CGFloat duration = motion_field(L, 2, "duration", 0);
	double repeat = motion_field(L, 2, "repeatCount", 0);
	BOOL autoreverses = motion_bool_field(L, 2, "autoreverses");
	NSArray *opacity = motion_samples(L, 2, "opacity", count);
	NSArray *scale = motion_samples(L, 2, "scaleEffect", count);
	NSArray *rotation = motion_samples(L, 2, "rotationEffect", count);
	NSArray *offsetX = motion_samples(L, 2, "offsetX", count);
	NSArray *offsetY = motion_samples(L, 2, "offsetY", count);
	CALayer *layer = motion_layer(view);
	LuaMotionBatch *batch = [LuaMotionBatch new];
	LuaReg *completion = lua_isfunction(L, 3) ? lua_reg_opt_unscoped(L, 3) : nil;
	if (completion) [batch.completions addObject:^{ motion_callback(completion, "keyframe completion"); }];
	void (^configure)(CAKeyframeAnimation *) = ^(CAKeyframeAnimation *animation) {
		animation.duration = duration;
		animation.calculationMode = kCAAnimationLinear;
		animation.repeatCount = repeat < 0 ? HUGE_VALF : (float)repeat;
		animation.autoreverses = autoreverses;
	};
	motion_run_batch(batch, ^{
		if (opacity) {
			CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
			configure(animation);
			NSMutableArray *values = [NSMutableArray array];
			float alpha = motion_alpha(view);
		for (NSNumber *value in opacity) [values addObject:@(value.doubleValue * alpha)];
			animation.values = values;
			[layer addAnimation:animation forKey:motion_key(@"keyframes.opacity")];
			[batch.layers addObject:layer];
		}
		if (scale || rotation || offsetX || offsetY) {
			LuaMotionEffects *effects = motion_effects(view, NO);
			CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
			configure(animation);
			NSMutableArray *values = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
			for (NSInteger i = 0; i < count; i++) {
				NSUInteger n = (NSUInteger)i;
				CGFloat s = (effects ? effects.scale : 1) * (scale ? [scale[n] doubleValue] : 1);
				CGFloat r = (effects ? effects.rotation : 0) + (rotation ? [rotation[n] doubleValue] : 0);
				CGFloat x = (effects ? effects.offsetX : 0) + (offsetX ? [offsetX[n] doubleValue] : 0);
				CGFloat y = (effects ? effects.offsetY : 0) + (offsetY ? [offsetY[n] doubleValue] : 0);
				[values addObject:[NSValue valueWithCATransform3D:motion_compose(view, s, r, x, y)]];
			}
			animation.values = values;
			[layer addAnimation:animation forKey:motion_key(@"keyframes.transform")];
			[batch.layers addObject:layer];
		}
	});
	return 0;
}

// _motionStop(view): removes this engine's animations from a view's layer.
static int bridge_motion_stop(lua_State *L) {
	MotionView *view = check_view(L, 1);
	motion_remove_animations(view.layer);
	return 0;
}

static int bridge_motion_reduced(lua_State *L) {
	lua_pushboolean(L, motion_reduced());
	return 1;
}

// Test hook: _motionOverrideReduceMotion(true | false | nil)
static int bridge_motion_override_reduce_motion(lua_State *L) {
	motionReduceOverride = lua_isnoneornil(L, 1) ? nil : @(lua_toboolean(L, 1));
	return 0;
}

// Test hook: _motionSettle() finishes every running animation now, running
// completions and removals as if the animations had ended.
static int bridge_motion_settle(lua_State *L) {
	(void)L;
	NSArray<LuaMotionBatch *> *batches = [motionBatches copy];
	[motionBatches removeAllObjects];
	for (LuaMotionBatch *batch in batches) {
		for (CALayer *layer in batch.layers) motion_remove_animations(layer);
		NSArray<id<LuaMotionAnimator>> *animators = [batch.animators copy];
		[batch.animators removeAllObjects];
		for (id<LuaMotionAnimator> animator in animators) [animator motionSettle];
		[batch finish];
	}
	// Completions of unanimated transactions arrive on the next turn.
	[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0]];
	return 0;
}

static void motion_push_value(lua_State *L, id value) {
	if ([value isKindOfClass:NSNumber.class]) { lua_pushnumber(L, [value doubleValue]); return; }
	if ([value isKindOfClass:NSValue.class]) {
		const char *type = [value objCType];
		if (strcmp(type, @encode(CGPoint)) == 0) {
			CGPoint point = motion_value_point(value);
			lua_createtable(L, 0, 2);
			lua_pushnumber(L, point.x); lua_setfield(L, -2, "x");
			lua_pushnumber(L, point.y); lua_setfield(L, -2, "y");
			return;
		}
		if (strcmp(type, @encode(CGRect)) == 0) {
			CGRect rect = motion_value_rect(value);
			lua_createtable(L, 0, 4);
			lua_pushnumber(L, rect.origin.x); lua_setfield(L, -2, "x");
			lua_pushnumber(L, rect.origin.y); lua_setfield(L, -2, "y");
			lua_pushnumber(L, rect.size.width); lua_setfield(L, -2, "width");
			lua_pushnumber(L, rect.size.height); lua_setfield(L, -2, "height");
			return;
		}
		if (strcmp(type, @encode(CATransform3D)) == 0) {
			CATransform3D t = [value CATransform3DValue];
			lua_createtable(L, 0, 3);
			lua_pushnumber(L, sqrt(t.m11 * t.m11 + t.m12 * t.m12)); lua_setfield(L, -2, "scale");
			lua_pushnumber(L, t.m41); lua_setfield(L, -2, "tx");
			lua_pushnumber(L, t.m42); lua_setfield(L, -2, "ty");
			return;
		}
	}
	lua_pushnil(L);
}

// Test hook: _motionAnimations(view) → {[keyPath] = {kind, from, to,
// duration, delay, speed, repeatCount, autoreverses, mass, stiffness,
// damping, count}} for this engine's animations on the view's layer, plus
// its arcs' strokeEnd animations.
static void motion_describe_layer(lua_State *L, CALayer *layer) {
	for (NSString *key in layer.animationKeys) {
		if (!motion_owns_key(key)) continue;
		CAAnimation *animation = [layer animationForKey:key];
		lua_createtable(L, 0, 12);
		NSString *kind = [animation isKindOfClass:CASpringAnimation.class] ? @"spring"
			: [animation isKindOfClass:CAKeyframeAnimation.class] ? @"keyframes"
			: [animation isKindOfClass:CATransition.class] ? @"transition" : @"timing";
		lua_pushstring(L, kind.UTF8String); lua_setfield(L, -2, "kind");
		lua_pushnumber(L, animation.duration); lua_setfield(L, -2, "duration");
		lua_pushnumber(L, animation.speed); lua_setfield(L, -2, "speed");
		lua_pushnumber(L, animation.repeatCount == HUGE_VALF ? -1 : animation.repeatCount); lua_setfield(L, -2, "repeatCount");
		lua_pushboolean(L, animation.autoreverses); lua_setfield(L, -2, "autoreverses");
		CFTimeInterval begin = animation.beginTime;
		lua_pushnumber(L, begin > 0 ? begin - [layer convertTime:CACurrentMediaTime() fromLayer:nil] : 0);
		lua_setfield(L, -2, "delay");
		if ([animation isKindOfClass:CABasicAnimation.class]) {
			CABasicAnimation *basic = (CABasicAnimation *)animation;
			motion_push_value(L, basic.fromValue); lua_setfield(L, -2, "from");
			motion_push_value(L, basic.toValue); lua_setfield(L, -2, "to");
		}
		if ([animation isKindOfClass:CASpringAnimation.class]) {
			CASpringAnimation *spring = (CASpringAnimation *)animation;
			lua_pushnumber(L, spring.mass); lua_setfield(L, -2, "mass");
			lua_pushnumber(L, spring.stiffness); lua_setfield(L, -2, "stiffness");
			lua_pushnumber(L, spring.damping); lua_setfield(L, -2, "damping");
		}
		if ([animation isKindOfClass:CAKeyframeAnimation.class]) {
			lua_pushinteger(L, (lua_Integer)((CAKeyframeAnimation *)animation).values.count);
			lua_setfield(L, -2, "count");
		}
		if ([animation isKindOfClass:CATransition.class]) {
			lua_pushstring(L, ((CATransition *)animation).type.UTF8String); lua_setfield(L, -2, "type");
			NSString *subtype = ((CATransition *)animation).subtype;
			if (subtype) { lua_pushstring(L, subtype.UTF8String); lua_setfield(L, -2, "subtype"); }
		}
		NSString *name = [key isEqualToString:kCATransition] ? @"contents" : [key substringFromIndex:kMotionKeyPrefix.length];
		lua_setfield(L, -2, name.UTF8String);
	}
}

static int bridge_motion_animations(lua_State *L) {
	MotionView *view = check_view(L, 1);
	lua_newtable(L);
	motion_describe_layer(L, view.layer);
	NSMutableArray<CAShapeLayer *> *shapes = [NSMutableArray array];
	for (MotionView *child in view.subviews) motion_shape_layers(child, shapes);
	lua_newtable(L);
	for (NSUInteger i = 0; i < shapes.count; i++) {
		lua_newtable(L);
		motion_describe_layer(L, shapes[i]);
		lua_rawseti(L, -2, (lua_Integer)i + 1);
	}
	lua_setfield(L, -2, "arcs");
	return 1;
}

// Test hook: whether a view is playing its removal transition.
static int bridge_motion_is_leaving(lua_State *L) {
	lua_pushboolean(L, motion_is_leaving(check_view(L, 1)));
	return 1;
}

/* ----- SF Symbol effects ----- */

#if TARGET_OS_IPHONE
#define MotionImageView UIImageView
#else
#define MotionImageView NSImageView
#endif

/* SwiftUI's `.symbolEffect`: the image view's own symbol animations. */
static NSSymbolEffect *motion_symbol_effect(const char *name) {
	if (strcmp(name, "bounce") == 0) return [NSSymbolBounceEffect effect];
	if (strcmp(name, "bounceUp") == 0) return [NSSymbolBounceEffect bounceUpEffect];
	if (strcmp(name, "bounceDown") == 0) return [NSSymbolBounceEffect bounceDownEffect];
	if (strcmp(name, "pulse") == 0) return [NSSymbolPulseEffect effect];
	if (strcmp(name, "variableColor") == 0) return [NSSymbolVariableColorEffect effect];
	if (strcmp(name, "scale") == 0) return [NSSymbolScaleEffect scaleUpEffect];
	if (strcmp(name, "appear") == 0) return [NSSymbolAppearEffect effect];
	if (strcmp(name, "disappear") == 0) return [NSSymbolDisappearEffect effect];
	if (strcmp(name, "wiggle") == 0) return [NSSymbolWiggleEffect effect];
	if (strcmp(name, "rotate") == 0) return [NSSymbolRotateEffect effect];
	if (strcmp(name, "breathe") == 0) return [NSSymbolBreatheEffect effect];
	return nil;
}

// _symbolEffect(imageView, name | nil, {repeating, repeatCount, speed}):
// plays an effect, or removes every effect when name is nil.
static int bridge_symbol_effect(lua_State *L) {
	MotionView *view = check_view(L, 1);
	if (![view isKindOfClass:MotionImageView.class])
		return luaL_error(L, "symbol effects need an image view, not %s", NSStringFromClass(view.class).UTF8String);
	MotionImageView *image = (MotionImageView *)view;
	if (lua_isnoneornil(L, 2)) { [image removeAllSymbolEffects]; return 0; }
	const char *name = luaL_checkstring(L, 2);
	NSSymbolEffect *effect = motion_symbol_effect(name);
	if (!effect) return luaL_error(L, "unknown symbol effect '%s'", name);
	NSSymbolEffectOptions *options = [NSSymbolEffectOptions options];
	if (lua_istable(L, 3)) {
		if (motion_bool_field(L, 3, "repeating")) options = [options optionsWithRepeating];
		double count = motion_field(L, 3, "repeatCount", 0);
		if (count > 0) options = [options optionsWithRepeatCount:(NSInteger)count];
		double speed = motion_field(L, 3, "speed", 0);
		if (speed > 0) options = [options optionsWithSpeed:speed];
	}
	// Reduce Motion: the system renders symbol effects in their reduced form.
	[image addSymbolEffect:effect options:options animated:YES];
	return 0;
}

#define LUA_OBJC_MOTION_FUNCTIONS \
	{"_motionTransaction", bridge_motion_transaction}, \
	{"_motionSetTransition", bridge_motion_set_transition}, \
	{"_motionSetMatched", bridge_motion_set_matched}, \
	{"_motionSetContentTransition", bridge_motion_set_content_transition}, \
	{"_motionInsert", bridge_motion_insert}, \
	{"_motionRemove", bridge_motion_remove}, \
	{"_motionStop", bridge_motion_stop}, \
	{"_keyframeAnimation", bridge_keyframe_animation}, \
	{"_motionReduced", bridge_motion_reduced}, \
	{"_motionOverrideReduceMotion", bridge_motion_override_reduce_motion}, \
	{"_motionSettle", bridge_motion_settle}, \
	{"_motionAnimations", bridge_motion_animations}, \
	{"_motionIsLeaving", bridge_motion_is_leaving}, \
	{"_symbolEffect", bridge_symbol_effect},

/* ----- Effect properties shared by every view ----- */

@interface MotionView (LuaMotionProperties)
@property(nonatomic) CGFloat opacity;
@property(nonatomic) CGFloat scaleEffect;
@property(nonatomic) CGFloat rotationEffect;
@property(nonatomic) CGFloat offsetX;
@property(nonatomic) CGFloat offsetY;
@end

@implementation MotionView (LuaMotionProperties)
- (CGFloat)opacity {
#if TARGET_OS_IPHONE
	return self.alpha;
#else
	return self.alphaValue;
#endif
}
- (void)setOpacity:(CGFloat)value {
	CGFloat clamped = MIN(1, MAX(0, value));
#if TARGET_OS_IPHONE
	self.alpha = clamped;
#else
	motion_layer(self);
	self.alphaValue = clamped;
#endif
}
- (CGFloat)scaleEffect { LuaMotionEffects *e = motion_effects(self, NO); return e ? e.scale : 1; }
- (void)setScaleEffect:(CGFloat)value { motion_effects(self, YES).scale = value; motion_apply_effects(self); }
- (CGFloat)rotationEffect { return motion_effects(self, NO).rotation; }
- (void)setRotationEffect:(CGFloat)value { motion_effects(self, YES).rotation = value; motion_apply_effects(self); }
- (CGFloat)offsetX { return motion_effects(self, NO).offsetX; }
- (void)setOffsetX:(CGFloat)value { motion_effects(self, YES).offsetX = value; motion_apply_effects(self); }
- (CGFloat)offsetY { return motion_effects(self, NO).offsetY; }
- (void)setOffsetY:(CGFloat)value { motion_effects(self, YES).offsetY = value; motion_apply_effects(self); }
@end
