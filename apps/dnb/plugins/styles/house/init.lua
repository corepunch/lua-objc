-- House: four to the floor from 118 to 128 BPM. A round kick with a deep
-- sidechain pump, claps on two and four, open hats on the off-beats;
-- seventh and ninth chords comped over an off-beat bass. Its flavours: Deep
-- on an electric piano, Classic, Disco on octave bass and strings, Piano
-- house, Organ house, Tribal on a percussion loop, Acid, and French house
-- opening its loops through a filter.

-- Dorian, minor and major loops of four chords, a bar each.
local PROGRESSIONS = {{1, 4, 1, 4}, {2, 5, 1, 1}, {1, 6, 4, 5}, {1, 7, 4, 4}, {6, 4, 1, 5}, {2, 4, 5, 5},
	{1, 3, 4, 4}, {4, 5, 6, 6}, {1, 1, 4, 5}}
-- Where house chords are struck: the comping rhythms of its pianists.
local COMPS = {"x..x..x...x.....", "..x...x...x...x.", "x......x..x.....", "...x..x....x..x.", "x.....x.x.....x.",
	"x..x....x..x....", "..x..x....x..x..", "x..x..x...x.x...", "x.x..x....x.....", "..x.x...x.x....."}

local BEATS = {
	{id = "house.four", name = "Four", lanes = {
		{"kick", "X...X...X...X..."},
		{"clap", "....X.......X...", gain = 0.85, light = false},
		{"openHat", "..x...x...x...x.", gain = 0.45},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.4, when = "energy"},
		{"ride", "x.o.x.o.x.o.x.o.", gain = 0.35, light = false},
		{"conga", ".......x..x....x", gain = 0.45, when = "complexity"},
	}},
	{id = "house.jack", name = "Jack", bars = 2, lanes = {
		{"kick", "X...X...X...X...|X...X...X...X..x"},
		{"clap", "....X.......X...", gain = 0.85, light = false},
		{"hat", "x.xxx.xxx.xxx.xx", gain = 0.3},
		{"openHat", "..x...x...x...x.", gain = 0.45, light = false},
		{"ghost", ".......g.....g..", when = "complexity"},
		{"cowbell", "......x.....x...", gain = 0.35, when = "energy"},
	}},
	{id = "house.deep", name = "Deep", bars = 2, lanes = {
		{"kick", "X...X...X...X...", gain = 0.95},
		{"snap", "....x.......x...", gain = 0.7, light = false},
		{"rim", "............x...|.......x....x...", gain = 0.4},
		{"hat", "..x...x...x...x.", gain = 0.5},
		{"shaker", "x.xxx.xxx.xxx.xx", gain = 0.28, when = "energy"},
		{"conga", "...x......x.....", gain = 0.4, when = "complexity"},
	}},
	{id = "house.disco", name = "Disco", bars = 2, lanes = {
		{"kick", "X...X...X...X..."},
		{"clap", "....X.......X...", gain = 0.85, light = false},
		{"openHat", "..x...x...x...x.", gain = 0.55},
		{"hat", "xo.oxo.oxo.oxo.o", gain = 0.3, light = false},
		{"tambourine", "x.x.x.x.x.x.x.x.", gain = 0.4, when = "energy"},
		{"cowbell", "x..x..x...x.x...|x..x..x...x..x..", gain = 0.3, when = "complexity"},
	}},
	{id = "house.tribal", name = "Tribal", bars = 2, lanes = {
		{"kick", "X...X...X...X..."},
		{"clap", "....x.......x...", gain = 0.7, light = false},
		{"conga", "..x..x.x..x..x.x|..x..x.x.x..x.x.", gain = 0.55},
		{"tomLow", "......x.......x.", gain = 0.45, light = false},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.35, when = "energy"},
		{"clave", "x..x..x...x.x...", gain = 0.3, when = "complexity"},
	}},
	{id = "house.chicago", name = "Chicago", bars = 2, lanes = {
		{"kick", "X...X...X...X...|X...X...X.x.X..."},
		{"clap", "....X.......X...", gain = 0.9, light = false},
		{"hat", "x.xxx.xxx.xxx.xx", gain = 0.32},
		{"openHat", "..x...x...x...x.", gain = 0.4, when = "energy"},
		{"tomMid", ".............x.x", gain = 0.4, when = "complexity"},
	}},
	-- Percussion loops for the tops channel.
	{id = "house.bongos", name = "Bongos", bars = 2, lanes = {
		{"conga", "x.xo.xo.x.xo.xo.|x.xo.xo.xoxo.xo."},
		{"shaker", "..x...x...x...x.", gain = 0.5},
	}},
	{id = "house.shakers", name = "Shakers", bars = 2, lanes = {
		{"shaker", "XoxoXoxoXoxoXoxo"},
		{"tambourine", "....x.......x...", gain = 0.6},
		{"cowbell", "..........x.....|......x.....x...", gain = 0.4},
	}},
}

local LINES = {
	-- The off-beat organ bass.
	{id = "house.offbeat", name = "Offbeat", notes = "2:0:1.5 6:0:1.5 10:0:1.5 14:0:1.5"},
	{id = "house.synco", name = "Syncopated", notes = "0:0:1.5 3:0:1.5? 6:7:1.5 10:0:1.5 14:4:1.5?"},
	{id = "house.octaves", name = "Disco Octaves", notes = "2:0:1 3:7:1 6:0:1 7:7:1 10:0:1 11:7:1 14:0:1 15:7:1"},
	{id = "house.walk", name = "Walk", notes = "0:0:2 3:0:1 6:2:2 8:4:2 11:4:1? 14:6:2 | 0:0:2 3:0:1 6:2:2 8:3:2 11:2:1? 14:1:2"},
	{id = "house.garage", name = "Garage", notes = "0:0:3 4:0:1? 7:7:2 10:6:2 13:4:2"},
	{id = "house.bump", name = "Bump", notes = "0:0:2 3:0:2 6:0:2? 8:6:2 11:4:2 14:2:2+ | 0:0:2 3:0:2 6:0:2? 8:7:2 11:6:2 14:4:2+"},
	{id = "house.low", name = "Low", notes = "0:0:6 7:0:1? 10:6:2 12:4:3"},
}

local FILLS = {"fill.claps", "fill.snares", "fill.congas", "fill.kicks", "@cut", "@retrig", "@reverse"}

local FLAVOURS = {
	{id = "deep", name = "Deep House", tempo = {118, 123}, swing = {0.06, 0.14},
		channels = {
			{role = "drums", beats = {"house.deep", "house.four"}},
			{role = "tops", beats = {"house.shakers", "house.bongos"}, gain = 0.5, chance = 0.5},
			{role = "bass", patches = {"bass.round", "bass.sub", "bass.fm", "bass.organ"}, lines = {"house.low", "house.offbeat", "house.bump", "@cell"}},
			{role = "pad", patches = {"pad.warm", "pad.glass", "pad.air"}, chance = 0.8},
			{role = "keys", patches = {"keys.rhodes", "keys.wurli", "keys.vibes"}},
			{role = "arp", patches = {"pluck.bell", "pluck.marimba", "pluck.glass"}, chance = 0.3, arp = {rates = {2}}},
			{role = "lead", patches = {"lead.sine", "lead.flute", "lead.vox"}, chance = 0.4,
				hooks = {"hook.voice", "hook.space", "hook.sigh", "hook.question", "@motif"}},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		}},
	{id = "classic", name = "Classic House", tempo = {122, 126}, swing = {0.04, 0.12},
		channels = {
			{role = "drums", beats = {"house.four", "house.jack", "house.chicago"}},
			{role = "bass", patches = {"bass.organ", "bass.fm", "bass.moog"}, lines = {"house.offbeat", "house.synco", "house.bump"}},
			{role = "pad", patches = {"pad.saw", "pad.strings", "pad.organ"}, chance = 0.7},
			{role = "keys", patches = {"keys.piano", "keys.organ", "keys.rhodes"}, chance = 0.7},
			{role = "stab", patches = {"stab.organ", "stab.saw", "stab.brass"}, steps = {"...x..x....x....", "..x...x...x.....", "...x..x...x..x.."}},
			{role = "arp", patches = {"pluck.saw", "pluck.chip", "pluck.bell"}, chance = 0.5, arp = {rates = {2}}},
			{role = "lead", patches = {"lead.saw", "lead.square", "lead.fm"}, chance = 0.6,
				hooks = {"hook.jack", "hook.riff", "hook.call", "hook.bounce", "@motif"}},
			{role = "fx", patches = {"fx.riser", "fx.siren"}},
		}},
	{id = "disco", name = "Disco House", tempo = {122, 127}, swing = {0.02, 0.08},
		channels = {
			{role = "drums", beats = {"house.disco", "house.four"}},
			{role = "tops", beats = {"house.shakers", "house.bongos"}, gain = 0.5, chance = 0.4},
			{role = "bass", patches = {"bass.moog", "bass.fm", "bass.pluck"}, lines = {"house.octaves", "house.walk", "house.synco"}},
			{role = "pad", patches = {"pad.strings", "pad.supersaw"}},
			{role = "keys", patches = {"keys.clav", "keys.piano", "keys.rhodes"}, chance = 0.6},
			{role = "stab", patches = {"stab.brass", "stab.pizzicato", "stab.saw"}, chance = 0.8},
			{role = "arp", patches = {"pluck.saw", "pluck.string"}, chance = 0.6, arp = {rates = {2, 1}}},
			{role = "fx", patches = {"fx.riser"}},
		},
		plan = {drop = {pad = "pad.chords"}}},
	-- The piano is the hook: bright chords, struck hard.
	{id = "piano", name = "Piano House", tempo = {122, 128}, swing = {0.02, 0.1},
		harmony = {progressions = {{1, 6, 4, 5}, {6, 4, 1, 5}, {1, 4, 6, 5}, {4, 5, 6, 6}, {1, 3, 4, 4}}},
		channels = {
			{role = "drums", beats = {"house.four", "house.jack"}},
			{role = "bass", patches = {"bass.organ", "bass.fm", "bass.round"}, lines = {"house.offbeat", "house.garage", "house.synco"}},
			{role = "pad", patches = {"pad.strings", "pad.warm"}, chance = 0.6},
			{role = "keys", patches = {"keys.piano"}, comp = {length = 2}},
			{role = "stab", patches = {"stab.piano", "stab.organ"}, chance = 0.4},
			{role = "lead", patches = {"lead.vox", "lead.sine", "lead.saw"}, chance = 0.5,
				hooks = {"hook.call", "hook.question", "hook.anthem", "hook.leap"}},
			{role = "fx", patches = {"fx.riser", "fx.wind"}},
		},
		plan = {intro = {keys = {"keys.comp", from = "half"}}, build = {keys = "keys.comp"},
			drop = {keys = "keys.comp"}}},
	{id = "organ", name = "Organ House", tempo = {124, 128}, swing = {0.08, 0.16},
		channels = {
			{role = "drums", beats = {"house.jack", "house.chicago", "house.four"}},
			{role = "bass", patches = {"bass.organ", "bass.donk", "bass.fm"}, lines = {"house.garage", "house.bump", "house.synco"}},
			{role = "keys", patches = {"keys.organ"}},
			{role = "stab", patches = {"stab.organ"}, steps = {"..x...x...x...x.", "...x..x....x..x."}},
			{role = "lead", patches = {"lead.square", "lead.fm"}, chance = 0.4, hooks = {"hook.jack", "hook.skank", "hook.bounce"}},
			{role = "fx", patches = {"fx.riser"}},
		}},
	{id = "tribal", name = "Tribal House", tempo = {124, 128}, swing = {0.04, 0.1},
		harmony = {progressions = {{1, 1, 1, 1}, {1, 1, 4, 4}, {1, 7, 1, 7}}, change = 0.2},
		channels = {
			{role = "drums", beats = {"house.tribal", "house.four"}},
			{role = "tops", beats = {"house.bongos", "break.bongo", "house.shakers"}, gain = 0.7},
			{role = "bass", patches = {"bass.sub", "bass.round", "bass.donk"}, lines = {"house.low", "@cell", "line.tresillo"}},
			{role = "stab", patches = {"stab.dub", "stab.pizzicato", "stab.organ"}, chance = 0.6},
			{role = "counter", patches = {"pluck.marimba", "pluck.string", "lead.flute"}, chance = 0.7,
				hooks = {"hook.tresillo", "hook.call", "hook.space", "@motif"}},
			{role = "texture", patches = {"texture.air", "texture.drone"}, chance = 0.6},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		},
		plan = {intro = {tops = {"tops.loop", from = "half"}}, breakdown = {tops = "tops.loop", counter = "counter.answer"},
			drop = {counter = {"counter.answer", from = "phrase"}}}},
	{id = "acid", name = "Acid House", tempo = {120, 126}, swing = {0.02, 0.1},
		harmony = {progressions = {{1, 1, 1, 1}, {1, 1, 4, 4}, {1, 7, 1, 7}}, change = 0.2, barsPerChord = 2},
		channels = {
			{role = "drums", beats = {"house.chicago", "house.jack"}},
			{role = "bass", patches = {"bass.acid", "bass.acidSquare"}, lines = {"@acid"}, octave = 0},
			{role = "pad", patches = {"pad.choir", "pad.dark"}, chance = 0.5},
			{role = "stab", patches = {"stab.organ", "stab.piano"}, chance = 0.5},
			{role = "texture", patches = {"texture.tape"}, chance = 0.4},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		},
		plan = {build = {bass = {"bass.line", from = "half", filter = {kind = "lowpass", from = 0.2, to = 0.7}}},
			breakdown = {bass = {"bass.line", filter = {kind = "lowpass", from = 0.25, to = 0.8}}}}},
	-- A disco loop heard through a filter that opens and closes.
	{id = "french", name = "French House", tempo = {122, 126}, swing = {0.02, 0.08},
		harmony = {progressions = {{1, 4, 1, 4}, {2, 5, 1, 1}, {1, 6, 4, 5}, {4, 5, 6, 6}}, change = 0.1},
		form = {openings = {"cold", "build"}, builds = {"sweep", "sweep", "rise"}, links = {"breakdown", "build", "breakdown build"}},
		channels = {
			{role = "drums", beats = {"house.disco", "house.four"}},
			{role = "bass", patches = {"bass.moog", "bass.pluck"}, lines = {"house.octaves", "house.walk", "house.bump"}},
			{role = "pad", patches = {"pad.strings", "pad.supersaw"}},
			{role = "stab", patches = {"stab.brass", "stab.saw"}, steps = {"x..x..x...x.....", "..x..x....x..x.."}},
			{role = "keys", patches = {"keys.clav", "keys.rhodes"}, chance = 0.5},
			{role = "fx", patches = {"fx.riser"}},
		},
		plan = {intro = {pad = {"pad.chords", filter = {kind = "lowpass", from = 0.15, to = 0.6}},
				stab = {"stab.hits", filter = {kind = "lowpass", from = 0.15, to = 0.6}}},
			drop = {pad = "pad.chords"},
			breakdown = {stab = {"stab.hits", filter = {kind = "lowpass", from = 0.8, to = 0.2}}}}},
}

return {
	api = 3,
	title = "House",
	symbol = "house.fill",
	summary = "Deep, Classic, Disco, Piano and more, four to the floor",
	defaults = {energy = 0.6, complexity = 0.5, humanize = 0.3, space = 0.45},
	kit = {
		kick = {base = 52, sweep = 110, sweepTime = 0.02, decay = 0.22, drive = 1.8, click = 0.3, length = 0.4},
		clap = {decay = 0.18, level = 1},
		hat = {scale = 1.7, decay = 0.02, openDecay = 0.1},
	},
	mix = {duckDepth = 0.65, duckRelease = 0.16, bass = 0.75, keys = 1.25},
	set = {form = {openings = {"build", "cold", "melodic"}, builds = {"sweep", "sweep", "roll", "rise"}},
		modes = {"dorian", "minor", "major"}, modulations = {0, 2, 5},
		arrangement = {introBars = 16, buildBars = 8, dropBars = 32, breakdownBars = 16, rebuildBars = 8,
			outroBars = 16, blendBars = 8, minCycles = 2, maxCycles = 3}},
	harmony = {progressions = PROGRESSIONS, voicing = {0, 2, 4, 6}, barsPerChord = 1, cells = COMPS},
	roles = {drums = {fills = FILLS, roll = "clap"}, bass = {octave = 1}},
	plan = {
		intro = {pad = {"pad.chords", from = "blend"}},
		drop = {pad = {"pad.chords", from = 16}, keys = "keys.comp", arp = {"arp.run", from = 8}},
		breakdown = {lead = {"lead.soft", from = 8}},
		outro = {bass = {"bass.line", to = 8}},
	},
	flavours = FLAVOURS,
	library = {beats = BEATS, lines = LINES},
}
