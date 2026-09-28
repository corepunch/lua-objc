// Shared Metal library for visualizer plugins (the visualizer host API).
// A scene plugin's Scene.metal defines
//   static float3 <id>Scene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f)
// returning linear colour for uv (0,0 top-left); Main.metal crossfades two
// scenes and finishes the picture. `inputs.values` is written by
// apps/dnb/models/Visuals.lua; Frame unpacks its header:
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
// stage spans ±0.5 vertically and ±f.aspect / 2 horizontally. The picture
// still fills the whole view; outside the stage it continues behind the
// panels.

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

static float2 stagePoint(float2 uv, const thread Frame &f) {
	return (uv - f.centre) * float2(f.unit.x, -f.unit.y);
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
