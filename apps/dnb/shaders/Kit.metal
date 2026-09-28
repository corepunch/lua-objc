// Shared Metal library for visualizer plugins (the visualizer host API).
// A scene draws into its own HDR layer, and shaders/Main.metal crossfades
// the current and next scene's layers, adds bloom and finishes the picture.
// A scene plugin either
//   - lists `draws` in its manifest: meshes whose vertex and fragment
//     functions (named <id>…) live in its Metal file. Geometry is computed
//     per vertex from vertex_id and instance_id, so curves, planets and
//     terrain cost vertices rather than pixels × segments. Or
//   - defines only
//       static float3 <id>Scene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f)
//     returning linear colour for uv (0,0 top-left); the host wraps it in a
//     full-screen draw.
// Every stage unpacks the frame with frameOf(inputs). `inputs.values` is
// written by apps/dnb/models/Visuals.lua:
//   0 level (RMS)      1 kick pulse     2 track hue      3 section intensity
//   4 section progress 5 beat phase     6 presence (0 idle … 1 playing)
//   7 band count N     8 scene          9 next scene     10 crossfade 0…1
//   11 snare pulse     12 low bands     13 high bands    14 travel   15 bar phase
//   16 … 19 stage x, y, width, height (uv of the view)
//   20 … 20+N-1 band levels             20+N … 20+2N-1 peak holds
//
// The stage is the main view rect: the part of the picture no panel covers,
// between the toolbar and the controls. Scenes compose around it, not the
// view, so their subject is never hidden behind glass. stagePoint(uv, f)
// gives a point in stage heights, centred on the stage with y up, so the
// stage spans ±0.5 vertically and ±f.aspect / 2 horizontally; stageClip
// maps such a point back to clip space, and a Camera projects the world
// onto the stage the same way. The picture still fills the whole view;
// outside the stage it continues behind the panels.

constant float TAU = 6.2831853;
constant int HEADER = 20;
constant float BAR_SPAN = 0.47;  // half-width covered by the mirrored spectrum bars
constant float BAR_HEIGHT = 0.4; // tallest bar, in stage heights above the horizon

struct Frame {
	float t, aspect, level, kick, hue, intensity, beat, presence, snare, low, high, travel, phase;
	int n;
	float2 centre; // the stage's centre in uv
	float2 unit;   // uv → stage heights along x and y
};

static Frame frameOf(constant ShaderInputs &inputs) {
	Frame f;
	f.t = inputs.time;
	// The stage, or the whole view before Lua has measured one.
	float4 stage = float4(inputs.values[16], inputs.values[17], inputs.values[18], inputs.values[19]);
	if (stage.z <= 0.0 || stage.w <= 0.0) stage = float4(0.0, 0.0, 1.0, 1.0);
	float viewAspect = inputs.size.x / max(inputs.size.y, 1.0);
	f.aspect = viewAspect * stage.z / stage.w;
	f.centre = stage.xy + stage.zw * 0.5;
	f.unit = float2(viewAspect, 1.0) / stage.w;
	f.level = inputs.values[0];
	f.kick = inputs.values[1];
	f.hue = inputs.values[2];
	f.intensity = inputs.values[3];
	f.beat = inputs.values[5];
	f.presence = inputs.values[6];
	f.n = max(int(inputs.values[7]), 2);
	f.snare = inputs.values[11];
	f.low = inputs.values[12];
	f.high = inputs.values[13];
	f.travel = inputs.values[14];
	f.phase = inputs.values[15];
	return f;
}

static float2 stagePoint(float2 uv, const thread Frame &f) {
	return (uv - f.centre) * float2(f.unit.x, -f.unit.y);
}

// Clip-space position of a stage point, the inverse of stagePoint.
static float4 stageClip(float2 p, const thread Frame &f, float depth = 0.5) {
	float2 uv = f.centre + p / float2(f.unit.x, -f.unit.y);
	return float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
}

// A pinhole camera whose picture spans the stage: `focal` is 1 / tan(fov/2)
// for the stage's height. World units are the scene's own; y is up.
constant float CAMERA_NEAR = 0.05;
constant float CAMERA_FAR = 400.0;

struct Camera {
	float3 eye, forward, right, up;
	float focal;
};

static Camera lookAt(float3 eye, float3 target, float focal, float roll = 0.0) {
	Camera c;
	c.eye = eye;
	c.forward = normalize(target - eye);
	float3 right = normalize(cross(float3(0.0, 1.0, 0.0), c.forward));
	float3 up = cross(c.forward, right);
	c.right = right * cos(roll) + up * sin(roll);
	c.up = up * cos(roll) - right * sin(roll);
	c.focal = focal;
	return c;
}

// Where a world point lands on the stage, and how far ahead it is.
static float3 cameraView(float3 world, const thread Camera &c) {
	float3 d = world - c.eye;
	return float3(dot(d, c.right), dot(d, c.up), dot(d, c.forward));
}

// Clip position of a view-space point (cameraView): the stage mapping of
// stageClip taken through the perspective divide, with standard depth so
// intersecting surfaces resolve correctly.
static float4 viewClip(float3 v, const thread Frame &f, const thread Camera &c) {
	float2 p = v.xy * c.focal * 0.5; // stage point × depth
	float x = (f.centre.x * 2.0 - 1.0) * v.z + 2.0 * p.x / f.unit.x;
	float y = (1.0 - f.centre.y * 2.0) * v.z + 2.0 * p.y / f.unit.y;
	float z = CAMERA_FAR / (CAMERA_FAR - CAMERA_NEAR) * (v.z - CAMERA_NEAR);
	return float4(x, y, z, v.z);
}

static float4 cameraClip(float3 world, const thread Frame &f, const thread Camera &c) {
	return viewClip(cameraView(world, c), f, c);
}

// The world direction through a stage point, for skies and backdrops.
static float3 cameraRay(float2 p, const thread Camera &c) {
	return normalize(c.forward + (p.x * c.right + p.y * c.up) * (2.0 / c.focal));
}

static float3 neon(float t) {
	// Cosine palette sweeping magenta → violet → cyan → amber.
	return 0.55 + 0.45 * cos(TAU * (t + float3(0.0, 0.33, 0.67)));
}

static float hash21(float2 p) {
	p = fract(p * float2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

static float2 hash22(float2 p) {
	float n = hash21(p);
	return float2(n, hash21(p + n + 17.0));
}

static float noise(float2 p) {
	float2 i = floor(p), f = fract(p);
	float2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
		mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}

static float fbm(float2 p, int octaves) {
	float v = 0.0, a = 0.5;
	for (int o = 0; o < octaves; o++) {
		v += a * noise(p);
		p = float2(p.x * 1.6 - p.y * 1.2, p.x * 1.2 + p.y * 1.6) + 3.1; // rotate between octaves
		a *= 0.5;
	}
	return v;
}

static float hash31(float3 p) {
	p = fract(p * float3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

static float noise3(float3 p) {
	float3 i = floor(p), f = fract(p);
	float3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i), hash31(i + float3(1, 0, 0)), u.x),
			mix(hash31(i + float3(0, 1, 0)), hash31(i + float3(1, 1, 0)), u.x), u.y),
		mix(mix(hash31(i + float3(0, 0, 1)), hash31(i + float3(1, 0, 1)), u.x),
			mix(hash31(i + float3(0, 1, 1)), hash31(i + float3(1, 1, 1)), u.x), u.y), u.z);
}

static float fbm3(float3 p, int octaves) {
	float v = 0.0, a = 0.5;
	for (int o = 0; o < octaves; o++) {
		v += a * noise3(p);
		p = p * 2.03 + float3(1.7, 9.2, 4.1);
		a *= 0.5;
	}
	return v;
}

static float ridgeNoise(float x, float seed) {
	float v = 0.0, a = 0.5, f = 1.0;
	for (int o = 0; o < 4; o++) {
		v += a * (1.0 - abs(noise(float2(x * f, seed + float(o) * 7.1)) * 2.0 - 1.0));
		f *= 2.1;
		a *= 0.5;
	}
	return v;
}

static float roundBox(float2 p, float2 extent, float r) {
	float2 q = abs(p) - extent + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

static float segment(float2 p, float2 a, float2 b) {
	float2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
	return length(pa - ba * h);
}

static float band(constant ShaderInputs &inputs, int i, int n, float idle, float t) {
	float v = inputs.values[HEADER + clamp(i, 0, n - 1)];
	float breathe = idle * (0.05 + 0.035 * sin(t * 1.7 + float(i) * 0.55));
	return max(v, breathe);
}

// Band level at a 0…1 position across the spectrum, interpolated.
static float spectrumAt(constant ShaderInputs &inputs, float x, const thread Frame &f) {
	float idle = 1.0 - f.presence;
	float s = clamp(x, 0.0, 1.0) * float(f.n - 1);
	int i = int(floor(s));
	return mix(band(inputs, i, f.n, idle, f.t), band(inputs, i + 1, f.n, idle, f.t), fract(s));
}

// Colour and coverage of the spectrum at `p` (x centred on 0, y up from the
// horizon, both in height units).
static float4 spectrumBars(constant ShaderInputs &inputs, float2 p, const thread Frame &f) {
	int n = f.n;
	float idle = 1.0 - f.presence;
	float span = BAR_SPAN * f.aspect;
	float slot = span / float(n);
	float ax = abs(p.x);
	int centre = int(floor(ax / slot));
	float3 colour = float3(0.0);
	float alpha = 0.0;
	for (int k = -1; k <= 1; k++) {
		int i = centre + k;
		if (i < 0 || i >= n) continue;
		float level = band(inputs, i, n, idle, f.t);
		float h = max(level * BAR_HEIGHT * (1.0 + 0.12 * f.kick), 0.004);
		float2 c = float2((float(i) + 0.5) * slot, h * 0.5);
		float d = roundBox(float2(ax, p.y) - c, float2(slot * 0.34, h * 0.5), slot * 0.3);
		float heat = clamp(p.y / BAR_HEIGHT, 0.0, 1.0);
		float3 tint = neon(f.hue + 0.55 * float(i) / float(n) + 0.25 * heat);
		tint = mix(tint, float3(1.0, 0.95, 0.9), smoothstep(0.55, 1.0, heat) * level * 0.7);
		float body = smoothstep(0.0015, -0.0015, d);
		float glow = exp(-max(d, 0.0) * 55.0) * (0.35 + 0.65 * level) * (0.55 + 0.6 * f.kick);
		colour += tint * (body * 1.15 + glow * 0.55);
		alpha = max(alpha, max(body, glow * 0.6));
		// Peak cap: a thin bright line that falls back after holding.
		float peak = max(inputs.values[HEADER + n + i] * BAR_HEIGHT * (1.0 + 0.12 * f.kick), 0.0);
		float capD = roundBox(float2(ax, p.y) - float2(c.x, peak + 0.012), float2(slot * 0.34, 0.0035), 0.003);
		float cap = smoothstep(0.0015, -0.0015, capD) + exp(-max(capD, 0.0) * 120.0) * 0.4;
		colour += mix(tint, float3(1.0), 0.6) * cap * step(0.01, peak);
		alpha = max(alpha, cap);
	}
	return float4(colour, alpha);
}

static float3 sky(float2 uv, float2 p, const thread Frame &f) {
	float3 colour = mix(float3(0.035, 0.012, 0.075), float3(0.10, 0.02, 0.14), uv.y);
	for (int r = 0; r < 2; r++) {
		float fr = float(r);
		float wave = sin(p.x * (2.2 + fr) + f.t * (0.23 + 0.1 * fr) + sin(p.x * 1.3 - f.t * 0.17 + fr) * 1.6);
		float y = 0.26 + 0.07 * fr + 0.06 * wave;
		float ribbon = exp(-pow((p.y - y) * (9.0 - 2.0 * fr), 2.0));
		colour += neon(f.hue + 0.18 + 0.2 * fr + 0.05 * wave) * ribbon * (0.12 + 0.2 * f.intensity)
			* (0.5 + 0.5 * f.presence + 0.6 * f.kick);
	}
	return colour;
}
