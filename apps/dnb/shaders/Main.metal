// The visualizer's finishing pass. The current scene has drawn into layer 1
// and, during a crossfade, the next into layer 2 (see Kit.metal); this
// crossfades them, adds bloom and finishes the picture.

constant float BLOOM_THRESHOLD = 0.75; // linear light below this does not bloom
constant float BLOOM_GAIN = 0.55;
constant int BLOOM_FIRST = 2;          // finest mip level read, a quarter of the view
constant int BLOOM_LEVELS = 5;

// A layer's colour plus its bloom. The layers are mipmapped every frame, so
// each coarser level is a wider box blur; four taps half a texel apart turn
// its squares into a soft tent, and the levels add up to a long glow.
static float3 layerColour(texture2d<float> layer, float2 uv) {
	constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);
	float3 colour = layer.sample(s, uv, level(0.0)).rgb;
	float3 bloom = float3(0.0);
	float2 size = float2(layer.get_width(), layer.get_height());
	for (int i = 0; i < BLOOM_LEVELS; i++) {
		float lod = float(BLOOM_FIRST + i);
		float2 texel = exp2(lod) / size * 0.5;
		float3 blur = layer.sample(s, uv + float2(texel.x, texel.y), level(lod)).rgb
			+ layer.sample(s, uv + float2(-texel.x, texel.y), level(lod)).rgb
			+ layer.sample(s, uv + float2(texel.x, -texel.y), level(lod)).rgb
			+ layer.sample(s, uv + float2(-texel.x, -texel.y), level(lod)).rgb;
		bloom += max(blur * 0.25 - BLOOM_THRESHOLD, 0.0);
	}
	return colour + bloom * (BLOOM_GAIN / float(BLOOM_LEVELS));
}

fragment float4 visualizer(ShaderVertex in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]],
		texture2d<float> current [[texture(0)]], texture2d<float> next [[texture(1)]]) {
	Frame f = frameOf(inputs);
	float2 uv = in.uv; // 0,0 top-left
	float fade = inputs.values[10];
	float3 colour = layerColour(current, uv);
	if (fade > 0.0) {
		// Crossfade through a brief bloom so the cut reads as a transition.
		float w = smoothstep(0.0, 1.0, fade);
		colour = mix(colour, layerColour(next, uv), w) * (1.0 + 0.6 * sin(w * 3.14159));
	}

	// Finish: a soft vignette around the stage, fine scanlines and grain
	// for a filmic surface.
	float2 v = uv - f.centre;
	colour *= max(1.0 - dot(v, v) * 1.1, 0.3);
	colour *= 0.94 + 0.06 * sin(uv.y * inputs.size.y * 1.5);
	colour += (hash21(uv * inputs.size + fract(f.t) * 91.0) - 0.5) * 0.035;
	colour = colour / (1.0 + colour * 0.35); // gentle tone map keeps highlights from clipping
	return float4(max(colour, 0.0), 1.0);
}
