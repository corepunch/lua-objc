// Solar System — a sun, planets, comets and an asteroid belt in a nebula,
// seen from a camera flying past one planet after another. World units: the sun has
// radius SPACE_SUN at the origin, orbits lie near the xz plane, y is up.
// Bodies are impostors: camera-facing quads whose fragments intersect the
// view ray with a sphere, so planets stay round and correctly foreshortened
// even as the camera passes a few radii away. Distances advance with the
// travelled distance, so the system turns faster when the music is loud.

constant float SPACE_SUN = 0.55;
constant int SPACE_PLANETS = 5;
constant float SPACE_ORBIT[5] = {1.5, 2.25, 3.05, 4.5, 5.9};
constant float SPACE_SIZE[5] = {0.1, 0.16, 0.12, 0.36, 0.21};
constant float SPACE_TILT[5] = {0.04, -0.05, 0.03, 0.02, -0.06}; // orbital inclination
constant float SPACE_PHASE[5] = {0.4, 2.3, 4.1, 5.3, 1.2};
constant float SPACE_SPIN[5] = {0.5, 0.9, 0.7, 1.6, 1.1};         // turns per unit of travel
constant int SPACE_RINGED = 3;
constant float SPACE_RING_INNER = 1.35; // in planet radii
constant float SPACE_RING_OUTER = 2.4;
constant float3 SPACE_RING_AXIS = float3(0.3, 1.0, 0.18);
constant float SPACE_BELT_INNER = 3.55;
constant float SPACE_BELT_OUTER = 4.0;
constant float SPACE_ORBIT_SPEED = 0.45; // radians per travel at unit radius
constant int SPACE_COMETS = 3;
constant float SPACE_COMET_A[3] = {5.2, 6.5, 4.4};  // semi-major axes
constant float SPACE_COMET_E[3] = {0.82, 0.88, 0.76};
constant float SPACE_COMET_W[3] = {0.6, 2.9, 4.6};  // orientation of the long axis
constant float SPACE_COMET_I[3] = {0.35, -0.25, 0.5};

constant int SPACE_TOUR[8] = {0, 1, 2, 3, 4, 3, 2, 1}; // planets visited, there and back
constant float SPACE_FLYBY_RATE = 0.11;                // flybys per unit of travel
constant float SPACE_FLYBY_BLEND = 0.3;                // the share of a flyby spent crossing to the next

static float3 spacePlanetPosition(int i, const thread Frame &f) {
	float r = SPACE_ORBIT[i];
	float theta = SPACE_PHASE[i] + f.travel * SPACE_ORBIT_SPEED / (r * sqrt(r));
	return float3(cos(theta) * r, sin(theta) * r * SPACE_TILT[i], sin(theta) * r);
}

struct SpaceShot {
	float3 eye, target;
	float roll;
};

// One flyby of the tour's k-th planet at s: −1 approaching, 0 closest,
// 1 leaving, and beyond along the same line. The camera runs against the
// planet's orbital motion, a few radii off its sunward or night side in
// turn, tracks it through closest approach, then turns to face its course,
// banking towards the planet as it passes.
static SpaceShot spaceFlyby(int k, float s, const thread Frame &f) {
	int i = SPACE_TOUR[k % 8];
	float3 planet = spacePlanetPosition(i, f);
	float radius = SPACE_SIZE[i];
	float3 outward = normalize(float3(planet.x, 0.0, planet.z));
	float3 along = float3(outward.z, 0.0, -outward.x); // against the orbital motion
	// Sunward and night side in turn; flipped on the way back, so a planet
	// visited twice is seen from both.
	float side = ((k % 2 == 0) != (k % 8 >= 4)) ? -1.0 : 1.0;
	float3 offset = outward * side * (radius * 3.2 + 0.3) + float3(0.0, 0.12 + radius * 0.8, 0.0);
	float span = 2.6 + radius * 4.0;
	SpaceShot shot;
	shot.eye = planet + offset + along * s * span;
	shot.target = mix(planet, shot.eye + along * 4.0 - offset * 0.5, smoothstep(0.0, 0.85, s));
	float3 right = cross(float3(0.0, 1.0, 0.0), along);
	shot.roll = -sign(dot(planet - shot.eye, right)) * 0.2 * exp(-3.0 * s * s);
	return shot;
}

// The camera flies the tour: each flyby's departure blends into the next
// one's approach, so the path stays continuous between planets.
static Camera spaceCamera(const thread Frame &f) {
	float phase = f.travel * SPACE_FLYBY_RATE;
	int k = int(floor(phase));
	float u = fract(phase);
	SpaceShot shot = spaceFlyby(k, u * 2.0 - 1.0, f);
	float w = smoothstep(1.0 - SPACE_FLYBY_BLEND, 1.0, u);
	if (w > 0.0) {
		SpaceShot next = spaceFlyby(k + 1, u * 2.0 - 3.0, f);
		shot.eye = mix(shot.eye, next.eye, w);
		shot.target = mix(shot.target, next.target, w);
		shot.roll = mix(shot.roll, next.roll, w);
	}
	return lookAt(shot.eye, shot.target, 2.1, shot.roll);
}

// A comet on an eccentric orbit with the sun at a focus. The true anomaly
// comes from the mean anomaly by its series, so it sweeps fast past the sun.
static float3 spaceCometPosition(int i, float travel, thread float3 &velocity) {
	float a = SPACE_COMET_A[i], e = SPACE_COMET_E[i];
	float m = travel * 0.16 / (a * sqrt(a)) * 3.0 + float(i) * 2.1;
	float nu = m + (2.0 * e - 0.25 * e * e * e) * sin(m) + 1.25 * e * e * sin(2.0 * m);
	float r = a * (1.0 - e * e) / (1.0 + e * cos(nu));
	float c = cos(SPACE_COMET_W[i]), s = sin(SPACE_COMET_W[i]);
	float2 flat = float2(cos(nu), sin(nu)) * r;
	float2 turned = float2(flat.x * c - flat.y * s, flat.x * s + flat.y * c);
	float3 p = float3(turned.x, turned.y * sin(SPACE_COMET_I[i]), turned.y * cos(SPACE_COMET_I[i]));
	// Direction of motion: along the orbit, towards increasing anomaly.
	float2 dflat = float2(-sin(nu), e + cos(nu));
	float2 dturned = float2(dflat.x * c - dflat.y * s, dflat.x * s + dflat.y * c);
	velocity = normalize(float3(dturned.x, dturned.y * sin(SPACE_COMET_I[i]), dturned.y * cos(SPACE_COMET_I[i])));
	return p;
}

// Pixels per stage height, for sizes given on screen.
static float spacePixels(constant ShaderInputs &inputs, const thread Frame &f) {
	return inputs.size.y / f.unit.y;
}

static float3 hash33(float3 p) {
	return float3(hash31(p), hash31(p + 19.19), hash31(p + 47.7));
}

// ---- Backdrop: nebula, the galaxy's band and stars, all at infinity.

static float3 spaceStars(float3 dir, float scale, float threshold, float t) {
	float3 c = dir * scale;
	float3 cell = floor(c);
	float3 star = cell + 0.2 + 0.6 * hash33(cell);
	float h = hash31(cell + 7.7);
	float d = length(c - star);
	float twinkle = 0.7 + 0.3 * sin(t * (1.0 + 3.0 * h) + h * 40.0);
	float3 tint = mix(float3(0.7, 0.8, 1.0), float3(1.0, 0.85, 0.7), hash31(cell + 3.3));
	return tint * smoothstep(0.09, 0.0, d) * step(threshold, h) * twinkle * (1.0 + 4.0 * (h - threshold));
}

fragment float4 spaceBackdrop(ShaderVertex in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = spaceCamera(f);
	float3 dir = cameraRay(stagePoint(in.uv, f), cam);
	float3 colour = float3(0.004, 0.003, 0.012);
	// Nebula: two coloured gas clouds with dark dust lanes, breathing with
	// the bass.
	float3 q = dir * 2.1 + float3(0.0, 0.0, f.t * 0.004);
	float gas = fbm3(q, 4);
	float wisps = fbm3(q * 2.3 + gas * 1.5, 3);
	float dust = smoothstep(0.45, 0.7, fbm3(q * 3.1 + 11.0, 3));
	float density = pow(saturate(gas * 1.35 - 0.3), 2.2) * (0.6 + 0.8 * wisps);
	float3 nebula = mix(neon(f.hue + 0.62), neon(f.hue + 0.92), saturate(wisps * 1.6 - 0.35));
	colour += nebula * density * (0.34 + 0.25 * f.low * f.presence) * (1.0 - 0.75 * dust);
	// The galaxy: a faint band of unresolved stars across the sky.
	float band = exp(-pow(dot(dir, normalize(float3(0.25, 0.95, -0.2))) * 5.5, 2.0));
	colour += float3(0.5, 0.45, 0.6) * band * (0.05 + 0.07 * fbm3(dir * 9.0, 3)) * (1.0 - 0.6 * dust);
	colour += spaceStars(dir, 110.0, 0.82, f.t) * (1.0 + band);
	colour += spaceStars(dir, 260.0, 0.7, f.t) * 0.45 * (0.4 + band);
	return float4(colour, 1.0);
}

// ---- Orbits: faint rings along each planet's path.

struct SpaceLine {
	float4 position [[position]];
	float3 colour;
};

vertex SpaceLine spaceOrbitVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
		constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = spaceCamera(f);
	int i = int(iid);
	float theta = float(vid) / 160.0 * TAU;
	float r = SPACE_ORBIT[i];
	float3 p = float3(cos(theta) * r, sin(theta) * r * SPACE_TILT[i], sin(theta) * r);
	SpaceLine out;
	out.position = cameraClip(p, f, cam);
	out.colour = neon(f.hue + 0.5 + 0.08 * float(i)) * (0.05 + 0.1 * spectrumAt(inputs, float(i) / 5.0, f));
	return out;
}

fragment float4 spaceOrbitFragment(SpaceLine in [[stage_in]]) {
	return float4(in.colour, 0.0);
}

// ---- Bodies: camera-facing quads shading a sphere.

struct SpaceBody {
	float4 position [[position]];
	float2 local; // −1…1 across the quad
	float3 world; // the quad point, for the view ray
	float3 centre [[flat]];
	float radius [[flat]];
	int index [[flat]];
};

// A quad facing the camera at the body's depth. `grow` widens it to hold
// the sphere's perspective silhouette, which swells beyond the radius close up.
static SpaceBody spaceBillboard(uint vid, float3 centre, float radius, const thread Frame &f,
		const thread Camera &cam, bool grow = true) {
	float2 corners[6] = {float2(-1, -1), float2(1, -1), float2(-1, 1),
		float2(1, -1), float2(1, 1), float2(-1, 1)};
	float2 c = corners[vid % 6];
	float3 v = cameraView(centre, cam);
	float d = length(centre - cam.eye);
	float extent = grow ? radius * min(d / sqrt(max(d * d - radius * radius, 1e-4)), 4.0) * 1.15 : radius;
	float3 q = float3(v.xy + c * extent, v.z);
	SpaceBody out;
	out.position = viewClip(q, f, cam);
	out.local = c;
	out.world = cam.eye + q.x * cam.right + q.y * cam.up + q.z * cam.forward;
	out.centre = centre;
	out.radius = radius;
	out.index = 0;
	return out;
}

// The sphere's world normal where the view ray through the quad point
// meets it, and the cosine between them; false where the ray misses.
static bool spaceHit(const thread SpaceBody &in, const thread Camera &cam, thread float3 &normal,
		thread float &mu) {
	float3 ray = normalize(in.world - cam.eye);
	float3 oc = cam.eye - in.centre;
	float b = dot(oc, ray);
	float h = b * b - (dot(oc, oc) - in.radius * in.radius);
	if (h < 0.0) return false;
	normal = (oc + ray * (-b - sqrt(h))) / in.radius;
	mu = saturate(-dot(normal, ray));
	return true;
}

vertex SpaceBody spaceSunVertex(uint vid [[vertex_id]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = spaceCamera(f);
	return spaceBillboard(vid, float3(0.0), SPACE_SUN * (1.0 + 0.04 * f.kick), f, cam);
}

fragment float4 spaceSunFragment(SpaceBody in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = spaceCamera(f);
	float3 n;
	float mu;
	if (!spaceHit(in, cam, n, mu)) discard_fragment();
	// Boiling granulation over a limb-darkened disc, white-hot at the centre.
	float grain = fbm3(n * 7.0 + float3(0.0, f.t * 0.08, f.travel * 0.05), 4);
	float3 hot = float3(1.0, 0.93, 0.78), cool = float3(1.0, 0.45, 0.12);
	float3 colour = mix(cool, hot, pow(mu, 0.6)) * (0.55 + 0.45 * mu) * (0.8 + 0.5 * grain);
	colour = mix(colour, neon(f.hue + 0.08), 0.15);
	return float4(colour * (2.4 + 1.6 * f.kick * f.presence + 0.8 * f.level), 1.0);
}

vertex SpaceBody spaceCoronaVertex(uint vid [[vertex_id]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = spaceCamera(f);
	return spaceBillboard(vid, float3(0.0), SPACE_SUN * 6.0, f, cam, false);
}

fragment float4 spaceCoronaFragment(SpaceBody in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	float r = length(in.local) * 6.0; // in sun radii
	float outside = max(r - 1.0, 0.0);
	float angle = atan2(in.local.y, in.local.x);
	// Streamers: slow angular noise stretched outwards; flares on the snare.
	float streamers = fbm(float2(angle * 3.0 + 10.0, r * 0.35 - f.t * 0.05), 3);
	float glow = exp(-outside * 2.2) * 0.9 + exp(-outside * 0.55) * 0.18;
	glow *= 0.75 + 0.9 * streamers * streamers;
	glow *= 1.0 + 1.2 * f.kick * f.presence + 0.6 * f.snare * f.presence;
	float edge = smoothstep(1.0, 0.8, length(in.local));
	return float4(mix(float3(1.0, 0.62, 0.3), neon(f.hue + 0.05), 0.35) * glow * edge, 0.0);
}

vertex SpaceBody spacePlanetVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
		constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = spaceCamera(f);
	int i = int(iid);
	float swell = 1.0 + 0.06 * spectrumAt(inputs, float(i) / 5.0, f) * f.presence;
	SpaceBody out = spaceBillboard(vid, spacePlanetPosition(i, f), SPACE_SIZE[i] * swell, f, cam);
	out.index = i;
	return out;
}

// Surface albedo for planet i at a direction in its own spinning frame.
static float3 spaceSurface(int i, float3 p, const thread Frame &f) {
	if (i == 0) { // cratered rock
		float n = fbm3(p * 4.0, 4);
		float craters = smoothstep(0.62, 0.7, fbm3(p * 9.0 + 3.0, 2));
		return mix(float3(0.42, 0.38, 0.35), float3(0.62, 0.58, 0.52), n) * (1.0 - 0.35 * craters);
	}
	if (i == 1) { // ocean world with continents and clouds
		float land = fbm3(p * 2.2, 5);
		float3 ground = land > 0.52 ? mix(float3(0.16, 0.36, 0.12), float3(0.52, 0.44, 0.28),
			smoothstep(0.55, 0.7, land)) : mix(float3(0.02, 0.1, 0.32), float3(0.05, 0.25, 0.5), land * 1.6);
		ground = mix(ground, float3(0.92), smoothstep(0.75, 0.9, abs(p.y)));
		float clouds = smoothstep(0.5, 0.75, fbm3(p * 3.0 + float3(f.t * 0.02, 0.0, 0.0), 4));
		return mix(ground, float3(0.95), clouds * 0.85);
	}
	if (i == 2) { // rust desert
		float n = fbm3(p * 3.0, 5);
		return mix(float3(0.55, 0.22, 0.1), float3(0.85, 0.55, 0.32), n) * (0.85 + 0.3 * fbm3(p * 12.0, 2));
	}
	if (i == 3) { // banded giant with a storm
		float warp = fbm3(p * 3.0, 3);
		float bands = sin(p.y * 22.0 + warp * 3.0) * 0.5 + 0.5;
		float3 colour = mix(float3(0.72, 0.52, 0.34), float3(0.95, 0.86, 0.7), bands);
		colour = mix(colour, float3(0.55, 0.3, 0.2), smoothstep(0.55, 0.8, sin(p.y * 7.0 + warp) * 0.5 + 0.5) * 0.5);
		float storm = smoothstep(0.22, 0.12, length(float2(atan2(p.z, p.x) - 1.0, (p.y + 0.35) * 2.2)));
		return mix(colour, float3(0.78, 0.32, 0.18), storm);
	}
	// ice world
	float n = fbm3(p * 2.5, 4);
	return mix(float3(0.55, 0.78, 0.9), float3(0.9, 0.97, 1.0), n) * (0.9 + 0.2 * sin(p.y * 30.0 + n * 6.0));
}

constant float3 SPACE_AIR[5] = {float3(0.0), float3(0.35, 0.6, 1.0), float3(1.0, 0.55, 0.35),
	float3(1.0, 0.85, 0.6), float3(0.5, 0.9, 1.0)};

fragment float4 spacePlanetFragment(SpaceBody in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = spaceCamera(f);
	float3 n;
	float mu;
	int i = in.index;
	if (!spaceHit(in, cam, n, mu)) discard_fragment();
	float rr = 1.0 - mu * mu; // towards 1 at the limb
	float3 light = normalize(-in.centre);
	float spin = f.travel * SPACE_SPIN[i] + SPACE_PHASE[i];
	float c = cos(spin), s = sin(spin);
	float3 body = float3(n.x * c - n.z * s, n.y, n.x * s + n.z * c);
	float lit = saturate(dot(n, light));
	float3 colour = spaceSurface(i, body, f) * (lit * 1.25 + 0.035);
	// Atmosphere: a lit rim that pulses with its band of the spectrum.
	float rim = pow(rr, 3.0) * smoothstep(-0.3, 0.4, dot(n, light));
	float band = spectrumAt(inputs, float(i) / 5.0, f);
	colour += SPACE_AIR[i] * rim * (0.6 + 1.2 * band * f.presence + 0.5 * f.kick * f.presence);
	// Seen against the sun, the atmosphere scatters it forward: the night
	// side passes show a bright ring around a dark disc, not a hole.
	float backlit = pow(saturate(dot(normalize(in.world - cam.eye), light)), 3.0);
	colour += (SPACE_AIR[i] + 0.08) * pow(rr, 6.0) * backlit * 2.5;
	// The gas giant's rings cast a band of shadow across its face.
	if (i == SPACE_RINGED) {
		float3 axis = normalize(SPACE_RING_AXIS);
		float3 p = in.centre + n * in.radius;
		float t = -dot(p - in.centre, axis) / dot(light, axis);
		float3 hit = p + light * t;
		float r = length(hit - in.centre) / in.radius;
		if (t > 0.0 && r > SPACE_RING_INNER && r < SPACE_RING_OUTER) colour *= 0.45;
	}
	return float4(colour, 1.0);
}

// ---- The ringed giant's rings: a flat annulus in its equatorial plane.

struct SpaceRing {
	float4 position [[position]];
	float2 local;
	float3 world;
};

vertex SpaceRing spaceRingVertex(uint vid [[vertex_id]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = spaceCamera(f);
	float2 corners[6] = {float2(-1, -1), float2(1, -1), float2(-1, 1),
		float2(1, -1), float2(1, 1), float2(-1, 1)};
	float2 c = corners[vid];
	float3 axis = normalize(SPACE_RING_AXIS);
	float3 e1 = normalize(cross(axis, float3(0.0, 0.0, 1.0)));
	float3 e2 = cross(axis, e1);
	float3 centre = spacePlanetPosition(SPACE_RINGED, f);
	float extent = SPACE_SIZE[SPACE_RINGED] * SPACE_RING_OUTER;
	SpaceRing out;
	out.world = centre + (c.x * e1 + c.y * e2) * extent;
	out.position = cameraClip(out.world, f, cam);
	out.local = c * SPACE_RING_OUTER;
	return out;
}

fragment float4 spaceRingFragment(SpaceRing in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	float r = length(in.local);
	if (r < SPACE_RING_INNER || r > SPACE_RING_OUTER) discard_fragment();
	// Ringlets and gaps, fading at both edges.
	float bands = 0.55 + 0.45 * sin(r * 42.0) * sin(r * 13.0 + 1.0);
	float gap = smoothstep(0.02, 0.05, abs(r - 1.9));
	float edge = smoothstep(SPACE_RING_INNER, SPACE_RING_INNER + 0.1, r)
		* smoothstep(SPACE_RING_OUTER, SPACE_RING_OUTER - 0.25, r);
	float alpha = bands * gap * edge * 0.75;
	// Shadowed where the planet blocks the sun.
	float3 centre = spacePlanetPosition(SPACE_RINGED, f);
	float3 toSun = normalize(-in.world);
	float3 rel = in.world - centre;
	float along = dot(rel, toSun);
	float miss = length(rel - toSun * along) / SPACE_SIZE[SPACE_RINGED];
	float shade = (along < 0.0 && miss < 1.0) ? 0.2 : 1.0;
	float3 colour = float3(0.85, 0.76, 0.62) * shade * (1.0 + 0.4 * f.snare * f.presence);
	return float4(colour * alpha, alpha);
}

// ---- The asteroid belt: points between the third and fourth orbits.

struct SpaceDust {
	float4 position [[position]];
	float size [[point_size]];
	float3 colour;
};

vertex SpaceDust spaceAsteroidVertex(uint vid [[vertex_id]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = spaceCamera(f);
	float id = float(vid);
	float h1 = hash21(float2(id, 1.3)), h2 = hash21(float2(id, 7.1)), h3 = hash21(float2(id, 3.7));
	float r = mix(SPACE_BELT_INNER, SPACE_BELT_OUTER, h1 * h1 * 0.5 + h2 * 0.5);
	float theta = h3 * TAU + f.travel * SPACE_ORBIT_SPEED / (r * sqrt(r));
	float3 p = float3(cos(theta) * r, (hash21(float2(id, 9.9)) - 0.5) * 0.12, sin(theta) * r);
	float3 v = cameraView(p, cam);
	float radius = 0.006 + 0.014 * pow(hash21(float2(id, 5.5)), 3.0);
	SpaceDust out;
	out.position = viewClip(v, f, cam);
	out.size = clamp(radius * cam.focal * 0.5 / max(v.z, 0.1) * spacePixels(inputs, f), 1.0, 8.0);
	float lit = 0.5 + 0.5 * dot(normalize(-p), normalize(cam.eye - p));
	float sparkle = step(0.93, hash21(float2(id, floor(f.t * 4.0)))) * f.kick * f.presence;
	out.colour = float3(0.62, 0.55, 0.48) * (0.15 + 0.4 * lit) + neon(f.hue + 0.2) * sparkle;
	return out;
}

fragment float4 spaceAsteroidFragment(SpaceDust in [[stage_in]], float2 point [[point_coord]]) {
	float r = length(point - 0.5) * 2.0;
	return float4(in.colour * smoothstep(1.0, 0.4, r), 0.0);
}

// ---- Comets: a dust tail (curving back along the orbit), an ion tail
// (straight away from the sun) and a glowing coma. Instance 3c + kind; each
// tail is a strip of camera-facing pairs, the coma the strip's first quad.

struct SpaceTail {
	float4 position [[position]];
	float across; // −1…1
	float along;  // 0 at the head … 1 at the tip
	float3 colour [[flat]];
	int kind [[flat]];
};

vertex SpaceTail spaceCometVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
		constant ShaderInputs &inputs [[buffer(0)]], constant float *params [[buffer(2)]]) {
	Frame f = frameOf(inputs);
	Camera cam = spaceCamera(f);
	int comet = int(iid) / 3, kind = int(iid) % 3;
	int points = int(params[0]);
	float3 velocity;
	float3 head = spaceCometPosition(comet, f.travel, velocity);
	float r = length(head);
	float3 away = head / r;
	float activity = saturate(3.2 / r - 0.25); // tails grow near the sun
	float side = (vid & 1) ? 1.0 : -1.0;
	SpaceTail out;
	out.kind = kind;
	out.across = side;
	if (kind == 2) {
		// Coma: one quad around the head; later vertices collapse onto it.
		int corner = min(int(vid), 3);
		float2 c = float2((corner & 1) ? 1.0 : -1.0, (corner & 2) ? 1.0 : -1.0);
		float3 v = cameraView(head, cam);
		float size = 0.07 + 0.08 * activity;
		out.position = viewClip(float3(v.xy + c * size, v.z), f, cam);
		out.across = c.x;
		out.along = c.y; // reused as the quad's second axis
		out.colour = float3(0.8, 0.95, 1.0) * (0.6 + 1.6 * activity) * (1.0 + 0.8 * f.high * f.presence);
		return out;
	}
	float along = float(vid / 2) / float(points - 1);
	float reach = (0.6 + 2.6 * activity) * (kind == 1 ? 1.25 : 1.0) * (1.0 + 0.35 * f.high * f.presence);
	float3 direction = kind == 1 ? away : normalize(mix(away, -velocity, 0.35 + 0.4 * along));
	float3 p = head + direction * along * reach;
	float3 v = cameraView(p, cam);
	float3 ahead = cameraView(head + direction * (along + 0.02) * reach, cam);
	float2 tangent = normalize(ahead.xy / max(ahead.z, 0.05) - v.xy / max(v.z, 0.05) + 1e-5);
	float width = (kind == 1 ? 0.025 + 0.06 * along : 0.04 + 0.28 * along) * (0.5 + 0.5 * activity);
	out.position = viewClip(float3(v.xy + float2(-tangent.y, tangent.x) * side * width, v.z), f, cam);
	out.along = along;
	out.colour = (kind == 1 ? float3(0.35, 0.65, 1.0) : float3(1.0, 0.9, 0.72)) * activity * 1.4;
	return out;
}

fragment float4 spaceCometFragment(SpaceTail in [[stage_in]]) {
	if (in.kind == 2) {
		float r = length(float2(in.across, in.along));
		return float4(in.colour * (exp(-r * 5.0) * 1.8 + smoothstep(0.18, 0.0, r) * 3.0), 0.0);
	}
	float across = 1.0 - in.across * in.across;
	float intensity = across * across * pow(1.0 - in.along, 1.6) * smoothstep(0.0, 0.05, in.along);
	return float4(in.colour * intensity, 0.0);
}
