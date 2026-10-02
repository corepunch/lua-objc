-- Trance blocks. 132-145 BPM, a kick on every beat, the bass on the
-- off-beats (classic) or rolling in 16ths (psy, tech) between the kicks,
-- supersaw chords two bars to a chord, a gated pluck arpeggio, and one
-- anthem that is stated, answered and brought home. Pitch is in scale
-- steps so every line works in minor, dorian, phrygian and the major
-- modes, and under i-VI-III-VII and its relatives.
--
-- Trance uses risers (a pitched sweep, a noise riser, a snare roll), so
-- this file writes them; the psy flavours simply never ask for them.
local list = {}

local function add(role, number, spec)
	spec.id = string.format("trance.%s.%03d", role, number)
	spec.role = role
	table.insert(list, spec)
end

-- DRUMS ---------------------------------------------------------------
-- The four-floor kick is the one constant; energy climbs by adding the
-- clap, the off-beat open hat, 16th hats, ride and shaker. The first
-- blocks carry no tonal content and no dependence on bass or lead: they
-- are the DJ intro and outro of a track.

-- Kick alone, a ghost of closed hat: the quietest thing a mix can start on.
add("drums", 1, {bars = 1, energy = 0.2, density = 0.1, brightness = 0.3,
	tags = {"fourfloor", "minimal", "sparse", "mixable"},
	lanes = {{"kick", "X...X...X...X..."}, {"hat", "..o...o...o...o.", gain = 0.25}}})
-- Kick and off-beat open hat: the trance heartbeat.
add("drums", 2, {bars = 1, energy = 0.3, density = 0.2, brightness = 0.5,
	tags = {"fourfloor", "straight", "sparse", "mixable"},
	lanes = {{"kick", "X...X...X...X..."}, {"openHat", "..x...x...x...x.", gain = 0.45}}})
-- Progressive intro: kick, shaker 16ths, a rim every other bar.
add("drums", 3, {bars = 2, energy = 0.35, density = 0.35, brightness = 0.6,
	tags = {"fourfloor", "minimal", "hypnotic", "mixable"}, flavours = {"progressive", "dream", "tech"},
	lanes = {{"kick", "X...X...X...X..."}, {"shaker", "xoxoxoxoxoxoxoxo", gain = 0.25},
		{"hat", "..x...x...x...x.", gain = 0.3}, {"rim", "................|............x...", gain = 0.3}}})
-- Kick, clap on 2 and 4 and the open hat: the groove before anything else.
add("drums", 4, {bars = 1, energy = 0.45, density = 0.4, brightness = 0.55,
	tags = {"fourfloor", "straight", "mixable"},
	lanes = {{"kick", "X...X...X...X..."}, {"clap", "....x.......x...", gain = 0.65},
		{"openHat", "..x...x...x...x.", gain = 0.45}}})
-- Psy intro: tight kick with a lone offbeat hat and a clave that wanders.
add("drums", 5, {bars = 2, energy = 0.4, density = 0.3, brightness = 0.6,
	tags = {"fourfloor", "minimal", "hypnotic", "mixable"}, flavours = {"psy", "goa", "tech", "acid"},
	lanes = {{"kick", "X...X...X...X..."}, {"hat", "..x...x...x...x.", gain = 0.35},
		{"clave", "...x..x....x....|...x.......x..x.", gain = 0.28}}})
-- Kick on 1 only and a washed hat: the stripped bar before a drop.
add("drums", 6, {bars = 1, energy = 0.22, density = 0.15, brightness = 0.4,
	tags = {"minimal", "sparse", "mixable"},
	lanes = {{"kick", "X...............", gain = 0.9}, {"openHat", "..............x.", gain = 0.3},
		{"hat", "o.o.o.o.o.o.o.o.", gain = 0.18}}})
-- The classic drop: kick, clap, off-beat open hat, 16th hats, ride lifting.
add("drums", 7, {bars = 1, energy = 0.7, density = 0.6, brightness = 0.65,
	tags = {"fourfloor", "straight", "driving", "euphoric"}, flavours = {"uplifting", "dream", "progressive"},
	lanes = {{"kick", "X...X...X...X..."}, {"clap", "....X.......X...", gain = 0.75},
		{"openHat", "..x...x...x...x.", gain = 0.5}, {"hat", "xo.oxo.oxo.oxo.o", gain = 0.28},
		{"ride", "..x...x...x...x.", gain = 0.3, when = "energy"},
		{"shaker", "...x...x...x...x", gain = 0.28, when = "complexity"}}})
-- Uplifting full: the same with a snare layered on the clap and a fill every second bar.
add("drums", 8, {bars = 2, energy = 0.85, density = 0.75, brightness = 0.7,
	tags = {"fourfloor", "driving", "euphoric", "busy"}, flavours = {"uplifting"},
	lanes = {{"kick", "X...X...X...X..."}, {"clap", "....X.......X...", gain = 0.8},
		{"snare", "....x.......x...|....x.......x.og", gain = 0.5},
		{"openHat", "..X...X...X...X.", gain = 0.55}, {"hat", "xoxoxoxoxoxoxoxo", gain = 0.26},
		{"ride", "..x...x...x...x.", gain = 0.32, when = "energy"},
		{"tambourine", "x.x.x.x.x.x.x.x.", gain = 0.24, when = "complexity"}}})
-- Progressive plateau: two bars, a swung shaker and a rim off the grid.
add("drums", 9, {bars = 2, energy = 0.6, density = 0.55, brightness = 0.55,
	tags = {"fourfloor", "hypnotic", "swung", "deep"}, flavours = {"progressive", "dream"},
	lanes = {{"kick", "X...X...X...X..."}, {"clap", "....x.......x...", gain = 0.6},
		{"hat", "..x...x...x...x.", gain = 0.4}, {"shaker", "xoxoxoxoxoxoxoxo", gain = 0.28},
		{"rim", "............x...|.......x....x...", gain = 0.35, when = "complexity"},
		{"openHat", "..x...x...x...x.", gain = 0.3, when = "energy"}}})
-- Psy: 16th offbeat hats in pairs, the snare as a rim, the kick a wall.
add("drums", 10, {bars = 1, energy = 0.78, density = 0.65, brightness = 0.7,
	tags = {"fourfloor", "driving", "hypnotic", "rolling"}, flavours = {"psy", "goa"},
	lanes = {{"kick", "X...X...X...X..."}, {"snare", "....x.......x...", gain = 0.5},
		{"hat", "..xx..xx..xx..xx", gain = 0.35}, {"openHat", "..x...x...x...x.", gain = 0.4},
		{"clave", "...x..x....x..x.", gain = 0.28, when = "complexity"},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.22, when = "energy"}}})
-- Tech trance: two bars, a kick that stutters at the end of the second, closed hats accented.
add("drums", 11, {bars = 2, energy = 0.85, density = 0.7, brightness = 0.65,
	tags = {"fourfloor", "driving", "busy", "syncopated"}, flavours = {"tech", "acid"},
	lanes = {{"kick", "X...X...X...X...|X...X...X...X.x."}, {"clap", "....X.......X...", gain = 0.85},
		{"hat", "xoXoxoXoxoXoxoXo", gain = 0.32}, {"rim", "...x..x....x..x.", gain = 0.38, when = "complexity"},
		{"ride", "x.x.x.x.x.x.x.x.", gain = 0.28, when = "energy"}}})
-- Dream: the kick soft, the clap a breath late, the tambourine held back.
add("drums", 12, {bars = 2, energy = 0.5, density = 0.45, brightness = 0.5,
	tags = {"fourfloor", "straight", "warm", "dreamy"}, flavours = {"dream", "uplifting"},
	lanes = {{"kick", "X...X...X...X...", gain = 0.92}, {"clap", "....x.......x...", gain = 0.6},
		{"openHat", "..x...x...x...x.", gain = 0.38}, {"tambourine", "x.x.x.x.x.x.x.x.", gain = 0.28, when = "energy"},
		{"snare", "..............og|............g.og", gain = 0.5, when = "complexity"}}})
-- Peak: four bars, snare roll in the last bar, crash on the one.
add("drums", 13, {bars = 4, energy = 1.0, density = 0.9, brightness = 0.8,
	tags = {"fourfloor", "driving", "busy", "euphoric"}, flavours = {"uplifting", "tech"},
	lanes = {{"kick", "X...X...X...X...|X...X...X...X...|X...X...X...X...|X...X...X...X..."},
		{"clap", "....X.......X...|....X.......X...|....X.......X...|................"},
		{"snare", "................|................|................|x...x...x.x.xxxx", gain = 0.65},
		{"openHat", "..x...x...x...x.|..x...x...x...x.|..x...x...x...x.|................", gain = 0.5},
		{"hat", "xoxoxoxoxoxoxoxo", gain = 0.26},
		{"ride", "..x...x...x...x.", gain = 0.3},
		{"crash", "X...............|................|................|................", gain = 0.7}}})
-- Acid trance: a minimal bounce, rim and cowbell for the 303 to talk over.
add("drums", 14, {bars = 2, energy = 0.55, density = 0.5, brightness = 0.6,
	tags = {"fourfloor", "minimal", "syncopated", "hypnotic"}, flavours = {"acid", "tech", "psy"},
	lanes = {{"kick", "X...X...X...X..."}, {"clap", "....x.......x...", gain = 0.7},
		{"hat", "..x...x...x...x.", gain = 0.4}, {"rim", "...x..x....x..x.|..x....x...x..x.", gain = 0.32},
		{"cowbell", "................|..........x.....", gain = 0.2, when = "complexity"}}})
-- Toms under the kick: a tribal Goa groove that stays sparse.
add("drums", 15, {bars = 2, energy = 0.5, density = 0.5, brightness = 0.5,
	tags = {"fourfloor", "hypnotic", "swung", "dark"}, flavours = {"goa", "psy", "progressive"},
	lanes = {{"kick", "X...X...X...X..."}, {"tomLow", "..x....x....x...|...x....x.....x.", gain = 0.4},
		{"tomMid", ".......x........|..........x.....", gain = 0.35, when = "complexity"},
		{"hat", "..x...x...x...x.", gain = 0.33}, {"shaker", "xoxoxoxoxoxoxoxo", gain = 0.22}}})
-- A tight drive: kick and 16th hat only, for the second half of a long drop.
add("drums", 16, {bars = 1, energy = 0.62, density = 0.5, brightness = 0.7,
	tags = {"fourfloor", "straight", "driving", "minimal"},
	lanes = {{"kick", "X...X...X...X..."}, {"hat", "xxxxxxxxxxxxxxxx", gain = 0.22},
		{"openHat", "..x...x...x...x.", gain = 0.42}, {"clap", "....x.......x...", gain = 0.55, light = false}}})

-- TOPS ----------------------------------------------------------------
-- A second layer over the kit: no kick of its own.
add("tops", 1, {bars = 1, energy = 0.4, density = 0.4, brightness = 0.9,
	tags = {"straight", "driving"},
	lanes = {{"openHat", "..x...x...x...x.", gain = 0.5}}})
add("tops", 2, {bars = 1, energy = 0.5, density = 0.7, brightness = 0.9,
	tags = {"rolling", "busy", "hypnotic"},
	lanes = {{"hat", "xxxxxxxxxxxxxxxx", gain = 0.2}, {"shaker", "xoxoxoxoxoxoxoxo", gain = 0.25}}})
add("tops", 3, {bars = 2, energy = 0.45, density = 0.35, brightness = 0.7,
	tags = {"syncopated", "sparse", "playful"}, flavours = {"progressive", "tech", "acid", "dream"},
	lanes = {{"rim", "...x..x....x..x.|..x....x...x..x.", gain = 0.35}, {"tambourine", "x.x.x.x.x.x.x.x.", gain = 0.2}}})
add("tops", 4, {bars = 2, energy = 0.6, density = 0.55, brightness = 0.7,
	tags = {"hypnotic", "swung", "dark"}, flavours = {"psy", "goa"},
	lanes = {{"conga", "..x.x...o.x.x...|..x...x.o...x.x.", gain = 0.35},
		{"clave", "...x..x....x..x.", gain = 0.28}, {"hat", "..xx..xx..xx..xx", gain = 0.3}}})
add("tops", 5, {bars = 1, energy = 0.7, density = 0.5, brightness = 0.85,
	tags = {"driving", "euphoric", "bright"}, flavours = {"uplifting", "dream"},
	lanes = {{"ride", "..x...x...x...x.", gain = 0.35}, {"tambourine", "x.x.x.x.x.x.x.x.", gain = 0.25},
		{"clap", "....o.......o...", gain = 0.3}}})
-- Four bars of snare build under a drop: the roll doubles every bar.
add("tops", 6, {bars = 4, energy = 0.9, density = 0.9, brightness = 0.9,
	tags = {"busy", "tense", "rolling"}, flavours = {"uplifting", "tech", "dream"},
	lanes = {{"snare", "....x.......x...|....x.......x...|x...x...x...x...|xxxxxxxxxxxxxxxx", gain = 0.55}}})
add("tops", 7, {bars = 1, energy = 0.3, density = 0.25, brightness = 0.9,
	tags = {"sparse", "minimal", "deep"}, flavours = {"progressive", "dream", "uplifting"},
	lanes = {{"shaker", "x.x.x.x.x.x.x.x.", gain = 0.22}, {"hat", "..o...o...o...o.", gain = 0.2}}})

-- BASS ----------------------------------------------------------------
-- The kick owns steps 0, 4, 8, 12; the bass lives between them. Lines
-- are written on the root and its octave and fifth so any chord of the
-- cadence carries them (follow = "chord").

-- The classic off-beat: one note in the gap after every kick.
add("bass", 1, {bars = 1, energy = 0.65, density = 0.4, brightness = 0.3, octave = 1,
	tags = {"offbeat", "driving", "euphoric", "pluck"}, flavours = {"uplifting", "progressive", "dream"},
	notes = "2:0:2 6:0:2 10:0:2 14:0:2"})
-- Octave pumping: root, then the octave above, in a two-bar sway.
add("bass", 2, {bars = 2, energy = 0.7, density = 0.45, brightness = 0.35, octave = 1,
	tags = {"offbeat", "octave", "driving", "euphoric"}, flavours = {"uplifting"},
	notes = "2:0:2 6:7:2 10:0:2 14:7:2 | 2:0:2 6:7:2 10:0:2 14:4:2"})
-- A long root under the kick: for breakdowns' last bars and intros.
add("bass", 3, {bars = 1, energy = 0.3, density = 0.1, brightness = 0.1, octave = 0,
	tags = {"sub", "pedal", "deep", "sparse", "held"}, excludes = {"rolling"},
	notes = "2:0:14"})
-- Two long notes a bar, ducking under the kick: the dream bass.
add("bass", 4, {bars = 2, energy = 0.45, density = 0.2, brightness = 0.25, octave = 0,
	tags = {"sub", "warm", "dreamy", "sparse", "pedal"}, flavours = {"dream", "progressive"},
	notes = "2:0:6 10:0:6 | 2:0:6 10:4:6"})
-- The rolling 16th bass: kicks at 0 4 8 12, three bass notes in each gap.
add("bass", 5, {bars = 1, energy = 0.8, density = 0.8, brightness = 0.4, octave = 1,
	tags = {"rolling", "driving", "hypnotic", "busy"}, flavours = {"tech", "uplifting", "progressive"},
	excludes = {"offbeat"},
	notes = "1:0:1 2:0:1 3:0:1 5:0:1 6:0:1 7:0:1 9:0:1 10:0:1 11:0:1 13:0:1 14:0:1 15:0:1"})
-- Psy gallop: the three notes root, root, octave, and a rest on the one.
add("bass", 6, {bars = 1, energy = 0.85, density = 0.75, brightness = 0.4, octave = 1,
	tags = {"rolling", "gallop", "hypnotic", "dark", "driving"}, flavours = {"psy", "goa"},
	excludes = {"offbeat"},
	notes = "1:0:1 2:0:1 3:7:1 5:0:1 6:0:1 7:7:1 9:0:1 10:0:1 11:7:1 13:0:1 14:0:1 15:7:1"})
-- Psy with the flat seven: the classic root, octave and b7 triplet feel.
add("bass", 7, {bars = 2, energy = 0.85, density = 0.75, brightness = 0.45, octave = 1,
	tags = {"rolling", "gallop", "hypnotic", "dark"}, flavours = {"psy", "goa", "tech"},
	excludes = {"offbeat"},
	notes = "1:0:1 2:0:1 3:7:1 5:0:1 6:0:1 7:7:1 9:0:1 10:0:1 11:7:1 13:0:1 14:7:1 15:0:1 | 1:0:1 2:0:1 3:7:1 5:0:1 6:0:1 7:7:1 9:0:1 10:0:1 11:7:1 13:4:1 14:4:1 15:7:1"})
-- Sparse psy: two hits in each gap, the one rolling in only when energy is up.
add("bass", 8, {bars = 1, energy = 0.55, density = 0.5, brightness = 0.4, octave = 1,
	tags = {"rolling", "minimal", "hypnotic", "sparse"}, flavours = {"psy", "goa", "tech", "progressive"},
	notes = "2:0:1 3:0:1 6:0:1 7:0:1? 10:0:1 11:0:1 14:0:1 15:7:1?"})
-- Acid bass: a 303 phrase, root and octave, accents, slides into the fifth.
add("bass", 9, {bars = 2, energy = 0.8, density = 0.7, brightness = 0.6, octave = 1,
	tags = {"acid", "syncopated", "driving", "hypnotic"}, flavours = {"acid"},
	excludes = {"offbeat"},
	notes = "1:0:1! 3:0:1 5:7:1~ 6:0:1 8:0:2! 11:4:1~ 13:0:1 14:7:1~ | 1:0:1! 3:0:1 5:0:1 6:7:1~ 8:0:2! 11:0:1 13:4:1~ 14:0:2!"})
-- A second acid line, steadier: one 16th note per beat and a long slide home.
add("bass", 10, {bars = 4, energy = 0.7, density = 0.55, brightness = 0.55, octave = 1,
	tags = {"acid", "hypnotic", "syncopated"}, flavours = {"acid", "tech"},
	notes = "2:0:1! 3:0:1 6:0:1! 7:7:1~ 10:0:1! 11:0:1 14:0:2! | 2:0:1! 3:0:1 6:0:1! 7:7:1~ 10:4:1! 11:4:1 14:0:2! | 2:0:1! 3:0:1 6:0:1! 7:7:1~ 10:0:1! 11:0:1 14:7:2! | 2:0:1! 3:0:1~ 6:4:1! 7:2:1~ 10:0:1! 11:0:1~ 14:0:2!"})
-- Tech rumble: kick-and-gap, the gap filled by a long, low, ducked note.
add("bass", 11, {bars = 1, energy = 0.75, density = 0.4, brightness = 0.2, octave = 0,
	tags = {"rolling", "sub", "driving", "dark", "minimal"}, flavours = {"tech", "progressive"},
	notes = "1:0:3 5:0:3 9:0:3 13:0:3"})
-- Moving off-beat: root, root, third, fifth over two bars; follows the chord.
add("bass", 12, {bars = 2, energy = 0.6, density = 0.4, brightness = 0.35, octave = 1,
	tags = {"offbeat", "walking", "warm", "melodic", "pluck"}, flavours = {"progressive", "dream", "uplifting"},
	notes = "2:0:2 6:0:2 10:2:2 14:4:2 | 2:0:2 6:0:2 10:4:2 14:2:2"})
-- Four-bar bass story: the off-beat, a lift to the fifth, a pickup, home.
add("bass", 13, {bars = 4, energy = 0.7, density = 0.5, brightness = 0.35, octave = 1,
	tags = {"offbeat", "walking", "euphoric", "driving"}, flavours = {"uplifting"},
	notes = "2:0:2 6:0:2 10:0:2 14:0:2 | 2:0:2 6:0:2 10:0:2 14:4:2 | 2:0:2 6:7:2 10:0:2 14:7:2 | 2:0:2 6:0:2 10:4:2 12:0:1 14:7:1 15:4:1"})
-- Triplet-ish drive: 3 notes a gap, the middle one a fifth, for the late drop.
add("bass", 14, {bars = 1, energy = 0.9, density = 0.9, brightness = 0.5, octave = 1,
	tags = {"rolling", "driving", "busy", "aggressive"}, flavours = {"tech", "psy"},
	excludes = {"offbeat"},
	notes = "1:0:1 2:0:1 3:0:1 5:0:1 6:0:1 7:4:1 9:0:1 10:0:1 11:0:1 13:0:1 14:7:1 15:0:1"})
-- Offbeat doubled: a pair of eighths in each gap, the second one when Energy is up.
add("bass", 15, {bars = 1, energy = 0.75, density = 0.6, brightness = 0.35, octave = 1,
	tags = {"offbeat", "driving", "pluck"}, flavours = {"uplifting", "tech", "progressive"},
	notes = "2:0:1 3:0:1? 6:0:1 7:0:1? 10:0:1 11:0:1? 14:0:1 15:7:1?"})

-- PAD -----------------------------------------------------------------
-- Pads hold chords for two bars; comp ones pump with the kick.
add("pad", 1, {bars = 2, energy = 0.4, density = 0.1, brightness = 0.4,
	tags = {"held", "dreamy", "warm", "ambient"}, hold = true})
add("pad", 2, {bars = 2, energy = 0.6, density = 0.3, brightness = 0.6,
	tags = {"chordal", "euphoric", "driving"}, flavours = {"uplifting", "dream"},
	comp = "0:14"})
-- Pumped: four chords a bar on the off-beat, gated by the sidechain.
add("pad", 3, {bars = 1, energy = 0.7, density = 0.5, brightness = 0.55,
	tags = {"chordal", "offbeat", "driving", "euphoric"}, flavours = {"uplifting", "tech"},
	comp = "2:2 6:2 10:2 14:2"})
add("pad", 4, {bars = 2, energy = 0.3, density = 0.1, brightness = 0.3,
	tags = {"held", "dark", "ambient", "deep"}, flavours = {"psy", "goa", "progressive", "acid"}, hold = true})
add("pad", 5, {bars = 1, energy = 0.55, density = 0.35, brightness = 0.5,
	tags = {"chordal", "hypnotic", "rhythmic"}, flavours = {"progressive", "tech", "acid"},
	comp = "0:6 8:6"})
add("pad", 6, {bars = 1, energy = 0.85, density = 0.4, brightness = 0.8,
	tags = {"chordal", "euphoric", "bright", "held"}, flavours = {"uplifting", "dream"},
	comp = "0:16"})

-- KEYS ----------------------------------------------------------------
-- The breakdown piano and vibes: chords in time, softly.
add("keys", 1, {bars = 1, energy = 0.3, density = 0.2, brightness = 0.5,
	tags = {"chordal", "dreamy", "melancholic", "sparse"}, flavours = {"dream", "uplifting", "progressive"},
	comp = "0:8"})
add("keys", 2, {bars = 1, energy = 0.5, density = 0.4, brightness = 0.55,
	tags = {"chordal", "rhythmic", "warm"}, flavours = {"progressive", "dream"},
	comp = "0:3 3:3 6:3 10:3 12:3"})
add("keys", 3, {bars = 1, energy = 0.4, density = 0.25, brightness = 0.5,
	tags = {"chordal", "soulful", "warm", "syncopated"}, flavours = {"progressive", "dream"},
	comp = "0:4 6:2 8:4"})
add("keys", 4, {bars = 1, energy = 0.6, density = 0.5, brightness = 0.6,
	tags = {"chordal", "bright", "euphoric", "rhythmic"}, flavours = {"uplifting", "dream"},
	comp = "0:2 2:2 4:2 8:2 10:2 12:2"})
add("keys", 5, {bars = 1, energy = 0.8, density = 0.6, brightness = 0.65,
	tags = {"chordal", "driving", "syncopated", "bright"}, flavours = {"tech", "uplifting", "acid"},
	comp = "0:2 3:2 6:2 10:2 13:3"})
add("keys", 6, {bars = 1, energy = 0.2, density = 0.1, brightness = 0.45,
	tags = {"chordal", "held", "melancholic", "sparse", "ambient"},
	comp = "0:16"})

-- STAB ----------------------------------------------------------------
-- Short chord hits: the rave stab, the off-beat chord, the tech trance bounce.
add("stab", 1, {bars = 1, energy = 0.5, density = 0.15, brightness = 0.7,
	tags = {"stab", "sparse", "euphoric"}, comp = "0:1"})
add("stab", 2, {bars = 1, energy = 0.6, density = 0.3, brightness = 0.7,
	tags = {"stab", "syncopated", "euphoric"}, flavours = {"uplifting", "dream"},
	comp = "0:1 6:1"})
add("stab", 3, {bars = 1, energy = 0.7, density = 0.4, brightness = 0.75,
	tags = {"stab", "syncopated", "driving", "rhythmic"}, flavours = {"uplifting", "tech"},
	comp = "0:1 3:1 6:1"})
add("stab", 4, {bars = 1, energy = 0.8, density = 0.55, brightness = 0.8,
	tags = {"stab", "offbeat", "driving", "bright"}, flavours = {"uplifting", "tech", "acid"},
	comp = "2:1 6:1 10:1 14:1"})
add("stab", 5, {bars = 1, energy = 0.7, density = 0.45, brightness = 0.7,
	tags = {"stab", "syncopated", "hypnotic", "dark"}, flavours = {"tech", "psy", "acid"},
	comp = "3:1 6:1 10:1 14:1"})
add("stab", 6, {bars = 1, energy = 0.45, density = 0.3, brightness = 0.6,
	tags = {"stab", "sparse", "hypnotic", "deep"}, flavours = {"progressive", "tech", "psy"},
	comp = "10:1"})
add("stab", 7, {bars = 1, energy = 0.9, density = 0.7, brightness = 0.85,
	tags = {"stab", "rhythmic", "busy", "aggressive"}, flavours = {"tech", "acid"},
	comp = "0:1 3:1 6:1 8:1 11:1 14:1"})
add("stab", 8, {bars = 1, energy = 0.65, density = 0.35, brightness = 0.7,
	tags = {"stab", "syncopated", "warm"}, flavours = {"uplifting", "progressive", "dream"},
	comp = "0:2 6:2"})

-- ARP -----------------------------------------------------------------
-- A gated pluck climbing the chord (1 the lowest tone); the order is the
-- tune of the loop.
add("arp", 1, {bars = 1, energy = 0.6, density = 0.5, brightness = 0.7,
	tags = {"arpeggio", "stepwise", "euphoric", "driving"},
	order = {1, 2, 3, 4, 5, 4, 3, 2}, rate = 1, gate = 0.7, mask = "XXXXXXXXXXXXXXXX", octave = 1})
add("arp", 2, {bars = 1, energy = 0.7, density = 0.6, brightness = 0.75,
	tags = {"arpeggio", "leap", "bright"}, flavours = {"uplifting", "dream", "progressive"},
	order = {1, 3, 2, 4, 3, 5, 4, 6}, rate = 1, gate = 0.7, mask = "XXXXXXXXXXXXXXXX", octave = 1})
add("arp", 3, {bars = 1, energy = 0.8, density = 0.7, brightness = 0.8,
	tags = {"arpeggio", "rhythmic", "driving", "bright"},
	order = {1, 2, 3, 5, 1, 2, 4, 5}, rate = 1, gate = 0.55, mask = "XXxXXxXXxXXxXXxX", octave = 1})
add("arp", 4, {bars = 1, energy = 0.65, density = 0.6, brightness = 0.7,
	tags = {"arpeggio", "leap", "hypnotic"}, flavours = {"progressive", "tech", "psy", "goa"},
	order = {1, 4, 3, 5, 2, 4, 3, 6}, rate = 1, gate = 0.65, mask = "XXXXXXXXXXXXXXXX", octave = 1})
-- Slow arp for breakdowns and dream: eighths, long gate.
add("arp", 5, {bars = 1, energy = 0.35, density = 0.25, brightness = 0.6,
	tags = {"arpeggio", "dreamy", "sparse", "ambient"}, flavours = {"dream", "progressive", "uplifting"},
	order = {1, 3, 5, 3, 4, 2}, rate = 2, gate = 0.9, mask = "XXXXXXXXXXXXXXXX", octave = 1})
-- Dotted: the delay-shaped 3-3-2 pulse, three notes and a rest.
add("arp", 6, {bars = 1, energy = 0.55, density = 0.4, brightness = 0.65,
	tags = {"arpeggio", "rhythmic", "syncopated", "bright"}, flavours = {"uplifting", "progressive", "dream", "tech"},
	order = {1, 3, 5, 3, 1, 3}, rate = 1, gate = 0.6, mask = "XXXXXXXXXXXXXXXX", octave = 1})
-- Psy: the repeating 1-note ostinato octave up and down with rests.
add("arp", 7, {bars = 1, energy = 0.75, density = 0.6, brightness = 0.75,
	tags = {"arpeggio", "hypnotic", "rhythmic", "dark"}, flavours = {"psy", "goa", "acid", "tech"},
	order = {1, 1, 4, 1, 3, 1, 5, 1}, rate = 1, gate = 0.5, mask = "XXXxXXxXXXXxXXxX", octave = 1})
-- Acid trance: staccato up and down the chord in a six-step tail.
add("arp", 8, {bars = 1, energy = 0.85, density = 0.8, brightness = 0.85,
	tags = {"arpeggio", "busy", "driving", "aggressive"}, flavours = {"acid", "tech", "psy"},
	order = {1, 2, 3, 4, 5, 6, 5, 4, 3, 2}, rate = 1, gate = 0.5, mask = "XXXXXXXXXXXXXXXX", octave = 2})
-- Goa: high, quick, a ladder of fifths.
add("arp", 9, {bars = 1, energy = 0.7, density = 0.7, brightness = 0.85,
	tags = {"arpeggio", "leap", "bright", "hypnotic"}, flavours = {"goa", "psy", "uplifting"},
	order = {1, 3, 5, 3, 2, 4, 6, 4}, rate = 1, gate = 0.6, mask = "XXXXXxXXXXXXXxXX", octave = 2})
-- Sparse: every other step, a slower breathing arp.
add("arp", 10, {bars = 1, energy = 0.4, density = 0.3, brightness = 0.65,
	tags = {"arpeggio", "sparse", "stepwise", "deep"}, flavours = {"progressive", "dream"},
	order = {1, 2, 3, 2, 4, 3}, rate = 2, gate = 0.8, mask = "XXXXXxXXXXXXXXXX", octave = 1})

-- LEAD ----------------------------------------------------------------
-- The tunes. Every hook has one idea: a rhythm and a shape, stated,
-- repeated, turned and brought home to the root or third.

-- The anthem: a held note stated at the fifth, repeated a step lower,
-- lifted to the ninth, then home.
add("lead", 1, {bars = 4, energy = 0.9, density = 0.3, brightness = 0.7,
	tags = {"hook", "euphoric", "held", "stepwise"}, flavours = {"uplifting", "dream"},
	notes = "0:7:3 3:7:1 4:6:2 6:4:2 8:4:8 | 0:5:3 3:5:1 4:4:2 6:2:2 8:2:8 | 0:4:3 3:4:1 4:5:2 6:7:2 8:9:6 14:7:2 | 0:6:4 4:4:4 8:7:8"})
-- Rise and fall: a step up each bar, then a long descent.
add("lead", 2, {bars = 4, energy = 0.8, density = 0.35, brightness = 0.65,
	tags = {"hook", "stepwise", "euphoric", "bright"}, flavours = {"uplifting", "progressive"},
	notes = "0:2:4 4:4:4 8:6:8 | 0:4:4 4:6:4 8:7:8 | 0:6:4 4:7:4 8:9:6 14:7:2 | 0:6:4 4:4:4 8:2:4 12:0:4"})
-- A two-bar call and a one-note answer, the leap of a sixth.
add("lead", 3, {bars = 2, energy = 0.7, density = 0.3, brightness = 0.6,
	tags = {"hook", "leap", "melancholic"}, flavours = {"uplifting", "dream", "progressive"},
	notes = "0:2:4 4:7:4 8:6:2 10:4:6 | 0:2:4 4:7:4 8:9:2 10:7:2 12:4:4"})
-- A dancing riff that holds still while the chords move.
add("lead", 4, {bars = 2, energy = 0.85, density = 0.55, brightness = 0.7, follow = "key",
	tags = {"riff", "syncopated", "rhythmic", "hypnotic"}, flavours = {"tech", "acid", "psy"},
	notes = "0:0:2 3:0:1 4:3:2 6:4:2 8:0:2 11:3:2 14:4:2 | 0:0:2 3:0:1 4:3:2 6:4:2 8:7:4 14:6:2"})
-- Progressive one-note idea: two notes to a bar, slid into, almost spoken.
add("lead", 5, {bars = 4, energy = 0.4, density = 0.15, brightness = 0.5,
	tags = {"hook", "stepwise", "dreamy", "sparse", "vocal"}, flavours = {"progressive", "dream"},
	notes = "0:4:6 6:5:2~ 8:4:8 | 0:2:6 6:4:2~ 8:2:8 | 0:4:6 6:5:2~ 8:7:8 | 0:6:4 4:4:4 8:0:8~"})
-- The lullaby: a slow, almost-diatonic seven-note shape around the fifth.
add("lead", 6, {bars = 4, energy = 0.5, density = 0.3, brightness = 0.6,
	tags = {"hook", "stepwise", "dreamy", "warm"}, flavours = {"dream", "uplifting"},
	notes = "0:4:4 4:5:4 8:4:4 12:2:4 | 0:4:4 4:5:4 8:6:4 12:7:4 | 0:4:4 4:5:4 8:4:4 12:2:4 | 0:0:4 4:2:4 8:0:8"})
-- Psy: a morse-like, one-pitch rhythm with a single turn in the last bar.
add("lead", 7, {bars = 2, energy = 0.8, density = 0.6, brightness = 0.75, follow = "key",
	tags = {"riff", "rhythmic", "hypnotic", "dark", "syncopated"}, flavours = {"psy", "goa", "tech"},
	notes = "0:4:1 2:4:1 3:4:1 6:4:2 8:4:1 11:4:2 14:3:2 | 0:4:1 2:4:1 3:4:1 6:4:2 8:6:1 11:4:2 14:2:2"})
-- A cascade down the octave; the first bar high, the last bar home.
add("lead", 8, {bars = 4, energy = 0.75, density = 0.5, brightness = 0.8,
	tags = {"hook", "stepwise", "bright", "euphoric"}, flavours = {"goa", "uplifting", "dream"},
	notes = "0:7:2 2:6:2 4:4:2 6:2:2 8:6:2 10:4:2 12:2:2 14:0:2 | 0:6:2 2:5:2 4:4:2 6:1:2 8:4:8 | 0:7:2 2:6:2 4:4:2 6:2:2 8:6:2 10:4:2 12:2:2 14:0:2 | 0:2:4 4:4:4 8:0:8"})
-- Acid riff: a pentatonic 303-like call, key-locked, with two accents.
add("lead", 9, {bars = 2, energy = 0.85, density = 0.6, brightness = 0.7, follow = "key",
	tags = {"riff", "syncopated", "rhythmic", "aggressive", "hook"}, flavours = {"acid", "tech"},
	notes = "0:0:2! 3:2:2 6:3:2 10:4:3 14:6:2 | 0:4:3 3:3:2 6:2:2 10:0:4"})
-- A short and a long: a four-note "doorbell" hook for the tech drop.
add("lead", 10, {bars = 1, energy = 0.6, density = 0.4, brightness = 0.65,
	tags = {"hook", "rhythmic", "bright", "playful"}, flavours = {"tech", "progressive", "psy"},
	notes = "0:4:2 3:4:1 6:6:2 10:4:2 13:2:3"})
-- The sigh: a falling third, over and over, lifted for the last bar.
add("lead", 11, {bars = 4, energy = 0.45, density = 0.2, brightness = 0.55,
	tags = {"hook", "melancholic", "stepwise", "sparse", "dreamy"}, flavours = {"progressive", "dream", "uplifting"},
	notes = "0:6:6 6:5:2 8:4:8 | 0:6:6 6:5:2 8:4:8 | 0:6:6 6:5:2 8:2:8 | 0:4:6 6:5:2 8:7:8"})
-- Three-note staircase, repeated, climbing a step each time: the build-up lead.
add("lead", 12, {bars = 2, energy = 0.9, density = 0.65, brightness = 0.85,
	tags = {"hook", "stepwise", "euphoric", "rhythmic", "bright"}, flavours = {"uplifting", "tech"},
	notes = "0:0:2 2:2:2 4:4:2 6:2:2 8:2:2 10:4:2 12:6:2 14:4:2 | 0:4:2 2:6:2 4:7:2 6:6:2 8:7:8"})
-- Slow breakdown lead: four held notes, a full phrase, a pickup.
add("lead", 13, {bars = 4, energy = 0.3, density = 0.1, brightness = 0.5,
	tags = {"hook", "held", "melancholic", "sparse", "dreamy"},
	notes = "0:4:12 | 0:2:8 8:4:8 | 0:6:12 | 0:4:6 8:2:8"})
-- A leaping octave answer: two bars, the tune a ninth up and down.
add("lead", 14, {bars = 2, energy = 0.65, density = 0.4, brightness = 0.75,
	tags = {"hook", "leap", "bright", "rhythmic"}, flavours = {"goa", "psy", "uplifting"},
	notes = "0:0:2 4:7:2 8:4:2 12:9:4 | 0:2:2 4:7:2 8:4:2 12:6:4"})

-- COUNTER -------------------------------------------------------------
-- Short answers that sit in the gaps of the lead.
add("counter", 1, {bars = 2, energy = 0.35, density = 0.15, brightness = 0.7,
	tags = {"answer", "stepwise", "sparse", "dreamy"}, flavours = {"dream", "progressive", "uplifting"},
	notes = "8:4:2 10:2:2 12:0:4 | 8:2:2 10:4:2 12:0:4"})
add("counter", 2, {bars = 2, energy = 0.55, density = 0.3, brightness = 0.75,
	tags = {"answer", "leap", "bright"}, flavours = {"uplifting", "goa", "dream"},
	notes = "10:7:1 11:6:1 12:4:4 | 10:9:1 11:7:1 12:4:4"})
add("counter", 3, {bars = 4, energy = 0.5, density = 0.2, brightness = 0.7,
	tags = {"answer", "sparse", "melancholic"}, flavours = {"uplifting", "progressive"},
	notes = "12:4:4 | 12:2:4 | 12:4:2 14:2:2 | 12:0:4"})
add("counter", 4, {bars = 1, energy = 0.7, density = 0.45, brightness = 0.8,
	tags = {"answer", "rhythmic", "syncopated", "playful"}, flavours = {"tech", "psy", "acid"},
	notes = "6:4:1 7:6:1 10:4:1 11:2:1 14:0:2"})
add("counter", 5, {bars = 2, energy = 0.4, density = 0.25, brightness = 0.7,
	tags = {"answer", "hypnotic", "stepwise"}, flavours = {"goa", "psy", "progressive"},
	notes = "4:4:2 6:3:2 8:2:4 | 4:4:2 6:3:2 8:0:4"})
add("counter", 6, {bars = 1, energy = 0.85, density = 0.6, brightness = 0.85,
	tags = {"answer", "busy", "bright", "euphoric"}, flavours = {"uplifting", "tech"},
	notes = "8:7:1 9:9:1 10:7:1 11:6:1 12:4:2 14:2:2"})

-- TEXTURE -------------------------------------------------------------
-- Sustained voices (semitones above the root) held across the phrase.
add("texture", 1, {bars = 4, energy = 0.2, density = 0.1, brightness = 0.3,
	tags = {"ambient", "dark", "deep", "held"}, voices = {0, 7}, every = 4})
add("texture", 2, {bars = 8, energy = 0.25, density = 0.1, brightness = 0.5,
	tags = {"ambient", "dreamy", "held"}, flavours = {"progressive", "dream", "uplifting"}, voices = {0, 7, 12}, every = 8})
add("texture", 3, {bars = 4, energy = 0.3, density = 0.15, brightness = 0.35,
	tags = {"ambient", "dark", "hypnotic", "held"}, flavours = {"psy", "goa", "tech", "acid"}, voices = {0, 5}, every = 4})
add("texture", 4, {bars = 4, energy = 0.35, density = 0.2, brightness = 0.6,
	tags = {"ambient", "melancholic", "held"}, voices = {0, 3, 7}, every = 4})
add("texture", 5, {bars = 8, energy = 0.4, density = 0.2, brightness = 0.7,
	tags = {"ambient", "bright", "euphoric", "held"}, flavours = {"uplifting", "dream", "progressive"},
	voices = {0, 7, 12, 19}, every = 8})
add("texture", 6, {bars = 2, energy = 0.5, density = 0.3, brightness = 0.4,
	tags = {"ambient", "tense", "dark", "held"}, flavours = {"tech", "psy", "acid"}, voices = {0, 1, 7}, every = 2})

-- FX ------------------------------------------------------------------
-- Trance builds with three layers: a pitched sweep, a noise riser and a
-- snare roll (see tops 6); the impact lands on the first bar of the drop.
add("fx", 1, {bars = 4, energy = 0.6, density = 0.4, brightness = 0.8, kind = "riser",
	tags = {"tense", "bright", "euphoric"}})
add("fx", 2, {bars = 8, energy = 0.7, density = 0.5, brightness = 0.9, kind = "riser",
	tags = {"tense", "bright", "euphoric"}, flavours = {"uplifting", "dream", "progressive"}})
add("fx", 3, {bars = 4, energy = 0.7, density = 0.5, brightness = 0.7, kind = "riser",
	tags = {"tense", "dark", "aggressive"}, flavours = {"tech", "acid", "psy", "goa"}})
add("fx", 4, {bars = 2, energy = 0.5, density = 0.3, brightness = 0.9, kind = "riser",
	tags = {"tense", "bright"}})
add("fx", 5, {bars = 1, energy = 0.9, density = 0.5, brightness = 0.4, kind = "impact",
	tags = {"euphoric", "deep"}})
add("fx", 6, {bars = 1, energy = 0.8, density = 0.4, brightness = 0.3, kind = "impact",
	tags = {"dark", "deep"}, flavours = {"tech", "psy", "acid", "goa"}})
add("fx", 7, {bars = 4, energy = 0.3, density = 0.2, brightness = 0.6, kind = "downlifter",
	tags = {"ambient", "dreamy"}})
add("fx", 8, {bars = 2, energy = 0.4, density = 0.3, brightness = 0.7, kind = "downlifter",
	tags = {"tense", "dark"}, flavours = {"tech", "psy", "acid"}})
add("fx", 9, {bars = 1, energy = 0.85, density = 0.3, brightness = 1.0, kind = "crash",
	tags = {"bright", "euphoric"}})
add("fx", 10, {bars = 1, energy = 0.7, density = 0.3, brightness = 0.9, kind = "crash",
	tags = {"bright"}, flavours = {"progressive", "dream", "tech"}})

return list
