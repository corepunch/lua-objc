-- Trance: 132 to 145 BPM. A punchy kick on every beat, an off-beat bass,
-- wide pads through long breakdowns, a gated arpeggio climbing the chord
-- and an anthem that returns, full, on the drop after the breakdown. Its
-- flavours: Uplifting, Progressive, Psytrance on a galloping bass, Acid
-- trance, driving Tech trance, Goa, and Dream trance on a piano.

-- The trance cadences: i–VI–III–VII and its relatives, two bars a chord.
local PROGRESSIONS = {{1, 6, 3, 7}, {6, 7, 1, 1}, {1, 6, 7, 5}, {1, 4, 6, 7}, {6, 4, 1, 7}, {1, 3, 7, 6}, {4, 6, 1, 7}}
local STATIC = {{1, 1, 1, 1}, {1, 1, 7, 7}, {1, 2, 1, 7}, {1, 1, 6, 7}}
local ARPS = {{1, 2, 3, 4, 5, 4, 3, 2}, {1, 3, 2, 4, 3, 5, 4, 6}, {1, 2, 3, 5, 1, 2, 4, 5}, {1, 4, 3, 5, 2, 4, 3, 6}}

local BEATS = {
	{id = "trance.classic", name = "Classic", lanes = {
		{"kick", "X...X...X...X..."},
		{"clap", "....X.......X...", gain = 0.75, light = false},
		{"openHat", "..x...x...x...x.", gain = 0.5},
		{"hat", "xo.oxo.oxo.oxo.o", gain = 0.3, light = false},
		{"ride", "..x...x...x...x.", gain = 0.35, when = "energy"},
		{"shaker", "...x...x...x...x", gain = 0.3, when = "complexity"},
	}},
	{id = "trance.progressive", name = "Progressive", bars = 2, lanes = {
		{"kick", "X...X...X...X..."},
		{"clap", "....x.......x...", gain = 0.7, light = false},
		{"hat", "..x...x...x...x.", gain = 0.45},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.3, light = false},
		{"rim", "............x...|.......x....x...", gain = 0.4, when = "complexity"},
		{"openHat", "..x...x...x...x.", gain = 0.35, when = "energy"},
	}},
	{id = "trance.psy", name = "Psy", lanes = {
		{"kick", "X...X...X...X..."},
		{"snare", "....x.......x...", gain = 0.6, light = false},
		{"hat", "..xx..xx..xx..xx", gain = 0.35},
		{"openHat", "..x...x...x...x.", gain = 0.4, light = false},
		{"clave", "...x..x....x..x.", gain = 0.3, when = "complexity"},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.25, when = "energy"},
	}},
	{id = "trance.tech", name = "Tech", bars = 2, lanes = {
		{"kick", "X...X...X...X...|X...X...X...X.x."},
		{"clap", "....X.......X...", gain = 0.85, light = false},
		{"hat", "xoXoxoXoxoXoxoXo", gain = 0.32},
		{"rim", "...x..x....x..x.", gain = 0.4, when = "complexity"},
		{"ride", "x.x.x.x.x.x.x.x.", gain = 0.3, when = "energy"},
	}},
	{id = "trance.dream", name = "Dream", bars = 2, lanes = {
		{"kick", "X...X...X...X...", gain = 0.95},
		{"clap", "....x.......x...", gain = 0.65, light = false},
		{"openHat", "..x...x...x...x.", gain = 0.4},
		{"tambourine", "x.x.x.x.x.x.x.x.", gain = 0.3, when = "energy"},
		{"snare", "..............og|............g.og", gain = 0.6, when = "complexity"},
	}},
}

local LINES = {
	{id = "trance.roll", name = "Roll", octave = 1, notes = "2:0:1 3:0:1 6:0:1 7:0:1 10:0:1 11:0:1 14:0:1 15:7:1?"},
	{id = "trance.octave", name = "Octave", octave = 1, notes = "2:0:1.6 6:7:1.6 10:0:1.6 14:7:1.6"},
	{id = "trance.triplet", name = "Drive", octave = 1, notes = "2:0:1 3:0:1? 6:0:1 7:0:1? 10:0:1 11:0:1? 14:0:1 15:0:1?"},
	{id = "trance.low", name = "Low", notes = "2:0:1.6 6:0:1.6 10:0:1.6 14:0:1.6"},
}

local FILLS = {"fill.roll", "fill.claps", "fill.snares", "fill.kicks", "@retrig", "@reverse"}

-- Later drops keep the anthem, from their first bar; the first waits for
-- its second half.
local ANTHEM = {{"lead.hook", from = 16, last = 0}, {"lead.hook", cycle = 1}}

local FLAVOURS = {
	{id = "uplifting", name = "Uplifting", tempo = {136, 140}, swing = {0, 0.02},
		channels = {
			{role = "drums", beats = {"trance.classic", "trance.tech"}},
			{role = "bass", patches = {"bass.pluck", "bass.reese", "bass.moog"}, lines = {"@offbeat", "trance.octave", "trance.roll"}},
			{role = "pad", patches = {"pad.supersaw", "pad.strings"}},
			{role = "stab", patches = {"stab.saw", "stab.rave", "stab.brass"}, steps = {"x...............", "x.....x.........", "x..x..x........."}},
			{role = "arp", patches = {"pluck.trance", "pluck.saw", "pluck.bell"}},
			{role = "lead", patches = {"lead.supersaw", "lead.saw"},
				hooks = {"hook.anthem", "hook.ascent", "hook.leap", "hook.circle", "hook.lament", "@motif"}},
			{role = "counter", patches = {"pluck.glass", "pluck.bell", "keys.vibes"}, chance = 0.5},
			{role = "fx", patches = {"fx.riser", "fx.siren"}},
		}},
	{id = "progressive", name = "Progressive", tempo = {132, 136}, swing = {0, 0.06},
		form = {intro = {2}, breakdown = {1, 1, 2}},
		channels = {
			{role = "drums", beats = {"trance.progressive", "trance.classic"}},
			{role = "bass", patches = {"bass.round", "bass.pluck", "bass.fm"}, lines = {"trance.low", "@offbeat", "@cell", "trance.triplet"}},
			{role = "pad", patches = {"pad.warm", "pad.glass", "pad.pwm", "pad.air"}},
			{role = "keys", patches = {"keys.vibes", "keys.rhodes"}, chance = 0.4},
			{role = "arp", patches = {"pluck.saw", "pluck.glass", "pluck.marimba", "pluck.string"}},
			{role = "lead", patches = {"lead.sine", "lead.vox", "lead.flute", "lead.fm"}, chance = 0.6,
				hooks = {"hook.voice", "hook.sigh", "hook.space", "hook.question", "@motif"}},
			{role = "texture", patches = {"texture.shimmer", "texture.air"}, chance = 0.7},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		}},
	{id = "psy", name = "Psytrance", tempo = {140, 145}, swing = {0, 0.02},
		harmony = {progressions = STATIC, change = 0.2, voicing = {0, 2, 4, 6}},
		channels = {
			{role = "drums", beats = {"trance.psy", "trance.tech"}},
			{role = "bass", patches = {"bass.psy"}, lines = {"@gallop"}},
			{role = "pad", patches = {"pad.dark", "pad.choir"}, chance = 0.5},
			{role = "arp", patches = {"pluck.acid", "pluck.chip", "pluck.bell"}, arp = {rates = {1}}},
			{role = "lead", patches = {"lead.fm", "lead.square", "lead.hoover"}, chance = 0.5,
				hooks = {"hook.morse", "hook.insist", "hook.cascade", "@motif"}},
			{role = "texture", patches = {"texture.drone", "texture.air"}, chance = 0.6},
			{role = "fx", patches = {"fx.siren", "fx.riser", "fx.wind"}},
		}},
	{id = "acid", name = "Acid Trance", tempo = {136, 142}, swing = {0, 0.04},
		harmony = {progressions = {{1, 1, 6, 7}, {1, 6, 3, 7}, {1, 1, 1, 7}}, change = 0.2},
		channels = {
			{role = "drums", beats = {"trance.tech", "trance.classic"}},
			{role = "bass", patches = {"bass.acid", "bass.acidSquare"}, lines = {"@acid"}},
			{role = "pad", patches = {"pad.supersaw", "pad.dark", "pad.choir"}},
			{role = "arp", patches = {"pluck.acid", "pluck.trance"}, arp = {rates = {1}}},
			{role = "lead", patches = {"lead.saw", "lead.square"}, chance = 0.5,
				hooks = {"hook.riff", "hook.dotted", "hook.arpeggio", "@motif"}},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	{id = "tech", name = "Tech Trance", tempo = {138, 142}, swing = {0, 0.03},
		harmony = {progressions = STATIC, change = 0.3, voicing = {0, 2, 4, 6}},
		form = {openings = {"cold", "build"}, links = {"build", "breakdown build", "double"}},
		channels = {
			{role = "drums", beats = {"trance.tech", "trance.psy"}},
			{role = "bass", patches = {"bass.rumble", "bass.psy", "bass.hoover"}, lines = {"trance.triplet", "trance.roll", "@rumble"}},
			{role = "stab", patches = {"stab.rave", "stab.fm", "stab.saw"}, steps = {"...x..x...x...x.", "x..x..x...x.....", "..x...x..x..x..."}},
			{role = "arp", patches = {"pluck.chip", "pluck.acid"}, chance = 0.6, arp = {rates = {1}}},
			{role = "lead", patches = {"lead.hoover", "lead.fm"}, chance = 0.4, hooks = {"hook.insist", "hook.morse", "hook.jack"}},
			{role = "texture", patches = {"texture.tape", "texture.drone"}, chance = 0.5},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	{id = "goa", name = "Goa", tempo = {138, 145}, swing = {0, 0.03},
		harmony = {progressions = {{1, 1, 2, 1}, {1, 2, 1, 7}, {1, 1, 7, 1}}, change = 0.3, voicing = {0, 2, 4, 6}},
		channels = {
			{role = "drums", beats = {"trance.psy", "trance.classic"}},
			{role = "bass", patches = {"bass.psy", "bass.pluck"}, lines = {"@gallop", "trance.roll"}},
			{role = "pad", patches = {"pad.choir", "pad.glass"}, chance = 0.6},
			{role = "arp", patches = {"pluck.string", "pluck.bell", "pluck.acid"}, arp = {rates = {1}, octave = 2}},
			{role = "lead", patches = {"lead.fm", "lead.vox", "lead.flute"}, hooks = {"hook.cascade", "hook.circle", "hook.tresillo", "@motif"}},
			{role = "counter", patches = {"pluck.glass", "pluck.marimba"}, chance = 0.6},
			{role = "texture", patches = {"texture.shimmer", "texture.drone"}, chance = 0.6},
			{role = "fx", patches = {"fx.wind", "fx.siren"}},
		}},
	-- The tune is on a piano, over strings.
	{id = "dream", name = "Dream Trance", tempo = {132, 138}, swing = {0, 0.04},
		channels = {
			{role = "drums", beats = {"trance.dream", "trance.classic"}},
			{role = "bass", patches = {"bass.round", "bass.pluck", "bass.fm"}, lines = {"trance.low", "@offbeat", "trance.octave"}},
			{role = "pad", patches = {"pad.strings", "pad.warm", "pad.choir"}},
			{role = "keys", patches = {"keys.piano", "keys.harp"}, chance = 0.6},
			{role = "arp", patches = {"pluck.bell", "pluck.glass", "keys.harp"}, arp = {rates = {1, 2}}},
			{role = "lead", patches = {"lead.pluck", "lead.sine", "lead.flute"},
				hooks = {"hook.lullaby", "hook.arpeggio", "hook.cascade", "hook.lament", "hook.anthem"}},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		}},
}

return {
	api = 3,
	title = "Trance",
	symbol = "sparkles",
	summary = "Uplifting, Progressive, Psy and more, with long breakdowns",
	defaults = {energy = 0.7, complexity = 0.6, humanize = 0.1, space = 0.6},
	kit = {
		kick = {base = 48, sweep = 150, sweepTime = 0.02, decay = 0.2, drive = 2.2, click = 0.45, length = 0.35},
		hat = {scale = 2, decay = 0.012, openDecay = 0.06},
	},
	mix = {duckDepth = 0.7, drums = 0.85, bass = 0.8, pad = 1.4, arp = 1.2, lead = 1.15, delayFeedback = 0.45,
		reverbSend = 1.1},
	throws = 8,
	set = {form = {openings = {"melodic", "melodic", "build"}, builds = {"roll", "roll", "rise"},
			links = {"breakdown build"}, breakdown = {1, 1, 2}},
		modes = {"minor", "phrygian"}, modulations = {2, 0},
		arrangement = {introBars = 16, buildBars = 8, dropBars = 32, breakdownBars = 24, rebuildBars = 8,
			outroBars = 16, blendBars = 8, minCycles = 2, maxCycles = 2}},
	-- The anthem returns after every breakdown: the harmony stays.
	harmony = {progressions = PROGRESSIONS, voicing = {0, 2, 4, 8}, barsPerChord = 2, change = 0},
	roles = {drums = {fills = FILLS}, arp = {arp = {rates = {1}, orders = ARPS, gate = 0.7, always = true, contour = false}}},
	plan = {
		-- The arpeggio runs from the intro's second phrase to the end.
		intro = {arp = {"arp.run", from = 8}, pad = false, keys = false},
		build = {arp = "arp.run", bass = {"bass.line", from = 4}},
		drop = {arp = "arp.run", pad = "pad.chords", stab = {"stab.hits", from = 16}, lead = ANTHEM,
			counter = {"counter.answer", cycle = 1}},
		breakdown = {bass = false, lead = {"lead.soft", from = 8}},
		outro = {arp = "arp.run", bass = {"bass.line", to = 8}},
	},
	flavours = FLAVOURS,
	library = {beats = BEATS, lines = LINES},
}
