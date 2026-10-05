-- Level 6: the flag is inside the keep; its only way in is a gate, and the
-- key waits on a pillar a spring reaches.
return {
	id = "keep",
	title = "Locked Keep",
	about = "The gate wants the key. A spring throws you up to it.",
	start = {0.4, 5.6},
	flag = {1, -5.6},
	blocks = {
		-- Continuous land catches missed jumps; the raised route still holds the rewards.
		{"large", 1, 1, w = 28, d = 26, h = 0.8, y = -0.8},
		{"large", 0, 5, yaw = 10}, {"lowLarge", 2, 6.5, yaw = -20}, {"low", -1.6, 6.4, yaw = 30},
		{"long", 0, 2.6, h = 1, yaw = 90},
		{"tall", -1.5, 0, h = 2.7}, {"tall", 1.5, 0, h = 2.7}, {"long", 0, 0, h = 1, yaw = 90},
		{"tall", -3.2, -1.6, h = 3.5, yaw = 30}, {"tall", 3.2, -1.6, h = 3.5, yaw = -30},
		{"large", 0, -3, yaw = 15}, {"large", -2, -4.4, h = 1.5, yaw = -20}, {"tall", 1, -5.6, h = 2.5, yaw = 10},
		{"lowLarge", 5, 4, yaw = 20}, {"large", 7.5, 1.6, h = 4, yaw = -25}, {"lowLong", 8, 4.4, yaw = 15},
		{"lowLarge", -3.8, 5.4, yaw = -15}, {"hexagon", -5.9, 4.4, h = 0.75, yaw = 20},
		-- The lawn allows walking round the keep. Close the courtyard on
		-- three sides so the key and front gate still have a purpose.
		{"large", 0, -4, w = 8, d = 7, h = 1, y = 0},
		{"tall", -4.5, -4, w = 1, d = 9, h = 3.5, y = 0},
		{"tall", 4.5, -4, w = 1, d = 9, h = 3.5, y = 0},
		{"tall", 0, -8, w = 10, d = 1, h = 3.5, y = 0},
		{"tall", -3.5, 0, w = 3, d = 2, h = 2.7, y = 0},
		{"tall", 3.5, 0, w = 3, d = 2, h = 2.7, y = 0},
		-- Ground approaches rejoin the raised routes after a missed jump.
		{"slope", 0, 7.2, w = 2.4, d = 2.4, h = 1, y = 0},
		{"slope", -3.8, 7.4, w = 2.4, d = 2, h = 0.5, y = 0},
		{"slope", 5, 6, w = 2.4, d = 2, h = 0.5, y = 0},
		{"slope", 1, -3.8, w = 2, d = 2, h = 1.5, y = 1},
	},
	props = {
		{"tree", 2.4, 6.9}, {"sign", -0.6, 4.4, yaw = 10}, {"flowers", 0.6, 5.6},
		{"rail", 0.5, 3, yaw = 90, y = 1}, {"rail", -0.5, 2.2, yaw = 270, y = 1},
		{"pine", -2, -3.9}, {"tree", 1.5, -6.1}, {"poles", -2.8, -5.3},
		{"rocks", 5.4, 4.5}, {"smallPine", 7.9, 1.1}, {"barrel", -4.2, 5.9}, {"crate", 8.4, 4.6, yaw = 15},
		-- A supply yard outside, a small garden inside the keep.
		{"tree", -9, 6}, {"pine", -8, 1}, {"tree", 11, 5},
		{"smallPine", 10, -3}, {"pine", -7, -6}, {"tree", 3, 9.5},
		{"crate", -7, 7, yaw = 15}, {"strongCrate", -8, 7}, {"barrel", -7.5, 8},
		{"fence", -7.5, 8.7}, {"hedge", -2.5, -6, yaw = 90},
		{"flowers", -2.8, -6.5}, {"flowers", 2.5, -6.8}, {"mushrooms", -3, -3.5},
		{"grass", 7.5, 7}, {"plant", 10, 7.5}, {"stones", -8, -3},
		{"arrows", 6.4, 6.3, yaw = 180}, {"sign", -5.3, 7.5, yaw = 15},
		{"tallFlowers", -2, 9.5}, {"flowers", 8, -4.5},
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
