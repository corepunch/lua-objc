#pragma mark - SceneView (declarative SceneKit)

/* A SwiftUI-style SceneView: an SCNView whose scene graph is described by
 * records (`<Node>`, `<Camera>`, `<Light>`) in an etlua template. The records
 * reconcile by id like the XML view reconciler: a node keeps its SCNNode,
 * running actions and pose across renders, changed attributes apply in
 * place, new nodes play their insertion transition and missing nodes their
 * removal transition. A node without an id is identified by its position
 * under its parent.
 *
 * Game state moves nodes every frame through `nodeStates`, a list of poses
 * keyed by id, without describing the scene again. An attribute only
 * reapplies when the template changes it, so a template that keeps saying
 * `position="…"` for a spawn point never snaps a moving node back.
 *
 * Every node is two SCNNodes: the outer one carries the pose (position,
 * rotation, scale) and the children; an inner content node carries the
 * model or geometry and the node's idle behaviours (`spin`, `bob`) and
 * transitions, so behaviours and poses never overwrite each other.
 *
 * Models load once per file through SceneKit's importers (OBJ, DAE, USDZ,
 * SCN) and are cloned per node, sharing geometry and materials
 * (shared/scene_models.m, which Reel's offline renderer uses too). Keyboard
 * events and a display-linked frame callback reach Lua through `onKey` and
 * `onFrame`, the two hooks a game loop needs.
 *
 * Touch (and the mouse, so a game can be tried on the Mac) reaches Lua as
 * two gestures: `onSwipe(view, direction)` with left, right, up or down,
 * sent as soon as a drag passes kSceneSwipeDistance, and `onTap(view)` for
 * a press released without travelling. One drag is one swipe or one tap,
 * never both. The view is shared by AppKit and UIKit: only the events and
 * colours differ.
 *
 * A game controller reaches Lua as `gamepad`, read each frame: the stick
 * and the four face buttons of whichever controller is connected. On a
 * touch screen, `virtualGamepad` puts Apple's on-screen controller
 * (GCVirtualController: a thumbstick on the left, A, B, X and Y on the
 * right) over the view while it is in a window; it reads through `gamepad`
 * like a real one. */

#if TARGET_OS_IPHONE
typedef UIColor SceneColor;
#define SCENE_HANDLE "uiview"
#else
typedef NSColor SceneColor;
#define SCENE_HANDLE "nsview"
#endif

/* "#rrggbb" or a semantic colour name. */
static SceneColor *scene_color(NSString *name) {
#if TARGET_OS_IPHONE
	return lua_objc_uikit_system_color(name.UTF8String);
#else
	return semantic_color(name);
#endif
}

@interface LuaSceneEntry : NSObject
@property(nonatomic, copy) NSString *key;
@property(nonatomic, copy) NSString *kind;
@property(nonatomic, strong) SCNNode *node;
@property(nonatomic, strong) SCNNode *content;
@property(nonatomic, copy) NSDictionary *spec;
@end
@implementation LuaSceneEntry
@end

@interface LuaSceneView : SCNView
@property(nonatomic, strong) LuaReg *keyReg;
@property(nonatomic, strong) LuaReg *frameReg;
@property(nonatomic, strong) LuaReg *swipeReg;
@property(nonatomic, strong) LuaReg *tapReg;
/* The drag in progress, in screen points with y growing downwards. */
@property(nonatomic) CGPoint dragOrigin;
@property(nonatomic) BOOL dragging;
@property(nonatomic) BOOL swiped;
@property(nonatomic, strong) NSMutableDictionary<NSString *, LuaSceneEntry *> *entries;
/* Whether the graph has been built once: the first build shows the scene as
 * it is, like a view appearing, and plays no insertion transitions. */
@property(nonatomic) BOOL built;
@property(nonatomic, strong) CADisplayLink *frameLink;
@property(nonatomic) CFTimeInterval lastFrame;
@property(nonatomic, strong) NSMutableSet<NSString *> *heldKeys;
@property(nonatomic) BOOL virtualGamepad;
#if TARGET_OS_IPHONE
@property(nonatomic, strong) GCVirtualController *virtualController;
#endif
- (void)setNodeStates:(NSArray *)states;
- (NSDictionary *)gamepad;
@end

static CGFloat scene_number(NSDictionary *spec, NSString *key, CGFloat fallback) {
	id value = spec[key];
	if ([value isKindOfClass:NSNumber.class]) return [value doubleValue];
	if ([value isKindOfClass:NSString.class] && [value length]) return [value doubleValue];
	return fallback;
}

static BOOL scene_bool(NSDictionary *spec, NSString *key, BOOL fallback) {
	id value = spec[key];
	if ([value isKindOfClass:NSNumber.class]) return [value boolValue];
	if ([value isKindOfClass:NSString.class]) return [value isEqualToString:@"true"] || [value isEqualToString:@"1"];
	return fallback;
}

/* Points the node's front (-z) at a point, upright. Plain `lookAt:` keeps
 * the node's current up vector, so a node turned before would keep a roll;
 * a camera that follows must stay level. */
static void scene_look(SCNNode *node, SCNVector3 target) {
	[node lookAt:target up:SCNVector3Make(0, 1, 0) localFront:SCNVector3Make(0, 0, -1)];
}

/* "x y z" (or a single number for all three) into a vector. */
static SCNVector3 scene_vector(NSDictionary *spec, NSString *key, SCNVector3 fallback) {
	id value = spec[key];
	if ([value isKindOfClass:NSNumber.class]) {
		CGFloat n = [value doubleValue];
		return SCNVector3Make(n, n, n);
	}
	if (![value isKindOfClass:NSString.class]) return fallback;
	NSArray<NSString *> *parts = [[value componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
		filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
	if (parts.count == 1) {
		CGFloat n = parts[0].doubleValue;
		return SCNVector3Make(n, n, n);
	}
	if (parts.count != 3) return fallback;
	return SCNVector3Make(parts[0].doubleValue, parts[1].doubleValue, parts[2].doubleValue);
}

static CGFloat scene_radians(CGFloat degrees) { return degrees * M_PI / 180.0; }

static BOOL scene_changed(NSDictionary *old, NSDictionary *spec, NSString *key) {
	id a = old[key], b = spec[key];
	return !(a == b || [a isEqual:b]);
}

/* Keys whose change replaces the node's content instead of adjusting it. */
static NSArray<NSString *> *scene_content_keys(void) {
	return @[@"model", @"geometry", @"width", @"height", @"length", @"radius", @"chamfer", @"color"];
}

static SCNGeometry *scene_geometry(NSDictionary *spec) {
	NSString *type = spec[@"geometry"];
	CGFloat width = scene_number(spec, @"width", 1), height = scene_number(spec, @"height", 1);
	CGFloat length = scene_number(spec, @"length", 1), radius = scene_number(spec, @"radius", 0.5);
	SCNGeometry *geometry = nil;
	if ([type isEqualToString:@"box"]) geometry = [SCNBox boxWithWidth:width height:height length:length
		chamferRadius:scene_number(spec, @"chamfer", 0)];
	else if ([type isEqualToString:@"sphere"]) geometry = [SCNSphere sphereWithRadius:radius];
	else if ([type isEqualToString:@"cylinder"]) geometry = [SCNCylinder cylinderWithRadius:radius height:height];
	else if ([type isEqualToString:@"cone"]) geometry = [SCNCone coneWithTopRadius:0 bottomRadius:radius height:height];
	else if ([type isEqualToString:@"plane"]) geometry = [SCNPlane planeWithWidth:width height:height];
	else if ([type isEqualToString:@"floor"]) {
		SCNFloor *floor = [SCNFloor floor];
		floor.reflectivity = 0;
		geometry = floor;
	}
	if (geometry && spec[@"color"]) geometry.firstMaterial.diffuse.contents = scene_color(spec[@"color"]);
	return geometry;
}

static SCNLightType scene_light_type(NSString *name) {
	if ([name isEqualToString:@"ambient"]) return SCNLightTypeAmbient;
	if ([name isEqualToString:@"omni"]) return SCNLightTypeOmni;
	if ([name isEqualToString:@"spot"]) return SCNLightTypeSpot;
	return SCNLightTypeDirectional;
}

/* SwiftUI's spring-like pop: overshoots slightly before settling. */
static float scene_ease_out_back(float t) {
	const float s = (float)kSceneTransitionOvershoot;
	t -= 1;
	return t * t * ((s + 1) * t + s) + 1;
}

@implementation LuaSceneView

- (instancetype)initWithFrame:(CGRect)frameRect {
	self = [super initWithFrame:frameRect options:nil];
	if (self) {
		_entries = [NSMutableDictionary dictionary];
		_heldKeys = [NSMutableSet set];
		self.scene = [SCNScene scene];
		self.antialiasingMode = SCNAntialiasingModeMultisampling4X;
		self.allowsCameraControl = NO;
		self.preferredFramesPerSecond = kSceneFramesPerSecond;
	}
	return self;
}

#pragma mark Graph reconciliation

- (void)applyTransition:(NSString *)name to:(LuaSceneEntry *)entry removing:(BOOL)removing {
	SCNNode *node = entry.node;
	NSTimeInterval duration = kSceneTransitionDuration;
	SCNAction *action = nil;
	if ([name isEqualToString:@"pop"]) {
		if (removing) {
			action = [SCNAction group:@[[SCNAction scaleTo:kSceneTransitionPopScale duration:duration],
				[SCNAction fadeOutWithDuration:duration]]];
		} else {
			node.scale = SCNVector3Make(0, 0, 0);
			action = [SCNAction scaleTo:1 duration:duration];
			action.timingFunction = ^float(float t) { return scene_ease_out_back(t); };
		}
	} else if ([name isEqualToString:@"rise"]) {
		CGFloat lift = kSceneTransitionRise;
		if (removing) {
			action = [SCNAction group:@[[SCNAction moveByX:0 y:lift z:0 duration:duration],
				[SCNAction fadeOutWithDuration:duration]]];
		} else {
			node.position = SCNVector3Make(node.position.x, node.position.y - lift, node.position.z);
			node.opacity = 0;
			action = [SCNAction group:@[[SCNAction moveByX:0 y:lift z:0 duration:duration],
				[SCNAction fadeInWithDuration:duration]]];
			action.timingMode = SCNActionTimingModeEaseOut;
		}
	} else if ([name isEqualToString:@"fade"]) {
		if (removing) action = [SCNAction fadeOutWithDuration:duration];
		else { node.opacity = 0; action = [SCNAction fadeInWithDuration:duration]; }
	}
	if (removing) {
		action = action ? [SCNAction sequence:@[action, [SCNAction removeFromParentNode]]] : nil;
		if (action) [node runAction:action forKey:@"transition"]; else [node removeFromParentNode];
	} else if (action) {
		[node runAction:action forKey:@"transition"];
	}
}

/* Idle behaviours run on the content node, so a pose from `nodeStates`
 * never cancels them: `spin` turns the content at that many degrees per
 * second, about the vertical axis for one number or per axis for "x y z";
 * `bob` floats it up and down by that many units every `bobPeriod`. */
- (void)applyBehaviours:(LuaSceneEntry *)entry {
	SCNNode *content = entry.content;
	NSDictionary *spec = entry.spec;
	[content removeActionForKey:@"spin"];
	[content removeActionForKey:@"bob"];
	id spinValue = spec[@"spin"];
	BOOL vertical = [spinValue isKindOfClass:NSNumber.class]
		|| ([spinValue isKindOfClass:NSString.class] && [spinValue rangeOfString:@" "].location == NSNotFound);
	SCNVector3 spin = vertical ? SCNVector3Make(0, scene_number(spec, @"spin", 0), 0)
		: scene_vector(spec, @"spin", SCNVector3Make(0, 0, 0));
	if (spin.x != 0 || spin.y != 0 || spin.z != 0) {
		[content runAction:[SCNAction repeatActionForever:[SCNAction rotateByX:scene_radians(spin.x)
			y:scene_radians(spin.y) z:scene_radians(spin.z) duration:1]] forKey:@"spin"];
	}
	CGFloat bob = scene_number(spec, @"bob", 0);
	if (bob != 0) {
		NSTimeInterval half = scene_number(spec, @"bobPeriod", kSceneBobPeriod) / 2;
		SCNAction *up = [SCNAction moveByX:0 y:bob z:0 duration:half];
		up.timingMode = SCNActionTimingModeEaseInEaseOut;
		[content runAction:[SCNAction repeatActionForever:[SCNAction sequence:@[up, [up reversedAction]]]]
			forKey:@"bob"];
	}
}

- (NSString *)buildContent:(LuaSceneEntry *)entry {
	[entry.content removeFromParentNode];
	SCNNode *content = [SCNNode node];
	NSDictionary *spec = entry.spec;
	NSString *error = nil;
	if ([entry.kind isEqualToString:@"node"]) {
		if (spec[@"model"]) {
			SCNNode *model = scene_model(spec[@"model"], &error);
			if (model) [content addChildNode:model];
		} else if (spec[@"geometry"]) {
			content.geometry = scene_geometry(spec);
			if (!content.geometry) error = [NSString stringWithFormat:@"unknown geometry '%@'", spec[@"geometry"]];
		}
	}
	entry.content = content;
	[entry.node addChildNode:content];
	return error;
}

/* Applies the attributes that differ from `old` (all of them when `old` is
 * nil). Camera and light attributes adjust the existing component. */
- (NSString *)apply:(NSDictionary *)spec to:(LuaSceneEntry *)entry previous:(NSDictionary *)old {
	SCNNode *node = entry.node;
	entry.spec = spec;
	NSString *error = nil;
#define CHANGED(k) (!old || scene_changed(old, spec, k))
	BOOL rebuild = !old;
	for (NSString *key in scene_content_keys()) if (CHANGED(key)) rebuild = YES;
	if (rebuild) {
		error = [self buildContent:entry];
		[self applyBehaviours:entry];
	} else if (CHANGED(@"spin") || CHANGED(@"bob") || CHANGED(@"bobPeriod")) {
		[self applyBehaviours:entry];
	}
	if (CHANGED(@"id") && spec[@"id"]) node.name = spec[@"id"];
	if (CHANGED(@"position")) node.position = scene_vector(spec, @"position", SCNVector3Make(0, 0, 0));
	if (CHANGED(@"rotation")) {
		SCNVector3 degrees = scene_vector(spec, @"rotation", SCNVector3Make(0, 0, 0));
		node.eulerAngles = SCNVector3Make(scene_radians(degrees.x), scene_radians(degrees.y), scene_radians(degrees.z));
	}
	if (CHANGED(@"scale")) node.scale = scene_vector(spec, @"scale", SCNVector3Make(1, 1, 1));
	if (CHANGED(@"hidden")) node.hidden = scene_bool(spec, @"hidden", NO);
	if (CHANGED(@"opacity")) node.opacity = scene_number(spec, @"opacity", 1);
	if (CHANGED(@"castsShadow") || rebuild) {
		BOOL casts = scene_bool(spec, @"castsShadow", YES);
		[entry.content enumerateHierarchyUsingBlock:^(SCNNode *child, BOOL *stop) { (void)stop; child.castsShadow = casts; }];
	}
	if ([entry.kind isEqualToString:@"camera"]) {
		if (!node.camera) node.camera = [SCNCamera camera];
		SCNCamera *camera = node.camera;
		/* A horizontal field of view keeps a scene's width framed however
		 * the window is shaped; vertical is SceneKit's default. */
		camera.projectionDirection = [spec[@"fieldOfViewAxis"] isEqual:@"horizontal"]
			? SCNCameraProjectionDirectionHorizontal : SCNCameraProjectionDirectionVertical;
		camera.fieldOfView = scene_number(spec, @"fieldOfView", kSceneFieldOfView);
		camera.zNear = scene_number(spec, @"zNear", kSceneNearPlane);
		camera.zFar = scene_number(spec, @"zFar", kSceneFarPlane);
		CGFloat orthographic = scene_number(spec, @"orthographicScale", 0);
		camera.usesOrthographicProjection = orthographic > 0;
		if (orthographic > 0) camera.orthographicScale = orthographic;
		if (!self.pointOfView.camera || !old) self.pointOfView = node;
	}
	if ([entry.kind isEqualToString:@"light"]) {
		if (!node.light) node.light = [SCNLight light];
		SCNLight *light = node.light;
		light.type = scene_light_type(spec[@"type"]);
		light.intensity = scene_number(spec, @"intensity", kSceneLightIntensity);
		light.color = spec[@"color"] ? scene_color(spec[@"color"]) : [SceneColor whiteColor];
		light.castsShadow = scene_bool(spec, @"castsShadow", NO);
		if (light.castsShadow) {
			light.shadowMode = SCNShadowModeForward;
			light.shadowRadius = scene_number(spec, @"shadowRadius", kSceneShadowRadius);
			light.shadowSampleCount = kSceneShadowSamples;
			light.shadowMapSize = CGSizeMake(kSceneShadowMapSize, kSceneShadowMapSize);
			light.shadowColor = [SceneColor colorWithWhite:0 alpha:scene_number(spec, @"shadowOpacity", kSceneShadowOpacity)];
		}
	}
	if (spec[@"lookAt"] && (CHANGED(@"lookAt") || CHANGED(@"position"))) {
		scene_look(node, scene_vector(spec, @"lookAt", SCNVector3Make(0, 0, 0)));
	}
#undef CHANGED
	return error;
}

- (void)reconcile:(NSArray *)records parent:(SCNNode *)parent key:(NSString *)parentKey
		seen:(NSMutableSet<NSString *> *)seen errors:(NSMutableArray<NSString *> *)errors {
	[records enumerateObjectsUsingBlock:^(NSDictionary *record, NSUInteger index, BOOL *stop) {
		(void)stop;
		if (![record isKindOfClass:NSDictionary.class]) return;
		NSString *kind = record[@"sceneKind"] ?: @"node";
		NSString *key = record[@"id"] ?: [NSString stringWithFormat:@"%@/%lu", parentKey, (unsigned long)index + 1];
		if ([seen containsObject:key]) {
			[errors addObject:[NSString stringWithFormat:@"duplicate scene node id '%@'", key]];
			return;
		}
		[seen addObject:key];
		NSMutableDictionary *spec = [record mutableCopy];
		[spec removeObjectForKey:@"items"];
		LuaSceneEntry *entry = self.entries[key];
		if (entry && (![entry.kind isEqualToString:kind] || entry.node.parentNode != parent)) {
			[entry.node removeFromParentNode];
			entry = nil;
		}
		NSString *error;
		if (entry) {
			error = [self apply:spec to:entry previous:entry.spec];
		} else {
			entry = [LuaSceneEntry new];
			entry.key = key;
			entry.kind = kind;
			entry.node = [SCNNode node];
			self.entries[key] = entry;
			error = [self apply:spec to:entry previous:nil];
			[parent addChildNode:entry.node];
			if (self.built && spec[@"transition"]) [self applyTransition:spec[@"transition"] to:entry removing:NO];
		}
		if (error) [errors addObject:[NSString stringWithFormat:@"%@: %@", key, error]];
		id children = record[@"items"];
		if ([children isKindOfClass:NSArray.class] && [children count]) {
			[self reconcile:children parent:entry.node key:key seen:seen errors:errors];
		}
	}];
}

/* Reconciles the whole graph; returns the problems it met (unknown
 * geometry, unreadable models, duplicate ids) without stopping. */
- (NSArray<NSString *> *)setGraph:(NSArray *)records {
	NSMutableSet<NSString *> *seen = [NSMutableSet set];
	NSMutableArray<NSString *> *errors = [NSMutableArray array];
	[SCNTransaction begin];
	SCNTransaction.disableActions = YES;
	[self reconcile:records parent:self.scene.rootNode key:@"" seen:seen errors:errors];
	NSMutableSet<SCNNode *> *surviving = [NSMutableSet setWithObject:self.scene.rootNode];
	for (NSString *key in seen) [surviving addObject:self.entries[key].node];
	for (NSString *key in self.entries.allKeys) {
		if ([seen containsObject:key]) continue;
		LuaSceneEntry *entry = self.entries[key];
		[self.entries removeObjectForKey:key];
		/* Only the topmost removed node plays its transition; its
		 * descendants leave with it. */
		if (![surviving containsObject:entry.node.parentNode]) continue;
		if (self.pointOfView == entry.node) self.pointOfView = nil;
		NSString *transition = entry.spec[@"transition"];
		if (transition) [self applyTransition:transition to:entry removing:YES];
		else [entry.node removeFromParentNode];
	}
	[SCNTransaction commit];
	self.built = YES;
	return errors;
}

/* Poses from game state: `{id, x, y, z, yaw, pitch, roll, scale, scaleX,
 * scaleY, scaleZ, opacity, hidden, lookX, lookY, lookZ}`, angles in degrees. Missing fields keep their current value; an
 * unknown id is ignored, so state can describe entities the template has
 * already removed. */
- (void)setNodeStates:(NSArray *)states {
	if (![states isKindOfClass:NSArray.class]) return;
	[SCNTransaction begin];
	SCNTransaction.disableActions = YES;
	for (NSDictionary *state in states) {
		if (![state isKindOfClass:NSDictionary.class]) continue;
		SCNNode *node = self.entries[state[@"id"]].node;
		if (!node) continue;
		if (state[@"x"] || state[@"y"] || state[@"z"]) {
			SCNVector3 p = node.position;
			node.position = SCNVector3Make(scene_number(state, @"x", p.x), scene_number(state, @"y", p.y),
				scene_number(state, @"z", p.z));
		}
		if (state[@"yaw"] || state[@"pitch"] || state[@"roll"]) {
			SCNVector3 e = node.eulerAngles;
			node.eulerAngles = SCNVector3Make(
				state[@"pitch"] ? scene_radians(scene_number(state, @"pitch", 0)) : e.x,
				state[@"yaw"] ? scene_radians(scene_number(state, @"yaw", 0)) : e.y,
				state[@"roll"] ? scene_radians(scene_number(state, @"roll", 0)) : e.z);
		}
		if (state[@"scale"] || state[@"scaleX"] || state[@"scaleY"] || state[@"scaleZ"]) {
			/* `scale` sets all three axes; `scaleX/Y/Z` then adjust one, so
			 * a pose can squash and stretch a node. */
			SCNVector3 current = node.scale;
			CGFloat s = scene_number(state, @"scale", NAN);
			CGFloat x = isnan(s) ? current.x : s, y = isnan(s) ? current.y : s, z = isnan(s) ? current.z : s;
			node.scale = SCNVector3Make(scene_number(state, @"scaleX", x), scene_number(state, @"scaleY", y),
				scene_number(state, @"scaleZ", z));
		}
		if (state[@"opacity"]) node.opacity = scene_number(state, @"opacity", 1);
		if (state[@"hidden"]) node.hidden = scene_bool(state, @"hidden", NO);
		/* `lookX/Y/Z` aims the node at a point, upright, as `lookAt` does
		 * in a template: a following camera turns every frame. */
		if (state[@"lookX"] || state[@"lookY"] || state[@"lookZ"]) {
			scene_look(node, SCNVector3Make(scene_number(state, @"lookX", 0), scene_number(state, @"lookY", 0),
				scene_number(state, @"lookZ", 0)));
		}
	}
	[SCNTransaction commit];
}

- (NSArray *)nodeStates { return @[]; }

#pragma mark Frame loop

#if TARGET_OS_IPHONE
- (void)didMoveToWindow {
	[super didMoveToWindow];
	[self attachWindow];
}
#else
- (void)viewDidMoveToWindow {
	[super viewDidMoveToWindow];
	[self attachWindow];
}
#endif

- (void)attachWindow {
	[self.frameLink invalidate];
	self.frameLink = nil;
	[self attachVirtualGamepad];
	if (!self.window) return;
	if (self.frameReg) {
		self.lastFrame = 0;
#if TARGET_OS_IPHONE
		self.frameLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(frameTick:)];
#else
		self.frameLink = [self displayLinkWithTarget:self selector:@selector(frameTick:)];
#endif
		[self.frameLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
	}
#if !TARGET_OS_IPHONE
	/* A game view takes the keyboard as soon as it appears, like a
	 * focused SwiftUI view with `.focusable()` and `.onKeyPress`. */
	if (self.keyReg && (!self.window.firstResponder || self.window.firstResponder == self.window)) {
		[self.window makeFirstResponder:self];
	}
#endif
}

#pragma mark Game controllers

- (void)setVirtualGamepad:(BOOL)virtualGamepad {
	_virtualGamepad = virtualGamepad;
	[self attachVirtualGamepad];
}

/* The on-screen controller shows while the view is in a window and goes
 * with it. The Mac has no on-screen controller; real ones still read. */
- (void)attachVirtualGamepad {
#if TARGET_OS_IPHONE
	BOOL wanted = self.virtualGamepad && self.window != nil;
	if (wanted && !self.virtualController) {
		GCVirtualControllerConfiguration *configuration = [GCVirtualControllerConfiguration new];
		configuration.elements = [NSSet setWithArray:@[GCInputLeftThumbstick, GCInputButtonA, GCInputButtonB,
			GCInputButtonX, GCInputButtonY]];
		self.virtualController = [GCVirtualController virtualControllerWithConfiguration:configuration];
		[self.virtualController connectWithReplyHandler:nil];
	} else if (!wanted && self.virtualController) {
		[self.virtualController disconnect];
		self.virtualController = nil;
	}
#endif
}

/* The connected controller's stick (`stickX`, `stickY`, y up, the d-pad
 * when the stick rests) and face buttons (`a`, `b`, `x`, `y`), or nil when
 * none is connected. */
- (NSDictionary *)gamepad {
	GCController *controller = GCController.current ?: GCController.controllers.firstObject;
	GCExtendedGamepad *pad = controller.extendedGamepad;
	if (!pad) return nil;
	float x = pad.leftThumbstick.xAxis.value, y = pad.leftThumbstick.yAxis.value;
	if (x == 0 && y == 0) x = pad.dpad.xAxis.value, y = pad.dpad.yAxis.value;
	return @{@"stickX": @(x), @"stickY": @(y), @"a": @(pad.buttonA.isPressed), @"b": @(pad.buttonB.isPressed),
		@"x": @(pad.buttonX.isPressed), @"y": @(pad.buttonY.isPressed)};
}

- (void)sendFrame:(CFTimeInterval)dt {
	lua_State *L = lua_reg_live_state(self.frameReg);
	if (!L || !lua_reg_push(self.frameReg)) return;
	push_objc(L, self, SCENE_HANDLE);
	lua_pushnumber(L, dt);
	lua_objc_pcall(L, 2, 0, "scene frame");
}

- (void)frameTick:(CADisplayLink *)link {
	CFTimeInterval now = link.timestamp;
	CFTimeInterval dt = self.lastFrame > 0 ? now - self.lastFrame : link.targetTimestamp - link.timestamp;
	self.lastFrame = now;
	[self sendFrame:dt];
}

- (BOOL)sendKey:(NSString *)key pressed:(BOOL)pressed {
	lua_State *L = lua_reg_live_state(self.keyReg);
	if (!key.length || !L || !lua_reg_push(self.keyReg)) return NO;
	push_objc(L, self, SCENE_HANDLE);
	lua_pushstring(L, key.UTF8String);
	lua_pushboolean(L, pressed);
	BOOL handled = NO;
	if (lua_objc_pcall(L, 3, 1, "scene key") == LUA_OK) { handled = lua_toboolean(L, -1); lua_pop(L, 1); }
	return handled;
}

#pragma mark Gestures

- (void)sendSwipe:(NSString *)direction {
	lua_State *L = lua_reg_live_state(self.swipeReg);
	if (!L || !lua_reg_push(self.swipeReg)) return;
	push_objc(L, self, SCENE_HANDLE);
	lua_pushstring(L, direction.UTF8String);
	lua_objc_pcall(L, 2, 0, "scene swipe");
}

- (void)sendTap {
	lua_State *L = lua_reg_live_state(self.tapReg);
	if (!L || !lua_reg_push(self.tapReg)) return;
	push_objc(L, self, SCENE_HANDLE);
	lua_objc_pcall(L, 1, 0, "scene tap");
}

- (void)dragBeganAt:(CGPoint)point {
	self.dragOrigin = point;
	self.dragging = YES;
	self.swiped = NO;
}

/* The swipe goes out the moment the finger has travelled far enough, along
 * the axis it moved most, so a game answers while the finger is still down. */
- (void)dragMovedTo:(CGPoint)point {
	if (!self.dragging || self.swiped) return;
	CGFloat dx = point.x - self.dragOrigin.x, dy = point.y - self.dragOrigin.y;
	if (MAX(fabs(dx), fabs(dy)) < kSceneSwipeDistance) return;
	self.swiped = YES;
	[self sendSwipe:fabs(dx) > fabs(dy) ? (dx < 0 ? @"left" : @"right") : (dy < 0 ? @"up" : @"down")];
}

- (void)dragEnded {
	BOOL tapped = self.dragging && !self.swiped;
	self.dragging = NO;
	if (tapped) [self sendTap];
}

- (void)dragCancelled {
	self.dragging = NO;
}

#if TARGET_OS_IPHONE

#pragma mark Touch

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	(void)event;
	if (self.swipeReg || self.tapReg) [self dragBeganAt:[touches.anyObject locationInView:self]];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	(void)event;
	[self dragMovedTo:[touches.anyObject locationInView:self]];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	(void)touches; (void)event;
	[self dragEnded];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	(void)touches; (void)event;
	[self dragCancelled];
}

#pragma mark Hardware keyboard

- (BOOL)canBecomeFirstResponder { return self.keyReg != nil; }

static NSString *scene_key_name(UIKey *key) {
	switch (key.keyCode) {
		case UIKeyboardHIDUsageKeyboardLeftArrow: return @"left";
		case UIKeyboardHIDUsageKeyboardRightArrow: return @"right";
		case UIKeyboardHIDUsageKeyboardDownArrow: return @"down";
		case UIKeyboardHIDUsageKeyboardUpArrow: return @"up";
		case UIKeyboardHIDUsageKeyboardSpacebar: return @"space";
		case UIKeyboardHIDUsageKeyboardReturnOrEnter: return @"return";
		case UIKeyboardHIDUsageKeyboardEscape: return @"escape";
		case UIKeyboardHIDUsageKeyboardTab: return @"tab";
		default: return key.charactersIgnoringModifiers.lowercaseString;
	}
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
	NSMutableSet<UIPress *> *unhandled = [NSMutableSet set];
	for (UIPress *press in presses) {
		NSString *key = press.key ? scene_key_name(press.key) : nil;
		if (key && [self sendKey:key pressed:YES]) [self.heldKeys addObject:key];
		else [unhandled addObject:press];
	}
	if (unhandled.count) [super pressesBegan:unhandled withEvent:event];
}

- (void)releasePresses:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event ended:(BOOL)ended {
	NSMutableSet<UIPress *> *unhandled = [NSMutableSet set];
	for (UIPress *press in presses) {
		NSString *key = press.key ? scene_key_name(press.key) : nil;
		if (key && [self.heldKeys containsObject:key]) {
			[self.heldKeys removeObject:key];
			[self sendKey:key pressed:NO];
		} else [unhandled addObject:press];
	}
	if (!unhandled.count) return;
	if (ended) [super pressesEnded:unhandled withEvent:event];
	else [super pressesCancelled:unhandled withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
	[self releasePresses:presses withEvent:event ended:YES];
}

- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
	[self releasePresses:presses withEvent:event ended:NO];
}

- (void)dealloc {
	[_frameLink invalidate];
}

#else

#pragma mark Keyboard

- (BOOL)acceptsFirstResponder { return self.keyReg != nil; }

static NSString *scene_key_name(NSEvent *event) {
	switch (event.keyCode) {
		case 123: return @"left";
		case 124: return @"right";
		case 125: return @"down";
		case 126: return @"up";
		case 49: return @"space";
		case 36: case 76: return @"return";
		case 53: return @"escape";
		case 48: return @"tab";
		case 51: case 117: return @"delete";
		default: return event.charactersIgnoringModifiers.lowercaseString;
	}
}

/* Keys report presses and releases, not repeats: a game reads which keys
 * are held and paces movement itself. */
- (void)keyDown:(NSEvent *)event {
	if (event.modifierFlags & NSEventModifierFlagCommand) { [super keyDown:event]; return; }
	NSString *key = scene_key_name(event);
	if (event.isARepeat) {
		if (![self.heldKeys containsObject:key]) [super keyDown:event];
		return;
	}
	if ([self sendKey:key pressed:YES]) [self.heldKeys addObject:key];
	else [super keyDown:event];
}

- (void)keyUp:(NSEvent *)event {
	NSString *key = scene_key_name(event);
	if (![self.heldKeys containsObject:key]) { [super keyUp:event]; return; }
	[self.heldKeys removeObject:key];
	[self sendKey:key pressed:NO];
}

/* Leaving the keyboard releases every held key; otherwise a key released
 * in another window would stay down forever. */
- (void)releaseHeldKeys {
	NSSet *held = [self.heldKeys copy];
	[self.heldKeys removeAllObjects];
	for (NSString *key in held) [self sendKey:key pressed:NO];
}

- (BOOL)resignFirstResponder {
	[self releaseHeldKeys];
	return [super resignFirstResponder];
}

- (void)viewWillMoveToWindow:(NSWindow *)window {
	[NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidResignKeyNotification object:nil];
	if (window) {
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowDidResignKey:)
			name:NSWindowDidResignKeyNotification object:window];
	}
	[super viewWillMoveToWindow:window];
}

- (void)windowDidResignKey:(NSNotification *)note {
	(void)note;
	[self releaseHeldKeys];
}

/* The mouse stands in for a finger. */
- (CGPoint)screenPoint:(NSEvent *)event {
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	return CGPointMake(point.x, self.isFlipped ? point.y : self.bounds.size.height - point.y);
}

- (void)mouseDown:(NSEvent *)event {
	if (self.keyReg) [self.window makeFirstResponder:self];
	if (self.swipeReg || self.tapReg) [self dragBeganAt:[self screenPoint:event]];
	else [super mouseDown:event];
}

- (void)mouseDragged:(NSEvent *)event {
	[self dragMovedTo:[self screenPoint:event]];
}

- (void)mouseUp:(NSEvent *)event {
	(void)event;
	[self dragEnded];
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[_frameLink invalidate];
}

#endif

@end

// _sceneView(onKey, onFrame, onSwipe, onTap)
static int bridge_scene_view(lua_State *L) {
	LuaSceneView *view = [[LuaSceneView alloc] initWithFrame:CGRectZero];
	view.keyReg = lua_reg_opt(L, 1);
	view.frameReg = lua_reg_opt(L, 2);
	view.swipeReg = lua_reg_opt(L, 3);
	view.tapReg = lua_reg_opt(L, 4);
	push_objc(L, view, SCENE_HANDLE);
	return 1;
}

/* _sceneGraph(view, records) -> problems: reconciles the scene graph with
 * `records` (see -reconcile:) and returns a list of problems, empty when
 * every node was built. */
static int bridge_scene_graph(lua_State *L) {
	LuaSceneView *view = lua_objc_check_object(L, 1, [LuaSceneView class], "SceneView");
	luaL_checktype(L, 2, LUA_TTABLE);
	id records = lua_to_objc_value(L, 2);
	NSArray<NSString *> *errors = [view setGraph:[records isKindOfClass:NSArray.class] ? records : @[]];
	lua_newtable(L);
	for (NSUInteger index = 0; index < errors.count; index++) {
		lua_pushstring(L, errors[index].UTF8String);
		lua_rawseti(L, -2, (lua_Integer)index + 1);
	}
	return 1;
}

/* _sceneBackground(view, color): the color behind the scene. */
static int bridge_scene_background(lua_State *L) {
	LuaSceneView *view = lua_objc_check_object(L, 1, [LuaSceneView class], "SceneView");
	view.scene.background.contents = lua_isstring(L, 2) ? scene_color(@(lua_tostring(L, 2))) : nil;
	return 0;
}

/* Test hook: every identified node as {kind, parent, x, y, z, yaw, scale,
 * opacity, hidden, model, geometry, children, spinning, bobbing, camera},
 * keyed by id; `camera` is true for the view's point of view. */
static int bridge_scene_nodes(lua_State *L) {
	LuaSceneView *view = lua_objc_check_object(L, 1, [LuaSceneView class], "SceneView");
	[SCNTransaction flush];
	NSMutableDictionary<NSValue *, NSString *> *keys = [NSMutableDictionary dictionary];
	for (LuaSceneEntry *entry in view.entries.allValues) keys[[NSValue valueWithNonretainedObject:entry.node]] = entry.key;
	lua_newtable(L);
	for (LuaSceneEntry *entry in view.entries.allValues) {
		SCNNode *node = entry.node;
		lua_newtable(L);
		lua_pushstring(L, entry.kind.UTF8String); lua_setfield(L, -2, "kind");
		NSString *parent = keys[[NSValue valueWithNonretainedObject:node.parentNode]];
		if (parent) { lua_pushstring(L, parent.UTF8String); lua_setfield(L, -2, "parent"); }
		lua_pushnumber(L, node.position.x); lua_setfield(L, -2, "x");
		lua_pushnumber(L, node.position.y); lua_setfield(L, -2, "y");
		lua_pushnumber(L, node.position.z); lua_setfield(L, -2, "z");
		lua_pushnumber(L, node.eulerAngles.y * 180.0 / M_PI); lua_setfield(L, -2, "yaw");
		lua_pushnumber(L, node.scale.x); lua_setfield(L, -2, "scale");
			lua_pushnumber(L, node.scale.y); lua_setfield(L, -2, "scaleY");
			lua_pushnumber(L, node.eulerAngles.x * 180.0 / M_PI); lua_setfield(L, -2, "pitch");
			lua_pushnumber(L, node.eulerAngles.z * 180.0 / M_PI); lua_setfield(L, -2, "roll");
		lua_pushnumber(L, node.opacity); lua_setfield(L, -2, "opacity");
		lua_pushboolean(L, node.hidden); lua_setfield(L, -2, "hidden");
		lua_pushinteger(L, (lua_Integer)entry.content.childNodes.count + (entry.content.geometry ? 1 : 0));
		lua_setfield(L, -2, "parts");
		lua_pushboolean(L, [entry.content actionForKey:@"spin"] != nil); lua_setfield(L, -2, "spinning");
		lua_pushboolean(L, [entry.content actionForKey:@"bob"] != nil); lua_setfield(L, -2, "bobbing");
		lua_pushboolean(L, view.pointOfView == node); lua_setfield(L, -2, "camera");
		if (node.light) { lua_pushstring(L, node.light.type.UTF8String); lua_setfield(L, -2, "light"); }
		lua_setfield(L, -2, entry.key.UTF8String);
	}
	return 1;
}

/* Test hook, without a window or events: `_sceneSend(view, "key", key,
 * pressed) -> handled`, `_sceneSend(view, "frame", dt)`, `_sceneSend(view,
 * "swipe", direction)`, `_sceneSend(view, "tap")`, or a whole drag through
 * the gesture classifier: `_sceneSend(view, "drag", x0, y0, x1, y1)` in
 * screen points. */
static int bridge_scene_send(lua_State *L) {
	LuaSceneView *view = lua_objc_check_object(L, 1, [LuaSceneView class], "SceneView");
	const char *kind = luaL_checkstring(L, 2);
	if (strcmp(kind, "frame") == 0) {
		[view sendFrame:luaL_checknumber(L, 3)];
		return 0;
	}
	if (strcmp(kind, "swipe") == 0) { [view sendSwipe:@(luaL_checkstring(L, 3))]; return 0; }
	if (strcmp(kind, "tap") == 0) { [view sendTap]; return 0; }
	if (strcmp(kind, "drag") == 0) {
		[view dragBeganAt:CGPointMake(luaL_checknumber(L, 3), luaL_checknumber(L, 4))];
		[view dragMovedTo:CGPointMake(luaL_checknumber(L, 5), luaL_checknumber(L, 6))];
		[view dragEnded];
		return 0;
	}
	lua_pushboolean(L, [view sendKey:@(luaL_checkstring(L, 3)) pressed:lua_toboolean(L, 4)]);
	return 1;
}
