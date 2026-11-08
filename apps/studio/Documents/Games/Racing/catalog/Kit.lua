-- The asset kit this game is built from: one place names it. Every model
-- path is `Kit.models .. name .. ".glb"`, and `Kit.manifest[name]` holds
-- the model's size, pivot and tags (generated from the models; read it
-- before placing a piece).
--
-- Kenney's road is one unit wide; the scene draws the kit `scale` times
-- larger, so a road is 4 scene units wide, and cars at `carScale` of the
-- kit's size, so two fit side by side. Track and scenery data are in kit
-- units (one road width); the game turns them into scene units.
return {
	name = "racing-kit",
	models = "assets/kenney/racing-kit/models/",
	manifest = require("assets.kenney.racing-kit.manifest"),
	scale = 4,
	carScale = 1.4,
}
