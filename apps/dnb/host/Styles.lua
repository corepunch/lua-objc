-- The style extension point: every genre the generator plays is a plugin in
-- plugins/styles/<id>/init.lua. Its manifest names and tunes the style
-- (tempo range, control defaults, sound) and composes it in three parts:
--   set       the DJ set's flavours, modes, section lengths and modulations
--             (StyleKit.newSet)
--   material  `(kit, rng, track, first)` → one cycle's grooves, harmony and
--             melody, drawn from its own seeded stream
--   arrange   `(kit, track, cycles)` → the track's lanes of blocks, built
--             with kit.lanes (see host/Arrangement.lua)
--   patterns  {id, part, bars, render(bar, ctx)}: each renders one bar of
--             its part; the kit shares the common ones (StyleKit.patterns)
-- `Styles:create(id, seed)` returns the composer the Synth plays
-- (host/Composer.lua). The kit is StyleKit, read-only.
local Plugins = require("Plugins")
local StyleKit = require("apps.dnb.host.StyleKit")
local Composer = require("apps.dnb.host.Composer")

local Styles = Plugins.extensionPoint({
	name = "style",
	api = 2,
	host = StyleKit,
	manifest = {
		title = "string",
		symbol = "string",
		summary = "string",
		tempo = "table",         -- {min, max, default} in BPM
		defaults = "table?",     -- control values the style starts from
		sound = "table?",        -- Synth.sound overrides
		set = "table",           -- StyleKit.newSet spec
		barsPerChord = "number?", -- how long each chord of a progression lasts; 2 by default
		material = "function",
		arrange = "function",
		patterns = "table",
	},
})

-- The picker's order.
Styles:load("apps.dnb.plugins.styles", {"dnb", "techno", "house", "trance", "dubstep", "breakbeat", "garage"})

--- A new composer for a style's set from `seed`.
function Styles:create(id, seed)
	return Composer.new(assert(self:get(id), "unknown style plugin: " .. tostring(id)), seed)
end

return Styles
