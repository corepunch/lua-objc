-- The style extension point: every genre the generator plays is a plugin in
-- plugins/styles/<id>/init.lua. Its manifest names and tunes the style
-- (tempo range, control defaults, the parts it plays, sound);
-- `create(kit, seed)` returns a composer with `bar(n, settings)`,
-- `trackAt(n)` and `trackStart(k)`. The kit is StyleKit, read-only.
local Plugins = require("Plugins")
local StyleKit = require("apps.dnb.host.StyleKit")

local Styles = Plugins.extensionPoint({
	name = "style",
	api = 1,
	host = StyleKit,
	manifest = {
		title = "string",
		symbol = "string",
		summary = "string",
		tempo = "table",     -- {min, max, default} in BPM
		defaults = "table?", -- control values the style starts from
		parts = "table?",    -- Model.parts ids the style plays; omitted, it plays them all
		sound = "table?",    -- Synth.sound overrides
		create = "function",
	},
})

-- The picker's order.
Styles:load("apps.dnb.plugins.styles", {"dnb", "techno", "house", "trance", "dubstep", "breakbeat", "garage"})

return Styles
