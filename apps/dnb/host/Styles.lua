-- The style extension point: every genre the generator plays is a plugin in
-- plugins/styles/<id>/init.lua. A style is data: its manifest names it and
-- says what its tracks are made of, and its blocks (plugins/styles/<id>/
-- blocks.lua, loaded here beside the shared ones) are the loops they are
-- arranged from (host/Blocks.lua).
--   set       the DJ set's modes and key lifts (StyleKit.newSet)
--   arc       the shape of a track: its length, energy curve and moves
--             (Canvas.defaults), which a flavour may override
--   flavours  the kinds of track it plays: each its tempo and swing, its
--             channels (eight at most, by role), the patch each may play
--             and the tags of the blocks it `wants` or must `avoid`
--   roles     what a channel of a role falls back on in every flavour
--   harmony   {progressions, voicing, barsPerChord, segmentBars, change},
--             which a flavour may override
--   library   its own patches and fills (host/Library.lua)
--   kit, mix  its drum design (models/Drums.lua) and balance (Synth.mix)
-- `Styles:create(id, seed)` returns the composer the Synth plays
-- (host/Composer.lua). The kit is StyleKit, read-only.
local Plugins = require("Plugins")
local StyleKit = require("apps.dnb.host.StyleKit")
local Composer = require("apps.dnb.host.Composer")

local Styles = Plugins.extensionPoint({
	name = "style",
	api = 4,
	host = StyleKit,
	manifest = {
		title = "string",
		symbol = "string",
		summary = "string",
		defaults = "table?",     -- control values the style starts from
		set = "table?",          -- StyleKit.newSet spec
		flavours = "table",
		roles = "table?",
		harmony = "table?",
		arc = "table?",
		library = "table?",
		kit = "table?",          -- Drums.design overrides
		mix = "table?",          -- Synth.mix overrides
		throws = "number?",      -- bars between dub throws; 4 by default
	},
})

-- The picker's order.
local ORDER = {"dnb", "techno", "house", "trance", "dubstep", "breakbeat", "garage"}
Styles:load("apps.dnb.plugins.styles", ORDER)
-- Blocks are data files beside the manifest, read by the host: a plugin's
-- sandbox has no `require`.
for _, style in ipairs(Styles:list()) do
	style.blocks = require("apps.dnb.plugins.styles." .. style.id .. ".blocks")
end

--- A new composer for a style's set from `seed`.
function Styles:create(id, seed)
	return Composer.new(assert(self:get(id), "unknown style plugin: " .. tostring(id)), seed)
end

return Styles
