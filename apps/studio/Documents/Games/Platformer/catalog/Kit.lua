-- The asset kit this game is built from: one place names it. Every model
-- path is `Kit.models .. name .. ".glb"`, and `Kit.manifest[name]` holds
-- the model's size, pivot, tags and animation clips (generated from the
-- models; read it before placing a piece).
return {
	name = "platformer-kit",
	models = "assets/kenney/platformer-kit/models/",
	manifest = require("assets.kenney.platformer-kit.manifest"),
}
