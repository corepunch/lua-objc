-- Race 1: an oval of four wide corners, two laps, two easy rivals.
-- The track is driven in order from the start, which drives toward +z;
-- right turns bend toward -x. Scenery is placed freely by its middle
-- (x, z) in road widths, at any yaw, off the road.
return {
	id = "oval",
	title = "Sunny Oval",
	laps = 2,
	track = {
		"start", "long", "long", "wideRight",
		"long", "wideRight",
		"long", "long", "long", "wideRight",
		"long", "wideRight",
	},
	rivals = {
		{"raceCarGreen", pace = 0.7},
		{"raceCarOrange", pace = 0.76},
	},
	scenery = {
		{"grandStandCovered", 1.6, 2.5, yaw = 90, scale = 1.4},
		{"grandStandCovered", 1.6, 4.3, yaw = 90, scale = 1.4},
		{"overheadLights", 0, 1.0, yaw = 0},
		{"flagCheckers", 1.1, 0.4, yaw = 90},
		{"treeLarge", -2.6, 3.1, yaw = 20},
		{"treeSmall", -3.3, 4.4, yaw = 70},
		{"treeLarge", -2.9, 5.6, yaw = 140},
		{"tentLong", -3.0, 0.9, yaw = 8},
		{"billboard", -6.9, 3.2, yaw = -80},
		{"treeLarge", -7.2, 0.4, yaw = 10},
		{"treeSmall", -7.0, 6.9, yaw = 45},
		{"treeLarge", 2.2, 8.4, yaw = 60},
		{"pylon", 1.0, 7.8, yaw = 0},
		{"pylon", 1.2, 7.2, yaw = 0},
		{"lightPostLarge", -6.2, -2.0, yaw = 135},
		{"treeSmall", 1.5, -2.6, yaw = 15},
	},
}
