-- House: four to the floor from 118 to 128 BPM. A round kick with a deep
-- sidechain pump, claps on two and four, open hats on the off-beats;
-- seventh and ninth chords comped over an off-beat bass. Its flavours: Deep
-- on an electric piano, Classic, Disco on octave bass and strings, Piano
-- house, Organ house, Tribal on a percussion loop, Acid, and French house
-- opening its loops through a filter. The track is one canvas (see `arc`):
-- house evolves in 8, 16 and 32 bar changes, with a couple of short breaks
-- instead of one big breakdown, and rarely a riser.

-- Dorian, minor and major loops of four chords, a bar each.
local PROGRESSIONS = {{1, 4, 1, 4}, {2, 5, 1, 1}, {1, 6, 4, 5}, {1, 7, 4, 4}, {6, 4, 1, 5}, {2, 4, 5, 5},
	{1, 3, 4, 4}, {4, 5, 6, 6}, {1, 1, 4, 5}}
local FILLS = {"fill.claps", "fill.snares", "fill.congas", "fill.kicks", "@cut", "@retrig", "@reverse"}

-- Deep house: a low soft curve with two valleys (about a quarter and 60%
-- of the way), almost no risers or rolls, layers returning rather than drops.
local DEEP = {riser = 0.1, roll = 0.1, impact = 0.3, drumless = 0.3, kickOut = 0.4, lift = 0, valley = 0.4,
	curve = {{0, 0.25}, {0.12, 0.4}, {0.22, 0.6}, {0.28, 0.45}, {0.38, 0.65}, {0.5, 0.7}, {0.58, 0.4}, {0.66, 0.7},
		{0.82, 0.6}, {0.92, 0.4}, {1, 0.2}}}
-- Acid: the 303 sweep is the build; a beatless break, then back to the groove.
local ACID = {riser = 0.2, roll = 0.3, impact = 0.4, drumless = 0.7, bassOut = 0.7, kickOut = 0.3, lift = 0, halftime = 0,
	curve = {{0, 0.3}, {0.12, 0.5}, {0.3, 0.8}, {0.45, 0.8}, {0.5, 0.35}, {0.58, 0.4}, {0.64, 0.9}, {0.82, 0.8},
		{0.92, 0.45}, {1, 0.25}}}

local FLAVOURS = {
	{id = "deep", name = "Deep House", tempo = {118, 123}, swing = {0.06, 0.14}, arc = DEEP,
		channels = {
			{role = "drums", wants = {"deep", "swung", "minimal"}},
			{role = "tops", gain = 0.5, chance = 0.5, wants = {"deep", "sparse"}},
			{role = "bass", patches = {"bass.round", "bass.sub", "bass.fm", "bass.organ"}, wants = {"deep", "sub", "warm"}},
			{role = "pad", patches = {"pad.warm", "pad.glass", "pad.air"}, chance = 0.8, wants = {"dreamy", "warm"}},
			{role = "keys", patches = {"keys.rhodes", "keys.wurli", "keys.vibes"}, wants = {"soulful", "deep"}},
			{role = "arp", patches = {"pluck.bell", "pluck.marimba", "pluck.glass"}, chance = 0.3, wants = {"dreamy"}},
			{role = "lead", patches = {"lead.sine", "lead.flute", "lead.vox"}, chance = 0.4, wants = {"vocal", "soulful", "sparse"}},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		}},
	{id = "classic", name = "Classic House", tempo = {122, 126}, swing = {0.04, 0.12},
		arc = {riser = 0.3, roll = 0.3, lift = 0.1},
		channels = {
			{role = "drums", wants = {"fourfloor", "driving", "shuffle"}},
			{role = "bass", patches = {"bass.organ", "bass.fm", "bass.moog"}, wants = {"offbeat", "bumpy"}},
			{role = "pad", patches = {"pad.saw", "pad.strings", "pad.organ"}, chance = 0.7},
			{role = "keys", patches = {"keys.piano", "keys.organ", "keys.rhodes"}, chance = 0.7, wants = {"syncopated", "chordal"}},
			{role = "stab", patches = {"stab.organ", "stab.saw", "stab.brass"}, wants = {"syncopated", "bumpy"}},
			{role = "arp", patches = {"pluck.saw", "pluck.chip", "pluck.bell"}, chance = 0.5},
			{role = "lead", patches = {"lead.saw", "lead.square", "lead.fm"}, chance = 0.6, wants = {"hook", "riff", "playful"}},
			{role = "fx", patches = {"fx.riser", "fx.siren"}},
		}},
	-- A filter that opens and closes over a disco loop: more risers and lift.
	{id = "disco", name = "Disco House", tempo = {122, 127}, swing = {0.02, 0.08},
		arc = {riser = 0.4, roll = 0.2, impact = 0.5, lift = 0.3, curve = {{0, 0.3}, {0.1, 0.5}, {0.25, 0.75}, {0.4, 0.85},
			{0.5, 0.45}, {0.6, 0.9}, {0.8, 0.7}, {0.92, 0.4}, {1, 0.25}}},
		channels = {
			{role = "drums", wants = {"playful", "swung"}},
			{role = "tops", gain = 0.5, chance = 0.4, wants = {"playful", "busy"}},
			{role = "bass", patches = {"bass.moog", "bass.fm", "bass.pluck"}, wants = {"octave", "walking", "playful"}},
			{role = "pad", patches = {"pad.strings", "pad.supersaw"}, wants = {"euphoric", "bright"}},
			{role = "keys", patches = {"keys.clav", "keys.piano", "keys.rhodes"}, chance = 0.6, wants = {"rhythmic", "playful"}},
			{role = "stab", patches = {"stab.brass", "stab.pizzicato", "stab.saw"}, chance = 0.8, wants = {"playful"}},
			{role = "arp", patches = {"pluck.saw", "pluck.string"}, chance = 0.6},
			{role = "fx", patches = {"fx.riser"}},
		}},
	-- The piano is the hook: bright chords, struck hard, a long melodic valley.
	{id = "piano", name = "Piano House", tempo = {122, 128}, swing = {0.02, 0.1},
		harmony = {progressions = {{1, 6, 4, 5}, {6, 4, 1, 5}, {1, 4, 6, 5}, {4, 5, 6, 6}, {1, 3, 4, 4}}},
		arc = {riser = 0.4, roll = 0.2, valley = 0.5, drumless = 0.5, lift = 0.3, curve = {{0, 0.25}, {0.1, 0.45}, {0.22, 0.75},
			{0.34, 0.85}, {0.42, 0.45}, {0.58, 0.4}, {0.66, 0.9}, {0.82, 0.75}, {0.92, 0.4}, {1, 0.2}}},
		channels = {
			{role = "drums", wants = {"fourfloor", "straight"}},
			{role = "bass", patches = {"bass.organ", "bass.fm", "bass.round"}, wants = {"soulful", "offbeat"}},
			{role = "pad", patches = {"pad.strings", "pad.warm"}, chance = 0.6},
			{role = "keys", patches = {"keys.piano"}, wants = {"soulful", "syncopated", "bright"}},
			{role = "stab", patches = {"stab.piano", "stab.organ"}, chance = 0.4, wants = {"soulful"}},
			{role = "lead", patches = {"lead.vox", "lead.sine", "lead.saw"}, chance = 0.5, wants = {"hook", "stepwise", "euphoric"}},
			{role = "fx", patches = {"fx.riser", "fx.wind"}},
		}},
	{id = "organ", name = "Organ House", tempo = {124, 128}, swing = {0.08, 0.16},
		arc = {riser = 0.2, roll = 0.2, lift = 0},
		channels = {
			{role = "drums", wants = {"driving", "shuffle", "syncopated"}},
			{role = "bass", patches = {"bass.organ", "bass.donk", "bass.fm"}, wants = {"bumpy", "syncopated"}},
			{role = "keys", patches = {"keys.organ"}, wants = {"offbeat", "chordal"}},
			{role = "stab", patches = {"stab.organ"}, wants = {"offbeat", "syncopated"}},
			{role = "lead", patches = {"lead.square", "lead.fm"}, chance = 0.4, wants = {"riff", "playful"}},
			{role = "fx", patches = {"fx.riser"}},
		}},
	-- A percussion loop carries the groove; it evolves rather than lifts.
	{id = "tribal", name = "Tribal House", tempo = {124, 128}, swing = {0.04, 0.1},
		harmony = {progressions = {{1, 1, 1, 1}, {1, 1, 4, 4}, {1, 7, 1, 7}}, change = 0.2},
		arc = {riser = 0.15, roll = 0.2, impact = 0.4, drumless = 0.3, kickOut = 0.4, lift = 0, valley = 0.4,
			curve = {{0, 0.3}, {0.12, 0.5}, {0.28, 0.75}, {0.42, 0.8}, {0.5, 0.5}, {0.6, 0.85}, {0.8, 0.8}, {0.92, 0.45}, {1, 0.25}}},
		channels = {
			{role = "drums", wants = {"rhythmic", "driving"}},
			{role = "tops", gain = 0.7, wants = {"rhythmic", "busy"}},
			{role = "bass", patches = {"bass.sub", "bass.round", "bass.donk"}, wants = {"sub", "hypnotic", "tresillo"}},
			{role = "stab", patches = {"stab.dub", "stab.pizzicato", "stab.organ"}, chance = 0.6, wants = {"dark", "hypnotic"}},
			{role = "counter", patches = {"pluck.marimba", "pluck.string", "lead.flute"}, chance = 0.7, wants = {"rhythmic", "hypnotic"}},
			{role = "texture", patches = {"texture.air", "texture.drone"}, chance = 0.6},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		}},
	{id = "acid", name = "Acid House", tempo = {120, 126}, swing = {0.02, 0.1}, arc = ACID,
		harmony = {progressions = {{1, 1, 1, 1}, {1, 1, 4, 4}, {1, 7, 1, 7}}, change = 0.2, barsPerChord = 2},
		channels = {
			{role = "drums", wants = {"driving", "syncopated"}},
			{role = "bass", patches = {"bass.acid", "bass.acidSquare"}, octave = 0, wants = {"acid", "hypnotic"}},
			{role = "pad", patches = {"pad.choir", "pad.dark"}, chance = 0.5, wants = {"dark"}},
			{role = "stab", patches = {"stab.organ", "stab.piano"}, chance = 0.5, wants = {"sparse", "hypnotic"}},
			{role = "texture", patches = {"texture.tape"}, chance = 0.4},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	-- A disco loop heard through a filter that opens and closes.
	{id = "french", name = "French House", tempo = {122, 126}, swing = {0.02, 0.08},
		harmony = {progressions = {{1, 4, 1, 4}, {2, 5, 1, 1}, {1, 6, 4, 5}, {4, 5, 6, 6}}, change = 0.1},
		arc = {riser = 0.5, roll = 0.1, impact = 0.3, drumless = 0.2, bassOut = 0.2, kickOut = 0.2, lift = 0.2, valley = 0.5,
			curve = {{0, 0.2}, {0.1, 0.35}, {0.2, 0.55}, {0.3, 0.8}, {0.42, 0.85}, {0.5, 0.5}, {0.6, 0.9}, {0.8, 0.8}, {0.92, 0.45}, {1, 0.2}}},
		channels = {
			{role = "drums", wants = {"playful", "swung"}},
			{role = "bass", patches = {"bass.moog", "bass.pluck"}, wants = {"octave", "pluck", "playful"}},
			{role = "pad", patches = {"pad.strings", "pad.supersaw"}, wants = {"bright", "euphoric"}},
			{role = "stab", patches = {"stab.brass", "stab.saw"}, wants = {"playful", "syncopated"}},
			{role = "keys", patches = {"keys.clav", "keys.rhodes"}, chance = 0.5, wants = {"rhythmic"}},
			{role = "fx", patches = {"fx.riser"}},
		}},
}

return {
	api = 4,
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
	set = {modes = {"dorian", "minor", "major"}, modulations = {0, 2, 5}},
	-- Loop evolution: layers change every 8, 16 and 32 bars; a short break
	-- or two (kick out a bar or two, a drumless 8-16) rather than a big
	-- breakdown; risers are rare, the long mix in and out are drums only.
	arc = {
		minutes = {5, 6.5}, intro = 32, outro = 32, riser = 0.25, riserBars = {4, 8}, roll = 0.2, impact = 0.3,
		valley = 0.45, drumless = 0.4, bassOut = 0.4, kickOut = 0.3, kickOutBars = {1, 2, 4}, halftime = 0, lift = 0.15,
		swap = 0.4,
		curve = {{0, 0.25}, {0.1, 0.4}, {0.22, 0.65}, {0.3, 0.8}, {0.42, 0.75}, {0.5, 0.4}, {0.6, 0.85}, {0.8, 0.7},
			{0.9, 0.4}, {1, 0.2}},
	},
	harmony = {progressions = PROGRESSIONS, voicing = {0, 2, 4, 6}, barsPerChord = 1, segmentBars = 16},
	roles = {drums = {fills = FILLS, roll = "clap"}, bass = {octave = 1}},
	flavours = FLAVOURS,
}
