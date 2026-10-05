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
		-- Continuous land catches missed jumps; the raised route still holds the rewards.
		{"large", 2, 1, w = 32, d = 24, h = 0.8, y = -0.8},
		{"lowLarge", 0, 5.2, h = 0.25, yaw = 8}, {"slope", 0, 2.6, yaw = 5}, {"large", 0.2, 0.6, h = 0.75, yaw = -10},
		{"large", 2.2, 0.4, h = 0.75, yaw = 10}, {"slope", 2.2, 0.4, yaw = 280}, {"tall", 4.2, 0.6, h = 1.5, yaw = -8},
		{"large", 4.4, -2, h = 2, yaw = 20}, {"tall", 4.2, -4.6, h = 2.5, yaw = -15},
		{"hexagon", 6.4, 1.4, h = 1.5, yaw = 20}, {"hexagon", 8.2, 0.2, h = 1.75}, {"hexagon", 9.8, 1.6, h = 2, yaw = -10},
		{"large", 11.8, 0.6, h = 2, yaw = 25},
		{"lowLong", -2.5, 5.6, h = 0.25, yaw = 80}, {"lowLarge", -6, 3.6, yaw = -20}, {"large", -6.6, 1.2, h = 1.25, yaw = 15},
		-- Ground approaches rejoin the raised routes after a missed jump.
		{"slope", 0, 7.2, w = 2.4, d = 2, h = 0.25, y = 0},
		{"slope", -6, 5.6, w = 2.4, d = 2, h = 0.5, y = 0},
		{"slope", 14.4, 0.6, w = 2.4, d = 3, yaw = 90, h = 2, y = 0},
	},
	props = {
		{"pine", 0.7, 5.8}, {"sign", -0.6, 4.6, yaw = 8}, {"smallPine", -0.6, 0.2},
		{"pine", 4.7, -5.1}, {"rocks", 3.6, -1.6}, {"tree", 12.2, 0}, {"smallPine", -6.5, 3.1},
		{"ramp", -6.4, 2.6, yaw = 15, y = 0.5}, {"barrel", -7, 0.8}, {"crate", 11.4, 1.2, yaw = 25},
		-- Snow groves and a sled-store yard border the slope practice area.
		{"pine", -9, 5}, {"smallPine", -10, 2}, {"tree", -9, -2},
		{"pine", 0, -7}, {"tree", 8, -5}, {"smallPine", 13, -3},
		{"pine", 10, 6}, {"smallPine", 5, 8}, {"tree", -3, 9},
		{"crate", -8, 6.5, yaw = 15}, {"barrel", -9, 6.5},
		{"fence", -8.5, 7.3}, {"stones", 7, 6}, {"rocks", -4, -2},
		{"stones", 2, -6}, {"sign", 15, 2.2, yaw = 90},
		{"arrows", -4.5, 5.7, yaw = 180}, {"barrel", 12, 5.5},
		{"smallPine", 14.5, 4.5}, {"rocks", -6, -5},
	},
	planks = {{-4.2, 4.7, y = 0.6}},
	coins = {
		{1, 5.4}, {0, 2.6, lift = 0.3}, {0.2, 0.6}, {2.2, 0.4, lift = 0.3}, {4.2, 0.6}, {4.4, -2}, {6.4, 1.4},
		{8.2, 0.2}, {9.8, 1.6}, {11.8, 0.6}, {-2.5, 5.6}, {-4.2, 4.7, y = 1.1}, {-6, 3.6}, {-6.6, 1.2},
	},
	stars = {{11.4, 1.2, lift = 0.9}, {-6.4, 0.8, lift = 0.6}, {3.6, -5}},
	hearts = {{-5.6, 4.1}},
	checkpoints = {{4.6, 1}},
}
