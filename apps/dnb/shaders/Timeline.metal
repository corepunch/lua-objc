// The arrangement timeline (models/Timeline.lua): one draw of instanced
// rounded rects, a section on the ruler or a block on its lane, into layer 1,
// then the finishing pass adds the bar grid and the fixed playhead. Blocks
// slide right to left: every position is a set bar, the playhead advances by
// its speed times `inputs.age` between updates, so the strip scrolls evenly
// on every display frame.
//
// values: [0] playhead (set bar), [1] bars per second, [2] lane rows,
//         [3] bars in view, [4] bars behind the playhead, [5] ruler height
//         as a fraction of the view, [6] display scale (pixels per point)
// data:   per instance row (-1 is the ruler), first bar, bars, colour

// Family and section tints: the system palette in its dark appearance.
constant float3 TIMELINE_COLOURS[10] = {
	float3(1.000, 0.216, 0.373), // drums: pink
	float3(1.000, 0.624, 0.039), // bass: orange
	float3(0.749, 0.353, 0.949), // chords: purple
	float3(0.353, 0.784, 0.980), // melody: cyan
	float3(1.000, 0.839, 0.039), // structure: yellow
	float3(0.039, 0.518, 1.000), // intro: blue
	float3(1.000, 0.839, 0.039), // build: yellow
	float3(1.000, 0.271, 0.227), // drop: red
	float3(0.251, 0.784, 0.878), // breakdown: teal
	float3(0.557, 0.557, 0.576), // outro: grey
};
constant float TIMELINE_GAP = 1.0;      // points between neighbouring blocks
constant float TIMELINE_RADIUS = 2.5;   // block corner radius in points
constant float TIMELINE_RESTING = 0.45; // a block's opacity away from the playhead
constant float TIMELINE_PAST = 0.5;     // what has played dims further
constant float TIMELINE_GRID = 0.06;    // a bar line's opacity; phrase lines double it

struct TimelineBlock {
	float4 position [[position]];
	float2 pixel;
	float4 rect [[flat]];   // left, top, right, bottom in pixels
	float3 colour [[flat]];
	float strength [[flat]];
};

static float timelinePlayhead(constant ShaderInputs &inputs) {
	return inputs.values[0] + inputs.values[1] * inputs.age;
}

vertex TimelineBlock timelineBlockVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
		constant ShaderInputs &inputs [[buffer(0)]], constant float *data [[buffer(1)]]) {
	float row = data[iid * 4], start = data[iid * 4 + 1], length = data[iid * 4 + 2];
	int colour = int(data[iid * 4 + 3]);
	float playhead = timelinePlayhead(inputs);
	float rows = max(inputs.values[2], 1.0), window = inputs.values[3], left = playhead - inputs.values[4];
	float ruler = inputs.values[5], scale = inputs.values[6];
	float2 size = inputs.size;
	float lane = (1.0 - ruler) / rows;
	float top = row < 0.0 ? 0.0 : ruler + row * lane;
	float bottom = row < 0.0 ? ruler : top + lane;
	float gap = TIMELINE_GAP * scale * 0.5;
	float4 rect = float4((start - left) / window * size.x + gap, top * size.y + gap,
		(start + length - left) / window * size.x - gap, bottom * size.y - gap);
	const uint corners[6] = {0, 1, 2, 2, 1, 3};
	uint corner = corners[vid];
	float2 p = float2((corner & 1) ? rect.z : rect.x, (corner & 2) ? rect.w : rect.y);
	bool playing = start <= playhead && playhead < start + length;
	TimelineBlock out;
	out.position = float4(p.x / size.x * 2.0 - 1.0, 1.0 - p.y / size.y * 2.0, 0.0, 1.0);
	out.pixel = p;
	out.rect = rect;
	out.colour = TIMELINE_COLOURS[colour];
	// The playing block brightens; what has played dims.
	out.strength = playing ? 1.0 : (start + length <= playhead ? TIMELINE_RESTING * TIMELINE_PAST : TIMELINE_RESTING);
	return out;
}

fragment float4 timelineBlockFragment(TimelineBlock in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	float2 centre = (in.rect.xy + in.rect.zw) * 0.5;
	float2 extent = max((in.rect.zw - in.rect.xy) * 0.5, float2(0.0));
	float radius = min(TIMELINE_RADIUS * inputs.values[6], min(extent.x, extent.y));
	float2 q = abs(in.pixel - centre) - extent + radius;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float alpha = saturate(0.5 - d) * in.strength;
	return float4(in.colour * alpha, alpha);
}

fragment float4 timeline(ShaderVertex in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]],
		texture2d<float> blocks [[texture(0)]]) {
	constexpr sampler s(filter::nearest, address::clamp_to_edge);
	float4 colour = blocks.sample(s, in.uv, level(0.0));
	float window = inputs.values[3], behind = inputs.values[4], ruler = inputs.values[5];
	float barsPerPixel = window / inputs.size.x;
	float bar = timelinePlayhead(inputs) - behind + in.uv.x * window;
	// Bar lines under the lanes, stronger on each eight-bar phrase.
	float fromLine = abs(fract(bar + 0.5) - 0.5) / barsPerPixel;
	float phrase = abs(fract(bar / 8.0 + 0.5) - 0.5) * 8.0 / barsPerPixel < 1.0 ? 2.0 : 1.0;
	float grid = in.uv.y > ruler ? saturate(1.0 - fromLine) * TIMELINE_GRID * phrase : 0.0;
	colour += float4(grid) * (1.0 - colour.a);
	// The fixed playhead.
	float head = saturate(1.5 * inputs.values[6] - abs(in.uv.x - behind / window) * inputs.size.x);
	return mix(colour, float4(1.0), head * 0.9);
}
