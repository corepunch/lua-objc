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

@interface LuaSectorSceneView : SCNView
@property(nonatomic, copy) NSArray<NSDictionary *> *sectors;
@property(nonatomic, strong) SCNNode *chartNode;
@property(nonatomic, strong) SCNNode *keyNode;
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

- (BOOL)isOpaque { return NO; }
/* The chart's PointerView above this view owns pointer and keyboard input. */
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }

/* The camera sits on a tilted line through the chart's center, far enough
 * back that the outer radius, the tallest ring and a lifted sector fit the
 * narrower side. */
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
	[self applySectors:self.sectors animated:NO];
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

static CGFloat sector_scene_number(NSDictionary *spec, NSString *key, CGFloat fallback) {
	NSNumber *value = spec[key];
	return [value isKindOfClass:NSNumber.class] ? value.doubleValue : fallback;
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

- (void)applySectors:(NSArray<NSDictionary *> *)sectors animated:(BOOL)animated {
	NSArray<SCNNode *> *existing = self.chartNode.childNodes;
	NSArray<NSDictionary *> *previous = self.sectors;
	self.sectors = sectors;
	[SCNTransaction begin];
	SCNTransaction.animationDuration = animated ? kSectorSceneLiftDuration : 0;
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
			CGFloat lift = MIN(1, MAX(0, sector_scene_number(spec, @"lift", 0)));
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
				NSBezierPath *outline = sector_scene_outline(start, end, inner, outer, gap);
				SCNShape *shape = [SCNShape shapeWithPath:outline ?: [NSBezierPath bezierPath] extrusionDepth:height];
				node.hidden = outline == nil;
				/* SCNShape's elements are its top face, underside, then walls. */
				NSArray<SCNMaterial *> *materials = node.geometry.materials;
				shape.materials = materials.count == 3 ? materials
					: @[sector_scene_material(YES), sector_scene_material(NO), sector_scene_material(NO)];
				node.geometry = shape;
			}
			NSColor *color = [semantic_color(spec[@"color"] ?: @"accent") colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
			CGFloat opacity = color.alphaComponent * alpha;
			NSColor *fill = [[color colorWithAlphaComponent:1] blendedColorWithFraction:1 - opacity ofColor:backdrop];
			for (SCNMaterial *material in node.geometry.materials) material.diffuse.contents = fill;
			/* SCNShape extrudes about its center; the base rests on the floor.
			 * A highlighted sector slides out along its middle and rises, like
			 * an exploded pie slice. */
			CGFloat middle = (start + (end > start ? end : start + 360)) / 2.0 * M_PI / 180.0;
			/* A closed ring has no middle to slide along; it only rises. */
			CGFloat sweep = end - start;
			CGFloat distance = (sweep <= 0 || sweep >= kArcFullCircleDegrees) ? 0 : lift * kSectorSceneLiftDistance;
			node.position = SCNVector3Make(cos(middle) * distance, -sin(middle) * distance,
				height / 2.0 + lift * kSectorSceneLiftHeight);
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
 * {startAngle, endAngle, inner, outer, height, gap, color, alpha, lift}. Nodes are
 * reused by index; geometry is rebuilt only when a sector's outline moves. */
static int bridge_sector_scene_configure(lua_State *L) {
	LuaSectorSceneView *view = lua_objc_check_object(L, 1, [LuaSectorSceneView class], "SectorScene");
	luaL_checktype(L, 2, LUA_TTABLE);
	BOOL animated = lua_toboolean(L, 3);
	NSMutableArray<NSDictionary *> *sectors = [NSMutableArray array];
	lua_Integer count = luaL_len(L, 2);
	for (lua_Integer index = 1; index <= count; index++) {
		lua_rawgeti(L, 2, index);
		if (lua_istable(L, -1)) {
			NSMutableDictionary *spec = [NSMutableDictionary dictionary];
			for (NSString *key in @[@"startAngle", @"endAngle", @"inner", @"outer", @"height", @"gap", @"alpha", @"lift"]) {
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
	[view applySectors:sectors animated:animated];
	return 0;
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
		lua_rawseti(L, -2, (lua_Integer)index + 1);
	}
	return 1;
}
