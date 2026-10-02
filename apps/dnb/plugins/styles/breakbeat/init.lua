-- Breakbeat: 120 to 140 BPM. Syncopated funk-break drums with ghost
-- snares, a record's break under the programmed kit, tom fills and a
-- slapping bassline. Its flavours: Big Beat, Nu Skool on an acid line,
-- Florida Breaks, Funky breaks on a clavinet, Progressive breaks, Electro
-- on an 808 and a cowbell, and Rave with its hoover and piano. One canvas
-- (see `arc`): no risers or snare rolls, the break thins and chops rather
-- than leaving, and the second peak returns the full groove.

local PROGRESSIONS = {{1, 1, 4, 1}, {1, 7, 6, 7}, {1, 4, 1, 5}, {1, 3, 4, 4}, {1, 1, 7, 7}, {1, 6, 4, 5}}
local MELODIC = {{1, 6, 3, 7}, {1, 4, 6, 5}, {6, 7, 1, 1}, {6, 4, 1, 5}}

local FILLS = {"fill.toms", "fill.tomsDown", "fill.stutter", "fill.snares", "fill.triplets", "@stutter", "@reverse", "@cut", "@tape"}

local FLAVOURS = {
	{id = "bigbeat", name = "Big Beat", tempo = {120, 132}, swing = {0.04, 0.12},
		-- Heavy, straight and loud: the break barely rests, the peaks are long.
		arc = {impact = 0.3, valley = 0.25, kickOut = 0.3, kickOutBars = {2, 4}, halftime = 0.1, fill = 0.7, lift = 0,
			curve = {{0, 0.3}, {0.1, 0.5}, {0.22, 0.8}, {0.32, 0.95}, {0.5, 0.75}, {0.55, 0.45}, {0.66, 0.95}, {0.85, 0.8}, {0.93, 0.5}, {1, 0.25}}},
		channels = {
			{role = "drums", wants = {"driving", "aggressive", "straight"}},
			{role = "tops", gain = 0.8, chops = true, wants = {"break", "driving"}},
			{role = "bass", patches = {"bass.moog", "bass.hoover", "bass.acid"}, wants = {"riff", "driving"}},
			{role = "stab", patches = {"stab.brass", "stab.rave", "stab.saw"}, wants = {"stab", "aggressive"}},
			{role = "keys", patches = {"keys.clav", "keys.organ"}, chance = 0.4},
			{role = "lead", patches = {"lead.hoover", "lead.saw", "lead.square"}, chance = 0.7, wants = {"riff", "hook", "aggressive"}},
			{role = "texture", patches = {"texture.tape"}, chance = 0.4},
			{role = "fx", patches = {"fx.siren"}, chance = 0.5},
		}},
	{id = "nuskool", name = "Nu Skool", tempo = {130, 138}, swing = {0.02, 0.1},
		-- Tight and dark: sharp kick-out moves, a short low valley.
		arc = {impact = 0.2, valley = 0.2, kickOut = 0.5, kickOutBars = {1, 2, 4}, halftime = 0.2, fill = 0.7,
			curve = {{0, 0.25}, {0.1, 0.45}, {0.2, 0.7}, {0.3, 0.9}, {0.5, 0.7}, {0.56, 0.35}, {0.65, 0.95}, {0.84, 0.8}, {0.93, 0.45}, {1, 0.2}}},
		channels = {
			{role = "drums", wants = {"syncopated", "driving"}},
			{role = "tops", gain = 0.4, chops = true, chance = 0.6, wants = {"break", "busy"}},
			{role = "bass", patches = {"bass.acid", "bass.acidSquare", "bass.growl", "bass.reeseWide"}, wants = {"acid", "rolling", "riff"}},
			{role = "pad", patches = {"pad.dark", "pad.pwm"}, chance = 0.6, wants = {"dark", "held"}},
			{role = "stab", patches = {"stab.fm", "stab.saw"}, chance = 0.6, wants = {"tense", "stab"}},
			{role = "arp", patches = {"pluck.acid", "pluck.chip"}, chance = 0.5, wants = {"tense", "driving"}},
			{role = "lead", patches = {"lead.fm", "lead.square"}, chance = 0.6, wants = {"riff", "tense", "rhythmic"}},
			{role = "fx", patches = {"fx.siren"}, chance = 0.4},
		}},
	{id = "florida", name = "Florida Breaks", tempo = {130, 140}, swing = {0.04, 0.1},
		-- Bright and bouncy: a vocal-style tune, a clear but short valley.
		arc = {impact = 0.2, valley = 0.25, kickOut = 0.35, kickOutBars = {2, 4}, halftime = 0.15, lift = 0.15,
			curve = {{0, 0.3}, {0.12, 0.5}, {0.25, 0.75}, {0.32, 0.9}, {0.5, 0.65}, {0.56, 0.4}, {0.66, 0.95}, {0.84, 0.75}, {0.93, 0.45}, {1, 0.25}}},
		channels = {
			{role = "drums", wants = {"electro", "syncopated", "playful"}},
			{role = "tops", gain = 0.35, chops = true, chance = 0.4, wants = {"playful", "break"}},
			{role = "bass", patches = {"bass.donk", "bass.fm", "bass.808", "bass.acid"}, wants = {"octave", "pluck", "playful"}},
			{role = "pad", patches = {"pad.saw", "pad.strings"}, chance = 0.6, wants = {"euphoric"}},
			{role = "stab", patches = {"stab.organ", "stab.piano", "stab.saw"}, chance = 0.5, wants = {"playful", "euphoric"}},
			{role = "arp", patches = {"pluck.saw", "pluck.bell"}, chance = 0.5, wants = {"bright", "playful"}},
			{role = "lead", patches = {"lead.vox", "lead.saw", "lead.sine"}, chance = 0.7, wants = {"hook", "answer", "vocal", "playful"}},
			{role = "fx", patches = {"fx.siren"}, chance = 0.3},
		}},
	{id = "funky", name = "Funky Breaks", tempo = {120, 130}, swing = {0.08, 0.18},
		harmony = {progressions = {{1, 4, 1, 4}, {1, 1, 4, 4}, {1, 4, 1, 5}, {2, 5, 1, 1}}, voicing = {0, 2, 4, 6}},
		-- The loop is the point: the break only thins, never leaves, and the
		-- keys carry the breakdown. Long, shallow peaks.
		arc = {impact = 0, valley = 0.2, drumless = 0, kickOut = 0.2, kickOutBars = {1, 2}, halftime = 0, fill = 0.4,
			curve = {{0, 0.35}, {0.1, 0.5}, {0.22, 0.7}, {0.3, 0.85}, {0.48, 0.75}, {0.55, 0.45}, {0.65, 0.85}, {0.85, 0.7}, {0.93, 0.45}, {1, 0.3}}},
		channels = {
			{role = "drums", wants = {"swung", "playful", "broken"}, avoid = {"aggressive"}},
			{role = "tops", gain = 0.85, chops = true, wants = {"break", "swung", "shuffle"}},
			{role = "bass", patches = {"bass.moog", "bass.upright", "bass.round"}, wants = {"walking", "slap", "warm", "playful"}},
			{role = "keys", patches = {"keys.clav", "keys.rhodes", "keys.wurli", "keys.organ"}, wants = {"rhythmic", "soulful", "warm"}},
			{role = "stab", patches = {"stab.brass", "stab.pizzicato"}, chance = 0.7, wants = {"offbeat", "playful"}},
			{role = "lead", patches = {"lead.flute", "lead.vox", "lead.square"}, chance = 0.6, wants = {"answer", "soulful", "playful"}},
			{role = "fx", patches = {"fx.wind"}, chance = 0.2},
		}},
	{id = "progressive", name = "Progressive Breaks", tempo = {126, 132}, swing = {0.02, 0.08},
		harmony = {progressions = MELODIC, voicing = {0, 2, 4, 8}},
		-- The longest, deepest breakdown of the genre: pads and tune, then the beat returns.
		arc = {impact = 0.4, valley = 0.4, drumless = 0.3, bassOut = 0.4, kickOut = 0.15, kickOutBars = {2, 4}, halftime = 0.35, lift = 0.3, fill = 0.5,
			curve = {{0, 0.25}, {0.12, 0.45}, {0.25, 0.7}, {0.34, 0.85}, {0.48, 0.5}, {0.55, 0.3}, {0.63, 0.9}, {0.82, 0.7}, {0.92, 0.4}, {1, 0.2}}},
		channels = {
			{role = "drums", wants = {"minimal", "halftime", "deep"}},
			{role = "bass", patches = {"bass.round", "bass.pluck", "bass.reese"}, wants = {"deep", "hypnotic", "pedal"}},
			{role = "pad", patches = {"pad.glass", "pad.warm", "pad.strings", "pad.air"}, wants = {"dreamy", "warm"}},
			{role = "arp", patches = {"pluck.glass", "pluck.trance", "pluck.string"}, wants = {"dreamy", "stepwise"}},
			{role = "lead", patches = {"lead.sine", "lead.vox", "lead.pluck"}, chance = 0.7, wants = {"melancholic", "stepwise", "dreamy"}},
			{role = "counter", patches = {"pluck.bell", "keys.vibes"}, chance = 0.5, wants = {"dreamy"}},
			{role = "texture", patches = {"texture.shimmer", "texture.air"}, chance = 0.7, wants = {"ambient"}},
			{role = "fx", patches = {"fx.wind"}, chance = 0.4},
		}},
	{id = "electro", name = "Electro", tempo = {124, 132}, swing = {0, 0.04},
		harmony = {progressions = {{1, 1, 1, 1}, {1, 1, 7, 7}, {1, 1, 4, 4}}, voicing = {0, 2, 4}, change = 0.2},
		-- Machine-steady: the grid stays, the valley is shallow, kick-outs are short.
		arc = {impact = 0.1, valley = 0.25, drumless = 0.1, bassOut = 0.4, kickOut = 0.4, kickOutBars = {1, 2}, halftime = 0, fill = 0.4, lift = 0,
			curve = {{0, 0.35}, {0.12, 0.55}, {0.28, 0.8}, {0.4, 0.85}, {0.5, 0.7}, {0.56, 0.4}, {0.66, 0.9}, {0.85, 0.75}, {0.93, 0.5}, {1, 0.3}}},
		channels = {
			{role = "drums", wants = {"electro", "straight"}},
			{role = "tops", chance = 0.6, wants = {"electro", "playful"}},
			{role = "bass", patches = {"bass.fm", "bass.donk", "bass.acidSquare", "bass.808"}, wants = {"octave", "driving", "riff"}},
			{role = "pad", patches = {"pad.choir", "pad.pwm"}, chance = 0.6, wants = {"dark", "held"}},
			{role = "stab", patches = {"stab.fm", "stab.organ"}, chance = 0.6, wants = {"tense", "stab"}},
			{role = "arp", patches = {"pluck.chip", "pluck.acid"}, wants = {"driving", "tense"}},
			{role = "lead", patches = {"lead.vox", "lead.square", "lead.fm"}, chance = 0.7, wants = {"hypnotic", "rhythmic", "straight"}},
			{role = "fx", patches = {"fx.siren"}, chance = 0.3},
		}},
	-- 1992: a hoover, a piano and the Amen.
	{id = "rave", name = "Rave", tempo = {132, 140}, swing = {0.02, 0.1},
		harmony = {progressions = {{1, 6, 4, 5}, {1, 7, 6, 7}, {6, 4, 1, 5}, {1, 1, 6, 7}}, voicing = {0, 2, 4, 7}},
		-- Euphoric: a piano breakdown, then the full Amen and hoover back; the key may lift.
		arc = {impact = 0.3, valley = 0.25, drumless = 0.15, kickOut = 0.35, kickOutBars = {2, 4}, halftime = 0, lift = 0.4,
			curve = {{0, 0.3}, {0.1, 0.5}, {0.22, 0.8}, {0.3, 0.95}, {0.48, 0.8}, {0.54, 0.4}, {0.65, 1}, {0.85, 0.8}, {0.93, 0.5}, {1, 0.25}}},
		channels = {
			{role = "drums", wants = {"gallop", "driving", "busy"}},
			{role = "tops", gain = 0.85, chops = true, wants = {"break", "aggressive"}},
			{role = "bass", patches = {"bass.hoover", "bass.808", "bass.sub"}, wants = {"sub", "held", "euphoric"}},
			{role = "keys", patches = {"keys.piano"}, wants = {"bright", "euphoric"}},
			{role = "stab", patches = {"stab.rave", "stab.piano"}, wants = {"euphoric", "rhythmic"}},
			{role = "lead", patches = {"lead.hoover", "lead.square"}, chance = 0.7, wants = {"anthem", "euphoric", "hook"}},
			{role = "texture", patches = {"texture.tape"}, chance = 0.5},
			{role = "fx", patches = {"fx.siren"}, chance = 0.4},
		}},
}

return {
	api = 4,
	title = "Breakbeat",
	symbol = "opticaldisc.fill",
	summary = "Big Beat, Nu Skool, Florida, Electro and more",
	defaults = {energy = 0.65, complexity = 0.55, humanize = 0.4, space = 0.3},
	kit = {
		kick = {base = 52, sweep = 120, sweepTime = 0.02, decay = 0.18, drive = 2, click = 0.4, length = 0.35},
		snare = {tone = 210, overtone = 350, bodyDecay = 0.06, noiseDecay = 0.13, noise = 0.5},
	},
	mix = {duckDepth = 0.35, stab = 1.15, tops = 0.8},
	set = {modes = {"minor", "dorian", "phrygian"}, modulations = {2}},
	-- One long canvas: a first peak about 30% in, a shallow valley where the
	-- break thins (drums stay), kick-out and chop moves, a bigger second peak
	-- near 65%. No risers or snare rolls; impacts are rare.
	arc = {
		minutes = {4, 5}, intro = 16, outro = 16, riser = 0, roll = 0, impact = 0.2, valley = 0.2, drumless = 0.15,
		bassOut = 0.4, kickOut = 0.35, kickOutBars = {1, 2, 4}, halftime = 0.1, lift = 0.15, fill = 0.7,
		curve = {{0, 0.3}, {0.1, 0.5}, {0.2, 0.75}, {0.3, 0.9}, {0.48, 0.7}, {0.55, 0.4}, {0.65, 0.95}, {0.85, 0.75}, {0.93, 0.45}, {1, 0.25}},
	},
	harmony = {progressions = PROGRESSIONS, voicing = {0, 2, 4, 6}, barsPerChord = 2, change = 0.3, segmentBars = 8},
	roles = {drums = {fills = FILLS}},
	flavours = FLAVOURS,
}
