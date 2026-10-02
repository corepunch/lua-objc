-- Dubstep: 136 to 150 BPM, felt at half time. The kick opens the bar and
-- the snare lands on beat three; the drop is the bass. Its flavours: Deep,
-- on a sub and a dub echo; Brostep, a wobble whose LFO restarts with every
-- note at a rate the note chooses; Riddim, one wub repeated until it is a
-- rhythm; Melodic, chords and a lead over the half-time; Dub, a skank and
-- a melodica; and Chillstep, mostly pads.

local PROGRESSIONS = {{1, 1, 1, 1}, {1, 1, 6, 7}, {1, 2, 1, 7}, {1, 6, 1, 5}}
local MELODIC = {{1, 6, 3, 7}, {6, 7, 1, 1}, {1, 4, 6, 5}, {6, 4, 1, 5}, {1, 3, 6, 7}}

local FILLS = {"fill.roll", "fill.triplets", "fill.toms", "@tape", "@stutter", "@cut", "@reverse"}

local FLAVOURS = {
	-- Sub and dub echo: a shallow, wide valley, few risers, silence as the move.
	{id = "deep", name = "Deep Dubstep", tempo = {138, 142}, swing = {0.04, 0.1},
		snares = {"roomy", "vintage", "fat", "layered"},
		arc = {riser = 0.3, roll = 0.15, impact = 0.6, valley = 0.5, drumless = 0.4, bassOut = 0.3, kickOut = 0.35,
			halftime = 0, lift = 0,
			curve = {{0, 0.25}, {0.12, 0.4}, {0.28, 0.6}, {0.4, 0.75}, {0.5, 0.5}, {0.6, 0.78}, {0.8, 0.6}, {0.9, 0.4}, {1, 0.2}}},
		channels = {
			{role = "drums", wants = {"deep", "halftime"}},
			{role = "bass", patches = {"bass.sub", "bass.808", "bass.wobble"}, wants = {"sub", "deep"}},
			{role = "pad", patches = {"pad.dark", "pad.air", "pad.choir"}},
			{role = "stab", patches = {"stab.dub", "stab.organ"}, chance = 0.4, wants = {"dub", "sparse"}},
			{role = "lead", patches = {"lead.sine", "lead.flute", "lead.vox"}, chance = 0.6, wants = {"sparse", "vocal"}},
			{role = "texture", patches = {"texture.tape", "texture.air", "texture.drone"}},
			{role = "fx", patches = {"fx.wind", "fx.riser"}},
		}},
	-- The wobble restarts on every note at a rate the note chooses: big
	-- risers and snare rolls, a drumless breakdown, silence, a bigger second drop.
	{id = "brostep", name = "Brostep", tempo = {140, 150}, swing = {0, 0.06},
		snares = {"crunchy", "fat", "layered", "tight"},
		arc = {riser = 0.9, roll = 0.85, impact = 0.95, valley = 0.45, drumless = 0.9, bassOut = 0.8, kickOut = 0.4,
			halftime = 0.5, lift = 0.3,
			curve = {{0, 0.25}, {0.1, 0.4}, {0.22, 0.65}, {0.3, 0.88}, {0.46, 0.85}, {0.5, 0.3}, {0.58, 0.4}, {0.62, 0.95},
				{0.82, 0.8}, {0.92, 0.4}, {1, 0.2}}},
		channels = {
			{role = "drums", wants = {"aggressive", "halftime"}},
			{role = "bass", patches = {"bass.wobble", "bass.yoi", "bass.growl"}, wants = {"wobble", "aggressive"}},
			{role = "pad", patches = {"pad.supersaw", "pad.dark"}, chance = 0.5},
			{role = "stab", patches = {"stab.rave", "stab.fm", "stab.saw"}, wants = {"aggressive", "stab"}},
			{role = "arp", patches = {"pluck.chip", "pluck.acid"}, chance = 0.4},
			{role = "lead", patches = {"lead.hoover", "lead.supersaw", "lead.square"}, chance = 0.5, wants = {"riff", "aggressive"}},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	-- One wub repeated until it is a rhythm: flat, repetitive, little build;
	-- the kick drops out instead.
	{id = "riddim", name = "Riddim", tempo = {140, 150}, swing = {0, 0.04},
		snares = {"tight", "crunchy", "rimshot", "layered"},
		harmony = {progressions = {{1, 1, 1, 1}, {1, 1, 1, 7}, {1, 2, 1, 1}}, change = 0.15},
		arc = {riser = 0.3, roll = 0.2, impact = 0.7, valley = 0.35, drumless = 0.2, bassOut = 0.3, kickOut = 0.6,
			halftime = 0, lift = 0,
			curve = {{0, 0.3}, {0.12, 0.5}, {0.25, 0.75}, {0.45, 0.8}, {0.5, 0.6}, {0.58, 0.82}, {0.8, 0.8}, {0.92, 0.45}, {1, 0.25}}},
		channels = {
			{role = "drums", wants = {"riddim", "halftime"}},
			{role = "bass", patches = {"bass.yoi", "bass.wobble", "bass.growl"}, wants = {"riddim", "rhythmic"}},
			{role = "stab", patches = {"stab.fm", "stab.brass"}, chance = 0.5, wants = {"stab", "sparse"}},
			{role = "texture", patches = {"texture.drone", "texture.tape"}, chance = 0.5},
			{role = "fx", patches = {"fx.siren", "fx.riser"}},
		}},
	-- Chords and a lead over the half-time: a long breakdown and a lift.
	{id = "melodic", name = "Melodic Dubstep", tempo = {138, 145}, swing = {0, 0.06},
		snares = {"fat", "layered", "roomy"},
		harmony = {progressions = MELODIC, voicing = {0, 2, 4, 8}, barsPerChord = 2, change = 0.1, segmentBars = 16},
		arc = {riser = 0.9, roll = 0.5, impact = 0.9, valley = 0.55, drumless = 0.9, bassOut = 0.7, kickOut = 0.2,
			halftime = 0.15, lift = 0.5,
			curve = {{0, 0.25}, {0.1, 0.4}, {0.22, 0.65}, {0.3, 0.85}, {0.42, 0.8}, {0.46, 0.3}, {0.58, 0.35}, {0.64, 0.95},
				{0.82, 0.75}, {0.92, 0.4}, {1, 0.2}}},
		channels = {
			{role = "drums", wants = {"melodic", "halftime"}},
			{role = "bass", patches = {"bass.wobble", "bass.reese", "bass.808"}, wants = {"melodic", "stepwise"}},
			{role = "pad", patches = {"pad.supersaw", "pad.strings", "pad.choir"}, wants = {"euphoric", "chordal"}},
			{role = "keys", patches = {"keys.piano", "keys.harp"}, chance = 0.6},
			{role = "arp", patches = {"pluck.glass", "pluck.bell", "pluck.trance"}, chance = 0.7, wants = {"euphoric", "arpeggio"}},
			{role = "lead", patches = {"lead.supersaw", "lead.vox", "lead.saw"}, wants = {"hook", "euphoric"}},
			{role = "counter", patches = {"pluck.bell", "keys.vibes"}, chance = 0.5},
			{role = "fx", patches = {"fx.riser", "fx.wind"}},
		}},
	-- Reggae's bones: a skank on the off-beat, a steppers kick, a melodica.
	{id = "dub", name = "Dub", tempo = {136, 142}, swing = {0.08, 0.16},
		snares = {"rimshot", "vintage", "roomy"},
		harmony = {progressions = {{1, 1, 4, 4}, {1, 7, 1, 7}, {1, 4, 1, 5}}, voicing = {0, 2, 4}, barsPerChord = 2},
		arc = {riser = 0.2, roll = 0.1, impact = 0.5, valley = 0.4, drumless = 0.3, bassOut = 0.2, kickOut = 0.5,
			halftime = 0, lift = 0,
			curve = {{0, 0.3}, {0.15, 0.45}, {0.3, 0.65}, {0.45, 0.7}, {0.52, 0.45}, {0.6, 0.72}, {0.8, 0.65}, {0.92, 0.4}, {1, 0.25}}},
		channels = {
			{role = "drums", wants = {"dub", "halftime"}},
			{role = "bass", patches = {"bass.sub", "bass.round", "bass.808"}, wants = {"dub", "walking"}},
			{role = "stab", patches = {"stab.organ", "stab.dub", "stab.piano"}, wants = {"dub", "offbeat"}},
			{role = "keys", patches = {"keys.organ", "keys.clav"}, chance = 0.5, wants = {"dub", "offbeat"}},
			{role = "lead", patches = {"lead.vox", "lead.flute", "lead.square"}, chance = 0.7, wants = {"dub", "offbeat"}},
			{role = "texture", patches = {"texture.tape"}, chance = 0.6},
			{role = "fx", patches = {"fx.siren", "fx.wind"}},
		}},
	-- Mostly pads: soft drums, a long valley, nothing aggressive.
	{id = "chill", name = "Chillstep", tempo = {136, 140}, swing = {0.04, 0.12},
		snares = {"roomy", "vintage", "layered"},
		harmony = {progressions = MELODIC, voicing = {2, 4, 6, 8}, barsPerChord = 2},
		arc = {riser = 0.4, roll = 0.15, impact = 0.5, valley = 0.55, drumless = 0.5, bassOut = 0.4, kickOut = 0.2,
			halftime = 0, lift = 0.2,
			curve = {{0, 0.2}, {0.12, 0.35}, {0.28, 0.55}, {0.4, 0.7}, {0.5, 0.4}, {0.62, 0.75}, {0.8, 0.55}, {0.92, 0.35}, {1, 0.2}}},
		channels = {
			{role = "drums", wants = {"dreamy", "halftime", "sparse"}, gain = 0.85},
			{role = "bass", patches = {"bass.sub", "bass.round"}, wants = {"sub", "pedal"}},
			{role = "pad", patches = {"pad.air", "pad.glass", "pad.warm", "pad.choir"}, wants = {"ambient", "held"}},
			{role = "keys", patches = {"keys.rhodes", "keys.vibes", "keys.harp"}, chance = 0.6},
			{role = "arp", patches = {"pluck.glass", "pluck.string", "pluck.bell"}, chance = 0.7, wants = {"dreamy"}},
			{role = "lead", patches = {"lead.vox", "lead.sine", "lead.pluck"}, chance = 0.8, wants = {"vocal", "dreamy"}},
			{role = "texture", patches = {"texture.shimmer", "texture.air"}},
			{role = "fx", patches = {"fx.wind"}},
		}},
}

return {
	api = 4,
	title = "Dubstep",
	symbol = "speaker.wave.3.fill",
	summary = "Deep, Brostep, Riddim and more at half time",
	defaults = {energy = 0.7, complexity = 0.5, humanize = 0.2, space = 0.35},
	kit = {
		kick = {base = 44, sweep = 140, sweepTime = 0.022, decay = 0.26, drive = 2.4, click = 0.4, length = 0.5},
		snare = {tone = 200, bodyDecay = 0.07, noiseDecay = 0.16, noise = 0.55},
	},
	mix = {duckDepth = 0.35, bass = 1.1, delayFeedback = 0.5},
	set = {modes = {"phrygian", "minor"}, modulations = {2}},
	-- One canvas of 5 minutes at 140: a mix-in, a first drop, a breakdown
	-- (drumless more often than not), a riser, snare roll and silence into a
	-- second drop. Flavours reshape the curve and how much they build.
	arc = {minutes = {4.5, 5.5}, intro = 16, outro = 16, riser = 0.6, roll = 0.5, impact = 0.8, valley = 0.45,
		drumless = 0.6, kickOut = 0.3, halftime = 0.25, lift = 0},
	harmony = {progressions = PROGRESSIONS, voicing = {0, 2, 4}, barsPerChord = 4},
	-- A dub melody sits an octave down.
	roles = {drums = {fills = FILLS}, lead = {octave = -1}},
	flavours = FLAVOURS,
}
