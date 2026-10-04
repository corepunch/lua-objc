-- The kit's pieces that stand on the blocks or span the water between them:
-- wooden platforms and ramps for bridges, crates, barrels, pipes, fences,
-- trees and ground cover.
--
-- `model` is the kit's file (`snow` the one a snow level uses instead) and
-- `scale` the size it is placed at. `solid` is its collision box at that
-- scale, in scene units, as for blocks (`w`, `d`, `h`, `shape`, `low`, and
-- `ox`, `oz` where the box sits in the piece's own frame); a placement's own
-- `scale` grows the box with the model. A `perch` is something items can sit
-- on, as on a crate or a bridge; a solid that is not a perch, a tree trunk,
-- is a wall. Pieces without `solid` are ground cover the hero walks through.
return {
	-- Wooden platforms: the planks of a bridge, a pallet, a ramp up a step.
	platform = {model = "platform", scale = 1.5, perch = true, solid = {w = 1.5, d = 1.5, h = 0.3}},
	fortified = {model = "platform-fortified", scale = 1.5, perch = true, solid = {w = 1.5, d = 1.5, h = 0.3}},
	ramp = {model = "platform-ramp", scale = 1.5, perch = true,
		solid = {w = 1.5, d = 1.5, h = 0.75, low = 0.18, shape = "ramp"}},
	-- Things to stand on and climb.
	crate = {model = "crate", scale = 1.6, perch = true, solid = {w = 0.8, d = 0.8, h = 0.8}},
	strongCrate = {model = "crate-strong", scale = 1.4, perch = true, solid = {w = 0.84, d = 0.84, h = 0.84}},
	barrel = {model = "barrel", scale = 1.5, perch = true, solid = {w = 0.78, d = 0.78, h = 0.72}},
	chest = {model = "chest", scale = 1.6, perch = true, solid = {w = 0.8, d = 0.8, h = 0.6}},
	brick = {model = "brick", scale = 1.6, perch = true, solid = {w = 0.8, d = 0.8, h = 0.8}},
	pipe = {model = "pipe", scale = 1.2, perch = true, solid = {w = 1.2, d = 1.2, h = 0.67}},
	rocks = {model = "rocks", scale = 1.4, perch = true, solid = {w = 0.9, d = 0.9, h = 0.55}},
	-- Walls: fences and hedges along an edge, tree trunks, poles.
	fence = {model = "fence-low-straight", scale = 1, solid = {w = 1, d = 0.2, h = 0.5, oz = 0.4}},
	rail = {model = "fence-straight", scale = 1, solid = {w = 1, d = 0.16, h = 0.6, oz = 0.42}},
	rope = {model = "fence-rope", scale = 1.5, solid = {w = 1.4, d = 0.2, h = 0.5}},
	hedge = {model = "hedge", scale = 1, solid = {w = 1, d = 0.3, h = 0.45, oz = 0.35}},
	poles = {model = "poles", scale = 1, solid = {w = 1.1, d = 0.34, h = 1}},
	tree = {model = "tree", snow = "tree-snow", scale = 1, solid = {w = 0.4, d = 0.4, h = 1.9}},
	pine = {model = "tree-pine", snow = "tree-pine-snow", scale = 1, solid = {w = 0.4, d = 0.4, h = 2}},
	smallPine = {model = "tree-pine-small", snow = "tree-pine-snow-small", scale = 1, solid = {w = 0.3, d = 0.3, h = 1.4}},
	-- Ground cover and dressing.
	flowers = {model = "flowers", scale = 1},
	tallFlowers = {model = "flowers-tall", scale = 1},
	grass = {model = "grass", scale = 1},
	plant = {model = "plant", scale = 1},
	stones = {model = "stones", scale = 1.4},
	mushrooms = {model = "mushrooms", scale = 1.2},
	sign = {model = "sign", scale = 1.3},
	arrow = {model = "arrow", scale = 1.3},
	arrows = {model = "arrows", scale = 1.3},
	lever = {model = "lever", scale = 1.2},
	bomb = {model = "bomb", scale = 1.2},
	door = {model = "door-rotate-large", scale = 1.4},
}
