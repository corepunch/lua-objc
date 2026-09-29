-- Breakbeat: 120 to 140 BPM. Syncopated funk-break drums with ghost
-- snares, a record's break under the programmed kit, tom fills and a
-- slapping bassline. Its flavours: Big Beat, Nu Skool on an acid line,
-- Florida Breaks, Funky breaks on a clavinet, Progressive breaks, Electro
-- on an 808 and a cowbell, and Rave with its hoover and piano.

local PROGRESSIONS = {{1, 1, 4, 1}, {1, 7, 6, 7}, {1, 4, 1, 5}, {1, 3, 4, 4}, {1, 1, 7, 7}, {1, 6, 4, 5}}
local MELODIC = {{1, 6, 3, 7}, {1, 4, 6, 5}, {6, 7, 1, 1}, {6, 4, 1, 5}}

-- Funky breaks: kick and snare patterns over a bar; "g" is a ghost snare.
local BEATS = {
	{id = "breaks.funky", name = "Funky", bars = 2, lanes = {
		{"kick", "X.x.......x.....|X.x...x...x..x.."},
		{"snare", "....X.......X..."},
		{"ghost", ".......g.g.....g|.......g......g.", light = false},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.45},
		{"openHat", "......x.......x.", gain = 0.4, when = "energy"},
		{"conga", "...x.......x....", gain = 0.4, when = "complexity"},
	}},
	{id = "breaks.skip", name = "Skip", bars = 2, lanes = {
		{"kick", "X......x..x.....|X......x..x..x.."},
		{"snare", "....X.......X..."},
		{"ghost", "..........g.....|......g...g.....", light = false},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.45},
		{"ride", "x...x...x...x...", gain = 0.3, when = "energy"},
		{"rim", "...x.......x....", gain = 0.4, when = "complexity"},
	}},
	{id = "breaks.busy", name = "Busy", bars = 2, lanes = {
		{"kick", "X.x...x...x..x..|X.x...x..x...x.."},
		{"snare", "....X.......X..."},
		{"ghost", ".......g......g.|.......g.g....g.", light = false},
		{"hat", "xoxoxoxoxoxoxoxo", gain = 0.35},
		{"openHat", "......x.......x.", gain = 0.4, when = "energy"},
		{"tambourine", "..x...x...x...x.", gain = 0.35, when = "complexity"},
	}},
	{id = "breaks.push", name = "Push", bars = 2, lanes = {
		{"kick", "X..x......x.....|X..x......x.x..."},
		{"snare", "....X.......X..."},
		{"ghost", "......g........g", light = false},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.45},
		{"openHat", "..x.......x.....", gain = 0.35, when = "energy"},
		{"cowbell", "x.......x.......", gain = 0.3, when = "complexity"},
	}},
	-- Electro: the 808 pattern with its cowbell.
	{id = "breaks.electro", name = "Electro", bars = 2, lanes = {
		{"kick", "X.....x...x.x...|X.....x...x....."},
		{"snare", "....X.......X..."},
		{"clap", "....x.......x...", gain = 0.6},
		{"hat", "xxxxxxxxxxxxxxxx", gain = 0.3},
		{"openHat", "..x...x...x...x.", gain = 0.35, when = "energy"},
		{"cowbell", "x..x..x...x.x...|x..x..x...x..x..", gain = 0.4, light = false},
	}},
	{id = "breaks.stomp", name = "Stomp", bars = 2, lanes = {
		{"kick", "X.....x.x.x.....|X.....x.x.x..x.."},
		{"snare", "....X.......X..."},
		{"clap", "....x.......x...", gain = 0.5, light = false},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.5},
		{"crash", "X...............|................", gain = 0.35, when = "energy"},
		{"ghost", ".......g.....g..", when = "complexity"},
	}},
}

local LINES = {
	{id = "breaks.funk", name = "Funk", notes = "0:0:2 3:0:1 4:7:1! 6:0:2 10:6:2 12:4:2 14:2:2? | 0:0:2 3:0:1 4:7:1! 6:0:2 10:4:2 12:6:2~ 14:7:2?"},
	{id = "breaks.slap", name = "Slap", notes = "0:0:1! 2:0:1 3:7:1 6:0:1! 8:0:1 10:6:1 11:7:1? 14:4:2"},
	{id = "breaks.low", name = "Low", notes = "0:0:4 6:0:2? 10:0:2 13:6:3~ | 0:0:4 6:0:2? 10:2:2 13:4:3~"},
	{id = "breaks.electro", name = "Electro", notes = "0:0:1 2:0:1 4:0:1 6:7:1! 8:0:1 10:0:1 12:6:1 14:7:1! | 0:0:1 2:0:1 4:0:1 6:7:1! 8:4:1 10:4:1 12:2:1 14:0:1"},
	{id = "breaks.rave", name = "Rave", notes = "0:0:3 3:0:3 6:0:2 8:7:3 11:6:3 14:4:2 | 0:0:3 3:0:3 6:0:2 8:2:3 11:4:3 14:6:2"},
}

local FILLS = {"fill.toms", "fill.tomsDown", "fill.stutter", "fill.snares", "fill.triplets", "@stutter", "@reverse", "@cut", "@tape"}
local RECORDS = {"break.amen", "break.funk", "break.stomp", "break.shuffle", "break.tambourine", "break.bongo"}

local FLAVOURS = {
	{id = "bigbeat", name = "Big Beat", tempo = {120, 132}, swing = {0.04, 0.12},
		snares = {"fat", "crunchy", "roomy", "layered"},
		channels = {
			{role = "drums", beats = {"breaks.stomp", "breaks.funky", "breaks.push"}, gain = 0.9},
			{role = "tops", beats = {"break.stomp", "break.amen", "break.funk"}, gain = 0.8, chops = true},
			{role = "bass", patches = {"bass.moog", "bass.hoover", "bass.acid"}, lines = {"breaks.low", "breaks.funk", "@cell", "line.tresillo"}},
			{role = "stab", patches = {"stab.brass", "stab.rave", "stab.saw"}, steps = {"x.....x...x.....", "x..x..x.........", "..x...x...x..x.."}},
			{role = "keys", patches = {"keys.clav", "keys.organ"}, chance = 0.4},
			{role = "lead", patches = {"lead.hoover", "lead.saw", "lead.square"}, chance = 0.7,
				hooks = {"hook.riff", "hook.insist", "hook.bounce", "hook.jack", "@motif"}},
			{role = "texture", patches = {"texture.tape"}, chance = 0.4},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		},
		plan = {intro = {tops = {"tops.loop", keep = true}}, drop = {tops = {"tops.loop", keep = true}}}},
	{id = "nuskool", name = "Nu Skool", tempo = {130, 138}, swing = {0.02, 0.1},
		snares = {"tight", "crunchy", "layered", "rimshot"},
		channels = {
			{role = "drums", beats = {"breaks.skip", "breaks.busy", "breaks.push"}},
			{role = "tops", beats = RECORDS, gain = 0.4, chops = true, chance = 0.6},
			{role = "bass", patches = {"bass.acid", "bass.acidSquare", "bass.growl", "bass.reeseWide"}, lines = {"@acid", "breaks.slap", "@cell"}},
			{role = "pad", patches = {"pad.dark", "pad.pwm"}, chance = 0.6},
			{role = "stab", patches = {"stab.fm", "stab.saw"}, chance = 0.6},
			{role = "arp", patches = {"pluck.acid", "pluck.chip"}, chance = 0.5},
			{role = "lead", patches = {"lead.fm", "lead.square"}, chance = 0.6, hooks = {"hook.morse", "hook.dotted", "hook.riff", "@motif"}},
			{role = "fx", patches = {"fx.riser", "fx.siren"}},
		}},
	{id = "florida", name = "Florida Breaks", tempo = {130, 140}, swing = {0.04, 0.1},
		snares = {"tight", "layered", "rimshot", "roomy"},
		channels = {
			{role = "drums", beats = {"breaks.funky", "breaks.busy", "breaks.electro"}},
			{role = "tops", beats = {"break.funk", "break.bongo", "break.tambourine"}, gain = 0.35, chops = true, chance = 0.4},
			{role = "bass", patches = {"bass.donk", "bass.fm", "bass.808", "bass.acid"}, lines = {"breaks.slap", "breaks.electro", "@acid", "line.octaves"}},
			{role = "pad", patches = {"pad.saw", "pad.strings"}, chance = 0.6},
			{role = "stab", patches = {"stab.organ", "stab.piano", "stab.saw"}, chance = 0.5},
			{role = "arp", patches = {"pluck.saw", "pluck.bell"}, chance = 0.5, arp = {rates = {2, 1}}},
			{role = "lead", patches = {"lead.vox", "lead.saw", "lead.sine"}, chance = 0.7,
				hooks = {"hook.call", "hook.question", "hook.bounce", "hook.octaves", "@motif"}},
			{role = "fx", patches = {"fx.riser"}},
		}},
	{id = "funky", name = "Funky Breaks", tempo = {120, 130}, swing = {0.08, 0.18},
		snares = {"vintage", "roomy", "rimshot"},
		harmony = {progressions = {{1, 4, 1, 4}, {1, 1, 4, 4}, {1, 4, 1, 5}, {2, 5, 1, 1}}, voicing = {0, 2, 4, 6}},
		channels = {
			{role = "drums", beats = {"breaks.funky", "breaks.push"}, gain = 0.8},
			{role = "tops", beats = {"break.funk", "break.shuffle", "break.bongo", "break.tambourine"}, gain = 0.85, chops = true},
			{role = "bass", patches = {"bass.moog", "bass.upright", "bass.round"}, lines = {"breaks.funk", "breaks.slap", "line.walk"}},
			{role = "keys", patches = {"keys.clav", "keys.rhodes", "keys.wurli", "keys.organ"}},
			{role = "stab", patches = {"stab.brass", "stab.pizzicato"}, chance = 0.7, steps = {"x.....x...x.....", "...x..x.....x..."}},
			{role = "lead", patches = {"lead.flute", "lead.vox", "lead.square"}, chance = 0.6,
				hooks = {"hook.call", "hook.riff", "hook.skank", "hook.bounce", "@motif"}},
			{role = "fx", patches = {"fx.riser", "fx.wind"}},
		},
		plan = {intro = {tops = {"tops.loop", keep = true}, keys = {"keys.comp", from = "half"}},
			drop = {tops = {"tops.loop", keep = true}, keys = "keys.comp"}}},
	{id = "progressive", name = "Progressive Breaks", tempo = {126, 132}, swing = {0.02, 0.08},
		harmony = {progressions = MELODIC, voicing = {0, 2, 4, 8}},
		form = {openings = {"melodic", "build"}, breakdown = {1, 2}},
		channels = {
			{role = "drums", beats = {"breaks.skip", "breaks.push", "breaks.funky"}},
			{role = "bass", patches = {"bass.round", "bass.pluck", "bass.reese"}, lines = {"breaks.low", "@cell", "line.push"}},
			{role = "pad", patches = {"pad.glass", "pad.warm", "pad.strings", "pad.air"}},
			{role = "arp", patches = {"pluck.glass", "pluck.trance", "pluck.string"}, arp = {rates = {1, 2}}},
			{role = "lead", patches = {"lead.sine", "lead.vox", "lead.pluck"}, chance = 0.7,
				hooks = {"hook.lament", "hook.voice", "hook.circle", "hook.space", "@motif"}},
			{role = "counter", patches = {"pluck.bell", "keys.vibes"}, chance = 0.5},
			{role = "texture", patches = {"texture.shimmer", "texture.air"}, chance = 0.7},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		},
		plan = {drop = {pad = "pad.chords"}}},
	{id = "electro", name = "Electro", tempo = {124, 132}, swing = {0, 0.04},
		snares = {"tight", "layered", "crunchy"},
		harmony = {progressions = {{1, 1, 1, 1}, {1, 1, 7, 7}, {1, 1, 4, 4}}, voicing = {0, 2, 4}, change = 0.2},
		channels = {
			{role = "drums", beats = {"breaks.electro"}},
			{role = "bass", patches = {"bass.fm", "bass.donk", "bass.acidSquare", "bass.808"}, lines = {"breaks.electro", "line.octaves", "@acid"}},
			{role = "pad", patches = {"pad.choir", "pad.pwm"}, chance = 0.6},
			{role = "stab", patches = {"stab.fm", "stab.organ"}, chance = 0.6},
			{role = "arp", patches = {"pluck.chip", "pluck.acid"}, arp = {rates = {1}}},
			{role = "lead", patches = {"lead.vox", "lead.square", "lead.fm"}, chance = 0.7,
				hooks = {"hook.morse", "hook.dotted", "hook.octaves", "hook.insist", "@motif"}},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	-- 1992: a hoover, a piano and the Amen.
	{id = "rave", name = "Rave", tempo = {132, 140}, swing = {0.02, 0.1},
		snares = {"vintage", "fat", "crunchy"},
		harmony = {progressions = {{1, 6, 4, 5}, {1, 7, 6, 7}, {6, 4, 1, 5}, {1, 1, 6, 7}}, voicing = {0, 2, 4, 7}},
		channels = {
			{role = "drums", beats = {"breaks.busy", "breaks.stomp"}, gain = 0.85},
			{role = "tops", beats = {"break.amen", "break.funk"}, gain = 0.85, chops = true},
			{role = "bass", patches = {"bass.hoover", "bass.808", "bass.sub"}, lines = {"breaks.rave", "breaks.low", "line.octaves"}},
			{role = "keys", patches = {"keys.piano"}, comp = {length = 2}},
			{role = "stab", patches = {"stab.rave", "stab.piano"}, steps = {"x..x..x...x.....", "x.....x..x..x..."}},
			{role = "lead", patches = {"lead.hoover", "lead.square"}, chance = 0.7, hooks = {"hook.jack", "hook.riff", "hook.insist", "hook.anthem"}},
			{role = "texture", patches = {"texture.tape"}, chance = 0.5},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		},
		plan = {intro = {tops = {"tops.loop", keep = true}}, breakdown = {keys = "keys.comp"},
			drop = {tops = {"tops.loop", keep = true}, keys = "keys.comp"}}},
}

return {
	api = 3,
	title = "Breakbeat",
	symbol = "opticaldisc.fill",
	summary = "Big Beat, Nu Skool, Florida, Electro and more",
	defaults = {energy = 0.65, complexity = 0.55, humanize = 0.4, space = 0.3},
	kit = {
		kick = {base = 52, sweep = 120, sweepTime = 0.02, decay = 0.18, drive = 2, click = 0.4, length = 0.35},
		snare = {tone = 210, overtone = 350, bodyDecay = 0.06, noiseDecay = 0.13, noise = 0.5},
	},
	mix = {duckDepth = 0.35, stab = 1.15, tops = 0.8},
	set = {form = {builds = {"roll", "stomp", "stomp", "sweep", "rise"}},
		modes = {"minor", "dorian", "phrygian"},
		arrangement = {introBars = 8, buildBars = 8, dropBars = 32, breakdownBars = 16, rebuildBars = 8,
			outroBars = 8, blendBars = 8, minCycles = 2, maxCycles = 3}},
	harmony = {progressions = PROGRESSIONS, voicing = {0, 2, 4, 6}, barsPerChord = 2},
	roles = {drums = {fills = FILLS}},
	plan = {
		intro = {drums = "drums.groove"},
		drop = {pad = {"pad.chords", from = 16}},
		breakdown = {lead = {"lead.soft", from = 8}},
		outro = {bass = {"bass.line", to = 4}},
	},
	flavours = FLAVOURS,
	library = {beats = BEATS, lines = LINES},
}
