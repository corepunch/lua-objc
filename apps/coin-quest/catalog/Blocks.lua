-- The building blocks a level is made of: Kenney's Platformer Kit pieces,
-- with the size the game collides against and the shape of their top.
--
-- `w` runs along x, `d` along z and `h` up, in scene units, before the
-- block's turn. A `box` top is flat; a `ramp` rises from `low` at +z to the
-- full height at -z (the kit's slopes); an `arch` bows up along x from
-- `low` at its ends to the full height in the middle (the kit's curves).
--
-- Each block's model is `block-<biome>-<model>.obj`. A block nothing stands
-- on shows the kit's overhang variant, its grass or snow draping over the
-- edge; one buried under another block shows the plain variant.
return {
	block = {w = 1, d = 1, h = 1, model = ""},
	low = {w = 1, d = 1, h = 0.5, model = "-low", overhang = "-overhang-low"},
	narrow = {w = 0.78, d = 0.78, h = 1, model = "-narrow", overhang = "-overhang-narrow"},
	lowNarrow = {w = 0.78, d = 0.78, h = 0.5, model = "-low-narrow", overhang = "-overhang-low-narrow"},
	long = {w = 2, d = 1, h = 1, model = "-long", overhang = "-overhang-long"},
	lowLong = {w = 2, d = 1, h = 0.5, model = "-low-long", overhang = "-overhang-low-long"},
	large = {w = 2, d = 2, h = 1, model = "-large", overhang = "-overhang-large"},
	lowLarge = {w = 2, d = 2, h = 0.5, model = "-low-large", overhang = "-overhang-low-large"},
	tall = {w = 2, d = 2, h = 2, model = "-large-tall", overhang = "-overhang-large-tall"},
	hexagon = {w = 1.1, d = 1.2, h = 1, model = "-hexagon", overhang = "-overhang-hexagon"},
	lowHexagon = {w = 1.1, d = 1.2, h = 0.5, model = "-low-hexagon", overhang = "-overhang-low-hexagon"},
	slope = {w = 2, d = 2, h = 0.76, low = 0.05, shape = "ramp", model = "-large-slope",
		overhang = "-overhang-large-slope"},
	slopeNarrow = {w = 1, d = 2, h = 0.77, low = 0.05, shape = "ramp", model = "-large-slope-narrow",
		overhang = "-overhang-large-slope-narrow"},
	arch = {w = 2, d = 1, h = 1, low = 0.26, shape = "arch", model = "-curve"},
	lowArch = {w = 2, d = 1, h = 0.5, low = 0.05, shape = "arch", model = "-curve-low"},
}
