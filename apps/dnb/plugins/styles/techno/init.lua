-- Techno: a four-on-the-floor set from 118 to 140 BPM. A long, driven kick
-- with a rumble rolling in its tail, off-beat hats and claps on two and
-- four. Its flavours: Peak Time, Acid on a squelching 303, Hypnotic on a
-- dub chord thrown into the delay, Industrial, Minimal with percussion
-- where the tune would be, Melodic, and slow, washed-out Dub Techno.

-- Minor-key loops; techno lives on one or two chords.
local PROGRESSIONS = {{1, 1, 1, 1}, {1, 1, 6, 6}, {1, 7, 1, 7}, {1, 1, 4, 4}, {1, 6, 1, 7}}
local MELODIC = {{1, 6, 3, 7}, {1, 4, 6, 5}, {6, 7, 1, 1}, {1, 3, 6, 7}, {1, 6, 4, 5}}

local BEATS = {
	{id = "techno.drive", name = "Drive", lanes = {
		{"kick", "X...X...X...X..."},
		{"clap", "....X.......X...", gain = 0.9, light = false},
		{"openHat", "..x...x...x...x.", gain = 0.5},
		{"hat", "xx.xxx.xxx.xxx.x", gain = 0.25, when = "energy"},
		{"ride", "..x...x...x...x.", gain = 0.35, light = false},
		{"rim", "...x...x...x.x.x", gain = 0.4, when = "complexity"},
	}},
	{id = "techno.peak", name = "Peak", bars = 2, lanes = {
		{"kick", "X...X...X...X...|X...X...X...X.x."},
		{"clap", "....X.......X...", gain = 0.9, light = false},
		{"hat", "xoxoxoxoxoxoxoxo", gain = 0.3},
		{"openHat", "..x...x...x...x.", gain = 0.55, light = false},
		{"ride", "x.x.x.x.x.x.x.x.", gain = 0.3, when = "energy"},
		{"tomLow", "......x......x..", gain = 0.4, when = "complexity"},
	}},
	-- A rim every third 16th turns against the kick's four.
	{id = "techno.hypnotic", name = "Hypnotic", bars = 3, lanes = {
		{"kick", "X...X...X...X..."},
		{"rim", "..x..x..x..x..x.|.x..x..x..x..x..|x..x..x..x..x..x", gain = 0.4},
		{"openHat", "..x...x...x...x.", gain = 0.4, light = false},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.3, when = "energy"},
		{"conga", ".....x.....x....", gain = 0.4, when = "complexity"},
	}},
	{id = "techno.industrial", name = "Industrial", bars = 2, lanes = {
		{"kick", "X...X...X...X.x.|X...X...X..xX..."},
		{"snare", "....X.......X...", gain = 0.7, light = false},
		{"clap", "....x.......x...", gain = 0.6},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.4},
		{"openHat", "..x...x...x...x.", gain = 0.4, when = "energy"},
		{"tomLow", "......x......x..", gain = 0.5, when = "complexity"},
	}},
	{id = "techno.minimal", name = "Minimal", bars = 2, lanes = {
		{"kick", "X...X...X...X..."},
		{"hat", "..x...x...x...x.", gain = 0.45},
		{"rim", "....x.......x...", gain = 0.5, light = false},
		{"clave", "x..x..x...x.x...|x..x..x...x..x..", gain = 0.35, when = "complexity"},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.25, when = "energy"},
	}},
	{id = "techno.broken", name = "Broken", bars = 2, lanes = {
		{"kick", "X.....X..X..X...|X.....X..X....x."},
		{"clap", "....X.......X...", gain = 0.85, light = false},
		{"hat", "xoxoxoxoxoxoxoxo", gain = 0.3},
		{"openHat", "..x.......x.....", gain = 0.45, when = "energy"},
		{"rim", "...x.....x.....x", gain = 0.4, when = "complexity"},
	}},
	{id = "techno.soft", name = "Soft Four", bars = 2, lanes = {
		{"kick", "X...X...X...X...", gain = 0.9},
		{"hat", "..x...x...x...x.", gain = 0.35},
		{"rim", "............x...|....x.......x...", gain = 0.4, light = false},
		{"shaker", "x.xxx.xxx.xxx.xx", gain = 0.22, when = "energy"},
		{"snap", "....x.......x...", gain = 0.5, when = "complexity"},
	}},
	-- Percussion loops: what a minimal tune has where a melody would be.
	{id = "techno.congas", name = "Congas", bars = 2, lanes = {
		{"conga", "..x..x.x..x.x..x|..x..x.x.x..x.x."},
		{"tambourine", "..x...x...x...x.", gain = 0.5},
	}},
	{id = "techno.clave", name = "Claves", bars = 2, lanes = {
		{"clave", "x..x..x...x.x...|x..x...x..x.x..."},
		{"cowbell", "......x.......x.", gain = 0.5},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.4},
	}},
	{id = "techno.toms", name = "Toms", bars = 2, lanes = {
		{"tomLow", "...x..x......x..|...x..x...x..x.."},
		{"tomMid", ".........x......|.........x.....x", gain = 0.8},
		{"rim", "..x...x...x...x.", gain = 0.5},
	}},
}

local LINES = {
	{id = "techno.pulse", name = "Pulse", notes = "0:0:1 3:0:1? 6:0:1 8:0:1 11:0:1? 14:0:1"},
	{id = "techno.offbeat", name = "Offbeat", notes = "2:0:2 6:0:2 10:0:2 14:0:2"},
	{id = "techno.stomp", name = "Stomp", notes = "0:0:1 2:0:1 3:0:1? 6:7:1! 8:0:1 10:0:1 11:0:1? 14:6:1"},
	{id = "techno.minor", name = "Minor", notes = "2:0:1 3:0:1 6:0:1 7:2:1? 10:0:1 11:0:1 14:6:1 15:4:1+"},
	{id = "techno.dub", name = "Dub", notes = "0:0:6 10:0:2? 14:6:2 | 0:0:6 10:4:2? 13:2:3"},
	{id = "techno.hook", name = "Bass Hook", notes = "0:0:2 3:0:2 6:2:2 8:0:2 11:6:2! 14:4:2 | 0:0:2 3:0:2 6:2:2 8:3:2 11:2:2! 14:0:2"},
}

local FILLS = {"fill.flam", "fill.claps", "fill.kicks", "fill.rims", "@retrig", "@cut", "@reverse"}

local FLAVOURS = {
	{id = "peak", name = "Peak Time", tempo = {130, 136}, swing = {0, 0.04},
		channels = {
			{role = "drums", beats = {"techno.drive", "techno.peak", "techno.broken"}},
			{role = "bass", patches = {"bass.rumble", "bass.psy", "bass.moog"}, lines = {"@rumble", "techno.stomp", "techno.pulse"}},
			{role = "pad", patches = {"pad.dark", "pad.pwm", "pad.saw"}, chance = 0.7},
			{role = "stab", patches = {"stab.saw", "stab.fm", "stab.rave"}, chance = 0.5},
			{role = "arp", patches = {"pluck.acid", "pluck.saw", "pluck.chip"}, chance = 0.6},
			{role = "lead", patches = {"lead.square", "lead.fm", "lead.hoover"}, chance = 0.5,
				hooks = {"hook.morse", "hook.insist", "hook.dotted", "hook.riff", "@motif"}},
			{role = "texture", patches = {"texture.drone", "texture.air"}, chance = 0.5},
			{role = "fx", patches = {"fx.riser", "fx.siren"}},
		}},
	-- The 303 is the tune: it rides the whole track.
	{id = "acid", name = "Acid", tempo = {126, 134}, swing = {0, 0.08},
		channels = {
			{role = "drums", beats = {"techno.drive", "techno.broken", "techno.minimal"}},
			{role = "tops", beats = {"techno.clave", "techno.congas"}, gain = 0.6, chance = 0.5},
			{role = "bass", patches = {"bass.acid", "bass.acidSquare"}, lines = {"@acid"}},
			{role = "pad", patches = {"pad.dark", "pad.choir"}, chance = 0.4},
			{role = "stab", patches = {"stab.saw", "stab.organ"}, chance = 0.3},
			{role = "arp", patches = {"pluck.acid", "pluck.chip"}, chance = 0.3},
			{role = "texture", patches = {"texture.tape", "texture.drone"}, chance = 0.4},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		},
		plan = {build = {bass = {"bass.line", from = "half", filter = {kind = "lowpass", from = 0.2, to = 0.7}}},
			breakdown = {bass = {"bass.line", filter = {kind = "lowpass", from = 0.25, to = 0.8}}}}},
	{id = "hypnotic", name = "Hypnotic", tempo = {126, 132}, swing = {0, 0.06},
		channels = {
			{role = "drums", beats = {"techno.hypnotic", "techno.minimal", "techno.drive"}},
			{role = "tops", beats = {"techno.toms", "techno.clave"}, gain = 0.5, chance = 0.4},
			{role = "bass", patches = {"bass.rumble", "bass.sub", "bass.round"}, lines = {"@rumble", "line.root", "techno.offbeat"}},
			{role = "pad", patches = {"pad.dark", "pad.air", "pad.glass"}, chance = 0.8},
			{role = "stab", patches = {"stab.dub", "stab.organ"}, steps = {"...x..x...x...x.", "......x.......x.", "...x.........x.."}},
			{role = "arp", patches = {"pluck.bell", "pluck.glass", "pluck.marimba"}, chance = 0.8, arp = {rates = {2, 1}}},
			{role = "texture", patches = {"texture.air", "texture.drone", "texture.shimmer"}},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		}},
	{id = "industrial", name = "Industrial", tempo = {134, 140}, swing = {0, 0.03},
		snares = {"crunchy", "fat", "tight"},
		channels = {
			{role = "drums", beats = {"techno.industrial", "techno.peak", "techno.broken"}},
			{role = "bass", patches = {"bass.growl", "bass.hoover", "bass.rumble"}, lines = {"techno.stomp", "techno.minor", "@rumble"}},
			{role = "stab", patches = {"stab.fm", "stab.rave"}, chance = 0.8},
			{role = "lead", patches = {"lead.hoover", "lead.fm"}, chance = 0.4, hooks = {"hook.morse", "hook.insist", "@motif"}},
			{role = "texture", patches = {"texture.tape", "texture.drone"}},
			{role = "fx", patches = {"fx.siren", "fx.wind"}},
		}},
	-- Percussion where the tune would be.
	{id = "minimal", name = "Minimal", tempo = {124, 130}, swing = {0.04, 0.12},
		form = {openings = {"cold", "cold", "build"}, builds = {"sweep", "rise", "stomp"}},
		channels = {
			{role = "drums", beats = {"techno.minimal", "techno.soft", "techno.hypnotic"}},
			{role = "tops", beats = {"techno.congas", "techno.clave", "techno.toms"}, gain = 0.7},
			{role = "bass", patches = {"bass.sub", "bass.fm", "bass.donk", "bass.round"}, lines = {"techno.pulse", "techno.hook", "techno.offbeat", "@cell"}},
			{role = "stab", patches = {"stab.dub", "stab.pizzicato"}, chance = 0.5},
			{role = "counter", patches = {"pluck.marimba", "pluck.bell", "pluck.glass"}, chance = 0.7,
				hooks = {"hook.space", "hook.echo", "hook.call", "@motif"}},
			{role = "texture", patches = {"texture.air", "texture.tape"}, chance = 0.6},
			{role = "fx", patches = {"fx.wind"}, chance = 0.7},
		},
		plan = {drop = {counter = {"counter.answer", from = "phrase"}}, breakdown = {tops = "tops.loop", counter = "counter.answer"}}},
	{id = "melodic", name = "Melodic", tempo = {120, 126}, swing = {0, 0.06},
		harmony = {progressions = MELODIC, voicing = {0, 2, 4, 6}, barsPerChord = 2},
		form = {openings = {"melodic", "build", "build"}, links = {"breakdown build", "breakdown build", "build"}, breakdown = {1, 2}},
		channels = {
			{role = "drums", beats = {"techno.soft", "techno.drive", "techno.minimal"}},
			{role = "bass", patches = {"bass.pluck", "bass.moog", "bass.round"}, lines = {"@offbeat", "@cell", "techno.hook", "techno.dub"}},
			{role = "pad", patches = {"pad.strings", "pad.supersaw", "pad.warm", "pad.glass"}},
			{role = "arp", patches = {"pluck.trance", "pluck.bell", "pluck.saw"}, arp = {rates = {1, 2}}},
			{role = "lead", patches = {"lead.sine", "lead.saw", "lead.vox", "lead.flute"}, chance = 0.8,
				hooks = {"hook.anthem", "hook.lament", "hook.circle", "hook.leap", "hook.voice", "@motif"}},
			{role = "counter", patches = {"pluck.glass", "keys.vibes", "pluck.string"}, chance = 0.5},
			{role = "texture", patches = {"texture.shimmer", "texture.air"}, chance = 0.6},
			{role = "fx", patches = {"fx.riser", "fx.wind"}},
		},
		plan = {drop = {pad = "pad.chords"}}},
	-- Slow and washed out: one chord, thrown into the delay.
	{id = "dub", name = "Dub Techno", tempo = {118, 124}, swing = {0.04, 0.1},
		harmony = {progressions = {{1, 1, 1, 1}, {1, 1, 4, 4}, {1, 1, 6, 6}}, voicing = {0, 2, 4, 6}, change = 0.1},
		form = {openings = {"cold", "melodic"}, builds = {"sweep", "rise"}, links = {"breakdown", "build", "double"}},
		channels = {
			{role = "drums", beats = {"techno.soft", "techno.minimal"}},
			{role = "bass", patches = {"bass.sub", "bass.round"}, lines = {"techno.dub", "line.root", "line.push"}},
			{role = "pad", patches = {"pad.dark", "pad.air", "pad.warm"}},
			{role = "stab", patches = {"stab.dub"}, steps = {"...x......x.....", "......x.........", "..x......x......"}},
			{role = "texture", patches = {"texture.tape", "texture.air"}},
			{role = "fx", patches = {"fx.wind"}},
		},
		plan = {intro = {stab = {"stab.hits", from = "half"}}, breakdown = {stab = "stab.hits"},
			drop = {pad = "pad.chords"}, outro = {stab = "stab.hits"}}},
}

return {
	api = 3,
	title = "Techno",
	symbol = "metronome.fill",
	summary = "Peak Time, Acid, Hypnotic and more, four to the floor",
	defaults = {energy = 0.7, complexity = 0.5, humanize = 0.15, space = 0.4},
	kit = {
		kick = {base = 50, sweep = 170, sweepTime = 0.018, decay = 0.3, drive = 2.6, click = 0.5, length = 0.55},
		hat = {scale = 1.9, decay = 0.012, openDecay = 0.07},
	},
	mix = {duckDepth = 0.55, drums = 0.8, bass = 0.75, stab = 1.15, delayFeedback = 0.5},
	set = {form = {openings = {"cold", "cold", "build"}, builds = {"stomp", "sweep", "rise", "roll"},
			links = {"build", "build", "double", "breakdown build", "breakdown"}},
		modes = {"minor", "phrygian"}, modulations = {0, 5, -2},
		arrangement = {introBars = 16, buildBars = 8, dropBars = 32, breakdownBars = 16, rebuildBars = 8,
			outroBars = 16, blendBars = 8, minCycles = 2, maxCycles = 3}},
	harmony = {progressions = PROGRESSIONS, voicing = {0, 2, 4}, barsPerChord = 4},
	roles = {drums = {fills = FILLS, roll = "clap"}},
	plan = {
		drop = {pad = {"pad.chords", from = 16}, arp = {"arp.run", from = 8}},
		breakdown = {bass = {"bass.hold", from = 8}, keys = false, stab = "stab.hits", lead = false},
	},
	flavours = FLAVOURS,
	library = {beats = BEATS, lines = LINES},
}
