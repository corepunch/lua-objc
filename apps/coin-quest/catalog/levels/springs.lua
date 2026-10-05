-- Level 2: cliffs round a lagoon, their tops joined by bridges. Springs on
-- the beaches throw the hero up onto them.
return {
	id = "springs",
	title = "Spring Cliffs",
	facing = 15,
	about = "Springs throw you high. Bridges join the cliff tops: follow them round.",
	start = {0.4, 5.6},
	flag = {-6.2, -4.4},
	blocks = {
		-- Continuous land catches missed jumps; the raised route still holds the rewards.
		{"large", 0, 1, w = 28, d = 26, h = 0.8, y = -0.8},
		-- The beach.
		{"lowLarge", 0, 5.4, yaw = 10}, {"lowLarge", 2.2, 6.2, yaw = -30}, {"lowLong", -2.2, 6.4, yaw = 55},
		{"lowHexagon", 3.8, 3.6, yaw = 20},
		-- East cliff.
		{"tall", 6.4, 1.6, yaw = 25, h = 3.5}, {"large", 7.4, 3.4, yaw = -15, h = 0.5}, {"lowLong", 5.4, -0.4, yaw = -40, h = 3.8},
		-- North cliff, two blocks high and turned.
		{"tall", 2.8, -3.6, yaw = -20, h = 4}, {"large", 0.6, -4.6, yaw = 10, h = 4.5}, {"lowLarge", 1.6, -1.6, yaw = 35},
		-- West cliff, highest, the flag on top.
		{"tall", -3.4, -4.6, yaw = 30, h = 5}, {"tall", -6.2, -4.4, yaw = -12, h = 5.5}, {"lowLarge", -4.4, 2.6, yaw = -20},
		{"large", -6.6, 0.8, yaw = 40, h = 0.75},
		-- Ground approaches rejoin the raised routes after a missed jump.
		{"slope", 0, 7.4, w = 2.4, d = 2, h = 0.5, y = 0},
		{"slope", -4.4, 4.4, w = 2.4, d = 2, h = 0.5, y = 0},
		{"slope", 1.6, 0.2, w = 2.4, d = 2, h = 0.5, y = 0},
	},
	props = {
		{"sign", 0.9, 5, yaw = 10}, {"pine", -2.6, 6.8}, {"flowers", 2.4, 6.4}, {"mushrooms", 3.8, 3.6},
		{"barrel", 7.8, 3.8}, {"tree", 6.8, 1}, {"crate", 5.1, -0.2, yaw = -40},
		-- The bridge from the east cliff to the north one.
		{"platform", 4.8, -1.9, yaw = 35, y = 3.5}, {"platform", 4, -2.6, yaw = 40, y = 3.65},
		{"rope", 4.9, -2.6, yaw = 38, y = 3.8},
		{"rocks", 1.6, -1.6}, {"grass", 0.4, -4.2},
		-- The bridge from the north cliff to the west one.
		{"platform", -1.2, -4.8, yaw = -8, y = 4.3}, {"platform", -2.1, -4.7, yaw = 6, y = 4.5},
		{"rail", -1.6, -5.4, yaw = 180, y = 4.6},
		{"pine", -6.6, -5}, {"chest", -5.6, -3.6, yaw = 200}, {"plant", -4.4, 2.6}, {"pipe", -6.6, 0.8},
		-- Groves frame the spring meadow; signs mark the ways back up.
		{"tree", -8, 4}, {"tree", -9, 1.5}, {"smallPine", -8, -1},
		{"pine", 9.5, -2}, {"tree", 10, 5}, {"pine", 5, -7},
		{"tree", -2, 9}, {"smallPine", 4.5, 8.5},
		{"flowers", -7, 3.5}, {"flowers", 8.5, 7}, {"grass", 3, 8},
		{"mushrooms", -7, -1.5}, {"plant", 8, -3}, {"stones", -1, -7},
		{"arrows", -3, 4.5, yaw = 180}, {"sign", 2.8, 0.5, yaw = 20},
		{"barrel", -8, 6}, {"crate", -9, 6, yaw = 15},
		{"flowers", -3, 8}, {"grass", -2, 1}, {"tallFlowers", 5.5, 6.5},
	},
	springs = {{3.8, 3.6}, {1.6, -1.6}, {-4.4, 2.6}},
	coins = {
		{2.2, 6.2}, {-2.2, 6.4}, {7.4, 3.4}, {6.4, 1.6}, {5.4, -0.4}, {4.4, -2.3, lift = 0.4}, {2.8, -3.6},
		{0.6, -4.6}, {-1.6, -4.8, lift = 0.4}, {-3.4, -4.6}, {-4.4, 2.6, lift = 1.2}, {-6.6, 0.8, lift = 0.7},
		{1.6, -1.6, lift = 1.2}, {-6.2, -3.8},
	},
	stars = {{7.6, 3.4, lift = 1.1}, {0.2, -5.2, lift = 1}, {-6.6, 0.8, lift = 1.3}},
	hearts = {{-3.4, -4.2}},
}
