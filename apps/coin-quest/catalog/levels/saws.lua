-- Level 3: a long ridge of turned blocks climbs north from the hub, saws
-- sweeping across it; wings of crates and pipes east and west.
return {
	id = "saws",
	title = "Saw Ridge",
	facing = -10,
	about = "Saws sweep the ridge. Wait for one to pass, then run.",
	start = {0.2, 6.6},
	flag = {0.8, -6.4},
	blocks = {
		{"lowLarge", 0, 6.4, yaw = 18}, {"lowLong", 2.2, 6.9, yaw = -25}, {"low", -1.6, 7.2, yaw = 40},
		{"large", 0.4, 3.6, yaw = -6}, {"large", 0.9, 1.2, yaw = 8, h = 1.5}, {"large", 0.3, -1.3, yaw = -10, h = 2},
		{"large", 1, -3.8, yaw = 14, h = 2.5}, {"tall", 0.8, -6.4, yaw = -20, h = 3},
		{"long", 4.2, 1.4, yaw = 24}, {"hexagon", 6.2, 0.4, yaw = 10, h = 1.5}, {"large", 8.2, -1.2, yaw = -35, h = 2},
		{"lowLarge", -3.4, 4.4, yaw = -15}, {"lowLong", -5.2, 2.4, yaw = 70}, {"large", -5.6, -0.6, yaw = 20},
		{"hexagon", -3.4, -1.8, yaw = 0, h = 1.75},
	},
	props = {
		{"sign", 0.8, 6, yaw = 18}, {"tree", 2.6, 7.2}, {"flowers", -1.6, 7.2},
		{"rail", 1.4, 3.1, yaw = 84}, {"rail", -0.6, 3.6, yaw = 264}, {"pine", 1.7, -6.9},
		{"crate", 4.6, 1.6, yaw = 30}, {"grass", 6.2, 0.4}, {"tree", 8.8, -1.8}, {"pipe", 7.6, -0.6},
		{"rocks", -3, 4}, {"plant", -5.2, 2.4}, {"smallPine", -6.1, -1.1}, {"barrel", -5.2, -0.2},
	},
	saws = {{-0.4, 3.6, 1.2, 3.6}, {1.7, 1.2, 0.1, 1.2}, {-0.5, -1.3, 1.1, -1.3}, {0.2, -3.8, 1.8, -3.8}, {3.4, 1.1, 5, 1.7}},
	coins = {
		{1.6, 6.4}, {2.4, 7}, {0.4, 3.6}, {0.9, 1.2}, {0.3, -1.3}, {1, -3.8}, {4.2, 1.4}, {6.2, 0.4}, {8.2, -1},
		{-3.4, 4.4}, {-5.2, 2.4}, {-5.6, -0.6}, {-3.4, -1.8},
	},
	stars = {{8.2, -1.2, lift = 1.1}, {-3.4, -1.8, lift = 1.1}, {0.4, -6.8}},
	checkpoints = {{-3, 4.8}},
}
