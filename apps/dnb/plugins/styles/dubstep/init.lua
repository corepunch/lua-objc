-- Dubstep: 136 to 150 BPM, felt at half time. The kick opens the bar and
-- the snare lands on beat three; the drop is the bass. Its flavours: Deep,
-- on a sub and a dub echo; Brostep, a wobble whose LFO restarts with every
-- note at a rate the note chooses; Riddim, one wub repeated until it is a
-- rhythm; Melodic, chords and a lead over the half-time; Dub, a skank and
-- a melodica; and Chillstep, mostly pads.

local PROGRESSIONS = {{1, 1, 1, 1}, {1, 1, 6, 7}, {1, 2, 1, 7}, {1, 6, 1, 5}}
local MELODIC = {{1, 6, 3, 7}, {6, 7, 1, 1}, {1, 4, 6, 5}, {6, 4, 1, 5}, {1, 3, 6, 7}}

local BEATS = {
	-- Triplet-feel hats: every third 16th, the swagger over the half time.
	{id = "dubstep.half", name = "Half", bars = 2, lanes = {
		{"kick", "X...............|X.........x....."},
		{"snare", "........X......."},
		{"hat", "X..x..X..x..X..x", gain = 0.5},
		{"openHat", "..............x.", gain = 0.4, when = "energy"},
		{"ghost", "......g.......gg", when = "complexity"},
		{"rim", "............x...", gain = 0.4, light = false},
	}},
	{id = "dubstep.skip", name = "Skip", bars = 2, lanes = {
		{"kick", "X..x............|X.............x."},
		{"snare", "........X......."},
		{"clap", "........x.......", gain = 0.5, light = false},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.4},
		{"openHat", "..........x.....", gain = 0.4, when = "energy"},
		{"ghost", ".....g.......g..", when = "complexity"},
	}},
	{id = "dubstep.stomp", name = "Stomp", bars = 2, lanes = {
		{"kick", "X.........x.....|X.....x...x....."},
		{"snare", "........X......."},
		{"clap", "........x.......", gain = 0.6},
		{"hat", "xoxoxoxoxoxoxoxo", gain = 0.3, light = false},
		{"kick", "...........o....", when = "complexity"},
		{"crash", "X...............|................", gain = 0.4, when = "energy"},
	}},
	{id = "dubstep.riddim", name = "Riddim", lanes = {
		{"kick", "X.....x.....x..."},
		{"snare", "........X......."},
		{"hat", "..x...x...x...x.", gain = 0.45},
		{"rim", "....x.......x...", gain = 0.35, when = "complexity"},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.25, when = "energy"},
	}},
	{id = "dubstep.deep", name = "Deep", bars = 2, lanes = {
		{"kick", "X..........x....|X..............."},
		{"snare", "........x.......", gain = 0.9},
		{"rim", "...x......x..x..|...x......x.....", gain = 0.4},
		{"hat", "..x...x...x...x.", gain = 0.4},
		{"shaker", "x.xxx.xxx.xxx.xx", gain = 0.25, when = "energy"},
		{"conga", ".....x.........x", gain = 0.35, when = "complexity"},
	}},
	{id = "dubstep.steppers", name = "Steppers", lanes = {
		{"kick", "X...x...X...x...", gain = 0.9},
		{"snare", "........X......."},
		{"rim", "....x.......x...", gain = 0.45},
		{"hat", "..x...x...x...x.", gain = 0.5},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.25, when = "energy"},
	}},
}

local LINES = {
	{id = "dubstep.riddim", name = "Riddim", notes = "0:0:3w3 4:0:3w3 8:0:3w3 12:0:2w6 14:0:2w6 | 0:0:3w3 4:0:3w3 8:7:3w3 12:6:2w6 14:0:2w6"},
	{id = "dubstep.yoi", name = "Yoi", notes = "0:0:4w2 4:0:2w4 6:0:2w4 8:0:4w2 12:4:4w3? | 0:0:4w2 4:0:2w4 6:0:2w4 8:6:4w2 12:0:4w6?"},
	{id = "dubstep.sub", name = "Sub", notes = "0:0:6 8:0:2? 11:6:4~ | 0:0:6 8:0:2? 11:2:4~"},
	{id = "dubstep.growl", name = "Growl", notes = "0:0:6w1 6:0:2w4 8:0:4w2 12:1b:4w3~ | 0:0:6w1 6:0:2w4 8:7:2w6 10:6:2w6 12:0:4w2"},
	{id = "dubstep.dub", name = "Dub", notes = "0:0:3 3:0:2? 6:4:2 8:0:3 12:6:2 14:4:2+ | 0:0:3 3:0:2? 6:2:2 8:0:3 12:4:3"},
	{id = "dubstep.melodic", name = "Melodic", notes = "0:0:8w1 8:0:4w2 12:4:4w2~ | 0:0:8w1 8:2:4w2 12:0:4w4"},
}

local FILLS = {"fill.roll", "fill.triplets", "fill.toms", "@tape", "@stutter", "@cut", "@reverse"}

local FLAVOURS = {
	{id = "deep", name = "Deep Dubstep", tempo = {138, 142}, swing = {0.04, 0.1},
		snares = {"roomy", "vintage", "fat", "layered"},
		channels = {
			{role = "drums", beats = {"dubstep.deep", "dubstep.half", "dubstep.steppers"}},
			{role = "bass", patches = {"bass.sub", "bass.808", "bass.wobble"}, lines = {"dubstep.sub", "@wobble", "dubstep.dub"}, rates = {0.5, 1, 1, 2}},
			{role = "pad", patches = {"pad.dark", "pad.air", "pad.choir"}},
			{role = "stab", patches = {"stab.dub", "stab.organ"}, chance = 0.4, steps = {"......x.........", "......x.......x."}},
			{role = "lead", patches = {"lead.sine", "lead.flute", "lead.vox"}, chance = 0.6, hooks = {"hook.space", "hook.voice", "hook.sigh", "@motif"}},
			{role = "texture", patches = {"texture.tape", "texture.air", "texture.drone"}},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		}},
	{id = "brostep", name = "Brostep", tempo = {140, 150}, swing = {0, 0.06},
		snares = {"crunchy", "fat", "layered", "tight"},
		channels = {
			{role = "drums", beats = {"dubstep.stomp", "dubstep.half", "dubstep.skip"}},
			{role = "bass", patches = {"bass.wobble", "bass.yoi", "bass.growl"}, lines = {"@wobble", "dubstep.yoi", "dubstep.growl"}, rates = {1, 2, 3, 4, 6}},
			{role = "pad", patches = {"pad.supersaw", "pad.dark"}, chance = 0.5},
			{role = "stab", patches = {"stab.rave", "stab.fm", "stab.saw"}, steps = {"......x.........", "......x.......x.", "...x..x........."}},
			{role = "arp", patches = {"pluck.chip", "pluck.acid"}, chance = 0.4, arp = {rates = {1, 2}}},
			{role = "lead", patches = {"lead.hoover", "lead.supersaw", "lead.square"}, chance = 0.5,
				hooks = {"hook.morse", "hook.insist", "hook.anthem", "@motif"}},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	{id = "riddim", name = "Riddim", tempo = {140, 150}, swing = {0, 0.04},
		snares = {"tight", "crunchy", "rimshot", "layered"},
		harmony = {progressions = {{1, 1, 1, 1}, {1, 1, 1, 7}, {1, 2, 1, 1}}, change = 0.15},
		channels = {
			{role = "drums", beats = {"dubstep.riddim", "dubstep.half"}},
			{role = "bass", patches = {"bass.yoi", "bass.wobble", "bass.growl"}, lines = {"dubstep.riddim", "dubstep.yoi", "@wobble"}, rates = {2, 3, 3, 4}},
			{role = "stab", patches = {"stab.fm", "stab.brass"}, chance = 0.5, steps = {"......x.........", "..x...x...x....."}},
			{role = "texture", patches = {"texture.drone", "texture.tape"}, chance = 0.5},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	{id = "melodic", name = "Melodic Dubstep", tempo = {138, 145}, swing = {0, 0.06},
		snares = {"fat", "layered", "roomy"},
		harmony = {progressions = MELODIC, voicing = {0, 2, 4, 8}, barsPerChord = 2, change = 0.1},
		form = {openings = {"melodic", "build"}, links = {"breakdown build"}, breakdown = {1, 2}},
		channels = {
			{role = "drums", beats = {"dubstep.half", "dubstep.stomp"}},
			{role = "bass", patches = {"bass.wobble", "bass.reese", "bass.808"}, lines = {"dubstep.melodic", "dubstep.sub", "@wobble"}, rates = {1, 2, 2}},
			{role = "pad", patches = {"pad.supersaw", "pad.strings", "pad.choir"}},
			{role = "keys", patches = {"keys.piano", "keys.harp"}, chance = 0.6},
			{role = "arp", patches = {"pluck.glass", "pluck.bell", "pluck.trance"}, chance = 0.7, arp = {rates = {2, 1}}},
			{role = "lead", patches = {"lead.supersaw", "lead.vox", "lead.saw"}, hooks = {"hook.anthem", "hook.ascent", "hook.lament", "hook.leap", "@motif"}},
			{role = "counter", patches = {"pluck.bell", "keys.vibes"}, chance = 0.5},
			{role = "fx", patches = {"fx.riser", "fx.wind"}},
		},
		plan = {drop = {pad = "pad.chords", lead = {"lead.hook", from = 8}, counter = {"counter.answer", from = 8}}}},
	-- Reggae's bones: a skank on the off-beat, a steppers kick, a melodica.
	{id = "dub", name = "Dub", tempo = {136, 142}, swing = {0.08, 0.16},
		snares = {"rimshot", "vintage", "roomy"},
		harmony = {progressions = {{1, 1, 4, 4}, {1, 7, 1, 7}, {1, 4, 1, 5}}, voicing = {0, 2, 4}, barsPerChord = 2},
		channels = {
			{role = "drums", beats = {"dubstep.steppers", "dubstep.deep"}},
			{role = "bass", patches = {"bass.sub", "bass.round", "bass.808"}, lines = {"dubstep.dub", "dubstep.sub", "line.walk"}},
			{role = "stab", patches = {"stab.organ", "stab.dub", "stab.piano"}, steps = {"....x.......x...", "..x...x...x...x."}},
			{role = "keys", patches = {"keys.organ", "keys.clav"}, chance = 0.5},
			{role = "lead", patches = {"lead.vox", "lead.flute", "lead.square"}, chance = 0.7,
				hooks = {"hook.skank", "hook.call", "hook.lament", "hook.offbeat", "@motif"}},
			{role = "texture", patches = {"texture.tape"}, chance = 0.6},
			{role = "fx", patches = {"fx.siren", "fx.wind"}},
		},
		plan = {intro = {stab = {"stab.hits", from = "half"}}, breakdown = {stab = "stab.hits"}}},
	{id = "chill", name = "Chillstep", tempo = {136, 140}, swing = {0.04, 0.12},
		snares = {"roomy", "vintage", "layered"},
		harmony = {progressions = MELODIC, voicing = {2, 4, 6, 8}, barsPerChord = 2},
		form = {openings = {"melodic", "melodic", "build"}, builds = {"rise", "sweep"}, intro = {2}},
		channels = {
			{role = "drums", beats = {"dubstep.deep", "dubstep.half"}, gain = 0.85},
			{role = "bass", patches = {"bass.sub", "bass.round"}, lines = {"dubstep.sub", "line.root", "dubstep.melodic"}},
			{role = "pad", patches = {"pad.air", "pad.glass", "pad.warm", "pad.choir"}},
			{role = "keys", patches = {"keys.rhodes", "keys.vibes", "keys.harp"}, chance = 0.6},
			{role = "arp", patches = {"pluck.glass", "pluck.string", "pluck.bell"}, chance = 0.7, arp = {rates = {2, 4}}},
			{role = "lead", patches = {"lead.vox", "lead.sine", "lead.pluck"}, chance = 0.8, hooks = {"hook.voice", "hook.lullaby", "hook.sigh", "hook.space", "@motif"}},
			{role = "texture", patches = {"texture.shimmer", "texture.air"}},
			{role = "fx", patches = {"fx.wind"}},
		},
		plan = {drop = {pad = "pad.chords", lead = {"lead.hook", from = 8}}}},
}

return {
	api = 3,
	title = "Dubstep",
	symbol = "speaker.wave.3.fill",
	summary = "Deep, Brostep, Riddim and more at half time",
	defaults = {energy = 0.7, complexity = 0.5, humanize = 0.2, space = 0.35},
	kit = {
		kick = {base = 44, sweep = 140, sweepTime = 0.022, decay = 0.26, drive = 2.4, click = 0.4, length = 0.5},
		snare = {tone = 200, bodyDecay = 0.07, noiseDecay = 0.16, noise = 0.55},
	},
	mix = {duckDepth = 0.35, bass = 1.1, delayFeedback = 0.5},
	set = {form = {builds = {"rise", "rise", "roll", "stomp"},
			links = {"breakdown build", "breakdown build", "build", "double"}},
		modes = {"phrygian", "minor"}, modulations = {0, -2},
		arrangement = {introBars = 8, buildBars = 8, dropBars = 16, breakdownBars = 8, rebuildBars = 8,
			outroBars = 8, blendBars = 4, minCycles = 2, maxCycles = 3}},
	harmony = {progressions = PROGRESSIONS, voicing = {0, 2, 4}, barsPerChord = 4},
	-- A dub melody sits an octave down.
	roles = {drums = {fills = FILLS}, lead = {octave = -1}},
	plan = {
		intro = {pad = "pad.chords"},
		build = {bass = {"bass.hold", from = 4}},
		drop = {pad = {"pad.chords", from = 8}, lead = false, counter = false, keys = {"keys.comp", from = 8}, arp = {"arp.run", from = 8}},
		breakdown = {lead = "lead.hook"},
		outro = {bass = "bass.hold"},
	},
	flavours = FLAVOURS,
	library = {beats = BEATS, lines = LINES},
}
