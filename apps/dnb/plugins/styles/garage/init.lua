-- UK Garage: 128 to 140 BPM, swung hard. The skippy two-step kick that
-- leaves beats two and four to the snare, shuffled hats, rim shots and
-- minor-ninth chords over a bouncing bass. The track is one canvas (see
-- `arc`): a first peak early, a long valley where only a vocal hook and
-- the pad stay over a skipping rim and sub (the garage "drop" is the kick
-- and bass coming back, not a riser), a second peak and a mix-out. Risers
-- are rare. Its flavours: 2-Step, Speed Garage on four kicks and a reese,
-- Future Garage washed out under a pitched lead, Bassline on a donk, and
-- Dark Garage, all sub and squares.

local PROGRESSIONS = {{1, 4, 1, 4}, {1, 6, 4, 5}, {4, 5, 1, 1}, {1, 7, 6, 4}, {2, 5, 1, 6}, {1, 3, 4, 4}, {6, 4, 1, 5}}
local DARK = {{1, 1, 1, 1}, {1, 1, 6, 7}, {1, 2, 1, 7}, {1, 7, 1, 7}}

local FILLS = {"fill.snares", "fill.rims", "fill.claps", "fill.stutter", "@stutter", "@cut", "@reverse"}

-- Peaks at a fifth and two thirds of the track, a valley between at about
-- 0.3 where the vocal and pad carry it.
local CURVE = {{0, 0.3}, {0.08, 0.5}, {0.2, 0.8}, {0.35, 0.75}, {0.42, 0.35}, {0.5, 0.3}, {0.58, 0.7}, {0.65, 0.9},
	{0.82, 0.7}, {0.92, 0.45}, {1, 0.25}}

local FLAVOURS = {
	-- Soulful: vocal hooks and Rhodes, the valley a drum-and-vocal gap.
	{id = "twostep", name = "2-Step", tempo = {130, 136}, swing = {0.24, 0.34},
		snares = {"rimshot", "tight", "layered", "vintage"},
		arc = {valley = 0.5, drumless = 0.35, lift = 0.25, kickOut = 0.5, swap = 0.4},
		channels = {
			{role = "drums", wants = {"twostep", "swung"}, avoid = {"fourfloor"}},
			{role = "bass", patches = {"bass.fm", "bass.round", "bass.reese", "bass.organ"}, wants = {"syncopated", "soulful", "walking"}},
			{role = "pad", patches = {"pad.warm", "pad.strings", "pad.glass"}, chance = 0.6, wants = {"warm"}},
			{role = "keys", patches = {"keys.wurli", "keys.rhodes", "keys.organ", "keys.vibes"}, wants = {"soulful"}},
			{role = "stab", patches = {"stab.organ", "stab.pizzicato", "stab.piano"}, chance = 0.5, wants = {"soulful", "syncopated"}},
			{role = "arp", patches = {"pluck.bell", "pluck.string", "pluck.marimba"}, chance = 0.4, wants = {"swung"}},
			{role = "lead", patches = {"lead.vox", "lead.sine", "lead.square"}, chance = 0.6, wants = {"hook", "vocal", "soulful"}},
			{role = "fx", patches = {"fx.riser", "fx.wind"}},
		}},
	-- Four kicks and a reese: the driving flavour, a short valley and risers.
	{id = "speed", name = "Speed Garage", tempo = {130, 136}, swing = {0.16, 0.26},
		snares = {"tight", "rimshot", "crunchy", "layered"},
		arc = {riser = 0.5, roll = 0.3, impact = 0.6, drumless = 0.15, kickOut = 0.25, halftime = 0, valley = 0.4,
			curve = {{0, 0.35}, {0.1, 0.6}, {0.2, 0.9}, {0.4, 0.85}, {0.46, 0.45}, {0.52, 0.45}, {0.6, 0.85},
				{0.65, 0.95}, {0.82, 0.8}, {0.92, 0.5}, {1, 0.3}}},
		channels = {
			{role = "drums", wants = {"fourfloor", "driving"}, avoid = {"halftime"}},
			{role = "bass", patches = {"bass.reese", "bass.reeseWide", "bass.wobble", "bass.hoover"}, wants = {"reese", "wobble", "octave"}},
			{role = "pad", patches = {"pad.saw", "pad.dark"}, chance = 0.5},
			{role = "keys", patches = {"keys.organ", "keys.piano"}, chance = 0.4, wants = {"bright", "rhythmic"}},
			{role = "stab", patches = {"stab.organ", "stab.rave", "stab.brass"}, wants = {"offbeat", "driving"}},
			{role = "lead", patches = {"lead.hoover", "lead.square", "lead.vox"}, chance = 0.4, wants = {"riff", "rhythmic"}},
			{role = "texture", patches = {"texture.tape"}, chance = 0.4},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	-- Atmospheric: the long valley is most of the middle, no risers, the
	-- half-time snare. Keeps its pads under the whole track.
	{id = "future", name = "Future Garage", tempo = {128, 134}, swing = {0.2, 0.3},
		snares = {"roomy", "vintage", "rimshot", "layered"},
		arc = {riser = 0, roll = 0, impact = 0.1, halftime = 0.6, drumless = 0.3, valley = 0.55, kickOut = 0.5,
			minutes = {4.5, 5.5}, lift = 0,
			curve = {{0, 0.2}, {0.12, 0.4}, {0.2, 0.65}, {0.3, 0.6}, {0.38, 0.3}, {0.55, 0.3}, {0.65, 0.7},
				{0.82, 0.6}, {0.92, 0.35}, {1, 0.2}}},
		channels = {
			{role = "drums", wants = {"halftime", "dreamy", "sparse"}, avoid = {"fourfloor"}, gain = 0.9},
			{role = "bass", patches = {"bass.sub", "bass.round", "bass.808"}, wants = {"sub", "pedal", "deep"}},
			{role = "pad", patches = {"pad.air", "pad.glass", "pad.choir", "pad.warm"}, wants = {"dreamy", "held"}},
			{role = "keys", patches = {"keys.vibes", "keys.rhodes", "keys.harp"}, chance = 0.7, wants = {"dreamy", "sparse"}},
			{role = "arp", patches = {"pluck.glass", "pluck.string"}, chance = 0.4, avoid = {"driving"}},
			{role = "lead", patches = {"lead.vox", "lead.sine", "lead.pluck"}, wants = {"vocal", "dreamy", "melancholic", "sparse"}},
			{role = "texture", patches = {"texture.tape", "texture.shimmer", "texture.air"}, wants = {"ambient"}},
			{role = "fx", patches = {"fx.wind"}},
		}},
	-- Donk bass on four kicks: the party flavour, high and short-valleyed.
	{id = "bassline", name = "Bassline", tempo = {134, 140}, swing = {0.1, 0.2},
		snares = {"tight", "layered", "crunchy"},
		harmony = {progressions = {{1, 1, 4, 4}, {1, 7, 6, 7}, {1, 4, 1, 5}, {1, 1, 6, 7}}, voicing = {0, 2, 4, 6}},
		arc = {riser = 0.4, roll = 0.3, impact = 0.6, drumless = 0.1, kickOut = 0.2, halftime = 0, valley = 0.4,
			curve = {{0, 0.4}, {0.1, 0.65}, {0.2, 0.9}, {0.4, 0.85}, {0.46, 0.5}, {0.52, 0.5}, {0.6, 0.9},
				{0.65, 0.95}, {0.82, 0.85}, {0.92, 0.55}, {1, 0.35}}},
		channels = {
			{role = "drums", wants = {"fourfloor", "playful"}, avoid = {"halftime"}},
			{role = "bass", patches = {"bass.donk", "bass.organ", "bass.yoi", "bass.fm"}, wants = {"pluck", "stab", "playful"}},
			{role = "keys", patches = {"keys.organ", "keys.piano"}, chance = 0.5, wants = {"offbeat", "bright"}},
			{role = "stab", patches = {"stab.organ", "stab.brass", "stab.rave"}, wants = {"offbeat", "playful"}},
			{role = "lead", patches = {"lead.square", "lead.vox", "lead.hoover"}, chance = 0.6, wants = {"hook", "leap", "playful"}},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	-- All sub and squares: a tense valley, stuttering stabs, few risers.
	{id = "dark", name = "Dark Garage", tempo = {134, 140}, swing = {0.14, 0.24},
		snares = {"tight", "crunchy", "rimshot"},
		harmony = {progressions = DARK, voicing = {0, 2, 4, 6}, change = 0.2},
		arc = {riser = 0.15, roll = 0.15, impact = 0.5, halftime = 0.3, drumless = 0.4, kickOut = 0.4, valley = 0.4,
			curve = {{0, 0.25}, {0.1, 0.45}, {0.2, 0.8}, {0.36, 0.8}, {0.42, 0.3}, {0.52, 0.3}, {0.6, 0.75},
				{0.65, 0.9}, {0.82, 0.8}, {0.92, 0.4}, {1, 0.2}}},
		channels = {
			{role = "drums", wants = {"dark", "tense"}, avoid = {"fourfloor"}},
			{role = "bass", patches = {"bass.sub", "bass.808", "bass.growl", "bass.reeseWide"}, wants = {"dark", "sub", "tense"}},
			{role = "pad", patches = {"pad.dark", "pad.choir"}, chance = 0.6, wants = {"dark", "deep"}},
			{role = "stab", patches = {"stab.fm", "stab.dub", "stab.brass"}, chance = 0.7, wants = {"dark", "tense"}},
			{role = "lead", patches = {"lead.square", "lead.fm"}, chance = 0.6, wants = {"dark", "riff", "minimal"}},
			{role = "texture", patches = {"texture.drone", "texture.tape"}, chance = 0.7, wants = {"dark"}},
			{role = "fx", patches = {"fx.siren", "fx.wind"}},
		}},
}

return {
	api = 4,
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
	set = {modes = {"minor", "dorian"}, modulations = {0, 5}},
	-- Vocal-led and sectional: the valley keeps the pad and the hook and
	-- usually drops the kick but not always the drums; risers are rare.
	arc = {
		minutes = {4, 5.5}, intro = 16, outro = 16, riser = 0.1, riserBars = {2, 4}, roll = 0.1, impact = 0.3,
		valley = 0.45, drumless = 0.5, bassOut = 0.6, kickOut = 0.5, kickOutBars = {1, 2, 4}, halftime = 0.1,
		lift = 0.15, fill = 0.5, curve = CURVE,
		breakdown = {"pad", "keys", "lead", "stab", "counter", "texture"},
	},
	harmony = {progressions = PROGRESSIONS, voicing = {0, 2, 4, 6, 8}, barsPerChord = 2, change = 0.1, segmentBars = 16},
	roles = {drums = {fills = FILLS}},
	flavours = FLAVOURS,
}
