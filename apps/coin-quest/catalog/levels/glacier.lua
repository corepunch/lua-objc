-- Level 8: lifts climb from the low islands to ledges, and from the ledges
-- to the glacier's top, where saws patrol.
return {
	id = "glacier",
	title = "Glacier Lifts",
	biome = "snow",
	about = "Ride the lifts up the glacier. Saws patrol the top.",
	start = {0.2, 6.6},
	flag = {-1.5, -2.5},
	blocks = {
		-- Continuous land catches missed jumps; the raised route still holds the rewards.
		{"large", 0, 2, w = 28, d = 24, h = 0.8, y = -0.8},
		{"lowLarge", 0, 6.2, yaw = 10}, {"lowLarge", 4.5, 5, yaw = -20}, {"lowLarge", -4.5, 5, yaw = 25},
		{"long", 4.5, 2, h = 3, yaw = 5}, {"long", -4.5, 2, h = 3, yaw = -8},
		{"large", 4.5, -1, h = 5, yaw = -12}, {"tall", 1.5, -1.5, h = 5.5, yaw = 15}, {"tall", -1.5, -2.5, h = 6, yaw = -10},
		{"large", -4.5, -1, h = 4, yaw = 20}, {"low", 2.4, 6.8, yaw = 40},
		-- Ground approaches rejoin the raised routes after a missed jump.
		{"slope", 0, 8.2, w = 2.4, d = 2, h = 0.5, y = 0},
		{"slope", 4.5, 7, w = 2.4, d = 2, h = 0.5, y = 0},
		{"slope", -4.5, 7, w = 2.4, d = 2, h = 0.5, y = 0},
	},
	props = {
		{"pine", 0.6, 6.8}, {"sign", -0.6, 5.6, yaw = 10}, {"smallPine", 5, 5.5}, {"rocks", -4, 5.5},
		{"pine", 4.9, -1.5}, {"tree", -1.9, -3}, {"smallPine", -4.9, -1.5}, {"crate", -5, 2.2, yaw = -8},
		{"rail", 4.5, 2.6, yaw = 5, y = 3}, {"chest", 4.8, -1.4, yaw = 180},
		-- A lift base camp: supplies by the approaches, pines at the perimeter.
		{"pine", -9, 7}, {"smallPine", -10, 4}, {"tree", -9, -1},
		{"pine", -5, -5}, {"tree", 2, -6}, {"smallPine", 7, -4},
		{"pine", 10, 2}, {"tree", 9, 7}, {"smallPine", -2, 10},
		{"crate", 7, 8.5}, {"barrel", 8, 8.5}, {"rope", 7.5, 9.3},
		{"crate", -7, 8.5, yaw = -15}, {"barrel", -8, 8.5},
		{"stones", -8.5, 2}, {"rocks", 9, -2}, {"stones", 0, -5},
		{"arrows", 5.9, 7.4, yaw = 180}, {"sign", -5.9, 7.4},
		{"smallPine", 3, 10.5}, {"stones", 2, 3.5},
	},
	movers = {
		{from = {6.8, 0.5, 3.4}, to = {6.8, 3, 3.4}},
		{from = {6.8, 3, 0.5}, to = {6.8, 5, 0.5}},
		{from = {-6.8, 0.5, 3.4}, to = {-6.8, 3, 3.4}},
	},
	saws = {{3.7, -1, 5.3, -1}, {0.7, -1.5, 2.3, -1.5}},
	coins = {
		{1.4, 5.8}, {4.5, 5}, {-4.5, 5}, {4.5, 2}, {-4, 2}, {6.8, 3.4, y = 2}, {4.5, -1}, {1.5, -1.5},
		{-1.5, -2}, {-4.5, -1}, {-6.8, 3.4, y = 2}, {2.4, 6.8},
	},
	stars = {{-4.5, -1, lift = 1.2}, {6.8, 0.5, y = 6.2}, {-1, -3}},
	hearts = {{5, 2}},
	checkpoints = {{-4, 1.6}},
}
