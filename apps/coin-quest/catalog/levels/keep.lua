-- Level 6: the flag is inside the keep; its only way in is a gate, and the
-- key waits on a pillar a spring reaches.
return {
	id = "keep",
	title = "Locked Keep",
	about = "The gate wants the key. A spring throws you up to it.",
	start = {0.4, 5.6},
	flag = {1, -5.6},
	blocks = {
		{"large", 0, 5, yaw = 10}, {"lowLarge", 2, 6.5, yaw = -20}, {"low", -1.6, 6.4, yaw = 30},
		{"long", 0, 2.6, h = 1, yaw = 90},
		{"tall", -1.5, 0, h = 5.5}, {"tall", 1.5, 0, h = 5.5}, {"long", 0, 0, h = 1, yaw = 90},
		{"tall", -3.2, -1.6, h = 4, yaw = 30}, {"tall", 3.2, -1.6, h = 4, yaw = -30},
		{"large", 0, -3, yaw = 15}, {"large", -2, -4.4, h = 1.5, yaw = -20}, {"tall", 1, -5.6, h = 2.5, yaw = 10},
		{"lowLarge", 5, 4, yaw = 20}, {"large", 7.5, 1.6, h = 4, yaw = -25}, {"lowLong", 8, 4.4, yaw = 15},
		{"lowLarge", -3.8, 5.4, yaw = -15}, {"hexagon", -5.9, 4.4, h = 0.75, yaw = 20},
	},
	props = {
		{"tree", 2.4, 6.9}, {"sign", -0.6, 4.4, yaw = 10}, {"flowers", 0.6, 5.6},
		{"rail", 0.5, 3, yaw = 90, y = 1}, {"rail", -0.5, 2.2, yaw = 270, y = 1},
		{"pine", -2, -3.9}, {"tree", 1.5, -6.1}, {"poles", 0, -2.4},
		{"rocks", 5.4, 4.5}, {"smallPine", 7.9, 1.1}, {"barrel", -4.2, 5.9}, {"crate", 8.4, 4.6, yaw = 15},
	},
	springs = {{5.4, 3.6}},
	keys = {{7.5, 1.6}},
	gates = {{0, 0}},
	coins = {
		{1.6, 6.2}, {2.4, 6.2}, {0, 2.4}, {0, -0.8}, {0, -3}, {-2, -4.4}, {5, 4.4}, {8, 4.4},
		{7.1, 1.2}, {-3.8, 5.4}, {-5.9, 4.4}, {0.6, -5.2},
	},
	stars = {{7.5, 1.6, lift = 1.2}, {-5.9, 4.4, lift = 1.2}, {-2.4, -4.8}},
}
