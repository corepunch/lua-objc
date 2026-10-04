-- Level 7: the first snow. Slopes and wooden ramps climb where a jump
-- would be needed; hexagon stones cross a bay to the east.
return {
	id = "frost",
	title = "Frost Slopes",
	biome = "snow",
	about = "Slopes and ramps are walked, not jumped. The stones across the bay are small: land in the middle.",
	start = {0, 5.6},
	flag = {4.2, -4.6},
	blocks = {
		{"lowLarge", 0, 5.2, h = 0.25, yaw = 8}, {"slope", 0, 2.6, yaw = 5}, {"large", 0.2, 0.6, h = 0.75, yaw = -10},
		{"large", 2.2, 0.4, h = 0.75, yaw = 10}, {"slope", 2.2, 0.4, yaw = 280}, {"tall", 4.2, 0.6, h = 1.5, yaw = -8},
		{"large", 4.4, -2, h = 2, yaw = 20}, {"tall", 4.2, -4.6, h = 2.5, yaw = -15},
		{"hexagon", 6.4, 1.4, h = 1.5, yaw = 20}, {"hexagon", 8.2, 0.2, h = 1.75}, {"hexagon", 9.8, 1.6, h = 2, yaw = -10},
		{"large", 11.8, 0.6, h = 2, yaw = 25},
		{"lowLong", -2.5, 5.6, h = 0.25, yaw = 80}, {"lowLarge", -6, 3.6, yaw = -20}, {"large", -6.6, 1.2, h = 1.25, yaw = 15},
	},
	props = {
		{"pine", 0.7, 5.8}, {"sign", -0.6, 4.6, yaw = 8}, {"smallPine", -0.6, 0.2},
		{"pine", 4.7, -5.1}, {"rocks", 3.6, -1.6}, {"tree", 12.2, 0}, {"smallPine", -6.5, 3.1},
		{"ramp", -6.4, 2.6, yaw = 15, y = 0.5}, {"barrel", -7, 0.8}, {"crate", 12.4, 1.2, yaw = 25},
	},
	planks = {{-4.2, 4.7, y = 0.6}},
	coins = {
		{1, 5.4}, {0, 2.6, lift = 0.3}, {0.2, 0.6}, {2.2, 0.4, lift = 0.3}, {4.2, 0.6}, {4.4, -2}, {6.4, 1.4},
		{8.2, 0.2}, {9.8, 1.6}, {11.8, 0.6}, {-2.5, 5.6}, {-4.2, 4.7, y = 1.1}, {-6, 3.6}, {-6.6, 1.2},
	},
	stars = {{12.4, 1.2, lift = 0.9}, {-6.4, 0.8, lift = 0.6}, {3.6, -5}},
	hearts = {{-5.6, 4.1}},
	checkpoints = {{4.6, 1}},
}
