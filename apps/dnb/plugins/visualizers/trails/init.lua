-- Light trails tracing rose curves, stretching as the music gets louder:
-- one glowing ribbon mesh per trail over a dark backdrop.
local TRAILS = 9
local POINTS = 120 -- samples along each trail; one more pair caps its head, so POINTS quads

return {
	api = 1,
	title = "Light Trails",
	symbol = "scribble.variable",
	shader = "Scene.metal",
	arc = {0.55, 1},
	draws = {
		{vertex = "fullscreenVertex", fragment = "trailsBackground", count = 3},
		{vertex = "trailsVertex", fragment = "trailsFragment", blend = "add",
			count = POINTS * 6, instances = TRAILS, params = {POINTS}},
	},
}
