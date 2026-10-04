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
		{"lowLarge", 0, 6.2, yaw = 10}, {"lowLarge", 4.5, 5, yaw = -20}, {"lowLarge", -4.5, 5, yaw = 25},
		{"long", 4.5, 2, h = 3, yaw = 5}, {"long", -4.5, 2, h = 3, yaw = -8},
		{"large", 4.5, -1, h = 5, yaw = -12}, {"tall", 1.5, -1.5, h = 5.5, yaw = 15}, {"tall", -1.5, -2.5, h = 6, yaw = -10},
		{"large", -4.5, -1, h = 4, yaw = 20}, {"low", 2.4, 6.8, yaw = 40},
	},
	props = {
		{"pine", 0.6, 6.8}, {"sign", -0.6, 5.6, yaw = 10}, {"smallPine", 5, 5.5}, {"rocks", -4, 5.5},
		{"pine", 4.9, -1.5}, {"tree", -1.9, -3}, {"smallPine", -4.9, -1.5}, {"crate", -5, 2.2, yaw = -8},
		{"rail", 4.5, 2.6, yaw = 5, y = 3}, {"chest", 4.8, -1.4, yaw = 180},
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
