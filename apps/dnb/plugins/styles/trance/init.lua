-- Trance: 132 to 145 BPM. A punchy kick on every beat, an off-beat bass,
-- wide pads through a long breakdown, a gated arpeggio climbing the chord
-- and an anthem that returns, full, on the second peak after it. The track
-- is one canvas (see `arc`): it builds from a mix-in to a first peak, falls
-- into a drumless breakdown that is a fifth of the track, climbs on a
-- riser, snare roll and impact to a higher second peak, often a tone up,
-- and winds down. Its flavours: Uplifting, Progressive, Psytrance on a
-- galloping bass, Acid trance, driving Tech trance, Goa, and Dream trance
-- on a piano. Psytrance, Goa and Tech evolve rather than lift: few risers.

-- The trance cadences: i–VI–III–VII and its relatives, two bars a chord.
local PROGRESSIONS = {{1, 6, 3, 7}, {6, 7, 1, 1}, {1, 6, 7, 5}, {1, 4, 6, 7}, {6, 4, 1, 7}, {1, 3, 7, 6}, {4, 6, 1, 7}}
local STATIC = {{1, 1, 1, 1}, {1, 1, 7, 7}, {1, 2, 1, 7}, {1, 1, 6, 7}}

local FILLS = {"fill.roll", "fill.claps", "fill.snares", "fill.kicks", "@retrig", "@reverse"}

-- Psytrance and its kin evolve by layering; they ride filters, not risers.
local EVOLVING = {riser = 0.1, roll = 0.15, impact = 0.4, lift = 0, drumless = 0.5, kickOut = 0.35,
	curve = {{0, 0.3}, {0.12, 0.45}, {0.25, 0.65}, {0.4, 0.85}, {0.55, 0.55}, {0.65, 0.9}, {0.82, 0.7}, {0.92, 0.4}, {1, 0.25}}}

local FLAVOURS = {
	{id = "uplifting", name = "Uplifting", tempo = {136, 140}, swing = {0, 0.02},
		channels = {
			{role = "drums", wants = {"fourfloor", "euphoric"}},
			{role = "bass", patches = {"bass.pluck", "bass.reese", "bass.moog"}, wants = {"offbeat", "euphoric"}},
			{role = "pad", patches = {"pad.supersaw", "pad.strings"}, wants = {"euphoric"}},
			{role = "stab", patches = {"stab.saw", "stab.rave", "stab.brass"}},
			{role = "arp", patches = {"pluck.trance", "pluck.saw", "pluck.bell"}},
			{role = "lead", patches = {"lead.supersaw", "lead.saw"}, wants = {"hook", "euphoric"}},
			{role = "counter", patches = {"pluck.glass", "pluck.bell", "keys.vibes"}, chance = 0.5},
			{role = "fx", patches = {"fx.riser", "fx.siren"}},
		}},
	{id = "progressive", name = "Progressive", tempo = {132, 136}, swing = {0, 0.06},
		arc = {riser = 0.5, roll = 0.2, lift = 0.15},
		channels = {
			{role = "drums", wants = {"fourfloor", "minimal"}},
			{role = "bass", patches = {"bass.round", "bass.pluck", "bass.fm"}, wants = {"driving", "rolling"}},
			{role = "pad", patches = {"pad.warm", "pad.glass", "pad.pwm", "pad.air"}},
			{role = "keys", patches = {"keys.vibes", "keys.rhodes"}, chance = 0.4},
			{role = "arp", patches = {"pluck.saw", "pluck.glass", "pluck.marimba", "pluck.string"}},
			{role = "lead", patches = {"lead.sine", "lead.vox", "lead.flute", "lead.fm"}, chance = 0.6, wants = {"sparse", "vocal"}},
			{role = "texture", patches = {"texture.shimmer", "texture.air"}, chance = 0.7},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		}},
	{id = "psy", name = "Psytrance", tempo = {140, 145}, swing = {0, 0.02}, arc = EVOLVING,
		harmony = {progressions = STATIC, change = 0.2, voicing = {0, 2, 4, 6}},
		channels = {
			{role = "drums", wants = {"hypnotic"}},
			{role = "bass", patches = {"bass.psy"}, wants = {"gallop", "rolling"}},
			{role = "pad", patches = {"pad.dark", "pad.choir"}, chance = 0.5},
			{role = "arp", patches = {"pluck.acid", "pluck.chip", "pluck.bell"}},
			{role = "lead", patches = {"lead.fm", "lead.square", "lead.hoover"}, chance = 0.5, wants = {"riff", "hypnotic"}},
			{role = "texture", patches = {"texture.drone", "texture.air"}, chance = 0.6},
			{role = "fx", patches = {"fx.siren", "fx.riser", "fx.wind"}},
		}},
	{id = "acid", name = "Acid Trance", tempo = {136, 142}, swing = {0, 0.04}, arc = {riser = 0.5, lift = 0},
		harmony = {progressions = {{1, 1, 6, 7}, {1, 6, 3, 7}, {1, 1, 1, 7}}, change = 0.2},
		channels = {
			{role = "drums", wants = {"driving"}},
			{role = "bass", patches = {"bass.acid", "bass.acidSquare"}, wants = {"acid"}},
			{role = "pad", patches = {"pad.supersaw", "pad.dark", "pad.choir"}},
			{role = "arp", patches = {"pluck.acid", "pluck.trance"}},
			{role = "lead", patches = {"lead.saw", "lead.square"}, chance = 0.5, wants = {"riff"}},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	{id = "tech", name = "Tech Trance", tempo = {138, 142}, swing = {0, 0.03}, arc = EVOLVING,
		harmony = {progressions = STATIC, change = 0.3, voicing = {0, 2, 4, 6}},
		channels = {
			{role = "drums", wants = {"driving"}},
			{role = "bass", patches = {"bass.rumble", "bass.psy", "bass.hoover"}, wants = {"rolling", "driving"}},
			{role = "stab", patches = {"stab.rave", "stab.fm", "stab.saw"}},
			{role = "arp", patches = {"pluck.chip", "pluck.acid"}, chance = 0.6},
			{role = "lead", patches = {"lead.hoover", "lead.fm"}, chance = 0.4, wants = {"riff"}},
			{role = "texture", patches = {"texture.tape", "texture.drone"}, chance = 0.5},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	{id = "goa", name = "Goa", tempo = {138, 145}, swing = {0, 0.03}, arc = EVOLVING,
		harmony = {progressions = {{1, 1, 2, 1}, {1, 2, 1, 7}, {1, 1, 7, 1}}, change = 0.3, voicing = {0, 2, 4, 6}},
		channels = {
			{role = "drums", wants = {"hypnotic"}},
			{role = "bass", patches = {"bass.psy", "bass.pluck"}, wants = {"gallop"}},
			{role = "pad", patches = {"pad.choir", "pad.glass"}, chance = 0.6},
			{role = "arp", patches = {"pluck.string", "pluck.bell", "pluck.acid"}},
			{role = "lead", patches = {"lead.fm", "lead.vox", "lead.flute"}, wants = {"hook", "dreamy"}},
			{role = "counter", patches = {"pluck.glass", "pluck.marimba"}, chance = 0.6},
			{role = "texture", patches = {"texture.shimmer", "texture.drone"}, chance = 0.6},
			{role = "fx", patches = {"fx.wind", "fx.siren"}},
		}},
	-- The tune is on a piano, over strings.
	{id = "dream", name = "Dream Trance", tempo = {132, 138}, swing = {0, 0.04},
		channels = {
			{role = "drums", wants = {"fourfloor", "dreamy"}},
			{role = "bass", patches = {"bass.round", "bass.pluck", "bass.fm"}, wants = {"offbeat"}},
			{role = "pad", patches = {"pad.strings", "pad.warm", "pad.choir"}},
			{role = "keys", patches = {"keys.piano", "keys.harp"}, chance = 0.6},
			{role = "arp", patches = {"pluck.bell", "pluck.glass", "keys.harp"}},
			{role = "lead", patches = {"lead.pluck", "lead.sine", "lead.flute"}, wants = {"hook", "dreamy"}},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		}},
}

return {
	api = 4,
	title = "Trance",
	symbol = "sparkles",
	summary = "Uplifting, Progressive, Psy and more, with a long breakdown",
	defaults = {energy = 0.7, complexity = 0.6, humanize = 0.1, space = 0.6},
	kit = {
		kick = {base = 48, sweep = 150, sweepTime = 0.02, decay = 0.2, drive = 2.2, click = 0.45, length = 0.35},
		hat = {scale = 2, decay = 0.012, openDecay = 0.06},
	},
	mix = {duckDepth = 0.7, drums = 0.85, bass = 0.8, pad = 1.4, arp = 1.2, lead = 1.15, delayFeedback = 0.45,
		reverbSend = 1.1},
	throws = 8,
	set = {modes = {"minor", "phrygian"}, modulations = {2}},
	-- One long canvas: a first peak by a third of the way, a drumless
	-- breakdown of about a fifth, a riser and a snare roll into a higher
	-- second peak, and a mix-out. The anthem and the harmony stay.
	arc = {
		minutes = {4.5, 5.5}, intro = 16, outro = 16, riser = 0.95, riserBars = {4, 8}, roll = 0.8, impact = 0.9,
		valley = 0.45, drumless = 0.95, bassOut = 0.8, kickOut = 0.15, halftime = 0, lift = 0.4,
		curve = {{0, 0.25}, {0.1, 0.4}, {0.22, 0.6}, {0.3, 0.9}, {0.42, 0.85}, {0.46, 0.3}, {0.62, 0.35}, {0.66, 0.95},
			{0.82, 0.75}, {0.92, 0.4}, {1, 0.2}},
	},
	-- The anthem returns after the breakdown: the harmony stays.
	harmony = {progressions = PROGRESSIONS, voicing = {0, 2, 4, 8}, barsPerChord = 2, change = 0, segmentBars = 16},
	roles = {drums = {fills = FILLS}},
	flavours = FLAVOURS,
}
