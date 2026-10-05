-- Level 5: ferries run out from the hub in three directions; a lift on the
-- north island rises to the plateau with the flag.
return {
	id = "lagoon",
	title = "Ferry Lagoon",
	about = "Ferries and lifts wait at each end. Step on and ride.",
	start = {-0.4, 0.6},
	flag = {4.6, -8.6},
	blocks = {
		-- Continuous land catches missed jumps; the raised route still holds the rewards.
		{"large", 0, -3, w = 34, d = 26, h = 0.8, y = -0.8},
		{"large", 0, 0, yaw = 20}, {"lowLarge", -2, 1.6, yaw = -25}, {"low", 1.2, 1.6, yaw = 50},
		{"large", 8.8, 0, yaw = -15}, {"lowLong", 8.6, 1.8, yaw = 30}, {"hexagon", 10.2, -1.4, h = 1.5, yaw = 10},
		{"large", 0, -8.6, yaw = 15}, {"tall", 4.6, -8.6, yaw = -20, h = 4}, {"lowLarge", -1.8, -9.6, yaw = 40},
		{"lowLarge", -9.6, 1.6, yaw = 10}, {"low", -10.8, 0, yaw = 30},
		-- Ground approaches rejoin the raised routes after a missed jump.
		{"slope", 0, 2.2, w = 2.4, d = 2.4, h = 1, y = 0},
		{"slope", -9.6, 3.6, w = 2.4, d = 2, h = 0.5, y = 0},
		{"slope", 8.8, 3.6, w = 2.4, d = 2.8, h = 0.5, y = 0},
		{"slope", 0, -6.4, w = 2.4, d = 2.4, h = 1, y = 0},
	},
	props = {
		{"tree", 0.6, -0.6}, {"sign", -0.8, 0.2, yaw = 20}, {"flowers", -2.4, 1.9},
		{"pine", 9.3, -0.5}, {"crate", 10.2, -1.4, y = 1.5}, {"tree", -0.5, -9.1}, {"pine", 5.1, -9.1},
		{"rocks", -9.4, 1.1}, {"pipe", -1.8, -9.6}, {"barrel", 7.9, 2.3},
		-- Cargo stops distinguish the three ferry destinations.
		{"tree", -13, 3}, {"pine", -12, -4}, {"tree", -7, -8},
		{"pine", 8, -10.5}, {"tree", 13, 1}, {"tree", 4, 5.5},
		{"crate", -11.5, 3}, {"barrel", -11.5, 4}, {"rope", -12.5, 3.5, yaw = 90},
		{"crate", 11, 3.5, yaw = 20}, {"barrel", 12, 3.5},
		{"stones", -4, -10}, {"plant", 5, -11}, {"grass", -5, -3},
		{"flowers", -3, 4.5}, {"mushrooms", -8, -4}, {"flowers", 5, -3},
		{"sign", 1.6, -5.8, yaw = 180}, {"arrows", 7, 4, yaw = 180},
		{"flowers", -8, 5.5}, {"grass", 10, -5}, {"tallFlowers", 1.5, 5},
	},
	movers = {
		{from = {2.4, 1, 0}, to = {6.5, 1, 0}},
		{from = {0, 1, -2.4}, to = {0, 1, -6.5}},
		{from = {2.4, 1, -8.6}, to = {2.4, 4, -8.6}},
		{from = {-4.2, 0.5, 1.5}, to = {-7.4, 0.5, 1.5}},
	},
	coins = {
		{-2, 1.6}, {0.8, -0.6}, {4.4, 0, y = 1.6}, {8.8, 0}, {8.4, 1.6}, {0, -4.4, y = 1.6}, {0, -8.6},
		{2.4, -8.6, y = 2.8}, {4.6, -8.2}, {-5.8, 1.5, y = 1.1}, {-9.6, 1.6}, {-1.8, -9.6, lift = 0.7},
	},
	stars = {{10.2, -1.4, lift = 0.6}, {4.6, -9, lift = 1.2}, {-10.8, 0, lift = 0.8}},
	hearts = {{-9.2, 2}},
	checkpoints = {{0.5, -8.2}},
}
