-- Level 5: ferries run out from the hub in three directions; a lift on the
-- north island rises to the plateau with the flag.
return {
	id = "lagoon",
	title = "Ferry Lagoon",
	about = "Ferries and lifts wait at each end. Step on and ride.",
	start = {-0.4, 0.6},
	flag = {4.6, -8.6},
	blocks = {
		{"large", 0, 0, yaw = 20}, {"lowLarge", -2, 1.6, yaw = -25}, {"low", 1.2, 1.6, yaw = 50},
		{"large", 8.8, 0, yaw = -15}, {"lowLong", 8.6, 1.8, yaw = 30}, {"hexagon", 10.2, -1.4, h = 1.5, yaw = 10},
		{"large", 0, -8.6, yaw = 15}, {"tall", 4.6, -8.6, yaw = -20, h = 4}, {"lowLarge", -1.8, -9.6, yaw = 40},
		{"lowLarge", -9.6, 1.6, yaw = 10}, {"low", -10.8, 0, yaw = 30},
	},
	props = {
		{"tree", 0.6, -0.6}, {"sign", -0.8, 0.2, yaw = 20}, {"flowers", -2.4, 1.9},
		{"pine", 9.3, -0.5}, {"crate", 10.2, -1.4, y = 1.5}, {"tree", -0.5, -9.1}, {"pine", 5.1, -9.1},
		{"rocks", -9.4, 1.1}, {"pipe", -1.8, -9.6}, {"barrel", 8.4, 2.2},
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
