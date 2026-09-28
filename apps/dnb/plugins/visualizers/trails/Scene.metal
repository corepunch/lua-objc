constant int TRAILS = 9;
constant int TRAIL_SEGMENTS = 28;
constant float TRAIL_SPAN = 1.6; // travel covered by one trail

// Light trails — ribbons tracing rose curves, their length set by the
// travelled distance so they stretch as the music gets louder.
static float3 trailsScene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f) {
	float2 p = float2((uv.x - 0.5) * f.aspect, 0.5 - uv.y);
	float3 colour = float3(0.015, 0.006, 0.04);
	for (int i = 0; i < TRAILS; i++) {
		float fi = float(i);
		float k = 2.0 + fmod(fi, 3.0);
		float amp = 0.32 + 0.12 * spectrumAt(inputs, fi / float(TRAILS), f);
		float3 tint = neon(f.hue + fi / float(TRAILS) * 0.7);
		float glow = 0.0;
		float2 prev = float2(0.0);
		for (int j = 0; j <= TRAIL_SEGMENTS; j++) {
			float s = f.travel * (1.2 + 0.15 * fi) + fi * 0.8 - float(j) * TRAIL_SPAN / float(TRAIL_SEGMENTS);
			float r = amp * (0.35 + 0.65 * cos(k * s * 0.5));
			float2 q = float2(r * cos(s * 0.5 + fi) * f.aspect * 0.8, r * sin(s * 0.5 + fi));
			if (j > 0) {
				float fade = 1.0 - float(j) / float(TRAIL_SEGMENTS);
				float d = segment(p, prev, q);
				// A hot core inside a soft inverse-square halo.
				glow += fade * fade * (0.00012 / (d * d + 0.0004) + smoothstep(0.006 * fade + 0.001, 0.0, d) * 1.2);
			}
			prev = q;
		}
		colour += tint * glow * (0.45 + 0.5 * f.level + 0.6 * f.snare);
	}
	return colour;
}
