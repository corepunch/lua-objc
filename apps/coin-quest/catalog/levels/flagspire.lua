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
		-- Continuous land catches missed jumps; the raised route still holds the rewards.
		{"large", 0, 1, w = 28, d = 24, h = 0.8, y = -0.8},
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
		-- Ground approaches rejoin the raised routes after a missed jump.
		{"slope", 0, 7.6, w = 2.4, d = 2, h = 0.5, y = 0},
		{"slope", 7, 5, w = 2.4, d = 2, h = 0.5, y = 0},
		{"slope", -9, -3, w = 2.4, d = 2, yaw = 270, h = 0.5, y = 0},
		{"slope", -5, 5.6, w = 2.4, d = 2, h = 0.5, y = 0},
	},
	props = {
		{"pine", 0.7, 6.2}, {"sign", -0.6, 5.2, yaw = 15}, {"smallPine", 7.5, 3.5}, {"rocks", -7.4, -3.4},
		{"crate", 7.4, 2.4, yaw = -20}, {"barrel", -5.4, 4}, {"fence", -7.2, -0.4, yaw = -15},
		-- A snowy trailhead round the spire, with clear space under the spiral.
		{"pine", -10, 5}, {"smallPine", -11, 1}, {"tree", -10, -6},
		{"pine", -5, -7}, {"tree", 0, -7}, {"smallPine", 5, -6},
		{"pine", 10, -2}, {"tree", 10, 5}, {"smallPine", 4, 8.5},
		{"crate", -8, 7, yaw = 15}, {"barrel", -9, 7}, {"rope", -8.5, 7.8},
		{"stones", 8, -5}, {"rocks", -3, -8}, {"stones", 3, 7},
		{"arrows", -6.5, 5.8, yaw = 180}, {"sign", 8.5, 5.2},
		{"barrel", 9, 7}, {"crate", 8, 7.5, yaw = 20}, {"smallPine", -3, 9},
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
