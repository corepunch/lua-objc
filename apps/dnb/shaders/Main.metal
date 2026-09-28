// The visualizer's entry point: unpacks the frame header, draws the current
// scene and, during a crossfade, the next, then finishes the picture. The
// `scene(index, …)` dispatcher before it is linked in by views/Visualizer.etlua
// from the loaded scene plugins, in their load order.

fragment float4 visualizer(ShaderVertex in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f;
	f.t = inputs.time;
	f.aspect = inputs.size.x / max(inputs.size.y, 1.0);
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
	float2 uv = in.uv; // 0,0 top-left

	float fade = inputs.values[10];
	float3 colour = scene(int(inputs.values[8]), inputs, uv, f);
	if (fade > 0.0) {
		// Crossfade through a brief bloom so the cut reads as a transition.
		float w = smoothstep(0.0, 1.0, fade);
		colour = mix(colour, scene(int(inputs.values[9]), inputs, uv, f), w) * (1.0 + 0.6 * sin(w * 3.14159));
	}

	// Finish: soft vignette, fine scanlines and grain for a filmic surface.
	float2 v = uv - 0.5;
	colour *= 1.0 - dot(v, v) * 1.1;
	colour *= 0.94 + 0.06 * sin(uv.y * inputs.size.y * 1.5);
	colour += (hash21(uv * inputs.size + fract(f.t) * 91.0) - 0.5) * 0.035;
	colour = colour / (1.0 + colour * 0.35); // gentle tone map keeps highlights from clipping
	return float4(max(colour, 0.0), 1.0);
}
