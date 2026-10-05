-- A safe playground with three readable landmarks: the crate orchard west,
-- a bridge and lookout east, and a terraced summit north. Misses land on
-- the lawn; low approaches make every branch climbable again from below.
return {
	id = "meadow",
	title = "Green Meadow",
	about = "Explore the orchard, cross the bridge, then climb the hill. The grass catches missed jumps.",
	start = {0, 7.8},
	flag = {0, -7},
	blocks = {
		-- One solid, palette-textured Kenney piece beneath the entire course.
		{"large", 0, 0, w = 32, d = 28, h = 0.8, y = -0.8},
		-- A broad hub and a gentle ramp to learn movement before any jumps.
		{"large", 0, 4, w = 6, d = 4, h = 0.5, y = 0},
		{"slope", 0, 7, w = 3, d = 2, h = 0.5, y = 0},
		-- East: wide landings, with low foothills beside the lookout.
		{"large", 5.5, 4, w = 3, d = 3, h = 1, y = 0},
		{"tall", 8, 2, w = 4, d = 4, h = 2, y = 0},
		{"lowLarge", 9.5, 4.8, w = 3, d = 2, h = 0.6, y = 0},
		{"large", 10.5, 2, w = 2, d = 3, h = 1.2, y = 0},
		{"hexagon", 8, 0.2, w = 2.2, d = 2.4, h = 2.8, y = 0},
		-- West: a forgiving stepping-stone shortcut to a crate orchard.
		{"lowHexagon", -4, 4, w = 1.8, d = 1.9, h = 0.4, y = 0},
		{"lowHexagon", -6, 3.5, w = 1.8, d = 1.9, h = 0.6, y = 0},
		{"large", -9, 3, w = 4, d = 4, h = 0.8, y = 0},
		{"slope", -9, 6, w = 3, d = 2, h = 0.8, y = 0},
		-- North: the arch is an optional shortcut; the side ramp rejoins it.
		{"arch", 0, 0.5, w = 4, d = 2, yaw = 90, h = 0.9, y = 0},
		{"large", 0, -2, w = 5, d = 3, h = 1, y = 0},
		{"slope", 3.5, -2, w = 3, d = 2, yaw = 90, h = 1, y = 0},
		{"large", 0, -4.5, w = 4, d = 2, h = 1.8, y = 0},
		{"large", 0, -7, w = 4, d = 3, h = 2.6, y = 0},
		-- Low foothills let a missed summit jump return to the main climb.
		{"lowLarge", -3.5, -4, w = 2.5, d = 3, h = 0.6, y = 0},
		{"large", -3.5, -6.5, w = 2.5, d = 2, h = 1.3, y = 0},
	},
	props = {
		{"sign", 1.7, 7.5, yaw = 0}, {"flowers", -2, 5.4}, {"grass", 2.3, 3.4},
		{"tallFlowers", -2.4, 2.4}, {"mushrooms", 2.3, 5.5},
		-- The bridge teaches a short jump, with grass underneath it.
		{"platform", 3.4, 4, yaw = 0, y = 0.45},
		{"rail", 3.4, 4.6, yaw = 0, y = 0.75},
		{"pine", 9.2, 0.6}, {"barrel", 6.2, 4.6}, {"plant", 10.5, 2},
		{"chest", 8, 0.2, yaw = 180},
		-- Crates offer a small optional climb; trees frame the yard's edges.
		{"crate", -9.6, 2.6, yaw = 0}, {"crate", -8.7, 2.6, yaw = 0},
		{"crate", -9.6, 2.6, yaw = 0, y = 1.6},
		{"tree", -10.4, 1.5}, {"tree", -7.8, 1.5}, {"flowers", -9.8, 4.4},
		{"fence", -10.6, 3.5, yaw = 90},
		-- A door remains visible before the finish flag is earned.
		{"door", -0.8, -7.6, yaw = 0}, {"smallPine", 1.4, -7.8},
		{"arrows", 1.8, -2.6, yaw = 180}, {"flowers", -1.4, -4.8},
		-- Ground-level scenery frames the return paths without blocking them.
		{"tree", -12, 7}, {"tree", 12, 6}, {"pine", -7, -6}, {"pine", 6, -7},
		{"flowers", -5, 7}, {"grass", 5, 7}, {"mushrooms", -5, -1},
		{"flowers", 5, -4}, {"stones", 11, -3}, {"plant", -11, -3},
	},
	coins = {
		-- A trail out of the start, then a choice of three branches.
		{0, 6}, {0, 4.5}, {0, 3},
		{3.4, 4, lift = 0.2}, {5.5, 4}, {8, 2}, {10.5, 2},
		{-4, 4}, {-6, 3.5}, {-8, 4}, {-10, 3.8},
		{0, 0.5, lift = 0.2}, {0, -2}, {0, -4.5}, {-3.5, -6.5},
	},
	stars = {{8, 0.2, lift = 0.9}, {-9.6, 2.6, lift = 0.9}, {1, -7, lift = 0.9}},
	hearts = {{-8.5, 3.8}},
	checkpoints = {{1.2, -2}},
}
