-- Drum & bass: an endless DJ set at 160–176 BPM. Two-step grooves with
-- ghost notes, breaks layered and chopped over the programmed kit, rolling
-- bass under voice-led extended chords. Its flavours are not shades of one
-- tune but different records: a liquid roller carried by an electric piano,
-- an anthem with a lead and its answer, a jungle tune that opens on the raw
-- Amen, neurofunk with nothing sweet in it, a minimal stepper on five
-- channels, a half-time tune, a jump-up wobbler, and one that is mostly air.

-- Scale degrees, one chord per two bars.
local PROGRESSIONS = {
	{1, 6, 3, 7}, {1, 4, 6, 5}, {1, 7, 6, 7}, {1, 1, 4, 6},
	{6, 7, 1, 1}, {1, 3, 6, 7}, {1, 6, 4, 5}, {4, 6, 1, 7},
	{1, 4, 7, 3}, {6, 4, 1, 5}, {1, 2, 6, 7}, {4, 5, 3, 6},
}
-- A tune that lives on one chord, or two.
local STATIC = {{1, 1, 1, 1}, {1, 1, 6, 6}, {1, 7, 1, 7}, {1, 1, 1, 7}}

local FILLS = {"fill.roll", "fill.toms", "fill.stutter", "fill.snares", "@stutter", "@cut", "@reverse", "@retrig"}

-- Raw-break records have no risers: the break thins and returns instead.
local RAW = {riser = 0.05, roll = 0.2, impact = 0.5, drumless = 0.3, kickOut = 0.5, halftime = 0.1,
	curve = {{0, 0.35}, {0.12, 0.5}, {0.25, 0.75}, {0.4, 0.85}, {0.5, 0.5}, {0.6, 0.9}, {0.8, 0.7}, {0.92, 0.4}, {1, 0.25}}}

local FLAVOURS = {
	-- Carried by the electric piano; a long, soft breakdown and a gentle second peak.
	{id = "liquid", name = "Liquid", tempo = {170, 175}, swing = {0.08, 0.16},
		arc = {riser = 0.4, roll = 0.2, impact = 0.5, valley = 0.5, drumless = 0.5, bassOut = 0.3, kickOut = 0.15,
			halftime = 0.1, lift = 0.15, fill = 0.5,
			curve = {{0, 0.25}, {0.12, 0.4}, {0.2, 0.7}, {0.4, 0.8}, {0.46, 0.45}, {0.58, 0.4}, {0.62, 0.85}, {0.82, 0.65}, {0.92, 0.4}, {1, 0.2}}},
		channels = {
			{role = "drums", wants = {"swung", "soulful", "twostep"}},
			{role = "tops", wants = {"break", "swung"}, gain = 0.45, chops = true, chance = 0.7},
			{role = "bass", patches = {"bass.round", "bass.sub", "bass.reese", "bass.upright"}, wants = {"sub", "soulful", "walking"}},
			{role = "pad", patches = {"pad.warm", "pad.saw", "pad.strings", "pad.glass"}, wants = {"warm"}},
			{role = "keys", patches = {"keys.rhodes", "keys.wurli", "keys.vibes", "keys.harp"}, wants = {"soulful", "warm"}},
			{role = "arp", patches = {"pluck.bell", "pluck.glass", "pluck.saw"}, chance = 0.6},
			{role = "lead", patches = {"lead.sine", "lead.flute", "lead.vox", "lead.saw"}, chance = 0.7, wants = {"hook", "vocal", "soulful"}},
			{role = "fx", patches = {"fx.riser", "fx.wind"}},
		}},
	-- A lead, the voice that answers it, and a wall of pads.
	{id = "anthem", name = "Anthem", tempo = {172, 176}, swing = {0.04, 0.1},
		arc = {riser = 0.95, roll = 0.8, impact = 0.9, drumless = 0.7, lift = 0.3, halftime = 0.05,
			curve = {{0, 0.25}, {0.1, 0.4}, {0.2, 0.7}, {0.26, 0.9}, {0.48, 0.85}, {0.52, 0.35}, {0.6, 0.4}, {0.64, 0.95}, {0.82, 0.8}, {0.92, 0.4}, {1, 0.2}}},
		channels = {
			{role = "drums", wants = {"twostep", "driving"}},
			{role = "bass", patches = {"bass.reese", "bass.pluck", "bass.moog"}, wants = {"rolling", "euphoric"}},
			{role = "pad", patches = {"pad.supersaw", "pad.strings", "pad.pwm"}, wants = {"euphoric"}},
			{role = "stab", patches = {"stab.saw", "stab.piano", "stab.pizzicato"}, chance = 0.5},
			{role = "arp", patches = {"pluck.trance", "pluck.saw", "pluck.chip"}},
			{role = "lead", patches = {"lead.supersaw", "lead.saw", "lead.square", "lead.fm"}, wants = {"hook", "euphoric"}},
			{role = "counter", patches = {"pluck.bell", "pluck.glass", "keys.vibes"}, chance = 0.7, wants = {"answer"}},
			{role = "fx", patches = {"fx.riser", "fx.siren"}},
		}},
	-- Opens on the raw break; no risers, the break thins and returns.
	{id = "jungle", name = "Jungle", tempo = {160, 170}, swing = {0.1, 0.2}, arc = RAW,
		harmony = {progressions = {{1, 6, 3, 7}, {1, 7, 6, 7}, {1, 1, 4, 6}, {1, 1, 6, 6}, {1, 4, 1, 7}}},
		channels = {
			{role = "drums", gain = 0.85, wants = {"broken", "swung"}},
			{role = "tops", wants = {"break"}, gain = 0.8, chops = true},
			{role = "bass", patches = {"bass.sub", "bass.808", "bass.reese", "bass.hoover"}, wants = {"sub", "reggae", "pedal"}},
			{role = "pad", patches = {"pad.dark", "pad.choir", "pad.strings"}, chance = 0.6},
			{role = "stab", patches = {"stab.rave", "stab.piano", "stab.organ", "stab.brass"}, chance = 0.8},
			{role = "lead", patches = {"lead.hoover", "lead.square", "lead.flute"}, chance = 0.5, wants = {"riff", "hypnotic"}},
			{role = "texture", patches = {"texture.tape", "texture.air"}, chance = 0.6},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	-- The break is the tune: little else plays.
	{id = "tearout", name = "Amen Tearout", tempo = {164, 172}, swing = {0.08, 0.16}, arc = RAW,
		harmony = {progressions = STATIC, change = 0.2},
		channels = {
			{role = "drums", gain = 0.7, wants = {"minimal", "broken"}},
			{role = "tops", wants = {"break", "aggressive"}, gain = 0.95, chops = true},
			{role = "bass", patches = {"bass.reeseWide", "bass.808", "bass.hoover"}, wants = {"dark", "pedal", "reese"}},
			{role = "stab", patches = {"stab.rave", "stab.fm"}, chance = 0.6},
			{role = "texture", patches = {"texture.drone", "texture.tape"}, chance = 0.5},
			{role = "fx", patches = {"fx.siren", "fx.wind"}},
		}},
	-- Nothing sweet: halftime switches, a drumless breakdown with riser and roll.
	{id = "neuro", name = "Neurofunk", tempo = {172, 176}, swing = {0, 0.08},
		arc = {riser = 1, roll = 0.9, impact = 0.9, drumless = 0.9, bassOut = 0.7, halftime = 0.7, lift = 0, valley = 0.4,
			curve = {{0, 0.3}, {0.12, 0.5}, {0.22, 0.85}, {0.45, 0.9}, {0.52, 0.3}, {0.6, 0.4}, {0.64, 0.95}, {0.82, 0.85}, {0.92, 0.45}, {1, 0.25}}},
		harmony = {progressions = {{1, 1, 6, 7}, {1, 1, 1, 7}, {1, 2, 1, 7}, {1, 6, 1, 5}, {1, 1, 4, 6}}, voicing = {0, 2, 4, 6}},
		channels = {
			{role = "drums", wants = {"dark", "aggressive", "syncopated"}},
			{role = "bass", patches = {"bass.growl", "bass.reeseWide", "bass.yoi", "bass.reese"}, wants = {"reese", "dark", "aggressive"}},
			{role = "pad", patches = {"pad.dark", "pad.pwm"}, chance = 0.5, wants = {"dark", "tense"}},
			{role = "stab", patches = {"stab.fm", "stab.saw", "stab.rave"}, wants = {"tense", "aggressive"}},
			{role = "arp", patches = {"pluck.acid", "pluck.chip", "pluck.saw"}, chance = 0.5},
			{role = "lead", patches = {"lead.fm", "lead.square"}, chance = 0.35, wants = {"riff", "dark"}},
			{role = "texture", patches = {"texture.drone", "texture.air"}, chance = 0.6},
			{role = "fx", patches = {"fx.riser", "fx.siren", "fx.wind"}},
		}},
	-- A bass line that never stops and a break tucked under the kit.
	{id = "rollers", name = "Rollers", tempo = {172, 175}, swing = {0.06, 0.14},
		arc = {riser = 0.6, roll = 0.4, valley = 0.4, drumless = 0.5, bassOut = 0.3, halftime = 0.1, lift = 0.1,
			curve = {{0, 0.3}, {0.12, 0.5}, {0.25, 0.75}, {0.45, 0.8}, {0.52, 0.5}, {0.6, 0.85}, {0.8, 0.8}, {0.92, 0.45}, {1, 0.25}}},
		channels = {
			{role = "drums", wants = {"rolling", "driving"}},
			{role = "tops", wants = {"break"}, gain = 0.5, chops = true, chance = 0.6},
			{role = "bass", patches = {"bass.reese", "bass.sub", "bass.moog", "bass.round"}, wants = {"rolling", "driving"}},
			{role = "pad", patches = {"pad.saw", "pad.warm", "pad.dark"}, chance = 0.7},
			{role = "keys", patches = {"keys.rhodes", "keys.clav", "keys.organ"}, chance = 0.4},
			{role = "stab", patches = {"stab.saw", "stab.dub", "stab.organ"}, chance = 0.6},
			{role = "arp", patches = {"pluck.saw", "pluck.marimba", "pluck.string"}, chance = 0.6},
			{role = "fx", patches = {"fx.riser", "fx.wind"}},
		}},
	-- Five channels: a kick, a snare, a sub and what is left out. It evolves
	-- rather than lifts: a shallow valley, a few risers.
	{id = "minimal", name = "Minimal", tempo = {170, 174}, swing = {0, 0.1},
		arc = {riser = 0.2, roll = 0.1, impact = 0.4, valley = 0.4, drumless = 0.3, bassOut = 0.3, kickOut = 0.5, halftime = 0.15, lift = 0,
			curve = {{0, 0.3}, {0.15, 0.45}, {0.3, 0.65}, {0.45, 0.75}, {0.55, 0.5}, {0.65, 0.8}, {0.85, 0.65}, {0.93, 0.4}, {1, 0.25}}},
		harmony = {progressions = STATIC, change = 0.15, voicing = {0, 2, 4, 6}},
		channels = {
			{role = "drums", wants = {"minimal", "sparse"}},
			{role = "bass", patches = {"bass.sub", "bass.808", "bass.round"}, wants = {"sub", "minimal", "pedal"}},
			{role = "stab", patches = {"stab.dub", "stab.pizzicato"}, chance = 0.6, wants = {"sparse"}},
			{role = "counter", patches = {"pluck.bell", "pluck.marimba", "keys.vibes"}, chance = 0.7, wants = {"sparse", "answer"}},
			{role = "texture", patches = {"texture.air", "texture.drone", "texture.tape"}},
			{role = "fx", patches = {"fx.wind"}, chance = 0.6},
		}},
	-- 170 felt as 85: the snare on three throughout.
	{id = "halftime", name = "Halftime", tempo = {166, 172}, swing = {0.1, 0.2},
		arc = {riser = 0.5, roll = 0.2, impact = 0.8, halftime = 1, drumless = 0.6, lift = 0.1, valley = 0.45},
		harmony = {progressions = {{1, 1, 6, 6}, {1, 6, 4, 5}, {1, 7, 6, 7}, {1, 1, 4, 4}}, barsPerChord = 4},
		channels = {
			{role = "drums", wants = {"halftime", "deep"}},
			{role = "bass", patches = {"bass.808", "bass.growl", "bass.wobble", "bass.sub"}, wants = {"halftime", "sub", "wobble"}},
			{role = "pad", patches = {"pad.dark", "pad.air", "pad.choir", "pad.glass"}},
			{role = "keys", patches = {"keys.vibes", "keys.rhodes", "keys.harp"}, chance = 0.5},
			{role = "arp", patches = {"pluck.glass", "pluck.string", "pluck.bell"}, chance = 0.5},
			{role = "lead", patches = {"lead.vox", "lead.sine", "lead.pluck"}, chance = 0.7, wants = {"hook", "melancholic"}},
			{role = "texture", patches = {"texture.shimmer", "texture.tape", "texture.air"}, chance = 0.7},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		}},
	-- Made for the dance floor: a wobbling bass that calls and answers itself.
	{id = "jumpup", name = "Jump-Up", tempo = {172, 176}, swing = {0.04, 0.12},
		arc = {riser = 1, roll = 0.7, impact = 1, drumless = 0.5, bassOut = 0.4, halftime = 0.2, lift = 0.2, valley = 0.4,
			curve = {{0, 0.3}, {0.1, 0.5}, {0.2, 0.85}, {0.45, 0.9}, {0.5, 0.4}, {0.58, 0.45}, {0.62, 0.95}, {0.82, 0.85}, {0.92, 0.45}, {1, 0.25}}},
		harmony = {progressions = STATIC, change = 0.3, voicing = {0, 2, 4, 6}},
		channels = {
			{role = "drums", wants = {"aggressive", "syncopated", "driving"}},
			{role = "bass", patches = {"bass.yoi", "bass.wobble", "bass.hoover", "bass.donk"}, wants = {"wobble", "playful", "stab"}},
			{role = "stab", patches = {"stab.brass", "stab.rave", "stab.organ"}, chance = 0.7, wants = {"playful", "bright"}},
			{role = "lead", patches = {"lead.hoover", "lead.square"}, chance = 0.4, wants = {"riff", "playful"}},
			{role = "texture", patches = {"texture.tape"}, chance = 0.4},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	-- Mostly air: pads, a flute, the break far away; long soft breakdowns.
	{id = "atmospheric", name = "Atmospheric", tempo = {162, 172}, swing = {0.08, 0.18},
		arc = {intro = 24, riser = 0.3, roll = 0.1, impact = 0.4, valley = 0.5, drumless = 0.6, bassOut = 0.5, kickOut = 0.1,
			halftime = 0.15, lift = 0.1,
			curve = {{0, 0.25}, {0.15, 0.4}, {0.28, 0.65}, {0.4, 0.75}, {0.45, 0.4}, {0.58, 0.35}, {0.64, 0.8}, {0.82, 0.6}, {0.92, 0.4}, {1, 0.2}}},
		channels = {
			{role = "drums", gain = 0.85, wants = {"swung", "mixable", "hypnotic"}},
			{role = "tops", wants = {"break"}, gain = 0.5, chops = true, chance = 0.8},
			{role = "bass", patches = {"bass.sub", "bass.round", "bass.upright"}, wants = {"sub", "deep", "walking"}},
			{role = "pad", patches = {"pad.air", "pad.glass", "pad.choir", "pad.strings"}, wants = {"ambient", "held"}},
			{role = "arp", patches = {"pluck.glass", "pluck.string", "keys.harp"}, chance = 0.7, wants = {"dreamy", "ambient"}},
			{role = "lead", patches = {"lead.flute", "lead.sine", "lead.pluck"}, chance = 0.7, wants = {"hook", "melancholic", "dreamy"}},
			{role = "texture", patches = {"texture.shimmer", "texture.air"}},
			{role = "fx", patches = {"fx.wind"}},
		}},
}

return {
	api = 4,
	title = "Drum & Bass",
	symbol = "waveform.path",
	summary = "Liquid, Jungle, Neurofunk, Rollers and more at 174",
	defaults = {energy = 0.65, complexity = 0.5, humanize = 0.35, space = 0.35},
	set = {modes = {"minor", "dorian", "phrygian"}, modulations = {5, -2, 3, 2}},
	-- A song-shaped track: a first peak by a quarter, a drumless breakdown
	-- at the middle, a riser and snare roll into a higher second peak.
	arc = {minutes = {4, 5}, intro = 16, outro = 16, riser = 0.8, riserBars = {4, 8}, roll = 0.5, impact = 0.7, valley = 0.45,
		drumless = 0.8, bassOut = 0.5, kickOut = 0.3, halftime = 0.25, lift = 0.2,
		curve = {{0, 0.25}, {0.12, 0.4}, {0.22, 0.7}, {0.3, 0.85}, {0.5, 0.4}, {0.62, 0.9}, {0.8, 0.65}, {0.9, 0.4}, {1, 0.2}}},
	harmony = {progressions = PROGRESSIONS, voicing = {2, 4, 6, 8}, barsPerChord = 2, segmentBars = 16},
	roles = {drums = {fills = FILLS}},
	flavours = FLAVOURS,
}
