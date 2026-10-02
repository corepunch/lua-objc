-- A solar system in a nebula: the sun and its corona, lit planets on their
-- orbits (one ringed), comets with dust and ion tails, and an asteroid belt,
-- seen from a camera flying past one planet after another.
local PLANETS = 5
local COMETS = 3
local TAIL_POINTS = 48
local ORBIT_POINTS = 160
local ASTEROIDS = 1400

return {
	api = 1,
	title = "Solar System",
	symbol = "sun.max.fill",
	shader = "Scene.metal",
	arc = {0, 0.65},
	draws = {
		{vertex = "fullscreenVertex", fragment = "spaceBackdrop", count = 3},
		{vertex = "spaceOrbitVertex", fragment = "spaceOrbitFragment", primitive = "lineStrip", blend = "add",
			depth = "test", count = ORBIT_POINTS + 1, instances = PLANETS},
		{vertex = "spaceSunVertex", fragment = "spaceSunFragment", depth = "write", count = 6},
		{vertex = "spacePlanetVertex", fragment = "spacePlanetFragment", depth = "write", count = 6,
			instances = PLANETS},
		{vertex = "spaceRingVertex", fragment = "spaceRingFragment", blend = "alpha", depth = "test", count = 6},
		{vertex = "spaceAsteroidVertex", fragment = "spaceAsteroidFragment", primitive = "point", blend = "add",
			depth = "test", count = ASTEROIDS},
		{vertex = "spaceCoronaVertex", fragment = "spaceCoronaFragment", blend = "add", depth = "test", count = 6},
		{vertex = "spaceCometVertex", fragment = "spaceCometFragment", primitive = "triangleStrip", blend = "add",
			depth = "test", count = TAIL_POINTS * 2, instances = COMETS * 3, params = {TAIL_POINTS}},
	},
}
