// Crystals — a six-fold kaleidoscope of drifting Voronoi cells whose
// facets light with their slice of the spectrum.
static float3 crystalsScene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f) {
	float2 p = stagePoint(uv, f);
	float angle = atan2(p.y, p.x) + f.travel * 0.2;
	float sector = TAU / 6.0;
	angle = abs(fmod(angle + TAU * 8.0, sector) - sector * 0.5);
	float2 q = float2(cos(angle), sin(angle)) * length(p) * 5.0 + float2(f.travel * 0.6, 0.0);
	float2 cell = floor(q);
	float first = 8.0, second = 8.0;
	float2 id = float2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			float2 c = cell + float2(x, y);
			float2 o = hash22(c);
			o = 0.5 + 0.4 * sin(f.t * 0.6 + o * TAU);
			float d = length(c + o - q);
			if (d < first) { second = first; first = d; id = c; }
			else if (d < second) second = d;
		}
	}
	float h = hash21(id);
	float level = spectrumAt(inputs, h, f);
	float edge = exp(-(second - first) * 30.0);
	float3 tint = neon(f.hue + h * 0.5);
	float3 colour = float3(0.02, 0.008, 0.05);
	// Facets glow from the centre like cut gems, bright with their band.
	colour += tint * (0.08 + level * 1.1) * pow(clamp(1.0 - first, 0.0, 1.0), 1.5);
	colour += mix(tint, float3(1.0), 0.5) * edge * (0.5 + 0.8 * f.high + 0.6 * f.kick);
	colour += tint * step(0.93, h) * f.snare * 0.8; // snare hits flash single facets
	return colour * (1.0 - smoothstep(0.4, 0.9, length(p)) * 0.6);
}
