-- Dubstep blocks. ~140 BPM felt at half time: the kick opens the bar, the
-- snare (or clap, or rimshot in the deep records) lands on beat three, and
-- the bass is the record. Flavours: deep, brostep, riddim, melodic, dub,
-- chill. See apps/dnb/BLOCKS.md. Pitch is in scale steps (0 root, 2 third,
-- 4 fifth, 7 octave), so every line works under minor, phrygian, dorian and
-- major and moves with the chord; `w<rate>` is the wobble rate of a note.
-- Risers: dubstep builds with them (8 bars of noise, a snare roll, a vocal
-- call, then a bar of silence), so the fx section writes four.

local blocks = {}
local function add(...) for _, b in ipairs({...}) do table.insert(blocks, b) end end

-- DRUMS ---------------------------------------------------------------
-- The half-time grid at every weight: from a kick and a rim for a DJ intro
-- up to a brostep stomp with a double snare. Kick on 1, snare on step 8.
add(
	{id = "dubstep.drums.001", role = "drums", bars = 2, energy = 0.2, density = 0.1, brightness = 0.3,
	 tags = {"halftime", "mixable", "minimal", "sparse", "deep"},
	 lanes = {{"kick", "X...............|X.........o....."}, {"rim", "........x.......", gain = 0.6}}},
	{id = "dubstep.drums.002", role = "drums", bars = 2, energy = 0.3, density = 0.25, brightness = 0.5,
	 tags = {"halftime", "mixable", "minimal", "sparse"},
	 lanes = {{"kick", "X...............|X..........x...."}, {"snare", "........x.......", gain = 0.8},
		{"hat", "..x...x...x...x.", gain = 0.35}}},
	{id = "dubstep.drums.003", role = "drums", bars = 2, energy = 0.35, density = 0.3, brightness = 0.4,
	 tags = {"halftime", "mixable", "deep", "swung", "sparse"}, flavours = {"deep", "chill", "dub"},
	 lanes = {{"kick", "X...............|X.......x......."}, {"rim", "........x.......", gain = 0.7},
		{"shaker", "x.xxx.xxx.xxx.xx", gain = 0.2}, {"hat", "..x...x...x...x.", gain = 0.3}}},
	{id = "dubstep.drums.004", role = "drums", bars = 1, energy = 0.4, density = 0.35, brightness = 0.5,
	 tags = {"halftime", "mixable", "dub", "straight", "minimal"}, flavours = {"dub", "deep"},
	 lanes = {{"kick", "X...x...X...x...", gain = 0.8}, {"rim", "........x.......", gain = 0.7},
		{"hat", "..x...x...x...x.", gain = 0.35}}},
	{id = "dubstep.drums.005", role = "drums", bars = 4, energy = 0.4, density = 0.3, brightness = 0.35,
	 tags = {"halftime", "mixable", "dreamy", "sparse", "deep"}, flavours = {"chill", "melodic", "deep"},
	 lanes = {{"kick", "X...............|X.........x.....|X...............|X...........x..."},
		{"snare", "........x.......", gain = 0.75}, {"hat", "x...x...x...x...", gain = 0.2},
		{"shaker", "..x...x...x...x.", gain = 0.2, when = "energy"}}},
	{id = "dubstep.drums.006", role = "drums", bars = 2, energy = 0.45, density = 0.45, brightness = 0.5,
	 tags = {"halftime", "mixable", "deep", "swung", "syncopated"}, flavours = {"deep", "dub"},
	 lanes = {{"kick", "X..........x....|X..............."}, {"snare", "........x.......", gain = 0.9},
		{"rim", "...x......x..x..|...x......x.....", gain = 0.4}, {"hat", "..x...x...x...x.", gain = 0.4},
		{"conga", ".....x.........x", gain = 0.35, when = "complexity"}}},
	{id = "dubstep.drums.007", role = "drums", bars = 2, energy = 0.5, density = 0.5, brightness = 0.55,
	 tags = {"halftime", "deep", "swung", "syncopated"}, flavours = {"deep", "melodic", "chill"},
	 lanes = {{"kick", "X...............|X.........x....."}, {"snare", "........X......."},
		{"hat", "X..x..X..x..X..x", gain = 0.5}, {"openHat", "..............x.", gain = 0.4, when = "energy"},
		{"ghost", "......g.......gg", when = "complexity"}, {"rim", "............x...", gain = 0.4, light = false}}},
	{id = "dubstep.drums.008", role = "drums", bars = 1, energy = 0.55, density = 0.45, brightness = 0.5,
	 tags = {"halftime", "dub", "straight"}, flavours = {"dub", "deep"},
	 lanes = {{"kick", "X...x...X...x...", gain = 0.9}, {"snare", "........X......."},
		{"rim", "....x.......x...", gain = 0.45}, {"hat", "..x...x...x...x.", gain = 0.5},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.25, when = "energy"}}},
	{id = "dubstep.drums.009", role = "drums", bars = 2, energy = 0.6, density = 0.55, brightness = 0.6,
	 tags = {"halftime", "melodic", "driving", "swung"}, flavours = {"melodic", "chill"},
	 lanes = {{"kick", "X..x............|X..........x...."}, {"snare", "........X......."},
		{"clap", "........x.......", gain = 0.5}, {"hat", "x.x.x.x.x.x.x.x.", gain = 0.4},
		{"openHat", "..x...x...x...x.", gain = 0.3, when = "energy"}, {"ghost", ".....g.......g..", when = "complexity"}}},
	{id = "dubstep.drums.010", role = "drums", bars = 2, energy = 0.65, density = 0.6, brightness = 0.6,
	 tags = {"halftime", "swung", "syncopated", "deep"}, flavours = {"deep", "melodic"},
	 -- Eighth-note triplets on the hat: the swagger that makes it 140, not 70.
	 lanes = {{"kick", "X...............|X.........x....."}, {"snare", "........X......."},
		{"hat", "x.xx.xx.xx.xx.xx.xx.xx.x", gain = 0.35, div = 24}, {"rim", "............x...", gain = 0.4}}},
	{id = "dubstep.drums.011", role = "drums", bars = 2, energy = 0.7, density = 0.6, brightness = 0.6,
	 tags = {"halftime", "driving", "syncopated"}, flavours = {"brostep", "melodic"},
	 lanes = {{"kick", "X..x............|X.............x."}, {"snare", "........X......."},
		{"clap", "........x.......", gain = 0.5, light = false}, {"hat", "x.x.x.x.x.x.x.x.", gain = 0.4},
		{"openHat", "..........x.....", gain = 0.4, when = "energy"}, {"ghost", ".....g.......g..", when = "complexity"}}},
	{id = "dubstep.drums.012", role = "drums", bars = 1, energy = 0.7, density = 0.5, brightness = 0.55,
	 tags = {"halftime", "riddim", "minimal", "syncopated", "rhythmic"}, flavours = {"riddim"},
	 lanes = {{"kick", "X.....x.....x..."}, {"snare", "........X......."}, {"hat", "..x...x...x...x.", gain = 0.45},
		{"rim", "....x.......x...", gain = 0.35, when = "complexity"}, {"shaker", "xoxoxoxoxoxoxoxo", gain = 0.25, when = "energy"}}},
	{id = "dubstep.drums.013", role = "drums", bars = 2, energy = 0.75, density = 0.45, brightness = 0.5,
	 tags = {"halftime", "riddim", "sparse", "minimal", "aggressive"}, flavours = {"riddim"},
	 -- Almost nothing: the wub is the rhythm and the drums only mark 1 and 3.
	 lanes = {{"kick", "X...............|X.......x......."}, {"snare", "........X......."},
		{"rim", "............x...", gain = 0.4}, {"hat", "x...x...x...x...", gain = 0.3, when = "energy"}}},
	{id = "dubstep.drums.014", role = "drums", bars = 2, energy = 0.85, density = 0.7, brightness = 0.6,
	 tags = {"halftime", "aggressive", "driving", "syncopated"}, flavours = {"brostep", "riddim"},
	 lanes = {{"kick", "X.........x.....|X.....x...x....."}, {"snare", "........X......."},
		{"clap", "........x.......", gain = 0.6}, {"hat", "xoxoxoxoxoxoxoxo", gain = 0.3, light = false},
		{"kick", "...........o....", when = "complexity"}, {"crash", "X...............|................", gain = 0.4, when = "energy"}}},
	{id = "dubstep.drums.015", role = "drums", bars = 4, energy = 0.9, density = 0.8, brightness = 0.65,
	 tags = {"halftime", "aggressive", "busy", "driving"}, flavours = {"brostep", "riddim"},
	 -- Four bars with the fill built in: toms into a crash on the next one.
	 lanes = {{"kick", "X.........x.....|X.....x.........|X.........x.....|X..x..x.....x..."},
		{"snare", "........X.......|........X.......|........X.......|........X..X.XX."},
		{"clap", "........x.......", gain = 0.55}, {"hat", "xoxoxoxoxoxoxoxo", gain = 0.3, light = false},
		{"tomHigh", "................|................|................|............x.x.", gain = 0.5},
		{"tomLow", "................|................|................|..............x.", gain = 0.55},
		{"crash", "X...............|................|................|................", gain = 0.5, when = "energy"}}},
	{id = "dubstep.drums.016", role = "drums", bars = 2, energy = 1.0, density = 0.85, brightness = 0.7,
	 tags = {"halftime", "aggressive", "busy"}, flavours = {"brostep"},
	 -- Snare and clap stacked, a second kick under the snare, open hat on every offbeat.
	 lanes = {{"kick", "X..x....x..x....|X.......x.x...x."}, {"snare", "........X......."}, {"clap", "........X.......", gain = 0.8},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.4}, {"openHat", "..x...x...x...x.", gain = 0.35},
		{"ghost", ".....g.g.....g.g", when = "complexity"}, {"crash", "X...............|................", gain = 0.5}}},
	{id = "dubstep.drums.017", role = "drums", bars = 4, energy = 0.8, density = 0.65, brightness = 0.6,
	 tags = {"halftime", "melodic", "driving", "euphoric"}, flavours = {"melodic"},
	 lanes = {{"kick", "X..x............|X.........x.....|X..x............|X.......x.x....."},
		{"snare", "........X......."}, {"clap", "........x.......", gain = 0.5},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.4}, {"openHat", "..x...x...x...x.", gain = 0.3, when = "energy"},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.2, when = "complexity"}}}
)

-- TOPS ----------------------------------------------------------------
-- A second layer over the kit: triplet hats, shaker, ride, congas.
add(
	{id = "dubstep.tops.001", role = "tops", bars = 1, energy = 0.3, density = 0.3, brightness = 0.9,
	 tags = {"halftime", "mixable", "sparse", "swung"}, lanes = {{"hat", "..x...x...x...x.", gain = 0.35}}},
	{id = "dubstep.tops.002", role = "tops", bars = 1, energy = 0.4, density = 0.55, brightness = 0.9,
	 tags = {"shuffle", "mixable", "swung", "deep"}, flavours = {"deep", "dub", "chill"},
	 lanes = {{"shaker", "x.xxx.xxx.xxx.xx", gain = 0.25}}},
	{id = "dubstep.tops.003", role = "tops", bars = 1, energy = 0.5, density = 0.6, brightness = 0.9,
	 tags = {"swung", "shuffle", "deep", "busy"}, flavours = {"deep", "melodic"},
	 lanes = {{"hat", "x.xx.xx.xx.xx.xx.xx.xx.x", gain = 0.3, div = 24}}},
	{id = "dubstep.tops.004", role = "tops", bars = 2, energy = 0.5, density = 0.4, brightness = 0.7,
	 tags = {"syncopated", "dub", "sparse"}, flavours = {"dub", "deep"},
	 lanes = {{"conga", ".....x.........x|..x.......x....."}, {"rim", "...x......x..x..|...x.........x..", gain = 0.35}}},
	{id = "dubstep.tops.005", role = "tops", bars = 1, energy = 0.65, density = 0.7, brightness = 0.95,
	 tags = {"straight", "driving", "busy"}, flavours = {"brostep", "melodic"},
	 lanes = {{"hat", "x.x.x.x.x.x.x.x.", gain = 0.35}, {"openHat", "..x...x...x...x.", gain = 0.3}}},
	{id = "dubstep.tops.006", role = "tops", bars = 2, energy = 0.7, density = 0.6, brightness = 0.8,
	 tags = {"syncopated", "rhythmic", "aggressive"}, flavours = {"riddim", "brostep"},
	 lanes = {{"rim", "....x.......x...|....x.....x.x...", gain = 0.4}, {"cowbell", "..............x.|................", gain = 0.3},
		{"hat", "xoxoxoxoxoxoxoxo", gain = 0.25}}},
	{id = "dubstep.tops.007", role = "tops", bars = 1, energy = 0.8, density = 0.9, brightness = 1.0,
	 tags = {"driving", "busy", "bright"}, flavours = {"brostep", "riddim", "melodic"},
	 lanes = {{"hat", "xxxxxxxxxxxxxxxx", gain = 0.25}, {"shaker", "xoxoxoxoxoxoxoxo", gain = 0.2}}},
	{id = "dubstep.tops.008", role = "tops", bars = 2, energy = 0.45, density = 0.35, brightness = 0.85,
	 tags = {"dreamy", "sparse", "mixable", "swung"}, flavours = {"chill", "melodic", "deep"},
	 lanes = {{"ride", "x.......x.......|x.......x.....x.", gain = 0.3}, {"shaker", "..x...x...x...x.", gain = 0.2}}}
)

-- BASS ----------------------------------------------------------------
-- The sub holds the root on 1 under the half-time kick; mid-bass notes
-- carry a wobble rate (w1 slow, w2 half-time wub, w3 triplet-ish, w4 fast,
-- w6 yoi chatter). Pitch moves by scale steps; 6 is the flat seventh in a
-- minor key and 1b the phrygian second.
add(
	-- Deep and sub-heavy: one long note, dropping out for the snare.
	{id = "dubstep.bass.001", role = "bass", bars = 2, energy = 0.25, density = 0.15, brightness = 0.05,
	 tags = {"sub", "pedal", "sparse", "deep", "halftime"}, flavours = {"deep", "chill", "dub"},
	 notes = "0:0:14 | 0:0:10"},
	{id = "dubstep.bass.002", role = "bass", bars = 2, energy = 0.35, density = 0.3, brightness = 0.05,
	 tags = {"sub", "sparse", "deep", "dark"}, flavours = {"deep", "chill", "melodic"},
	 notes = "0:0:6 8:0:2? 11:6:4~ | 0:0:6 8:0:2? 11:2:4~"},
	{id = "dubstep.bass.003", role = "bass", bars = 4, energy = 0.4, density = 0.3, brightness = 0.05,
	 tags = {"sub", "pedal", "melancholic", "held"}, flavours = {"chill", "melodic"},
	 notes = "0:0:16 | 0:0:12 12:4:4~ | 0:0:16 | 0:0:8 8:2:6~"},
	{id = "dubstep.bass.004", role = "bass", bars = 2, energy = 0.45, density = 0.4, brightness = 0.15,
	 tags = {"sub", "walking", "dub", "soulful", "syncopated"}, flavours = {"dub", "deep"},
	 notes = "0:0:3 3:0:2? 6:4:2 8:0:3 12:6:2 14:4:2+ | 0:0:3 3:0:2? 6:2:2 8:0:3 12:4:3"},
	{id = "dubstep.bass.005", role = "bass", bars = 2, energy = 0.5, density = 0.4, brightness = 0.1,
	 tags = {"sub", "pluck", "dub", "rhythmic"}, flavours = {"dub", "deep"},
	 -- Reggae bass: the root, a rest where the skank falls, then the fifth and the octave.
	 notes = "0:0:2 3:0:1 6:0:2 8:4:2 11:7:1 12:4:2 | 0:0:2 3:0:1 6:0:2 8:6:2 10:4:2 12:2:2 14:0:2"},
	{id = "dubstep.bass.006", role = "bass", bars = 2, energy = 0.55, density = 0.45, brightness = 0.3,
	 tags = {"wobble", "sub", "deep", "dark"}, flavours = {"deep", "melodic"},
	 notes = "0:0:6w1 6:0:2w4 8:0:4w2 12:1b:4w3~ | 0:0:6w1 6:0:2w4 8:7:2w6 10:6:2w6 12:0:4w2"},
	{id = "dubstep.bass.007", role = "bass", bars = 2, energy = 0.6, density = 0.5, brightness = 0.3,
	 tags = {"wobble", "melodic", "stepwise", "dreamy"}, flavours = {"melodic", "chill"},
	 notes = "0:0:8w1 8:0:4w2 12:4:4w2~ | 0:0:8w1 8:2:4w2 12:0:4w4"},
	{id = "dubstep.bass.008", role = "bass", bars = 4, energy = 0.65, density = 0.5, brightness = 0.35,
	 tags = {"wobble", "melodic", "euphoric", "leap"}, flavours = {"melodic"},
	 notes = "0:0:8w1 8:0:4w2 12:4:4w2~ | 0:0:8w1 8:2:4w2 12:4:4w3 | 0:0:8w1 8:0:4w2 12:6:4w2~ | 0:0:6w1 6:7:2w4 8:6:4w2 12:4:4w4"},
	-- Riddim: one wub, repeated until it is the rhythm.
	{id = "dubstep.bass.009", role = "bass", bars = 2, energy = 0.7, density = 0.55, brightness = 0.45,
	 tags = {"wobble", "riddim", "rhythmic", "minimal", "halftime"}, flavours = {"riddim"},
	 notes = "0:0:3w3 4:0:3w3 8:0:3w3 12:0:2w6 14:0:2w6 | 0:0:3w3 4:0:3w3 8:7:3w3 12:6:2w6 14:0:2w6"},
	{id = "dubstep.bass.010", role = "bass", bars = 1, energy = 0.75, density = 0.6, brightness = 0.5,
	 tags = {"wobble", "riddim", "rhythmic", "minimal", "pedal"}, flavours = {"riddim"},
	 -- A single bar, hammered: wub-wub-wub-rest, the tension is in the repeat.
	 notes = "0:0:3w3 4:0:3w3 8:0:3w3 13:0:2w6"},
	{id = "dubstep.bass.011", role = "bass", bars = 2, energy = 0.75, density = 0.65, brightness = 0.5,
	 tags = {"wobble", "riddim", "syncopated", "aggressive", "stab"}, flavours = {"riddim"},
	 notes = "0:0:2w3 3:0:2w3 6:0:2w3 10:0:3w2 14:0:2w6 | 0:0:2w3 3:0:2w3 6:0:2w3 10:6:3w2 14:7:2w6"},
	{id = "dubstep.bass.012", role = "bass", bars = 2, energy = 0.8, density = 0.7, brightness = 0.55,
	 tags = {"wobble", "aggressive", "rhythmic", "busy"}, flavours = {"brostep", "riddim"},
	 -- The yoi: a wide vowel on the long note, answered by a chatter of fast wubs.
	 notes = "0:0:4w2 4:0:2w4 6:0:2w4 8:0:4w2 12:4:4w3? | 0:0:4w2 4:0:2w4 6:0:2w4 8:6:4w2 12:0:4w6?"},
	{id = "dubstep.bass.013", role = "bass", bars = 2, energy = 0.85, density = 0.75, brightness = 0.6,
	 tags = {"wobble", "aggressive", "syncopated", "busy"}, flavours = {"brostep"},
	 notes = "0:0:3w2 3:0:1w6 4:0:2w4 6:0:2w4 8:0:3w2 11:7:1w6 12:6:2w4 14:4:2w6 | 0:0:3w2 3:0:1w6 4:0:2w4 6:0:2w4 8:0:4w3 12:1b:2w6 14:0:2w6"},
	{id = "dubstep.bass.014", role = "bass", bars = 4, energy = 0.9, density = 0.8, brightness = 0.6,
	 tags = {"wobble", "aggressive", "leap", "busy"}, flavours = {"brostep"},
	 notes = "0:0:6w1 6:0:2w4 8:0:4w2 12:1b:4w3~ | 0:0:6w1 6:0:2w4 8:7:2w6 10:6:2w6 12:0:4w2 | 0:0:4w2 4:0:2w6 6:0:2w6 8:6:4w2 12:4:2w4 14:6:2w4 | 0:0:2w6 2:0:2w6 4:0:2w6 6:0:2w6 8:7:4w3 12:0:4w1"},
	{id = "dubstep.bass.015", role = "bass", bars = 2, energy = 0.95, density = 0.9, brightness = 0.7,
	 tags = {"wobble", "aggressive", "busy", "syncopated"}, flavours = {"brostep", "riddim"},
	 -- Growl with a screech: fast triplets that climb to the octave and fall back.
	 notes = "0:0:2w4 2:0:2w4 4:0:2w6 6:0:2w6 8:0:2w4 10:7:2w6 12:6:2w6 14:4:2w6 | 0:0:2w4 2:0:2w4 4:0:2w6 6:0:2w6 8:7:4w3 12:6:2w6 14:0:2w6"},
	{id = "dubstep.bass.016", role = "bass", bars = 2, energy = 0.6, density = 0.5, brightness = 0.25,
	 tags = {"sub", "pluck", "syncopated", "deep", "tense"}, flavours = {"deep", "brostep"},
	 notes = "0:0:2 3:0:1 6:0:2 8:0:2? 10:6:2 12:0:2 | 0:0:2 3:0:1 6:0:2 8:2:2? 10:4:2 12:6:3"},
	{id = "dubstep.bass.017", role = "bass", bars = 1, energy = 0.3, density = 0.2, brightness = 0.05,
	 tags = {"sub", "pedal", "sparse", "minimal"}, notes = "0:0:10 11:0:1?"}
)

-- PAD ------------------------------------------------------------------
add(
	{id = "dubstep.pad.001", role = "pad", bars = 4, energy = 0.2, density = 0.1, brightness = 0.3,
	 tags = {"held", "ambient", "dark", "dreamy", "sparse"}, hold = true},
	{id = "dubstep.pad.002", role = "pad", bars = 2, energy = 0.35, density = 0.25, brightness = 0.4,
	 tags = {"chordal", "melancholic", "sparse"}, flavours = {"chill", "melodic", "deep"}, comp = "0:12 12:4"},
	{id = "dubstep.pad.003", role = "pad", bars = 2, energy = 0.5, density = 0.35, brightness = 0.5,
	 tags = {"chordal", "euphoric", "rhythmic"}, flavours = {"melodic", "chill"}, comp = "0:6 6:6 12:4"},
	{id = "dubstep.pad.004", role = "pad", bars = 1, energy = 0.65, density = 0.5, brightness = 0.6,
	 tags = {"chordal", "euphoric", "rhythmic", "bright"}, flavours = {"melodic"}, comp = "0:3 3:3 6:2 10:3 13:3"},
	{id = "dubstep.pad.005", role = "pad", bars = 4, energy = 0.3, density = 0.1, brightness = 0.35,
	 tags = {"held", "ambient", "tense", "dark"}, flavours = {"deep", "brostep", "riddim"}, hold = true},
	{id = "dubstep.pad.006", role = "pad", bars = 1, energy = 0.75, density = 0.4, brightness = 0.7,
	 tags = {"chordal", "held", "euphoric", "bright"}, flavours = {"melodic", "brostep"}, comp = "0:8 8:8!"}
)

-- KEYS -----------------------------------------------------------------
add(
	{id = "dubstep.keys.001", role = "keys", bars = 1, energy = 0.25, density = 0.15, brightness = 0.5,
	 tags = {"sparse", "melancholic", "chordal", "dreamy"}, flavours = {"chill", "melodic", "deep"}, comp = "0:8 10:4"},
	{id = "dubstep.keys.002", role = "keys", bars = 1, energy = 0.4, density = 0.3, brightness = 0.5,
	 tags = {"chordal", "soulful", "syncopated"}, flavours = {"chill", "melodic"}, comp = "0:3 6:2 10:4"},
	{id = "dubstep.keys.003", role = "keys", bars = 1, energy = 0.5, density = 0.4, brightness = 0.5,
	 tags = {"chordal", "dub", "offbeat", "warm"}, flavours = {"dub"}, comp = "4:2 12:2"},
	{id = "dubstep.keys.004", role = "keys", bars = 1, energy = 0.6, density = 0.5, brightness = 0.6,
	 tags = {"chordal", "euphoric", "rhythmic"}, flavours = {"melodic"}, comp = "0:2 3:2 6:2 10:2 13:3"},
	{id = "dubstep.keys.005", role = "keys", bars = 1, energy = 0.7, density = 0.6, brightness = 0.6,
	 tags = {"chordal", "euphoric", "busy", "rhythmic"}, flavours = {"melodic", "brostep"},
	 comp = "0:3 3:3 6:2 10:3 13:2?"},
	{id = "dubstep.keys.006", role = "keys", bars = 1, energy = 0.3, density = 0.2, brightness = 0.55,
	 tags = {"sparse", "dub", "warm", "swung"}, flavours = {"dub", "deep", "chill"}, comp = "2:2 14:2?"}
)

-- STAB -----------------------------------------------------------------
-- Dub chord stabs: one hit on the "and" of 2, left to echo.
add(
	{id = "dubstep.stab.001", role = "stab", bars = 1, energy = 0.3, density = 0.1, brightness = 0.5,
	 tags = {"sparse", "dub", "offbeat", "deep"}, flavours = {"deep", "dub", "chill"}, comp = "6:1"},
	{id = "dubstep.stab.002", role = "stab", bars = 1, energy = 0.45, density = 0.2, brightness = 0.5,
	 tags = {"sparse", "dub", "offbeat", "syncopated"}, flavours = {"deep", "dub", "riddim"}, comp = "6:1 14:1"},
	{id = "dubstep.stab.003", role = "stab", bars = 1, energy = 0.5, density = 0.35, brightness = 0.55,
	 tags = {"dub", "offbeat", "rhythmic", "soulful"}, flavours = {"dub"}, comp = "4:1 12:1"},
	{id = "dubstep.stab.004", role = "stab", bars = 1, energy = 0.6, density = 0.45, brightness = 0.55,
	 tags = {"dub", "offbeat", "busy", "rhythmic"}, flavours = {"dub"}, comp = "2:1 6:1 10:1 14:1"},
	{id = "dubstep.stab.005", role = "stab", bars = 1, energy = 0.65, density = 0.4, brightness = 0.7,
	 tags = {"stab", "aggressive", "syncopated", "rhythmic"}, flavours = {"brostep", "riddim"},
	 comp = "3:1 6:1 10:1? 14:1"},
	{id = "dubstep.stab.006", role = "stab", bars = 1, energy = 0.75, density = 0.5, brightness = 0.8,
	 tags = {"stab", "aggressive", "bright", "rhythmic"}, flavours = {"brostep"}, comp = "0:1! 3:1 6:1 10:1 14:1?"},
	{id = "dubstep.stab.007", role = "stab", bars = 1, energy = 0.8, density = 0.5, brightness = 0.75,
	 tags = {"stab", "tense", "syncopated", "hook"}, flavours = {"riddim", "brostep"},
	 comp = "6:1 10:1? 14:2!"},
	{id = "dubstep.stab.008", role = "stab", bars = 1, energy = 0.4, density = 0.3, brightness = 0.5,
	 tags = {"chordal", "warm", "offbeat", "sparse"}, flavours = {"melodic", "chill", "deep"}, comp = "6:2 14:2"},
	{id = "dubstep.stab.009", role = "stab", bars = 1, energy = 0.55, density = 0.3, brightness = 0.5,
	 tags = {"dub", "sparse", "syncopated", "swung"}, flavours = {"dub", "deep"},
	 comp = "6:1 14:1+"}
)

-- ARP ------------------------------------------------------------------
-- Chord tones counted from 1 (lowest) with higher numbers climbing an octave.
add(
	{id = "dubstep.arp.001", role = "arp", bars = 1, energy = 0.3, density = 0.25, brightness = 0.7,
	 tags = {"arpeggio", "dreamy", "sparse", "stepwise"}, flavours = {"chill", "melodic"},
	 order = {1, 2, 3, 2}, rate = 4, gate = 0.8, mask = "XXXXXXXXXXXXXXXX", octave = 2},
	{id = "dubstep.arp.002", role = "arp", bars = 1, energy = 0.4, density = 0.4, brightness = 0.75,
	 tags = {"arpeggio", "melancholic", "stepwise"}, flavours = {"chill", "melodic", "deep"},
	 order = {1, 3, 2, 3, 4, 3}, rate = 2, gate = 0.6, mask = "XXXXXXXXXXXXXXXX", octave = 1},
	{id = "dubstep.arp.003", role = "arp", bars = 1, energy = 0.5, density = 0.5, brightness = 0.8,
	 tags = {"arpeggio", "euphoric", "rhythmic"}, flavours = {"melodic"},
	 order = {1, 2, 3, 4, 3, 2}, rate = 2, gate = 0.5, mask = "XXxxXXxxXXxxXXxx", octave = 1},
	{id = "dubstep.arp.004", role = "arp", bars = 1, energy = 0.6, density = 0.6, brightness = 0.8,
	 tags = {"arpeggio", "driving", "bright", "busy"}, flavours = {"melodic", "chill"},
	 order = {1, 3, 2, 4}, rate = 1, gate = 0.5, mask = "XXxxXXxxXXxxXXxx", octave = 1},
	{id = "dubstep.arp.005", role = "arp", bars = 2, energy = 0.65, density = 0.5, brightness = 0.7,
	 tags = {"arpeggio", "syncopated", "playful", "leap"}, flavours = {"brostep", "melodic"},
	 order = {1, 4, 2, 4, 3, 4, 2, 3}, rate = 2, gate = 0.4, mask = "XX.XxX.XXx.XxX.X", octave = 2},
	{id = "dubstep.arp.006", role = "arp", bars = 1, energy = 0.7, density = 0.7, brightness = 0.85,
	 tags = {"arpeggio", "aggressive", "tense", "busy"}, flavours = {"brostep", "riddim"},
	 order = {1, 1, 3, 1, 4, 1, 3, 2}, rate = 1, gate = 0.35, mask = "XXXxXXXxXXXxXXXx", octave = 2},
	{id = "dubstep.arp.007", role = "arp", bars = 1, energy = 0.35, density = 0.3, brightness = 0.6,
	 tags = {"arpeggio", "dub", "sparse", "warm"}, flavours = {"dub", "deep"},
	 order = {1, 3, 2}, rate = 4, gate = 0.9, mask = "X.xXX.xXX.xXX.xX", octave = 1},
	{id = "dubstep.arp.008", role = "arp", bars = 2, energy = 0.8, density = 0.8, brightness = 0.9,
	 tags = {"arpeggio", "euphoric", "bright", "busy"}, flavours = {"melodic"},
	 order = {1, 2, 3, 4, 3, 2, 1, 2, 3, 4, 5, 4, 3, 2}, rate = 1, gate = 0.45, mask = "XXXXXXXXXXXXXXXX", octave = 1}
)

-- LEAD -----------------------------------------------------------------
-- Sparse hooks that leave the half-time room to breathe: long notes, one
-- idea stated, repeated, turned, brought home. Dubstep leads sit an octave
-- down in this style.
add(
	{id = "dubstep.lead.001", role = "lead", bars = 4, energy = 0.25, density = 0.2, brightness = 0.4,
	 tags = {"hook", "held", "melancholic", "sparse", "stepwise"}, flavours = {"chill", "deep"},
	 notes = "0:4:8 8:6:6~ | 0:7:10 12:6:4~ | 0:4:8 8:2:6~ | 0:0:12"},
	{id = "dubstep.lead.002", role = "lead", bars = 4, energy = 0.35, density = 0.3, brightness = 0.45,
	 tags = {"hook", "dreamy", "stepwise", "vocal"}, flavours = {"chill", "melodic"},
	 notes = "0:2:6 6:4:2~ 8:2:4 12:0:4 | 0:2:6 6:4:2~ 8:6:8 | 0:7:6 6:6:2~ 8:4:4 12:2:4 | 0:1:4 4:2:4~ 8:0:8"},
	{id = "dubstep.lead.003", role = "lead", bars = 2, energy = 0.4, density = 0.35, brightness = 0.5,
	 tags = {"hook", "dub", "answer", "soulful"}, flavours = {"dub", "deep"},
	 notes = "2:7:2 6:6:2 10:4:2 14:6:2 | 2:7:2 6:4:2 10:2:2 14:0:2"},
	{id = "dubstep.lead.004", role = "lead", bars = 4, energy = 0.5, density = 0.4, brightness = 0.55,
	 tags = {"hook", "melancholic", "stepwise", "held"}, flavours = {"melodic", "chill"},
	 notes = "0:7:4 4:6:4 8:5:4 12:4:4 | 0:4:8 10:2:2 12:3:4 | 0:6:4 4:5:4 8:4:4 12:2:4 | 0:2:4 4:1:4 8:0:8"},
	{id = "dubstep.lead.005", role = "lead", bars = 2, energy = 0.5, density = 0.3, brightness = 0.6,
	 tags = {"hook", "dub", "call", "sparse", "tense"}, flavours = {"dub", "riddim"},
	 notes = "0:7:3 3:6:1 4:4:4 | 8:2:2 10:3:2 12:4:4"},
	{id = "dubstep.lead.006", role = "lead", bars = 4, energy = 0.6, density = 0.45, brightness = 0.65,
	 tags = {"hook", "euphoric", "leap", "bright"}, flavours = {"melodic"},
	 notes = "0:4:6 6:5:2 8:4:4 12:2:4 | 0:4:6 6:5:2 8:6:4 12:7:4 | 0:8:6 6:7:2 8:6:4 12:4:4 | 0:4:4 4:2:4 8:0:8~"},
	{id = "dubstep.lead.007", role = "lead", bars = 4, energy = 0.65, density = 0.5, brightness = 0.7,
	 tags = {"hook", "euphoric", "stepwise", "rhythmic"}, flavours = {"melodic"},
	 notes = "0:0:4 4:2:4 8:4:6 14:6:2 | 0:7:8 8:6:4 12:4:4 | 0:2:4 4:4:4 8:6:6 14:7:2 | 0:9:6 6:8:2 8:7:8~"},
	{id = "dubstep.lead.008", role = "lead", bars = 2, energy = 0.7, density = 0.5, brightness = 0.75,
	 tags = {"riff", "aggressive", "rhythmic", "tense"}, flavours = {"brostep", "riddim"}, follow = "key",
	 notes = "0:0:2 3:0:1 6:2:2 8:0:2 11:6:2 14:7:2 | 0:0:2 3:0:1 6:2:2 8:3:2 11:2:2 14:0:2"},
	{id = "dubstep.lead.009", role = "lead", bars = 1, energy = 0.75, density = 0.4, brightness = 0.8,
	 tags = {"riff", "aggressive", "rhythmic", "hook", "sparse"}, flavours = {"brostep"}, follow = "key",
	 -- Morse-code insistence: three short, one long, repeated.
	 notes = "0:4:1 2:4:1 4:4:1 6:6:6 14:4:2"},
	{id = "dubstep.lead.010", role = "lead", bars = 4, energy = 0.8, density = 0.6, brightness = 0.85,
	 tags = {"hook", "euphoric", "leap", "busy", "bright"}, flavours = {"melodic", "brostep"},
	 notes = "0:9:2 2:7:2 4:4:2 6:2:2 8:7:2 10:4:2 12:2:2 14:0:2 | 0:8:2 2:6:2 4:4:2 6:1:2 8:4:8 | 0:9:2 2:7:2 4:4:2 6:2:2 8:7:2 10:4:2 12:2:2 14:0:2 | 0:2:4 4:4:4 8:0:8"},
	{id = "dubstep.lead.011", role = "lead", bars = 4, energy = 0.45, density = 0.3, brightness = 0.5,
	 tags = {"hook", "vocal", "dreamy", "sparse"}, flavours = {"chill", "deep", "melodic"},
	 notes = "0:4:8 8:6:6~ | 0:7:10 12:6:4~ | 0:4:6 6:2:2~ 8:4:8 | 0:2:4 4:0:12"},
	{id = "dubstep.lead.012", role = "lead", bars = 2, energy = 0.85, density = 0.55, brightness = 0.9,
	 tags = {"riff", "aggressive", "bright", "leap"}, flavours = {"brostep"}, follow = "key",
	 notes = "0:7:2 2:9:2 4:7:2 6:4:4 12:6:2 14:7:2 | 0:7:2 2:9:2 4:11:2 6:9:4 12:7:4"},
	{id = "dubstep.lead.013", role = "lead", bars = 2, energy = 0.55, density = 0.35, brightness = 0.55,
	 tags = {"hook", "dub", "offbeat", "rhythmic"}, flavours = {"dub", "riddim"}, follow = "key",
	 notes = "2:7:2 6:6:2 10:4:2 14:6:2 | 2:7:2 6:9:2 10:7:2 14:4:2"},
	{id = "dubstep.lead.014", role = "lead", bars = 4, energy = 0.3, density = 0.15, brightness = 0.4,
	 tags = {"hook", "held", "dark", "sparse", "melancholic"}, flavours = {"deep", "chill", "riddim"},
	 notes = "0:4:12 | 0:3:8 8:2:8~ | 0:4:12 | 0:1:6 6:0:10"}
)

-- COUNTER --------------------------------------------------------------
-- Answers in the gaps a lead leaves: short phrases on beats 3-4.
add(
	{id = "dubstep.counter.001", role = "counter", bars = 2, energy = 0.3, density = 0.15, brightness = 0.7,
	 tags = {"answer", "sparse", "dreamy", "ambient"}, flavours = {"chill", "melodic", "deep"},
	 notes = "10:7:2 14:4:2 | 10:6:2 14:2:2"},
	{id = "dubstep.counter.002", role = "counter", bars = 2, energy = 0.45, density = 0.3, brightness = 0.7,
	 tags = {"answer", "stepwise", "bright", "playful"}, flavours = {"melodic", "chill"},
	 notes = "8:4:2 10:6:2 12:7:4 | 8:6:2 10:4:2 12:2:4"},
	{id = "dubstep.counter.003", role = "counter", bars = 2, energy = 0.5, density = 0.3, brightness = 0.6,
	 tags = {"answer", "dub", "offbeat", "sparse"}, flavours = {"dub", "deep"}, follow = "key",
	 notes = "6:9:1 14:7:2 | 6:9:1 10:7:1 14:4:2"},
	{id = "dubstep.counter.004", role = "counter", bars = 4, energy = 0.6, density = 0.45, brightness = 0.8,
	 tags = {"answer", "leap", "euphoric"}, flavours = {"melodic"},
	 notes = "8:7:2 10:9:2 12:7:4 | 12:4:4 | 8:7:2 10:9:2 12:11:4 | 8:9:2 10:7:2 12:4:4"},
	{id = "dubstep.counter.005", role = "counter", bars = 2, energy = 0.7, density = 0.5, brightness = 0.85,
	 tags = {"answer", "rhythmic", "tense", "aggressive"}, flavours = {"brostep", "riddim"}, follow = "key",
	 notes = "10:6:1 12:4:1 14:6:1 | 10:6:1 12:7:1 14:9:2"},
	{id = "dubstep.counter.006", role = "counter", bars = 1, energy = 0.4, density = 0.2, brightness = 0.75,
	 tags = {"answer", "sparse", "bright", "hypnotic"}, notes = "12:7:2 14:9:2"}
)

-- TEXTURE --------------------------------------------------------------
-- Held voices as semitones over the root.
add(
	{id = "dubstep.texture.001", role = "texture", bars = 4, energy = 0.1, density = 0.05, brightness = 0.2,
	 tags = {"ambient", "dark", "deep"}, voices = {0, 7}, every = 4},
	{id = "dubstep.texture.002", role = "texture", bars = 4, energy = 0.2, density = 0.1, brightness = 0.4,
	 tags = {"ambient", "dreamy"}, flavours = {"chill", "melodic", "deep"}, voices = {0, 7, 12}, every = 4},
	{id = "dubstep.texture.003", role = "texture", bars = 8, energy = 0.25, density = 0.1, brightness = 0.3,
	 tags = {"ambient", "tense", "dark"}, flavours = {"brostep", "riddim", "deep"}, voices = {0, 6}, every = 8},
	{id = "dubstep.texture.004", role = "texture", bars = 2, energy = 0.3, density = 0.15, brightness = 0.5,
	 tags = {"ambient", "warm", "dub"}, flavours = {"dub", "deep"}, voices = {0, 7, 10}, every = 2},
	{id = "dubstep.texture.005", role = "texture", bars = 4, energy = 0.35, density = 0.2, brightness = 0.6,
	 tags = {"ambient", "melancholic", "held"}, flavours = {"chill", "melodic"}, voices = {3, 7, 10}, every = 4},
	{id = "dubstep.texture.006", role = "texture", bars = 4, energy = 0.5, density = 0.3, brightness = 0.7,
	 tags = {"ambient", "tense", "hypnotic"}, flavours = {"brostep", "riddim"}, voices = {0, 1, 7}, every = 4}
)

-- FX -------------------------------------------------------------------
-- Dubstep builds: a riser to the drop, then a bar of silence and a sub boom.
add(
	{id = "dubstep.fx.001", role = "fx", bars = 8, energy = 0.5, density = 0.4, brightness = 0.8,
	 tags = {"riser", "tense"}, kind = "riser"},
	{id = "dubstep.fx.002", role = "fx", bars = 4, energy = 0.6, density = 0.5, brightness = 0.9,
	 tags = {"riser", "tense", "bright"}, kind = "riser"},
	{id = "dubstep.fx.003", role = "fx", bars = 8, energy = 0.7, density = 0.6, brightness = 0.85,
	 tags = {"riser", "aggressive", "busy"}, flavours = {"brostep", "riddim"}, kind = "riser"},
	{id = "dubstep.fx.004", role = "fx", bars = 4, energy = 0.35, density = 0.2, brightness = 0.6,
	 tags = {"riser", "dreamy", "ambient"}, flavours = {"chill", "melodic", "deep"}, kind = "riser"},
	{id = "dubstep.fx.005", role = "fx", bars = 1, energy = 0.7, density = 0.3, brightness = 0.1,
	 tags = {"impact", "deep", "sub"}, kind = "impact"},
	{id = "dubstep.fx.006", role = "fx", bars = 1, energy = 0.9, density = 0.5, brightness = 0.4,
	 tags = {"impact", "aggressive"}, flavours = {"brostep", "riddim"}, kind = "impact"},
	{id = "dubstep.fx.007", role = "fx", bars = 1, energy = 0.5, density = 0.2, brightness = 0.3,
	 tags = {"impact", "dark", "sparse"}, flavours = {"deep", "dub", "chill"}, kind = "impact"},
	{id = "dubstep.fx.008", role = "fx", bars = 4, energy = 0.3, density = 0.2, brightness = 0.5,
	 tags = {"downlifter", "dreamy"}, kind = "downlifter"},
	{id = "dubstep.fx.009", role = "fx", bars = 2, energy = 0.5, density = 0.3, brightness = 0.4,
	 tags = {"downlifter", "dark", "aggressive"}, flavours = {"brostep", "riddim", "deep"}, kind = "downlifter"},
	{id = "dubstep.fx.010", role = "fx", bars = 1, energy = 0.6, density = 0.4, brightness = 0.9,
	 tags = {"crash", "bright"}, kind = "crash"}
)

return blocks
