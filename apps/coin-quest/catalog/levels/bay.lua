-- Level 4: plank bridges radiate from the hub across the bay; the planks
-- fall a moment after they are stood on and float back later.
return {
	id = "bay",
	title = "Plank Bay",
	facing = 10,
	about = "Loose planks fall a moment after you land on them. Spikes bite only when they are up.",
	start = {0.3, 4.7},
	flag = {0, -6},
	blocks = {
		{"large", 0, 4.2, yaw = 12}, {"lowLarge", 2, 5.6, yaw = -18}, {"low", -1.6, 5.4, yaw = 40},
		{"large", 0.2, -2.4, yaw = -15, h = 1.5}, {"lowLong", -1.8, -3, yaw = 60, h = 1.7},
		{"tall", 0, -5.6, yaw = 20, h = 2.5},
		{"tall", 9.4, 1.2, yaw = -25, h = 2}, {"lowLong", 9, 3.2, yaw = 10, h = 1},
		{"lowLarge", -6.4, 3.8, yaw = 25}, {"large", -6.8, 0.8, yaw = -10, h = 4}, {"low", -8.2, 2.4, yaw = 15},
	},
	props = {
		{"tree", 0.6, 3.6}, {"sign", -0.4, 3.5, yaw = 12}, {"flowers", 2.4, 6},
		{"pine", 0.6, -3}, {"smallPine", 0.5, -6.1}, {"rocks", 9.8, 0.6}, {"barrel", -6.6, 4.4},
		{"crate", -1.6, -3.2, yaw = 60}, {"fence", 9.2, 3.6, yaw = 10}, {"chest", -7.2, 0.4, yaw = 170},
	},
	planks = {{0, 2.2, y = 1.1}, {0.3, 0.6, y = 1.3}, {3.9, 3.4, y = 1}, {5.5, 2.8, y = 1.3}, {7.1, 2.2, y = 1.6},
		{-2.5, 3.6, y = 0.8}, {-4.1, 3.8, y = 0.6}},
	spikes = {{-6, 4.2}, {-5.6, 3.2}, {0.6, -2.2}, {9.2, 3.1}},
	springs = {{-6.9, 3.4}},
	coins = {
		{1.6, 5.2}, {2.4, 5.8}, {0, 2.2, y = 1.6}, {0.3, 0.6, y = 1.8}, {0.2, -2.4}, {0, -5.2}, {3.9, 3.4, y = 1.5},
		{5.5, 2.8, y = 1.8}, {7.1, 2.2, y = 2.1}, {9.4, 1.2}, {9.6, 3.2}, {-2.5, 3.6, y = 1.3}, {-4.1, 3.8, y = 1.1},
		{-5.6, 4.4}, {-6.8, 0.8}, {-1.8, -3},
	},
	stars = {{-6.8, 0.8, lift = 1.2}, {8.8, 1.6}, {-8.2, 2.4, lift = 1}},
	hearts = {{8.8, 0.6}},
	checkpoints = {{-0.4, -2.8}},
}
