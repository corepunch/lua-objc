-- Level 1: a grassy hub of overlapping mounds; a wooden bridge east to a
-- tower of stacked ledges, hexagon stones west to a crate yard, and an arch
-- north to the hill with the flag.
return {
	id = "meadow",
	title = "Green Meadow",
	about = "Run and jump. Bridges, ramps and stones lead every way from the meadow.",
	start = {1.9, 5.6},
	flag = {-0.6, -6.6},
	blocks = {
		-- The hub: mounds turned every way, each a step above the last.
		{"lowLarge", 1.8, 5.5, yaw = -20},
		{"large", 0, 4, yaw = 15, h = 0.75},
		{"large", -1.8, 5.2, yaw = 38, h = 0.5},
		{"large", -0.6, 2.2, yaw = -8, h = 1},
		{"low", 1.6, 2.7, yaw = 50},
		-- East: the tower, ledges climbing round a tall block.
		{"tall", 8.2, 2.4, yaw = -18, h = 2},
		{"large", 6.8, 4, yaw = 20, h = 1.25},
		{"lowLong", 9.6, 4.2, yaw = 70, h = 2.6},
		{"hexagon", 10.4, 1.4, yaw = 10, h = 3},
		-- West: stepping stones to the crate yard.
		{"lowHexagon", -4.2, 4.6, yaw = 20},
		{"lowHexagon", -5.9, 3.7, yaw = -15, h = 0.6},
		{"hexagon", -7.5, 4.6, yaw = 5, h = 0.75},
		{"large", -9.4, 3.6, yaw = -28, h = 1},
		{"lowLarge", -10.4, 1.8, yaw = 12},
		-- North: an arch over the water to the hill.
		{"arch", -0.6, -0.4, yaw = 82, h = 1.2, y = 0},
		{"large", -0.8, -3, yaw = -12, h = 1},
		{"lowLong", 1.2, -3.6, yaw = 30, h = 1.3},
		{"tall", -0.6, -5.4, yaw = 22, h = 2},
		{"large", 1, -6.6, yaw = -30, h = 2.5},
		{"large", -0.6, -6.6, yaw = 8, h = 3},
	},
	props = {
		{"sign", 2.6, 6.1, yaw = -20}, {"flowers", -1.6, 5.4}, {"grass", 0.6, 4.6}, {"tree", -1.1, 1.6},
		{"tallFlowers", 1.7, 2.6}, {"mushrooms", -2.4, 5.6},
		-- The east bridge, planks turned along it, a rail on its south side.
		{"platform", 2.3, 3.7, yaw = -12, y = 0.45}, {"platform", 3.7, 3.9, yaw = -6, y = 0.6},
		{"platform", 5.1, 4.1, yaw = 4, y = 0.75},
		{"rail", 3, 4.3, yaw = -10, y = 0.75}, {"rail", 4.4, 4.5, yaw = -2, y = 0.9},
		{"pine", 8.6, 1.6}, {"barrel", 7.2, 4.4}, {"crate", 9.9, 4.6, yaw = 25, y = 2.6}, {"plant", 10.4, 1.4},
		-- The crate yard.
		{"crate", -9.8, 3.2, yaw = 10}, {"crate", -9, 4.2, yaw = -18}, {"crate", -9.8, 3.2, yaw = 30, y = 1.8},
		{"fence", -10.5, 1.4, yaw = 12}, {"flowers", -7.5, 4.6},
		-- The hill.
		{"ramp", 1.4, -2.2, yaw = 200, y = 0}, {"smallPine", -1.4, -3.4}, {"tree", 1.4, -7.3},
		{"arrows", -1.6, -2.3, yaw = 180}, {"flowers", -0.2, -5.1},
	},
	coins = {
		{0.2, 4}, {-1.8, 5.2}, {-0.6, 2.2}, {3.7, 3.9, lift = 0.3}, {6.8, 4}, {8.2, 2.4}, {9.6, 4.2},
		{-4.2, 4.6}, {-5.9, 3.7}, {-7.5, 4.6}, {-10.4, 1.8}, {-0.6, -0.4, lift = 0.4}, {-0.8, -3}, {1.2, -3.6},
		{-0.6, -5.4},
	},
	stars = {{10.4, 1.4, lift = 1}, {-9.8, 3.2, lift = 0.9}, {1, -6.6, lift = 0.9}},
	hearts = {{-9.2, 4}},
}
