-- A drone flyover of alpine peaks at twilight, banking through the valleys:
-- a static terrain mesh of ridged massifs and pyramidal summits, dark tarns,
-- a navy sky with stars, and a few high cloud banks.
-- Terrain strips: the finest grid level whole, then each coarser level's
-- ring around its hole (see Scene.metal); each strip is 32 cells.
local TERRAIN = {side = 128, strip = 32, levels = 3}
local perRow = TERRAIN.side // TERRAIN.strip
local ring = TERRAIN.side // 4 * 2 * perRow + TERRAIN.side
local STRIPS = TERRAIN.side * perRow + (TERRAIN.levels - 1) * ring
local CLOUD_SIDE = 7                      -- cloud banks on a side × side world lattice

return {
	api = 1,
	title = "Valley Flight",
	symbol = "mountain.2.fill",
	shader = "Scene.metal",
	arc = {0, 0.7},
	draws = {
		{vertex = "landscapeTerrainVertex", fragment = "landscapeTerrainFragment", depth = "write",
			primitive = "triangleStrip", count = (TERRAIN.strip + 1) * 2, instances = STRIPS},
		{vertex = "landscapeWaterVertex", fragment = "landscapeWaterFragment", depth = "write", count = 6},
		{vertex = "landscapeSkyVertex", fragment = "landscapeSkyFragment", depth = "test", count = 3},
		{vertex = "landscapeCloudVertex", fragment = "landscapeCloudFragment", blend = "alpha", depth = "test",
			count = 6, instances = CLOUD_SIDE * CLOUD_SIDE, params = {CLOUD_SIDE}},
	},
}
