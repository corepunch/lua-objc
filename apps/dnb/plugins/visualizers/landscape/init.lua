-- A drone flyover of river valleys at sunset, banking through soft turns:
-- a static terrain mesh, reflective water, a sky with clouds and cloud banks.
local TERRAIN = {cells = 300, size = 180} -- grid cells per side, world units per side
local CLOUD_SIDE = 7                      -- cloud banks on a side × side world lattice

return {
	api = 1,
	title = "Valley Flight",
	symbol = "mountain.2.fill",
	shader = "Scene.metal",
	sections = {"intro", "breakdown", "drop"},
	draws = {
		{vertex = "fullscreenVertex", fragment = "landscapeSkyFragment", count = 3},
		{vertex = "landscapeTerrainVertex", fragment = "landscapeTerrainFragment", depth = "write",
			count = TERRAIN.cells * TERRAIN.cells * 6, params = {TERRAIN.cells, TERRAIN.size}},
		{vertex = "landscapeWaterVertex", fragment = "landscapeWaterFragment", depth = "write", count = 6},
		{vertex = "landscapeCloudVertex", fragment = "landscapeCloudFragment", blend = "alpha", depth = "test",
			count = 6, instances = CLOUD_SIDE * CLOUD_SIDE, params = {CLOUD_SIDE}},
	},
}
