-- Level 10: a spiral of stones climbs round the spire, a stone higher at
-- every turn, to the flag on its top. A lift and loose planks lead out to
-- the stars.
return {
	id = "flagspire",
	title = "Flagspire",
	biome = "snow",
	about = "Climb the spiral round the spire. Fall, and you start the turn again.",
	start = {0, 5.8},
	flag = {0, 0},
	blocks = {
		{"tall", 0, 0, h = 7, yaw = 20},
		{"lowLarge", 0, 5.6, yaw = 15},
		{"hexagon", 0, 3.4, h = 1, yaw = 10},
		{"hexagon", 2.4, 2.4, h = 1.75, yaw = 35},
		{"hexagon", 3.4, 0, h = 2.5, yaw = 60},
		{"hexagon", 2.4, -2.4, h = 3.25, yaw = 85},
		{"hexagon", 0, -3.4, h = 4, yaw = 110},
		{"hexagon", -2.4, -2.4, h = 4.75, yaw = 135},
		{"hexagon", -3.4, 0, h = 5.5, yaw = 160},
		{"hexagon", -2.4, 2.4, h = 6.25, yaw = 185},
		{"lowLarge", 7, 3, yaw = -20}, {"lowLarge", -7, -3, yaw = 30},
		{"lowLarge", -7, 0.2, yaw = -15}, {"lowLarge", -5, 3.6, yaw = 25}, {"lowLong", -2.6, 5.2, yaw = 10},
	},
	props = {
		{"pine", 0.7, 6.2}, {"sign", -0.6, 5.2, yaw = 15}, {"smallPine", 7.5, 3.5}, {"rocks", -7.4, -3.4},
		{"crate", 7.4, 2.4, yaw = -20}, {"barrel", -5.4, 4}, {"fence", -7.2, -0.4, yaw = -15},
	},
	movers = {{from = {4.6, 0.5, 4}, to = {4.6, 2.5, 4}}},
	planks = {{-5.2, -2.4, y = 4.6}, {-6.2, -1, y = 3.5}},
	coins = {
		{1, 5}, {0, 3.4}, {2.4, 2.4}, {3.4, 0}, {2.4, -2.4}, {0, -3.4}, {-2.4, -2.4}, {-3.4, 0},
		{-2.4, 2.4}, {7, 3.4}, {-7, -3}, {-5, 3.6}, {-7, 0.6}, {0, 0, lift = 0.1},
	},
	stars = {{7.4, 2.4, lift = 0.9}, {-7, -2.6, lift = 1.2}, {0, 0, lift = 1.1}},
	hearts = {{6.6, 3.4}},
}
