-- Level 3: snow. A ramp climbs to the first terrace, spikes sit on it, and
-- a spring on a tall stone reaches the peak.
return {
	id = "peak",
	title = "Snow Peak",
	biome = "snow",
	start = {0, 0.5, 0.4},
	pieces = {
		{"block-snow-low-large", 0, 0, 0},
		{"block-snow-large-slope", 0, 0, -2.08},
		{"block-snow-large", 0, 0, -4.16},
		{"block-snow-large-tall", 2.1, 0, -5.2, yaw = 15},
		{"block-snow-large-tall", -0.2, 0, -7.4, yaw = -25},
		{"block-snow-large-tall", 2.2, 0, -9.4, yaw = 10},
		{"block-snow-large-tall", 2.2, 2, -9.4, yaw = 10},
		{"tree-pine-snow", -0.8, 0.5, -0.6, yaw = 10},
		{"tree-pine-snow-small", 0.6, 1, -4.6, yaw = 60},
		{"stones", -0.5, 2, -7.9, yaw = 20},
	},
	coins = {
		{0, 0.6, -2.0},
		{0.4, 1, -3.8},
		{2.1, 2, -5.2},
		{-0.2, 2, -7.4},
		{2.0, 4, -9.2},
	},
	springs = {
		{0.1, 2, -7.7},
	},
	spikes = {
		{-0.5, 1, -4.5},
	},
	flag = {2.4, 4, -9.6},
}
