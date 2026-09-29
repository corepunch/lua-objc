-- UK Garage: 128 to 140 BPM, swung hard. The skippy two-step kick that
-- leaves beats two and four to the snare, shuffled hats, rim shots and
-- minor-ninth chords over a bouncing bass. Its flavours: 2-Step, Speed
-- Garage on four kicks and a reese, Future Garage washed out under a
-- pitched lead, Bassline on a donk, and Dark Garage, all sub and squares.

local PROGRESSIONS = {{1, 4, 1, 4}, {1, 6, 4, 5}, {4, 5, 1, 1}, {1, 7, 6, 4}, {2, 5, 1, 6}, {1, 3, 4, 4}, {6, 4, 1, 5}}
local DARK = {{1, 1, 1, 1}, {1, 1, 6, 7}, {1, 2, 1, 7}, {1, 7, 1, 7}}
local COMPS = {"x.....x...x.....", "...x..x.......x.", "x..x......x..x..", "..x..x....x.....", "x......x..x.....",
	"x..x..x...x.....", "..x...x..x....x.", "x....x..x.x.....", "x.x...x......x..", "...x...x..x..x.."}

local BEATS = {
	{id = "garage.twostep", name = "2-Step", bars = 2, lanes = {
		{"kick", "X.........x.....|X.........x..x.."},
		{"snare", "....X.......X...", gain = 0.9},
		{"clap", "....x.......x...", gain = 0.6, light = false},
		{"hat", ".x.x.x.x.x.x.x.x", gain = 0.4},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.25, when = "energy"},
		{"openHat", "..............x.", gain = 0.45, light = false},
		{"rim", ".......x.......x|.......x.x.....x", gain = 0.4, light = false},
		{"shaker", "..x...x...x...x.", gain = 0.35, when = "complexity"},
	}},
	{id = "garage.skippy", name = "Skippy", bars = 2, lanes = {
		{"kick", "X......x..x.....|X.x.......x....."},
		{"snare", "....X.......X...", gain = 0.9},
		{"clap", "....x.......x...", gain = 0.5, light = false},
		{"hat", ".x.x.x.x.x.x.x.x", gain = 0.4},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.22, when = "energy"},
		{"openHat", "......x.......x.", gain = 0.4, light = false},
		{"rim", "...x.....x.....x", gain = 0.4, when = "complexity"},
	}},
	{id = "garage.four", name = "4x4", bars = 2, lanes = {
		{"kick", "X...X...X...X..."},
		{"clap", "....X.......X...", gain = 0.85, light = false},
		{"snare", "....x.......x...", gain = 0.5},
		{"hat", ".x.x.x.x.x.x.x.x", gain = 0.4},
		{"openHat", "..x...x...x...x.", gain = 0.5},
		{"rim", ".......x.......x|.......x.....x.x", gain = 0.35, when = "complexity"},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.25, when = "energy"},
	}},
	{id = "garage.future", name = "Future", bars = 2, lanes = {
		{"kick", "X......x..x.....|X.........x....."},
		{"rim", "....x...........|....x.......x...", gain = 0.6},
		{"snare", "............X...", gain = 0.8},
		{"snap", "....x.......x...", gain = 0.5, light = false},
		{"hat", ".x...x.x.x...x.x", gain = 0.35},
		{"shaker", "..x...x...x...x.", gain = 0.3, when = "energy"},
		{"ghost", ".........g.....g", when = "complexity"},
	}},
	{id = "garage.dark", name = "Dark", bars = 2, lanes = {
		{"kick", "X.....x...x.....|X.........x.x..."},
		{"snare", "....X.......X...", gain = 0.9},
		{"hat", "x.xxx.xxx.xxx.xx", gain = 0.3},
		{"openHat", "..x.......x.....", gain = 0.35, when = "energy"},
		{"rim", ".......x.....x..", gain = 0.4, when = "complexity"},
	}},
}

local LINES = {
	{id = "garage.bounce", name = "Bounce", notes = "0:0:3 3:0:1 6:7:2~ 10:0:2? 13:4:3~"},
	{id = "garage.skip", name = "Skip", notes = "0:0:2 2:7:2~ 7:0:2? 10:2:4~"},
	{id = "garage.roll", name = "Roll", notes = "0:0:4 6:0:1 7:7:2~ 11:6:1? 12:4:4~"},
	{id = "garage.donk", name = "Donk", notes = "2:0:1 3:0:1? 6:0:1 7:7:1! 10:0:1 11:0:1? 14:6:1 15:7:1!"},
	{id = "garage.wob", name = "Warp", notes = "0:0:6w2 6:0:2w4 8:7:4w3~ 12:0:4w2? | 0:0:6w2 6:0:2w4 8:6:4w3~ 12:4:4w2?"},
	{id = "garage.low", name = "Low", notes = "0:0:6 7:0:1? 10:0:2 13:6:3~ | 0:0:6 7:0:1? 10:2:2 13:0:3"},
}

local FILLS = {"fill.snares", "fill.rims", "fill.claps", "fill.stutter", "@stutter", "@cut", "@reverse"}

local FLAVOURS = {
	{id = "twostep", name = "2-Step", tempo = {130, 136}, swing = {0.24, 0.34},
		snares = {"rimshot", "tight", "layered", "vintage"},
		channels = {
			{role = "drums", beats = {"garage.twostep", "garage.skippy"}},
			{role = "bass", patches = {"bass.fm", "bass.round", "bass.reese", "bass.organ"}, lines = {"garage.bounce", "garage.skip", "garage.roll", "@cell"}},
			{role = "pad", patches = {"pad.warm", "pad.strings", "pad.glass"}, chance = 0.6},
			{role = "keys", patches = {"keys.wurli", "keys.rhodes", "keys.organ", "keys.vibes"}},
			{role = "stab", patches = {"stab.organ", "stab.pizzicato", "stab.piano"}, chance = 0.5, steps = {"......x.........", "...x..x.......x."}},
			{role = "arp", patches = {"pluck.bell", "pluck.string", "pluck.marimba"}, chance = 0.4, arp = {rates = {2}}},
			{role = "lead", patches = {"lead.vox", "lead.sine", "lead.square"}, chance = 0.6,
				hooks = {"hook.call", "hook.question", "hook.bounce", "hook.voice", "@motif"}},
			{role = "fx", patches = {"fx.riser", "fx.wind"}},
		}},
	{id = "speed", name = "Speed Garage", tempo = {130, 136}, swing = {0.16, 0.26},
		snares = {"tight", "rimshot", "crunchy", "layered"},
		channels = {
			{role = "drums", beats = {"garage.four", "garage.twostep"}},
			{role = "bass", patches = {"bass.reese", "bass.reeseWide", "bass.wobble", "bass.hoover"}, lines = {"garage.wob", "garage.roll", "garage.bounce"}},
			{role = "pad", patches = {"pad.saw", "pad.dark"}, chance = 0.5},
			{role = "keys", patches = {"keys.organ", "keys.piano"}, chance = 0.4},
			{role = "stab", patches = {"stab.organ", "stab.rave", "stab.brass"}, steps = {"......x.........", "..x...x...x....."}},
			{role = "lead", patches = {"lead.hoover", "lead.square", "lead.vox"}, chance = 0.4,
				hooks = {"hook.jack", "hook.insist", "hook.skank", "@motif"}},
			{role = "texture", patches = {"texture.tape"}, chance = 0.4},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	-- Keeps its pads under the whole track.
	{id = "future", name = "Future Garage", tempo = {128, 134}, swing = {0.2, 0.3},
		snares = {"roomy", "vintage", "rimshot", "layered"},
		form = {openings = {"melodic", "cold"}, builds = {"rise", "sweep"}, intro = {1, 2}},
		channels = {
			{role = "drums", beats = {"garage.future", "garage.skippy"}, gain = 0.9},
			{role = "bass", patches = {"bass.sub", "bass.round", "bass.808"}, lines = {"garage.low", "garage.skip", "line.push"}},
			{role = "pad", patches = {"pad.air", "pad.glass", "pad.choir", "pad.warm"}},
			{role = "keys", patches = {"keys.vibes", "keys.rhodes", "keys.harp"}, chance = 0.7},
			{role = "arp", patches = {"pluck.glass", "pluck.string"}, chance = 0.4, arp = {rates = {2, 4}}},
			{role = "lead", patches = {"lead.vox", "lead.sine", "lead.pluck"}, hooks = {"hook.voice", "hook.sigh", "hook.space", "hook.lullaby", "@motif"}},
			{role = "texture", patches = {"texture.tape", "texture.shimmer", "texture.air"}},
			{role = "fx", patches = {"fx.wind"}},
		},
		plan = {intro = {pad = "pad.chords"}, build = {pad = "pad.chords"}, drop = {pad = "pad.chords"},
			breakdown = {pad = "pad.chords", lead = "lead.soft"}, outro = {pad = "pad.chords"}}},
	{id = "bassline", name = "Bassline", tempo = {134, 140}, swing = {0.1, 0.2},
		snares = {"tight", "layered", "crunchy"},
		harmony = {progressions = {{1, 1, 4, 4}, {1, 7, 6, 7}, {1, 4, 1, 5}, {1, 1, 6, 7}}, voicing = {0, 2, 4, 6}},
		channels = {
			{role = "drums", beats = {"garage.four"}},
			{role = "bass", patches = {"bass.donk", "bass.organ", "bass.yoi", "bass.fm"}, lines = {"garage.donk", "garage.wob", "garage.roll"}},
			{role = "keys", patches = {"keys.organ", "keys.piano"}, chance = 0.5},
			{role = "stab", patches = {"stab.organ", "stab.brass", "stab.rave"}, steps = {"..x...x...x...x.", "......x.......x."}},
			{role = "lead", patches = {"lead.square", "lead.vox", "lead.hoover"}, chance = 0.6,
				hooks = {"hook.jack", "hook.bounce", "hook.octaves", "hook.skank", "@motif"}},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	{id = "dark", name = "Dark Garage", tempo = {134, 140}, swing = {0.14, 0.24},
		snares = {"tight", "crunchy", "rimshot"},
		harmony = {progressions = DARK, voicing = {0, 2, 4, 6}, change = 0.2},
		form = {openings = {"cold", "build"}, links = {"build", "breakdown", "double", "breakdown build"}},
		channels = {
			{role = "drums", beats = {"garage.dark", "garage.skippy"}},
			{role = "bass", patches = {"bass.sub", "bass.808", "bass.growl", "bass.reeseWide"}, lines = {"garage.low", "garage.wob", "@cell"}},
			{role = "pad", patches = {"pad.dark", "pad.choir"}, chance = 0.6},
			{role = "stab", patches = {"stab.fm", "stab.dub", "stab.brass"}, chance = 0.7},
			{role = "lead", patches = {"lead.square", "lead.fm"}, chance = 0.6, hooks = {"hook.morse", "hook.insist", "hook.dotted", "@motif"}},
			{role = "texture", patches = {"texture.drone", "texture.tape"}, chance = 0.7},
			{role = "fx", patches = {"fx.siren", "fx.wind"}},
		}},
}

return {
	api = 3,
	title = "UK Garage",
	symbol = "figure.dance",
	summary = "2-Step, Speed Garage, Future Garage and more, shuffled",
	defaults = {energy = 0.6, complexity = 0.55, humanize = 0.35, space = 0.45},
	kit = {
		kick = {base = 50, sweep = 100, sweepTime = 0.02, decay = 0.2, drive = 1.8, click = 0.3, length = 0.38},
		snare = {tone = 220, overtone = 360, bodyDecay = 0.045, noiseDecay = 0.08, noise = 0.45},
		hat = {scale = 1.8, decay = 0.014, openDecay = 0.08},
	},
	mix = {duckDepth = 0.4, keys = 1.2},
	set = {form = {openings = {"cold", "build", "melodic"}, builds = {"sweep", "rise", "roll"}},
		modes = {"minor", "dorian"}, modulations = {0, 5},
		arrangement = {introBars = 8, buildBars = 8, dropBars = 32, breakdownBars = 16, rebuildBars = 8,
			outroBars = 16, blendBars = 8, minCycles = 2, maxCycles = 3}},
	harmony = {progressions = PROGRESSIONS, voicing = {0, 2, 4, 6, 8}, barsPerChord = 2, cells = COMPS},
	roles = {drums = {fills = FILLS}},
	plan = {
		intro = {pad = false},
		drop = {keys = "keys.comp", pad = {"pad.chords", from = 16}},
		breakdown = {lead = "lead.soft"},
		outro = {bass = {"bass.line", to = 8}},
	},
	flavours = FLAVOURS,
	library = {beats = BEATS, lines = LINES},
}
