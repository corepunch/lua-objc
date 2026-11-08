-- Level 2: a spring throws the hero onto a tower too tall to jump; spikes
-- guard the first island.
return {
	id = "hills",
	title = "Spring Hills",
	biome = "grass",
	start = {0, 1, 0.3},
	pieces = {
		{"block-grass-large", 0, 0, 0},
		{"block-grass-large", 2.0, 0, -0.4, yaw = -15},
		{"block-grass-large-tall", 0.2, 0, -3.0, yaw = 10},
		{"block-grass-large-tall", -0.6, 0, -5.6, yaw = -20},
		{"block-grass-large-tall", -0.6, 2, -5.6, yaw = -20},
		{"block-grass-large", 1.8, 0, -7.4, yaw = 30},
		{"block-grass-low-large", 3.9, 0, -6.6, yaw = 5},
		{"tree", 2.6, 1, 0.3, yaw = 10},
		{"flowers-tall", -0.5, 1, 0.6, yaw = 40},
		{"rocks", 1.5, 1, -7.8, yaw = 20},
	},
	coins = {
		{1.8, 1, -1.0},
		{-0.1, 2, -2.7},
		{0.6, 3.4, -3.3},
		{-0.6, 4, -5.6},
		{1.8, 1, -7.2},
	},
	springs = {
		{0.6, 2, -3.3},
	},
	spikes = {
		{2.5, 1, -0.9},
	},
	flag = {4.0, 0.5, -6.7},
}
