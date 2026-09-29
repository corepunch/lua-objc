#import <SceneKit/SceneKit.h>

/* A SectorChart drawn as raised SceneKit solids instead of flat Arc strokes.
 * Lua (ui/sectors.lua) owns the geometry, heights, hit testing and
 * interaction; this view only renders the sectors it is handed. Each sector is
 * an SCNShape extruded from its outline with square edges and its own soft
 * gradient, standing on a shadow-only floor so the chart rests on the page.
 *
 * Scene units are points; the chart lies in the xy plane with its floor at
 * z = 0 and sectors extruding towards +z. The camera tilts down onto it, like
 * Excel's 3-D pie, so the sides show. Pointer locations are unprojected onto
 * a sector's top face (Lua picks the height) and handed back to Sectors.hit,
 * so hit testing still uses the flat geometry.
 *
 * Opacity is applied by blending towards the window background rather than
 * with SceneKit transparency: a translucent solid would show its own hidden
 * sides, and a clear-backed SCNView does not composite partial alpha the way
 * a CAShapeLayer arc does. */

static NSColor *semantic_color(NSString *name);

static CGFloat sector_scene_number(NSDictionary *spec, NSString *key, CGFloat fallback) {
	NSNumber *value = spec[key];
	return [value isKindOfClass:NSNumber.class] ? value.doubleValue : fallback;
}

@interface LuaSectorSceneView : SCNView <LuaMotionAnimator>
@property(nonatomic, copy) NSArray<NSDictionary *> *sectors;
@property(nonatomic, strong) SCNNode *chartNode;
@property(nonatomic, strong) SCNNode *keyNode;
/* Whether the key light casts the soft contact shadow; on by default.
 * (NSView already owns `shadow`, an NSShadow.) */
@property(nonatomic) BOOL castsShadow;
/* A running transition: sector pairs to tween between, the sectors to show
 * once it ends, the transaction's animation and the display link that steps
 * it while the view is on screen. */
@property(nonatomic, copy) NSArray<NSDictionary *> *transitionFrom;
@property(nonatomic, copy) NSArray<NSDictionary *> *transitionTo;
@property(nonatomic, copy) NSArray<NSDictionary *> *transitionFinal;
@property(nonatomic) MotionSpec transitionSpec;
@property(nonatomic) CFTimeInterval transitionStart;
@property(nonatomic, strong) CADisplayLink *transitionLink;
@end

static SCNNode *sector_scene_light(SCNLightType type, CGFloat intensity) {
	SCNLight *light = [SCNLight light];
	light.type = type;
	light.intensity = intensity;
	SCNNode *node = [SCNNode node];
	node.light = light;
	return node;
}

/* Every slice carries its own gradient across its outline (SCNShape maps a
 * face's texture coordinates to the outline's bounds): a multiplied shade
 * deepens the color towards the lower right, and a faint emitted glow lifts
 * it towards the upper left, where the key light comes from. Together they
 * read as a lit, slightly curved surface rather than a flat fill. */
/* A diagonal ramp holding `from` until `fadeStart` (0 at the lower right, 1
 * at the upper left), then blending to `to`. */
static NSImage *sector_scene_ramp(NSColor *from, NSColor *to, CGFloat fadeStart) {
	return [NSImage imageWithSize:NSMakeSize(64, 64) flipped:NO drawingHandler:^BOOL(NSRect rect) {
		NSGradient *gradient = [[NSGradient alloc] initWithColors:@[from, from, to]
			atLocations:(CGFloat[]){0, fadeStart, 1} colorSpace:NSColorSpace.sRGBColorSpace];
		[gradient drawInRect:rect angle:kSectorSceneGradientAngle];
		return YES;
	}];
}

static NSImage *sector_scene_shade(void) {
	static NSImage *image;
	if (!image) image = sector_scene_ramp([NSColor colorWithWhite:kSectorSceneGradientShade alpha:1], NSColor.whiteColor, 0);
	return image;
}

static NSImage *sector_scene_glow(void) {
	static NSImage *image;
	if (!image) image = sector_scene_ramp(NSColor.blackColor, [NSColor colorWithWhite:kSectorSceneGradientGlow alpha:1],
		1 - kSectorSceneGradientGlowReach);
	return image;
}

@implementation LuaSectorSceneView

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect options:nil];
	if (self) {
		_sectors = @[];
		self.backgroundColor = NSColor.clearColor;
		self.antialiasingMode = SCNAntialiasingModeMultisampling4X;
		self.allowsCameraControl = NO;
		SCNScene *scene = [SCNScene scene];
		self.scene = scene;
		self.chartNode = [SCNNode node];
		[scene.rootNode addChildNode:self.chartNode];

		SCNCamera *camera = [SCNCamera camera];
		camera.fieldOfView = kSectorSceneFieldOfView;
		camera.zNear = 1;
		camera.zFar = kSectorSceneFarPlane;
		SCNNode *cameraNode = [SCNNode node];
		cameraNode.camera = camera;
		[scene.rootNode addChildNode:cameraNode];
		self.pointOfView = cameraNode;

		/* Two lights, both overhead. The key, from above and behind to the
		 * upper left, lights the tops and casts a soft shadow down and to the
		 * right onto the floor. The fill, from above the viewer, is the only
		 * light that reaches the front walls, at a glancing angle, so they
		 * keep their hue but stay darker than the tops. Nothing lights the
		 * chart from below or from the side. */
		SCNNode *keyNode = sector_scene_light(SCNLightTypeDirectional, kSectorSceneKeyIntensity);
		keyNode.eulerAngles = SCNVector3Make(kSectorSceneKeyPitch, kSectorSceneKeyYaw, 0);
		SCNLight *key = keyNode.light;
		key.castsShadow = YES;
		key.shadowMode = SCNShadowModeForward;
		key.shadowColor = [NSColor colorWithWhite:0 alpha:kSectorSceneShadowOpacity];
		key.shadowRadius = kSectorSceneShadowRadius;
		key.shadowSampleCount = kSectorSceneShadowSamples;
		key.shadowMapSize = CGSizeMake(kSectorSceneShadowMapSize, kSectorSceneShadowMapSize);
		key.automaticallyAdjustsShadowProjection = NO;
		key.zNear = 1;
		key.zFar = kSectorSceneShadowDistance * 2;
		[scene.rootNode addChildNode:keyNode];
		self.keyNode = keyNode;
		_castsShadow = YES;
		SCNNode *fillNode = sector_scene_light(SCNLightTypeDirectional, kSectorSceneFillIntensity);
		fillNode.eulerAngles = SCNVector3Make(kSectorSceneFillPitch, 0, 0);
		[scene.rootNode addChildNode:fillNode];

		/* The floor draws nothing but the shadows that fall on it. */
		SCNPlane *floor = [SCNPlane planeWithWidth:kSectorSceneFarPlane height:kSectorSceneFarPlane];
		floor.firstMaterial.lightingModelName = SCNLightingModelShadowOnly;
		[scene.rootNode addChildNode:[SCNNode nodeWithGeometry:floor]];
		[self updateCamera];
	}
	return self;
}

- (void)setCastsShadow:(BOOL)castsShadow {
	_castsShadow = castsShadow;
	self.keyNode.light.castsShadow = castsShadow;
}

- (BOOL)isOpaque { return NO; }
/* The chart's PointerView above this view owns pointer and keyboard input. */
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }

/* The camera sits on a tilted line through the chart's center, far enough
 * back that the outer radius and the tallest ring fit the narrower side. */
- (void)updateCamera {
	CGFloat radius = MAX(MIN(self.bounds.size.width, self.bounds.size.height) / 2.0, 1);
	CGFloat distance = radius * kSectorSceneFitMargin / tan(kSectorSceneFieldOfView * M_PI / 360.0);
	self.pointOfView.position = SCNVector3Make(0, -distance * sin(kSectorSceneTilt), distance * cos(kSectorSceneTilt));
	self.pointOfView.eulerAngles = SCNVector3Make(kSectorSceneTilt, 0, 0);
	/* A directional light's shadow map covers `orthographicScale` around the
	 * light node; back the node away along its beam so the whole chart and
	 * the floor around it fall inside the map. */
	self.keyNode.light.orthographicScale = radius * kSectorSceneShadowCoverage;
	self.keyNode.position = SCNVector3Zero;
	SCNVector3 beam = self.keyNode.worldFront;
	self.keyNode.position = SCNVector3Make(-beam.x * kSectorSceneShadowDistance,
		-beam.y * kSectorSceneShadowDistance, -beam.z * kSectorSceneShadowDistance);
}

- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; [self updateCamera]; }

- (void)viewDidChangeEffectiveAppearance {
	[super viewDidChangeEffectiveAppearance];
	[self renderSectors:self.sectors animated:NO];
}

/* The outline of a sector in scene coordinates (y up, centered). `start` and
 * `end` are the sector's whole share, clockwise from east in y-down points
 * like Arc. Each straight side is offset `gap / 2` from its boundary ray, so
 * the gap between neighbours has parallel sides and the same width at every
 * radius. Returns nil when the gap consumes the sector. */
static NSBezierPath *sector_scene_outline(CGFloat start, CGFloat end, CGFloat inner, CGFloat outer, CGFloat gap) {
	NSBezierPath *path = [NSBezierPath bezierPath];
	path.flatness = kSectorSceneFlatness;
	CGFloat sweep = end - start;
	if (sweep <= 0 || sweep >= kArcFullCircleDegrees) {
		path.windingRule = NSWindingRuleEvenOdd;
		[path appendBezierPathWithOvalInRect:NSMakeRect(-outer, -outer, outer * 2, outer * 2)];
		if (inner > 0) [path appendBezierPathWithOvalInRect:NSMakeRect(-inner, -inner, inner * 2, inner * 2)];
		return path;
	}
	CGFloat half = MAX(0, gap) / 2.0;
	if (half >= outer) return nil;
	/* A side offset `half` from a ray meets radius r at asin(half / r) inside
	 * it. Flipping y turns clockwise-on-screen into decreasing math angles. */
	CGFloat outerInset = asin(half / outer) * 180.0 / M_PI;
	if (sweep <= outerInset * 2) return nil;
	[path appendBezierPathWithArcWithCenter:NSZeroPoint radius:outer
		startAngle:-(start + outerInset) endAngle:-(end - outerInset) clockwise:YES];
	CGFloat innerInset = inner > half ? asin(half / inner) * 180.0 / M_PI : 90;
	if (inner > 0 && sweep > innerInset * 2) {
		[path appendBezierPathWithArcWithCenter:NSZeroPoint radius:inner
			startAngle:-(end - innerInset) endAngle:-(start + innerInset) clockwise:NO];
	} else {
		/* The sides meet before the hole (or the center of a pie): the
		 * sector ends in a point on its bisector. */
		CGFloat middle = -(start + sweep / 2.0) * M_PI / 180.0;
		CGFloat apex = half / sin(sweep / 2.0 * M_PI / 180.0);
		if (apex >= outer) return nil;
		[path lineToPoint:NSMakePoint(cos(middle) * apex, sin(middle) * apex)];
	}
	[path closePath];
	return path;
}

/* Relative luminance, which lightening raises even for a color whose
 * brightest channel is already full. */
static CGFloat sector_scene_luminance(NSColor *color) {
	return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent;
}

/* The top face carries the slice's gradient. The walls and underside are a
 * plain color: SCNShape wraps a face's texture onto its walls as well, and a
 * gradient there reads as a light shining on the chart's lower edge. */
static SCNMaterial *sector_scene_material(BOOL top) {
	SCNMaterial *material = [SCNMaterial material];
	material.lightingModelName = SCNLightingModelPhysicallyBased;
	material.roughness.contents = @(kSectorSceneRoughness);
	material.metalness.contents = @0;
	if (top) {
		material.multiply.contents = sector_scene_shade();
		material.emission.contents = sector_scene_glow();
	}
	return material;
}

/* New sectors from Lua. While a transition runs they become what it ends
 * on, so a hover restyle under the pointer that started a drill does not cut
 * the motion short. */
- (void)applySectors:(NSArray<NSDictionary *> *)sectors animated:(BOOL)animated {
	if (self.transitionTo) { self.transitionFinal = sectors; return; }
	[self renderSectors:sectors animated:animated];
}

/* The running transition's sectors at `progress`. Angles and radii move
 * linearly (a spring may overshoot); the color blends from the old sector's
 * to the new. */
- (NSArray<NSDictionary *> *)transitionSectorsAtProgress:(CGFloat)progress {
	NSMutableArray<NSDictionary *> *sectors = [NSMutableArray array];
	for (NSUInteger index = 0; index < self.transitionTo.count; index++) {
		NSDictionary *from = self.transitionFrom[index], *to = self.transitionTo[index];
		NSMutableDictionary *spec = [to mutableCopy];
		for (NSString *key in @[@"startAngle", @"endAngle", @"inner", @"outer", @"alpha"]) {
			CGFloat a = sector_scene_number(from, key, 0), b = sector_scene_number(to, key, 0);
			spec[key] = @(a + (b - a) * progress);
		}
		spec[@"inner"] = @(MAX(0, [spec[@"inner"] doubleValue]));
		spec[@"highlight"] = @0;
		if (from[@"color"]) spec[@"fromColor"] = from[@"color"];
		spec[@"blend"] = @(MIN(1, MAX(0, progress)));
		[sectors addObject:spec];
	}
	return sectors;
}

- (void)stepTransition:(CADisplayLink *)link {
	(void)link;
	CFTimeInterval elapsed = CACurrentMediaTime() - self.transitionStart;
	if (elapsed >= self.transitionSpec.delay + motion_duration(self.transitionSpec)) { [self motionSettle]; return; }
	[self renderSectors:[self transitionSectorsAtProgress:motion_progress(self.transitionSpec, elapsed)] animated:NO];
}

/* The display link runs only while the view is in a window; a transition
 * begun off screen waits there and ends when the transaction is settled. */
- (void)updateTransitionLink {
	BOOL runs = self.transitionTo != nil && self.window != nil;
	if (runs && !self.transitionLink) {
		self.transitionLink = [self displayLinkWithTarget:self selector:@selector(stepTransition:)];
		[self.transitionLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
	} else if (!runs && self.transitionLink) {
		[self.transitionLink invalidate];
		self.transitionLink = nil;
	}
}

/* Tweens from `from` to `to` (arrays of equal length, paired by index) with
 * the open transaction's animation, then shows `final`. Outside an animated
 * transaction, and under Reduce Motion, `final` shows at once. SCNShape
 * outlines cannot be animated implicitly, so the view is its own animator
 * and rebuilds the moving outlines each frame. */
- (void)transitionFrom:(NSArray<NSDictionary *> *)from to:(NSArray<NSDictionary *> *)to
	final:(NSArray<NSDictionary *> *)final {
	if (self.transitionTo) [self motionSettle];
	MotionSpec spec;
	if (from.count != to.count || from.count == 0 || !motion_animate(self, &spec)) {
		[self renderSectors:final animated:NO];
		return;
	}
	self.transitionFrom = from;
	self.transitionTo = to;
	self.transitionFinal = final;
	self.transitionSpec = spec;
	self.transitionStart = CACurrentMediaTime();
	[self renderSectors:[self transitionSectorsAtProgress:0] animated:NO];
	[self updateTransitionLink];
}

- (void)motionSettle {
	if (!self.transitionTo) return;
	NSArray<NSDictionary *> *final = self.transitionFinal;
	self.transitionFrom = nil; self.transitionTo = nil; self.transitionFinal = nil;
	[self updateTransitionLink];
	/* Transition solids are paired, not the final sectors in order. */
	for (SCNNode *node in [self.chartNode.childNodes copy]) [node removeFromParentNode];
	self.sectors = @[];
	[self renderSectors:final animated:NO];
	motion_animator_finished(self);
}

- (void)viewDidMoveToWindow {
	[super viewDidMoveToWindow];
	[self updateTransitionLink];
}

- (void)renderSectors:(NSArray<NSDictionary *> *)sectors animated:(BOOL)animated {
	NSArray<SCNNode *> *existing = self.chartNode.childNodes;
	NSArray<NSDictionary *> *previous = self.sectors;
	self.sectors = sectors;
	[SCNTransaction begin];
	SCNTransaction.animationDuration = animated ? kSectorSceneHighlightDuration : 0;
	[self.effectiveAppearance performAsCurrentDrawingAppearance:^{
		NSColor *backdrop = [NSColor.windowBackgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
		[sectors enumerateObjectsUsingBlock:^(NSDictionary *spec, NSUInteger index, BOOL *stop) {
			(void)stop;
			CGFloat start = sector_scene_number(spec, @"startAngle", 0);
			CGFloat end = sector_scene_number(spec, @"endAngle", 0);
			CGFloat inner = sector_scene_number(spec, @"inner", 0);
			CGFloat outer = sector_scene_number(spec, @"outer", 0);
			CGFloat height = MAX(0, sector_scene_number(spec, @"height", 0));
			CGFloat gap = MAX(0, sector_scene_number(spec, @"gap", 0));
			CGFloat alpha = MIN(1, MAX(0, sector_scene_number(spec, @"alpha", 1)));
			CGFloat highlight = MIN(1, MAX(0, sector_scene_number(spec, @"highlight", 0)));
			SCNNode *node = index < existing.count ? existing[index] : nil;
			if (!node) {
				node = [SCNNode node];
				[self.chartNode addChildNode:node];
			}
			NSDictionary *old = index < previous.count ? previous[index] : nil;
			BOOL sameShape = old && node.geometry
				&& sector_scene_number(old, @"startAngle", NAN) == start
				&& sector_scene_number(old, @"endAngle", NAN) == end
				&& sector_scene_number(old, @"inner", NAN) == inner
				&& sector_scene_number(old, @"outer", NAN) == outer
				&& sector_scene_number(old, @"height", NAN) == height
				&& sector_scene_number(old, @"gap", NAN) == gap;
			if (!sameShape) {
				NSBezierPath *outline = outer > inner ? sector_scene_outline(start, end, inner, outer, gap) : nil;
				SCNShape *shape = [SCNShape shapeWithPath:outline ?: [NSBezierPath bezierPath] extrusionDepth:height];
				node.hidden = outline == nil;
				/* SCNShape's elements are its top face, underside, then walls. */
				NSArray<SCNMaterial *> *materials = node.geometry.materials;
				shape.materials = materials.count == 3 ? materials
					: @[sector_scene_material(YES), sector_scene_material(NO), sector_scene_material(NO)];
				node.geometry = shape;
			}
			NSColor *color = [semantic_color(spec[@"color"] ?: @"accent") colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
			if (spec[@"fromColor"]) {
				NSColor *origin = [semantic_color(spec[@"fromColor"]) colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
				color = [origin blendedColorWithFraction:sector_scene_number(spec, @"blend", 1) ofColor:color] ?: color;
			}
			CGFloat opacity = color.alphaComponent * alpha;
			/* A highlighted sector stands out from the page where it stands,
			 * top and walls alike: it takes its color at full strength, undoing
			 * any fade towards the backdrop, and then steps further away from
			 * the backdrop, lighter in dark mode and deeper in light mode. It
			 * never moves: under the tilted camera a sector that rose or slid
			 * out covered its neighbours at the back of the chart and left the
			 * pointer at the front, so the highlight flickered and read
			 * differently at every angle. */
			opacity += (1 - opacity) * highlight;
			NSColor *fill = [[color colorWithAlphaComponent:1] blendedColorWithFraction:1 - opacity ofColor:backdrop];
			NSColor *contrast = sector_scene_luminance(backdrop) < 0.5 ? NSColor.whiteColor : NSColor.blackColor;
			fill = [fill blendedColorWithFraction:highlight * kSectorSceneHighlightContrast ofColor:contrast] ?: fill;
			for (SCNMaterial *material in node.geometry.materials) material.diffuse.contents = fill;
			/* SCNShape extrudes about its center; the base rests on the floor. */
			node.position = SCNVector3Make(0, 0, height / 2.0);
		}];
	}];
	for (NSUInteger index = existing.count; index > sectors.count; index--) {
		[existing[index - 1] removeFromParentNode];
	}
	[SCNTransaction commit];
}

@end

static int bridge_sector_scene(lua_State *L) {
	CGFloat width = (CGFloat)luaL_optnumber(L, 1, 160);
	CGFloat height = (CGFloat)luaL_optnumber(L, 2, width);
	LuaSectorSceneView *view = [[LuaSectorSceneView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	push_objc(L, view, "nsview");
	return 1;
}

/* sectorSceneConfigure(view, sectors, animated): `sectors` is an array of
 * {startAngle, endAngle, inner, outer, height, gap, color, alpha, highlight}. Nodes are
 * reused by index; geometry is rebuilt only when a sector's outline moves. */
static NSArray<NSDictionary *> *sector_scene_specs(lua_State *L, int arg) {
	luaL_checktype(L, arg, LUA_TTABLE);
	NSMutableArray<NSDictionary *> *sectors = [NSMutableArray array];
	lua_Integer count = luaL_len(L, arg);
	for (lua_Integer index = 1; index <= count; index++) {
		lua_rawgeti(L, arg, index);
		if (lua_istable(L, -1)) {
			NSMutableDictionary *spec = [NSMutableDictionary dictionary];
			for (NSString *key in @[@"startAngle", @"endAngle", @"inner", @"outer", @"height", @"gap", @"alpha", @"highlight"]) {
				lua_getfield(L, -1, key.UTF8String);
				if (lua_isnumber(L, -1)) spec[key] = @(lua_tonumber(L, -1));
				lua_pop(L, 1);
			}
			lua_getfield(L, -1, "color");
			if (lua_isstring(L, -1)) spec[@"color"] = @(lua_tostring(L, -1));
			lua_pop(L, 1);
			[sectors addObject:spec];
		}
		lua_pop(L, 1);
	}
	return sectors;
}

static int bridge_sector_scene_configure(lua_State *L) {
	BOOL animated = lua_toboolean(L, 3);
	NSArray<NSDictionary *> *sectors = sector_scene_specs(L, 2);
	LuaSectorSceneView *view = lua_objc_check_object(L, 1, [LuaSectorSceneView class], "SectorScene");
	[view applySectors:sectors animated:animated];
	return 0;
}

/* sectorSceneTransition(view, from, to, final): inside an animated
 * transaction, tweens the paired sectors `from[i]` to `to[i]` with its
 * animation, then shows `final`; otherwise shows `final` at once. */
static int bridge_sector_scene_transition(lua_State *L) {
	NSArray<NSDictionary *> *from = sector_scene_specs(L, 2), *to = sector_scene_specs(L, 3);
	NSArray<NSDictionary *> *final = sector_scene_specs(L, 4);
	LuaSectorSceneView *view = lua_objc_check_object(L, 1, [LuaSectorSceneView class], "SectorScene");
	[view transitionFrom:from to:to final:final];
	return 0;
}

/* Test hook: the number of sector pairs in the running transition, 0 when
 * none runs. `_motionSettle` ends it. */
static int bridge_sector_scene_transition_state(lua_State *L) {
	LuaSectorSceneView *view = lua_objc_check_object(L, 1, [LuaSectorSceneView class], "SectorScene");
	lua_pushinteger(L, (lua_Integer)view.transitionTo.count);
	return 1;
}

/* sectorScenePoint(view, x, y, z): the chart point (top-left, y down, like
 * Sectors.hit) under a view point, where the camera ray meets the plane
 * `z` points above the floor. Returns nil when the ray is parallel to it. */
static int bridge_sector_scene_point(lua_State *L) {
	LuaSectorSceneView *view = lua_objc_check_object(L, 1, [LuaSectorSceneView class], "SectorScene");
	CGFloat x = luaL_checknumber(L, 2), y = view.bounds.size.height - luaL_checknumber(L, 3);
	CGFloat plane = luaL_optnumber(L, 4, 0);
	SCNVector3 near = [view unprojectPoint:SCNVector3Make(x, y, 0)];
	SCNVector3 far = [view unprojectPoint:SCNVector3Make(x, y, 1)];
	CGFloat dz = far.z - near.z;
	if (fabs(dz) < 1e-9) { lua_pushnil(L); return 1; }
	CGFloat t = (plane - near.z) / dz;
	CGFloat half = MIN(view.bounds.size.width, view.bounds.size.height) / 2.0;
	lua_pushnumber(L, near.x + (far.x - near.x) * t + half);
	lua_pushnumber(L, half - (near.y + (far.y - near.y) * t));
	return 2;
}

/* Test hook: per node {alpha, height, chamfer, x, y, z} in scene units;
 * alpha is the opacity the node's color was blended to. */
static int bridge_sector_scene_nodes(lua_State *L) {
	LuaSectorSceneView *view = lua_objc_check_object(L, 1, [LuaSectorSceneView class], "SectorScene");
	[SCNTransaction flush];
	lua_newtable(L);
	NSArray<SCNNode *> *nodes = view.chartNode.childNodes;
	for (NSUInteger index = 0; index < nodes.count; index++) {
		SCNNode *node = nodes[index];
		SCNShape *shape = (SCNShape *)node.geometry;
		lua_newtable(L);
		lua_pushnumber(L, shape.extrusionDepth); lua_setfield(L, -2, "height");
		lua_pushnumber(L, shape.chamferRadius); lua_setfield(L, -2, "chamfer");
		lua_pushnumber(L, index < view.sectors.count ? sector_scene_number(view.sectors[index], @"alpha", 1) : 1);
		lua_setfield(L, -2, "alpha");
		lua_pushnumber(L, node.position.x); lua_setfield(L, -2, "x");
		lua_pushnumber(L, node.position.y); lua_setfield(L, -2, "y");
		lua_pushnumber(L, node.position.z); lua_setfield(L, -2, "z");
		NSColor *fill = [node.geometry.firstMaterial.diffuse.contents isKindOfClass:NSColor.class]
			? [node.geometry.firstMaterial.diffuse.contents colorUsingColorSpace:NSColorSpace.sRGBColorSpace] : nil;
		lua_pushnumber(L, fill ? sector_scene_luminance(fill) : 0);
		lua_setfield(L, -2, "luminance");
		lua_rawseti(L, -2, (lua_Integer)index + 1);
	}
	return 1;
}
