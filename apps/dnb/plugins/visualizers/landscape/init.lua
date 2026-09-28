-- A low flight along a river valley at sunset: terrain mesh, reflective
-- water, a sky with clouds and cloud banks drifting past.
local ROWS, COLUMNS = 150, 150
local CLOUDS = 40

return {
	api = 1,
	title = "Valley Flight",
	symbol = "mountain.2.fill",
	shader = "Scene.metal",
	sections = {"intro", "breakdown", "drop"},
	draws = {
		{vertex = "fullscreenVertex", fragment = "landscapeSkyFragment", count = 3},
		{vertex = "landscapeTerrainVertex", fragment = "landscapeTerrainFragment", depth = "write",
			count = ROWS * COLUMNS * 6, params = {ROWS, COLUMNS}},
		{vertex = "landscapeWaterVertex", fragment = "landscapeWaterFragment", depth = "write", count = 6},
		{vertex = "landscapeCloudVertex", fragment = "landscapeCloudFragment", blend = "alpha", depth = "test",
			count = 6, instances = CLOUDS, params = {CLOUDS}},
	},
}
