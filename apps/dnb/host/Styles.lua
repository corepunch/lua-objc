-- The style extension point: every genre the generator plays is a plugin in
-- plugins/styles/<id>/init.lua. A style is data: its manifest names it and
-- says what its tracks are made of.
--   set       the DJ set's modes, section lengths, forms and modulations
--             (StyleKit.newSet)
--   flavours  the kinds of track it plays: each its tempo and swing, its
--             channels (eight at most, by role) and what each may play
--   roles     what a channel of a role falls back on in every flavour
--   harmony   {progressions, voicing, barsPerChord}, which a flavour may
--             override
--   plan      what each role plays in each section, over StyleKit.plan
--   library   its own beats, lines, hooks and patches (host/Library.lua)
--   kit, mix  its drum design (models/Drums.lua) and balance (Synth.mix)
--   patterns  {id, part, bars, render(bar, ctx)} of its own, beside the
--             shared ones (StyleKit.patterns); most styles need none
-- `Styles:create(id, seed)` returns the composer the Synth plays
-- (host/Composer.lua). The kit is StyleKit, read-only.
local Plugins = require("Plugins")
local StyleKit = require("apps.dnb.host.StyleKit")
local Composer = require("apps.dnb.host.Composer")

local Styles = Plugins.extensionPoint({
	name = "style",
	api = 3,
	host = StyleKit,
	manifest = {
		title = "string",
		symbol = "string",
		summary = "string",
		defaults = "table?",     -- control values the style starts from
		set = "table",           -- StyleKit.newSet spec
		flavours = "table",
		roles = "table?",
		harmony = "table?",
		plan = "table?",
		library = "table?",
		kit = "table?",          -- Drums.design overrides
		mix = "table?",          -- Synth.mix overrides
		throws = "number?",      -- bars between dub throws; 4 by default
		patterns = "table?",
	},
})

-- The picker's order.
Styles:load("apps.dnb.plugins.styles", {"dnb", "techno", "house", "trance", "dubstep", "breakbeat", "garage"})

--- A new composer for a style's set from `seed`.
function Styles:create(id, seed)
	return Composer.new(assert(self:get(id), "unknown style plugin: " .. tostring(id)), seed)
end

return Styles
