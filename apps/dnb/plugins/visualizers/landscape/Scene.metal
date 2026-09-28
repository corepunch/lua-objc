constant int RIDGES = 6;         // layers, far to near

// A night flight over layered ridges. Far layers drift slowly behind
// fog; the nearest ones rush past and their peaks rise with the spectrum.
static float3 landscapeScene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f) {
	float2 p = float2((uv.x - 0.5) * f.aspect, 1.0 - uv.y); // y up from the bottom
	// Dusk sky: indigo overhead, a neon glow along the far ridges.
	float3 glow = neon(f.hue + 0.05);
	float3 colour = mix(glow * 0.55, float3(0.03, 0.01, 0.08), smoothstep(0.35, 1.0, p.y));
	// Stars: one point per cell, twinkling, only where the sky is dark.
	float2 grid = uv * float2(f.aspect, 1.0) * 70.0;
	float2 cell = floor(grid);
	float2 spot = hash22(cell) * 0.8 + 0.1;
	float star = smoothstep(0.09, 0.0, length(fract(grid) - spot)) * step(0.8, hash21(cell + 5.3));
	colour += star * (0.5 + 0.5 * sin(f.t * 3.0 + hash21(cell + 3.1) * TAU)) * smoothstep(0.5, 0.85, p.y);
	// A low moon that pulses with the kick.
	float2 moon = p - float2(0.28 * f.aspect, 0.66);
	float3 moonColour = mix(glow, float3(1.0), 0.55);
	colour += moonColour * (smoothstep(0.07, 0.066, length(moon)) * 0.8
		+ exp(-length(moon) * 8.0) * (0.2 + 0.35 * f.kick));
	float3 fog = glow * 0.42;
	for (int i = 0; i < RIDGES; i++) {
		float fi = float(i);
		float near = fi / float(RIDGES - 1);
		float scale = 0.7 + 1.4 * (1.0 - near);
		float x = p.x * scale + f.travel * (0.3 + 2.6 * near * near) + fi * 11.3;
		float base = 0.5 - 0.085 * fi;
		float height = base + (0.16 + 0.16 * near) * ridgeNoise(x * 0.9, fi * 3.7) - 0.08;
		// The nearest ridges carry the spectrum on their crests.
		height += spectrumAt(inputs, fract(abs(x) * 0.07), f) * 0.1 * near * near * (1.0 + 0.3 * f.kick);
		if (p.y < height) {
			// Atmospheric perspective: far ridges dissolve into the glow.
			float3 body = mix(float3(0.035, 0.012, 0.06), fog, pow(1.0 - near, 1.4) * 0.85);
			body *= 1.0 - 0.5 * smoothstep(0.0, 0.25, height - p.y) * near;
			float rim = exp(-(height - p.y) * (50.0 + 120.0 * near));
			colour = body + neon(f.hue + 0.35 + 0.08 * fi) * rim * (0.2 + 0.7 * near) * (0.6 + 0.6 * f.level + 0.5 * f.kick);
		}
	}
	// Ground mist rising with the bass.
	colour += fog * exp(-p.y * 10.0) * (0.25 + 0.5 * f.low);
	return colour;
}
