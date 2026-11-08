-- Level 1: islands to hop across, one step up, a drop to the flag.
-- Pieces are {"model", x, y, z, yaw = degrees}; y is where a piece stands.
-- Sizes come from the kit's manifest: block-grass-large is 2.08 wide and
-- 1 tall, block-grass-large-tall 2 tall.
return {
	id = "meadow",
	title = "Green Meadow",
	biome = "grass",
	start = {0, 1, 0.3},
	pieces = {
		{"block-grass-large", 0, 0, 0},
		{"block-grass-large", 2.0, 0, 0.5, yaw = 20},
		{"block-grass-large", 0.6, 0, -2.7, yaw = -12},
		{"block-grass-large-tall", -0.6, 0, -5.0, yaw = 25},
		{"block-grass-large-tall", 1.4, 0, -7.4, yaw = 40},
		{"block-grass-large", 3.8, 0, -8.6, yaw = 10},
		{"tree", -0.7, 1, -0.6, yaw = 30},
		{"flowers", 2.4, 1, 0.9, yaw = 70},
		{"mushrooms", 1.0, 1, -3.2, yaw = 10},
		{"tree-pine-small", -1.1, 2, -5.4, yaw = 15},
		{"grass", 3.4, 1, -8.0, yaw = 50},
	},
	coins = {
		{2.0, 1, 0.3},
		{0.6, 1, -2.7},
		{-0.4, 2, -4.8},
		{0.4, 2.6, -6.2},
		{1.4, 2, -7.4},
	},
	flag = {4.0, 1, -8.9},
}
