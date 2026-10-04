-- Level 9: a loop round a frozen lake: spikes, planks, a saw lane, a ferry
-- and a spring to the summit on the far shore.
return {
	id = "avalanche",
	title = "Avalanche Loop",
	biome = "snow",
	about = "Round the lake and up to the summit. Checkpoints keep your place.",
	start = {0.4, 6.4},
	flag = {-6, -6},
	blocks = {
		{"large", 0, 6, yaw = 15}, {"lowLong", 2.2, 6.6, yaw = -20},
		{"long", 4.5, 5.5, h = 1.5, yaw = 10}, {"long", 6.5, 5.4, h = 1.5, yaw = -5},
		{"large", 9, 3, h = 1.5, yaw = 25}, {"lowLarge", 9.2, 0.5, yaw = -15}, {"hexagon", 9.5, -1.8, h = 1.5, yaw = 10},
		{"tall", 8.5, -4.5, h = 2, yaw = -20}, {"long", 6, -5, h = 2, yaw = 8}, {"long", 4, -5.1, h = 2, yaw = -6},
		{"lowLarge", -2, -6, yaw = 30}, {"large", -4, -6.5, h = 1, yaw = -10}, {"tall", -6, -6, h = 4.5, yaw = 15},
		{"lowLarge", -6.5, -2, yaw = -25}, {"large", -6, 1, h = 1, yaw = 20}, {"lowLong", -4, 3.5, yaw = 80},
	},
	props = {
		{"pine", 0.6, 5.4}, {"sign", -0.6, 5.4, yaw = 15}, {"barrel", 2.6, 6.8}, {"smallPine", 9.5, 3.5},
		{"rocks", 8.9, -4}, {"pine", -4.5, -7}, {"tree", -6.5, -6.5}, {"smallPine", -6.5, 1.5},
		{"rail", 5.5, 6.1, yaw = 3, y = 1.5}, {"crate", 4, -4.6, yaw = -6}, {"pipe", -2, -6},
	},
	spikes = {{4.5, 5.5}, {6.5, 5.4}, {9, 0.5}, {6, -5}},
	saws = {{3.2, -5.1, 6.8, -5}},
	planks = {{1.5, -5.5, y = 1.6}, {0, -5.9, y = 1.2}},
	movers = {{from = {-6.5, 1, -3.9}, to = {-6.5, 1, -3.9}}},
	springs = {{-6.6, -2.2}},
	coins = {
		{1.4, 5.4}, {3.6, 5.5}, {7.4, 5.4}, {9, 3}, {9.2, 0.5}, {9.5, -1.8}, {8.5, -4.5}, {6.5, -5}, {4.6, -5.4},
		{1.5, -5.5, y = 2.1}, {-2, -6, lift = 0.7}, {-4, -6.5}, {-6.5, -2}, {-6, 1}, {-4, 3.5},
	},
	stars = {{9.5, -1.8, lift = 1.2}, {-6, -5.6, lift = 1.2}, {-4, 4.2}},
	hearts = {{8.9, 3.4}},
	checkpoints = {{9, 3}, {-2.4, -5.6}},
}
