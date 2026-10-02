-- Techno: a four-on-the-floor set from 118 to 140 BPM. A long, driven kick
-- with a rumble rolling in its tail, off-beat hats and claps on two and
-- four. Its flavours: Peak Time, Acid on a squelching 303, Hypnotic on a
-- dub chord thrown into the delay, Industrial, Minimal with percussion
-- where the tune would be, Melodic, and slow, washed-out Dub Techno.
-- The track is one canvas (see `arc`) that does not build: it has no risers
-- and no key lift, and evolves in plateaus, layers entering and leaving on
-- phrase boundaries, with kick-outs and one shallow reduction for relief.
-- A long mix-in and mix-out leave room for a DJ.

-- Minor-key loops; techno lives on one or two chords.
local PROGRESSIONS = {{1, 1, 1, 1}, {1, 1, 6, 6}, {1, 7, 1, 7}, {1, 1, 4, 4}, {1, 6, 1, 7}}
local MELODIC = {{1, 6, 3, 7}, {1, 4, 6, 5}, {6, 7, 1, 1}, {1, 3, 6, 7}, {1, 6, 4, 5}}

local FILLS = {"fill.flam", "fill.claps", "fill.kicks", "fill.rims", "@retrig", "@cut", "@reverse"}

-- A flat plateau: in at a quarter, a step up, one shallow reduction at the
-- middle, a late peak, out.
local FLAT = {{0, 0.3}, {0.1, 0.45}, {0.25, 0.65}, {0.4, 0.75}, {0.52, 0.4}, {0.6, 0.72}, {0.8, 0.78}, {0.92, 0.45}, {1, 0.25}}

local FLAVOURS = {
	{id = "peak", name = "Peak Time", tempo = {130, 136}, swing = {0, 0.04},
		-- Stronger valley, a crash or impact on the way back in, a late peak.
		arc = {impact = 0.6, valley = 0.5, kickOut = 0.45, drumless = 0.3, fill = 0.8,
			curve = {{0, 0.3}, {0.1, 0.5}, {0.25, 0.7}, {0.4, 0.8}, {0.52, 0.35}, {0.6, 0.8}, {0.8, 0.9}, {0.92, 0.5}, {1, 0.25}}},
		channels = {
			{role = "drums", wants = {"fourfloor", "driving", "rolling"}},
			{role = "tops", gain = 0.7, chance = 0.5, wants = {"driving", "rolling"}},
			{role = "bass", patches = {"bass.rumble", "bass.psy", "bass.moog"}, wants = {"rolling", "driving"}},
			{role = "pad", patches = {"pad.dark", "pad.pwm", "pad.saw"}, chance = 0.7},
			{role = "stab", patches = {"stab.saw", "stab.fm", "stab.rave"}, chance = 0.5, wants = {"rhythmic", "tense"}},
			{role = "arp", patches = {"pluck.acid", "pluck.saw", "pluck.chip"}, chance = 0.6, wants = {"driving", "tense"}},
			{role = "lead", patches = {"lead.square", "lead.fm", "lead.hoover"}, chance = 0.5, wants = {"hook", "rhythmic"}},
			{role = "fx", patches = {"fx.riser", "fx.siren"}},
		}},
	-- The 303 is the tune: it rides the whole track.
	{id = "acid", name = "Acid", tempo = {126, 134}, swing = {0, 0.08},
		arc = {valley = 0.4, kickOut = 0.35, impact = 0.2,
			curve = {{0, 0.3}, {0.1, 0.5}, {0.25, 0.68}, {0.4, 0.75}, {0.55, 0.42}, {0.62, 0.74}, {0.82, 0.78}, {0.92, 0.45}, {1, 0.25}}},
		channels = {
			{role = "drums", wants = {"swung", "driving", "broken"}},
			{role = "tops", gain = 0.6, chance = 0.5, wants = {"syncopated", "playful"}},
			{role = "bass", patches = {"bass.acid", "bass.acidSquare"}, wants = {"acid", "riff"}},
			{role = "pad", patches = {"pad.dark", "pad.choir"}, chance = 0.4},
			{role = "stab", patches = {"stab.saw", "stab.organ"}, chance = 0.3},
			{role = "arp", patches = {"pluck.acid", "pluck.chip"}, chance = 0.3},
			{role = "texture", patches = {"texture.tape", "texture.drone"}, chance = 0.4},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	-- Flat: nothing leaves or enters but a layer at a time, and the groove is
	-- the point.
	{id = "hypnotic", name = "Hypnotic", tempo = {126, 132}, swing = {0, 0.06},
		arc = {intro = 32, outro = 32, valley = 0.3, kickOut = 0.4, impact = 0.1, jitter = 0.03, curve = FLAT},
		channels = {
			{role = "drums", wants = {"hypnotic", "syncopated", "minimal"}},
			{role = "tops", gain = 0.5, chance = 0.4, wants = {"hypnotic"}},
			{role = "bass", patches = {"bass.rumble", "bass.sub", "bass.round"}, wants = {"hypnotic", "pedal", "rolling"}},
			{role = "pad", patches = {"pad.dark", "pad.air", "pad.glass"}, chance = 0.8, wants = {"hypnotic", "ambient"}},
			{role = "stab", patches = {"stab.dub", "stab.organ"}, wants = {"hypnotic", "sparse"}},
			{role = "lead", patches = {"lead.fm", "lead.square"}, chance = 0.3, wants = {"hypnotic", "sparse"}},
			{role = "texture", patches = {"texture.air", "texture.drone", "texture.shimmer"}},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		}},
	{id = "industrial", name = "Industrial", tempo = {134, 140}, swing = {0, 0.03},
		snares = {"crunchy", "fat", "tight"},
		arc = {impact = 0.5, valley = 0.4, kickOut = 0.5, drumless = 0.2, fill = 0.8,
			curve = {{0, 0.35}, {0.1, 0.55}, {0.25, 0.75}, {0.45, 0.85}, {0.55, 0.4}, {0.62, 0.85}, {0.82, 0.9}, {0.93, 0.5}, {1, 0.3}}},
		channels = {
			{role = "drums", wants = {"aggressive", "driving", "busy"}},
			{role = "tops", gain = 0.6, chance = 0.4, wants = {"aggressive"}},
			{role = "bass", patches = {"bass.growl", "bass.hoover", "bass.rumble"}, wants = {"aggressive", "dark", "riff"}},
			{role = "stab", patches = {"stab.fm", "stab.rave"}, chance = 0.8, wants = {"aggressive", "dark"}},
			{role = "lead", patches = {"lead.hoover", "lead.fm"}, chance = 0.4, wants = {"aggressive", "hook"}},
			{role = "texture", patches = {"texture.tape", "texture.drone"}, wants = {"dark", "tense"}},
			{role = "fx", patches = {"fx.siren", "fx.wind"}},
		}},
	-- Percussion where the tune would be.
	{id = "minimal", name = "Minimal", tempo = {124, 130}, swing = {0.04, 0.12},
		arc = {intro = 32, outro = 32, valley = 0.3, kickOut = 0.4, impact = 0.05, jitter = 0.03, curve = FLAT},
		channels = {
			{role = "drums", wants = {"minimal", "swung", "sparse"}},
			{role = "tops", gain = 0.7, wants = {"syncopated", "rhythmic", "minimal"}},
			{role = "bass", patches = {"bass.sub", "bass.fm", "bass.donk", "bass.round"}, wants = {"minimal", "pluck", "rhythmic"}},
			{role = "stab", patches = {"stab.dub", "stab.pizzicato"}, chance = 0.5, wants = {"minimal", "playful"}},
			{role = "counter", patches = {"pluck.marimba", "pluck.bell", "pluck.glass"}, chance = 0.7, wants = {"playful", "sparse"}},
			{role = "lead", patches = {"lead.pluck", "lead.sine"}, chance = 0.4, wants = {"sparse", "minimal"}},
			{role = "texture", patches = {"texture.air", "texture.tape"}, chance = 0.6},
			{role = "fx", patches = {"fx.wind"}, chance = 0.7},
		}},
	{id = "melodic", name = "Melodic", tempo = {120, 126}, swing = {0, 0.06},
		-- More movement: a deeper reduction and a swell into a higher second half.
		arc = {valley = 0.5, impact = 0.4, swap = 0.5, morph = 0.6, kickOut = 0.3, drumless = 0.5, minutes = {5, 6},
			curve = {{0, 0.25}, {0.1, 0.45}, {0.22, 0.65}, {0.35, 0.85}, {0.48, 0.45}, {0.52, 0.35}, {0.62, 0.8}, {0.8, 0.9}, {0.92, 0.45}, {1, 0.2}}},
		harmony = {progressions = MELODIC, voicing = {0, 2, 4, 6}, barsPerChord = 2},
		channels = {
			{role = "drums", wants = {"minimal", "rolling", "driving"}},
			{role = "bass", patches = {"bass.pluck", "bass.moog", "bass.round"}, wants = {"melodic", "offbeat", "warm"}},
			{role = "pad", patches = {"pad.strings", "pad.supersaw", "pad.warm", "pad.glass"}, wants = {"melancholic", "dreamy"}},
			{role = "keys", patches = {"keys.vibes", "keys.rhodes"}, chance = 0.5, wants = {"melancholic", "chordal"}},
			{role = "arp", patches = {"pluck.trance", "pluck.bell", "pluck.saw"}, wants = {"melancholic", "euphoric", "dreamy"}},
			{role = "lead", patches = {"lead.sine", "lead.saw", "lead.vox", "lead.flute"}, chance = 0.8, wants = {"melancholic", "euphoric", "stepwise"}},
			{role = "texture", patches = {"texture.shimmer", "texture.air"}, chance = 0.6, wants = {"dreamy"}},
			{role = "fx", patches = {"fx.riser", "fx.wind"}},
		}},
	-- Slow and washed out: one chord, thrown into the delay. Long drumless dubs.
	{id = "dub", name = "Dub Techno", tempo = {118, 124}, swing = {0.04, 0.1},
		arc = {intro = 32, outro = 32, valley = 0.45, drumless = 0.9, bassOut = 0.5, kickOut = 0.5, kickOutBars = {2, 4},
			impact = 0, fill = 0.2, halftime = 0, minutes = {5, 6}, jitter = 0.03,
			curve = {{0, 0.25}, {0.12, 0.45}, {0.25, 0.6}, {0.38, 0.65}, {0.48, 0.3}, {0.62, 0.3}, {0.7, 0.65}, {0.85, 0.65}, {0.93, 0.4}, {1, 0.2}}},
		harmony = {progressions = {{1, 1, 1, 1}, {1, 1, 4, 4}, {1, 1, 6, 6}}, voicing = {0, 2, 4, 6}, change = 0.1},
		channels = {
			{role = "drums", wants = {"deep", "minimal", "sparse"}, avoid = {"aggressive", "busy"}},
			{role = "tops", gain = 0.5, chance = 0.4, wants = {"dub", "sparse"}, avoid = {"aggressive", "busy"}},
			{role = "bass", patches = {"bass.sub", "bass.round"}, wants = {"pedal", "deep", "sub"}, avoid = {"aggressive", "rolling"}},
			{role = "pad", patches = {"pad.dark", "pad.air", "pad.warm"}, wants = {"held", "ambient"}},
			{role = "keys", patches = {"keys.rhodes"}, chance = 0.4, wants = {"deep", "sparse"}},
			{role = "stab", patches = {"stab.dub"}, wants = {"dub", "sparse", "deep"}, avoid = {"aggressive"}},
			{role = "texture", patches = {"texture.tape", "texture.air"}, avoid = {"aggressive"}},
			{role = "fx", patches = {"fx.wind"}},
		}},
}

return {
	api = 4,
	title = "Techno",
	symbol = "metronome.fill",
	summary = "Peak Time, Acid, Hypnotic and more, four to the floor",
	defaults = {energy = 0.7, complexity = 0.5, humanize = 0.15, space = 0.4},
	kit = {
		kick = {base = 50, sweep = 170, sweepTime = 0.018, decay = 0.3, drive = 2.6, click = 0.5, length = 0.55},
		hat = {scale = 1.9, decay = 0.012, openDecay = 0.07},
	},
	mix = {duckDepth = 0.55, drums = 0.8, bass = 0.75, stab = 1.15, delayFeedback = 0.5},
	set = {modes = {"minor", "phrygian"}, modulations = {0, 5, -2}},
	-- Plateaus of 8 to 32 bars, no risers or rolls, and no key lift; relief
	-- comes from kick-outs and one shallow reduction. A 32-bar mix-in and
	-- mix-out are for the DJ.
	arc = {
		minutes = {5, 6}, intro = 32, outro = 32, phrase = 8, riser = 0, roll = 0, impact = 0.25,
		valley = 0.42, drumless = 0.4, bassOut = 0.5, kickOut = 0.4, kickOutBars = {1, 2, 4}, halftime = 0, lift = 0,
		fill = 0.5, swap = 0.4, curve = FLAT,
	},
	harmony = {progressions = PROGRESSIONS, voicing = {0, 2, 4}, barsPerChord = 4, segmentBars = 32},
	roles = {drums = {fills = FILLS, roll = "clap"}},
	flavours = FLAVOURS,
}
