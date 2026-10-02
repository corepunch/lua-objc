-- Blocks every genre may play (`common.<role>.<nnn>`). Genre-neutral: pitch
-- is in scale steps so it works under any mode, drums are plain, and no block
-- names a flavour. The hooks, bass lines and record breaks were converted
-- from the former library/Hooks.lua, Lines.lua and Beats.lua. See BLOCKS.md.
local blocks = {}

local function add(role, number, spec)
	spec.id = string.format("common.%s.%03d", role, number)
	spec.role = role
	table.insert(blocks, spec)
end

-- Leads: the four-bar hooks -----------------------------------------------
local function lead(number, name, energy, density, tags, notes, follow)
	add("lead", number, {bars = 4, energy = energy, density = density, tags = tags, notes = notes, follow = follow, name = name})
end

-- Long notes that climb to the ninth and come home: the trance anthem.
lead(1, "Anthem", 0.8, 0.4, {"hook", "euphoric", "held", "leap"}, [[
	0:4:6 6:5:2 8:4:4 12:2:4 | 0:4:6 6:5:2 8:6:4 12:7:4 |
	0:8:6 6:7:2 8:6:4 12:4:4 | 0:4:4 4:2:4 8:0:8~]])
lead(2, "Ascent", 0.8, 0.45, {"hook", "euphoric", "stepwise", "bright"}, [[
	0:0:4 4:2:4 8:4:6 14:6:2 | 0:7:8 8:6:4 12:4:4 |
	0:2:4 4:4:4 8:6:6 14:7:2 | 0:9:6 6:8:2 8:7:8~]])
-- A pentatonic riff that sits still while the chords move.
lead(3, "Riff", 0.65, 0.55, {"riff", "rhythmic", "playful"}, [[
	0:0:2 3:2:2 6:3:2 10:4:3 14:6:2 | 0:4:3 3:3:2 6:2:2 10:0:4 |
	0:0:2 3:2:2 6:3:2 10:4:3 14:6:2 | 0:4:3 3:6:2 6:7:2 10:4:6]], "key")
lead(4, "Jack", 0.7, 0.6, {"riff", "rhythmic", "driving", "syncopated"}, [[
	0:4:1 2:4:1 3:4:2 6:6:2 8:4:2 11:2:2 14:4:2 | 0:4:1 2:4:1 3:4:2 6:7:2 8:6:2 11:4:4 |
	0:4:1 2:4:1 3:4:2 6:6:2 8:4:2 11:2:2 14:4:2 | 0:2:1 2:2:1 3:2:2 6:3:2 8:0:6]], "key")
-- A call, and an answer that waits for it.
lead(5, "Call", 0.55, 0.4, {"hook", "answer", "stepwise"}, [[
	0:7:3 3:6:1 4:4:4 | 8:2:2 10:3:2 12:4:4 |
	0:7:3 3:6:1 4:4:4 | 8:4:2 10:2:2 12:0:4]])
lead(6, "Question", 0.5, 0.45, {"hook", "dreamy", "soulful"}, [[
	0:0:2 2:2:2 4:4:3 8:6:6~ | 4:4:2 6:2:2 8:0:6 |
	0:0:2 2:2:2 4:4:3 8:7:6~ | 4:6:2 6:4:2 8:2:2+ 10:0:6]])
-- Step by step down the scale: a lament.
lead(7, "Lament", 0.5, 0.3, {"hook", "melancholic", "stepwise", "held"}, [[
	0:7:4 4:6:4 8:5:4 12:4:4 | 0:4:8 10:2:2 12:3:4 |
	0:6:4 4:5:4 8:4:4 12:2:4 | 0:2:4 4:1:4 8:0:8]])
lead(8, "Sigh", 0.35, 0.2, {"hook", "melancholic", "ambient", "held", "sparse"}, [[
	0:4:6 6:3:2~ 8:2:8 | 0:6:6 6:5:2~ 8:4:8 |
	0:4:6 6:3:2~ 8:2:4 12:1:4 | 0:0:12]])
-- The chord, climbed and descended.
lead(9, "Arpeggio", 0.7, 0.65, {"hook", "arpeggio", "bright"}, [[
	0:0:2 2:2:2 4:4:2 6:7:2 8:4:2 10:2:2 12:4:4 | 0:0:2 2:2:2 4:4:2 6:7:2 8:9:4 12:7:4 |
	0:0:2 2:2:2 4:4:2 6:7:2 8:4:2 10:2:2 12:4:4 | 0:7:2 2:4:2 4:2:2 6:0:2 8:0:8]])
lead(10, "Cascade", 0.75, 0.7, {"hook", "arpeggio", "stepwise", "busy", "bright"}, [[
	0:9:2 2:7:2 4:4:2 6:2:2 8:7:2 10:4:2 12:2:2 14:0:2 | 0:8:2 2:6:2 4:4:2 6:1:2 8:4:8 |
	0:9:2 2:7:2 4:4:2 6:2:2 8:7:2 10:4:2 12:2:2 14:0:2 | 0:2:4 4:4:4 8:0:8]])
-- Two notes to a bar, each slid into: almost sung.
lead(11, "Voice", 0.45, 0.2, {"hook", "vocal", "soulful", "held", "sparse"}, [[
	0:4:8 8:6:6~ | 0:7:10 12:6:4~ |
	0:4:8 8:2:6~ | 0:0:12]])
lead(12, "Lullaby", 0.4, 0.35, {"hook", "dreamy", "warm", "stepwise"}, [[
	0:2:6 6:4:2~ 8:2:4 12:0:4 | 0:2:6 6:4:2~ 8:6:8 |
	0:7:6 6:6:2~ 8:4:4 12:2:4 | 0:1:4 4:2:4~ 8:0:8]])
-- Off the beat throughout.
lead(13, "Offbeat", 0.6, 0.4, {"riff", "offbeat", "syncopated"}, [[
	2:7:2 6:6:2 10:4:2 14:6:2 | 2:7:2 6:9:2 10:7:2 14:4:2 |
	2:7:2 6:6:2 10:4:2 14:6:2 | 2:4:2 6:2:2 10:0:6]], "key")
lead(14, "Skank", 0.55, 0.35, {"riff", "offbeat", "playful", "sparse"}, [[
	2:4:1 6:4:1 10:6:1 14:4:1 | 2:4:1 6:4:1 10:7:2 13:6:2 |
	2:4:1 6:4:1 10:6:1 14:4:1 | 2:2:1 6:2:1 10:0:4]], "key")
-- Root and octave thrown about.
lead(15, "Octaves", 0.7, 0.6, {"hook", "leap", "rhythmic", "driving"}, [[
	0:0:2 2:7:2 4:0:2 6:7:2 8:6:2 10:4:4 | 0:0:2 2:7:2 4:0:2 6:7:2 8:9:2 10:7:4 |
	0:0:2 2:7:2 4:0:2 6:7:2 8:6:2 10:4:4 | 0:4:2 2:2:2 4:0:2 6:7:2 8:0:8]])
-- The tresillo as a tune.
lead(16, "Tresillo", 0.65, 0.5, {"hook", "syncopated", "rhythmic"}, [[
	0:4:3 3:6:3 6:7:2 10:6:2 12:4:4 | 0:4:3 3:6:3 6:7:2 10:9:2 12:7:4 |
	0:4:3 3:6:3 6:7:2 10:6:2 12:4:4 | 0:2:3 3:1:3 6:0:10]])
lead(17, "Dotted", 0.55, 0.5, {"riff", "rhythmic", "hypnotic"}, [[
	0:0:3 3:2:3 6:4:3 9:2:3 12:0:4 | 0:0:3 3:2:3 6:4:3 9:6:3 12:4:4 |
	0:0:3 3:2:3 6:4:3 9:2:3 12:0:4 | 0:6:3 3:4:3 6:2:3 9:0:7]], "key")
-- One note insisted on, then let go.
lead(18, "Insist", 0.6, 0.5, {"riff", "hypnotic", "tense", "rhythmic"}, [[
	0:4:2 2:4:2 4:4:2 6:4:1 7:6:1 8:4:4 | 0:4:2 2:4:2 4:4:2 6:4:1 7:2:1 8:4:4 |
	0:4:2 2:4:2 4:4:2 6:4:1 7:6:1 8:7:4 14:6:2 | 0:4:4 4:2:4 8:0:8]], "key")
lead(19, "Morse", 0.6, 0.45, {"riff", "hypnotic", "tense", "rhythmic"}, [[
	0:7:1 1:7:1 3:7:1 6:7:2 10:6:1 11:6:1 14:4:2 | 0:7:1 1:7:1 3:7:1 6:9:2 10:7:4 |
	0:7:1 1:7:1 3:7:1 6:7:2 10:6:1 11:6:1 14:4:2 | 0:4:1 1:4:1 3:4:1 6:2:2 10:0:6]], "key")
-- A wide leap, filled in by step: the oldest shape a melody has.
lead(20, "Leap", 0.6, 0.45, {"hook", "leap", "stepwise", "warm"}, [[
	0:0:4 4:7:4 8:6:2 10:5:2 12:4:4 | 0:4:4 4:3:2+ 6:2:2 8:4:8 |
	0:0:4 4:9:4 8:8:2 10:7:2 12:6:4 | 0:4:4 4:2:4 8:0:8]])
lead(21, "Bounce", 0.65, 0.55, {"hook", "playful", "rhythmic"}, [[
	0:0:2 3:4:1 4:0:2 7:4:1 8:0:2 11:6:1 12:4:4 | 0:0:2 3:4:1 4:0:2 7:4:1 8:7:4 12:6:4 |
	0:0:2 3:4:1 4:0:2 7:4:1 8:0:2 11:6:1 12:4:4 | 0:2:2 3:4:1 4:2:2 7:1:1 8:0:8]])
-- Sparse: one phrase, and room after it.
lead(22, "Space", 0.35, 0.2, {"hook", "ambient", "dreamy", "sparse"}, [[
	0:4:2 3:6:2 6:7:6 | 12:6:2 14:4:2 |
	0:4:2 3:6:2 6:9:6 | 12:7:2~ 14:4:2]])
lead(23, "Echo", 0.5, 0.4, {"riff", "hypnotic", "rhythmic"}, [[
	0:7:2 4:7:2+ 8:4:2 12:4:2+ | 0:6:2 4:6:2+ 8:2:2 12:2:2+ |
	0:7:2 4:7:2+ 8:4:2 12:4:2+ | 0:4:2 4:2:2 8:0:8]], "key")
-- Neighbour notes circling the fifth.
lead(24, "Circle", 0.5, 0.5, {"hook", "stepwise", "hypnotic"}, [[
	0:4:2 2:5:2 4:4:2 6:3:2 8:4:4 12:2:4 | 0:4:2 2:5:2 4:4:2 6:3:2 8:4:4 12:6:4 |
	0:4:2 2:5:2 4:4:2 6:3:2 8:4:4 12:7:4 | 0:6:2 2:4:2 4:2:2 6:1:2 8:0:8]])

-- Counters: answers, written against the leads rather than copies of them --
local function counter(number, name, energy, density, tags, notes, follow)
	add("counter", number, {bars = 4, energy = energy, density = density, tags = tags, notes = notes, follow = follow, name = name})
end
-- Rests where the lead sings; a falling third and a held fifth below it.
counter(1, "Reply", 0.4, 0.25, {"answer", "held", "soulful", "sparse"}, [[
	8:2:4 12:1:4 | 0:0:6 8:2:8 |
	8:4:4 12:2:4 | 0:1:4 4:0:12]])
-- Short answers in the gaps, a sixth below.
counter(2, "Gap Filler", 0.5, 0.4, {"answer", "rhythmic", "playful"}, [[
	6:2:2 10:0:2 14:2:2 | 6:4:2 10:2:2 14:0:2 |
	6:2:2 10:0:2 14:2:2 | 4:4:2 6:2:2 8:0:6]])
-- Slow thirds climbing under everything.
counter(3, "Under Line", 0.35, 0.2, {"answer", "stepwise", "dreamy", "held"}, [[
	0:-3:8 8:-2:8 | 0:-1:8 8:0:8 |
	0:-3:8 8:-2:8 | 0:-1:8 8:-3:8]])
-- Off-beat pushes, held still in the key.
counter(4, "Push Back", 0.6, 0.5, {"answer", "offbeat", "syncopated", "tense"}, [[
	3:2:2 7:4:2 11:2:2 | 3:4:2 7:6:2 11:4:2 |
	3:2:2 7:4:2 11:2:2 | 3:0:2 7:2:2 11:0:4]], "key")
counter(5, "Descent", 0.45, 0.35, {"answer", "stepwise", "melancholic"}, [[
	0:6:4 4:5:4 8:4:4 12:2:4 | 0:2:8 8:1:8 |
	0:5:4 4:4:4 8:2:4 12:1:4 | 0:0:16]])

-- Bass --------------------------------------------------------------------
local function bass(number, name, energy, density, tags, notes, bars, follow)
	add("bass", number, {bars = bars or 1, energy = energy, density = density, tags = tags, notes = notes, follow = follow, name = name})
end
-- The root, once a bar: under a breakdown, or a tune that needs nothing more.
bass(1, "Root", 0.3, 0.1, {"sub", "held", "minimal", "sparse", "pedal"}, "0:0:14")
-- Root and octave in eighths.
bass(2, "Octaves", 0.65, 0.7, {"octave", "driving", "rolling"}, "0:0:2 2:7:2 4:0:2 6:7:2 8:0:2 10:7:2 12:0:2 14:7:2?")
-- A walk up to the fifth and home again, over two bars.
bass(3, "Walk", 0.5, 0.4, {"walking", "stepwise", "warm"}, "0:0:4 4:2:4 8:3:4 12:4:4 | 0:4:4 4:3:4 8:2:4 12:1:4", 2)
-- The tresillo in the bass.
bass(4, "Tresillo", 0.7, 0.6, {"syncopated", "driving"}, "0:0:3 3:0:3 6:0:2 8:7:2? 10:4:2+ 12:0:3 | 0:0:3 3:0:3 6:4:2 8:6:3 12:4:2? 14:2:2+", 2)
-- One long note, then a late push into the next bar.
bass(5, "Push", 0.45, 0.3, {"sub", "held", "syncopated"}, "0:0:10 11:0:1? 12:6:2 14:7:2~")
-- Neutral additions.
bass(6, "Long Notes", 0.25, 0.1, {"sub", "held", "deep", "sparse"}, "0:0:16 | 0:0:8 8:4:8", 2)
bass(7, "Root Fifth", 0.4, 0.3, {"sub", "held", "pedal", "warm"}, "0:0:8 8:4:8")
bass(8, "Four Walk", 0.55, 0.5, {"walking", "driving", "soulful"},
	"0:0:4 4:0:4 8:2:4 12:4:4 | 0:4:4 4:3:4 8:2:4 12:0:4 | 0:0:4 4:0:4 8:4:4 12:6:4 | 0:7:4 4:6:4 8:4:4 12:2:4", 4)
bass(9, "Pulse", 0.6, 0.65, {"driving", "rolling", "straight", "pedal"}, "0:0:2 2:0:2 4:0:2 6:0:2 8:0:2 10:0:2 12:0:2 14:0:2")
bass(10, "Octave Jump", 0.7, 0.5, {"octave", "driving", "syncopated"}, "0:0:3 3:7:1 4:0:3 7:7:1 8:0:3 11:7:1 12:0:2 14:7:2")
bass(11, "Offbeat", 0.6, 0.4, {"offbeat", "driving"}, "2:0:2 6:0:2 10:0:2 14:0:2")
bass(12, "Slide", 0.5, 0.3, {"sub", "deep", "dark"}, "0:0:6 8:0:4 12:2:2~ 14:0:2", 1)

-- Tops: the record breaks, played as the record's solo ------------------------
local function break_(number, name, energy, density, tags, bpm, bars, lanes)
	add("tops", number, {bars = bars, energy = energy, density = density, tags = tags, kit = "break", bpm = bpm, send = bpm == 120 and 0.1 or (bpm == 116 or bpm == 112) and 0.14 or 0.12, lanes = lanes, name = name})
end
-- The Amen break, recreated: the four-bar drum solo from The Winstons'
-- "Amen, Brother" (1969) that jungle and drum & bass were built on.
break_(1, "Amen", 0.8, 0.8, {"break", "syncopated", "busy"}, 137, 4, {
	{"breakKick", "X.x.......x.....|X.x.......x.....|X.x.......x.....|..........xo...."},
	{"breakSnare", "....X..o.o..X..o|....X..o.o..X..o|....X..o.o....X.|..o.X..o.o....X."},
	{"breakRide", "x...x...x...x...", gain = 0.62},
	{"breakRide", "..x...x...x...x.", gain = 0.45},
	{"crash", "................|................|................|..........X.....", gain = 0.8},
})
break_(2, "Funk Break", 0.6, 0.7, {"break", "shuffle", "playful"}, 102, 2, {
	{"breakKick", "X.x...x...x..x..|X.x...x...x..o.."},
	{"breakSnare", "....X..g.g.gX..g|....X..g.g.gX.g."},
	{"breakHat", "XoxoXoxoXoxoXoxo", gain = 0.55},
})
break_(3, "Tambourine", 0.55, 0.6, {"break", "playful", "swung"}, 116, 2, {
	{"breakKick", "X.x.......x.x...|X.x....x..x....."},
	{"breakSnare", "....X.......X...|....X.....g.X..g"},
	{"tambourine", "xoxoxoxoxoxoxoxo", gain = 0.6},
})
break_(4, "Bongo Break", 0.5, 0.6, {"break", "playful", "broken"}, 112, 2, {
	{"breakKick", "X.....x.x.......|X.....x.x....x.."},
	{"breakSnare", "....X.......X...|....X.......X.g."},
	{"conga", "x.xo.xo.x.xo.xo.", gain = 0.7},
	{"breakHat", "..x...x...x...x.", gain = 0.5},
})
break_(5, "Shuffle Break", 0.6, 0.65, {"break", "shuffle", "swung"}, 110, 2, {
	{"breakKick", "X..x..x...x..x..|X..x..x...x....."},
	{"breakSnare", "....X..g....X..g|....X..g.g..X.g."},
	{"breakHat", "x.xx.xx.x.xx.xx.", gain = 0.5},
})
break_(6, "Stomp Break", 0.75, 0.55, {"break", "straight", "driving", "aggressive"}, 120, 2, {
	{"breakKick", "X.....x.x.x.....|X.....x.x.x..x.."},
	{"breakSnare", "....X.......X...|....X.......X.o."},
	{"breakHat", "x.x.x.x.x.x.x.x.", gain = 0.55},
	{"breakRide", "x...x...x...x...", gain = 0.3},
})

-- Minimal tops: shakers and hats, no kick ---------------------------------------
add("tops", 7, {bars = 1, energy = 0.25, density = 0.3, tags = {"minimal", "straight", "mixable", "sparse"},
	lanes = {{"shaker", "x.o.x.o.x.o.x.o.", gain = 0.5}}})
add("tops", 8, {bars = 2, energy = 0.35, density = 0.45, tags = {"minimal", "shuffle", "mixable", "swung"},
	lanes = {{"hat", "..x...x...x...x.|..x...x...x..xo."}, {"shaker", "xoxoxoxoxoxoxoxo", gain = 0.4}}})
add("tops", 9, {bars = 1, energy = 0.45, density = 0.55, tags = {"minimal", "straight", "mixable", "driving"},
	lanes = {{"hat", "x.xxx.xxx.xxx.xx", gain = 0.55}, {"openHat", "..x...x...x...x.", gain = 0.5}}})

-- Drums: simple, neutral, mixable loops ---------------------------------------
add("drums", 1, {bars = 1, energy = 0.2, density = 0.1, tags = {"fourfloor", "straight", "mixable", "minimal", "sparse"},
	lanes = {{"kick", "X...X...X...X..."}}})
add("drums", 2, {bars = 1, energy = 0.3, density = 0.3, tags = {"fourfloor", "straight", "mixable", "minimal"},
	lanes = {{"kick", "X...X...X...X..."}, {"hat", "..x...x...x...x.", gain = 0.6}}})
add("drums", 3, {bars = 2, energy = 0.4, density = 0.4, tags = {"fourfloor", "straight", "mixable"},
	lanes = {{"kick", "X...X...X...X..."}, {"hat", "..x...x...x...x."}, {"clap", "....x.......x...|....x.......x..o"}}})
add("drums", 4, {bars = 1, energy = 0.45, density = 0.5, tags = {"fourfloor", "straight", "mixable", "driving"},
	lanes = {{"kick", "X...X...X...X..."}, {"hat", "x.x.x.x.x.x.x.x.", gain = 0.55}, {"openHat", "..x...x...x...x.", gain = 0.5}}})
add("drums", 5, {bars = 2, energy = 0.55, density = 0.6, tags = {"fourfloor", "straight", "mixable", "rolling"},
	lanes = {{"kick", "X...X...X...X..."}, {"hat", "xoxoxoxoxoxoxoxo", gain = 0.5}, {"snare", "....x.......x...|....x.......x.g."}, {"openHat", "..x...x...x...x.", gain = 0.5}}})
add("drums", 6, {bars = 2, energy = 0.5, density = 0.45, tags = {"straight", "mixable", "minimal", "broken"},
	lanes = {{"kick", "X.....x...x.....|X.....x.....x..."}, {"hat", "x.x.x.x.x.x.x.x.", gain = 0.5}, {"rim", "....x.......x...", gain = 0.6}}})
add("drums", 7, {bars = 2, energy = 0.35, density = 0.3, tags = {"halftime", "straight", "mixable", "minimal"},
	lanes = {{"kick", "X.......x.......|X.......x....x.."}, {"snare", "........x.......|........x......."}, {"hat", "x.x.x.x.x.x.x.x.", gain = 0.45}}})
add("drums", 8, {bars = 2, energy = 0.7, density = 0.75, tags = {"fourfloor", "straight", "driving", "busy"},
	lanes = {{"kick", "X...X...X...X..."}, {"hat", "xxxxxxxxxxxxxxxx", gain = 0.45}, {"openHat", "..x...x...x...x.", gain = 0.55},
		{"clap", "....X.......X...|....X.......X.x."}, {"shaker", "xoxoxoxoxoxoxoxo", gain = 0.35, when = "complexity"}}})

-- Pads: sustained chords --------------------------------------------------------
local function pad(number, name, energy, density, brightness, tags)
	add("pad", number, {bars = 4, hold = true, energy = energy, density = density, brightness = brightness, tags = tags, name = name})
end
pad(1, "Warm Bed", 0.25, 0.1, 0.3, {"held", "warm", "ambient", "deep"})
pad(2, "Wide Shimmer", 0.45, 0.2, 0.8, {"held", "bright", "dreamy", "euphoric"})
pad(3, "Dark Cloud", 0.35, 0.15, 0.2, {"held", "dark", "tense", "ambient"})
pad(4, "Long Swell", 0.55, 0.2, 0.55, {"held", "euphoric", "warm"})
pad(5, "Hollow", 0.3, 0.1, 0.4, {"held", "melancholic", "ambient", "dreamy"})

-- Keys comps ------------------------------------------------------------------
local function keys(number, name, energy, density, tags, comp, bars)
	add("keys", number, {bars = bars or 1, energy = energy, density = density, tags = tags, comp = comp, name = name})
end
keys(1, "Whole Notes", 0.3, 0.15, {"chordal", "held", "warm", "sparse"}, "0:16")
keys(2, "Offbeat Chords", 0.55, 0.4, {"chordal", "offbeat", "soulful"}, "2:2 6:2 10:2 14:2")
keys(3, "Soul Comp", 0.5, 0.45, {"chordal", "syncopated", "soulful", "warm"}, "0:3 3:3 8:2 11:3 14:2")
keys(4, "Piano House", 0.65, 0.55, {"chordal", "rhythmic", "bright", "playful"}, "0:2 3:2 6:2 10:2! 12:2 14:2?")
keys(5, "Slow Pulse", 0.35, 0.25, {"chordal", "dreamy", "held"}, "0:6 8:6")
keys(6, "Two Bar Comp", 0.45, 0.35, {"chordal", "syncopated", "warm"}, "0:4 6:2 10:4", 1)

-- Stabs --------------------------------------------------------------------------
local function stab(number, name, energy, density, tags, comp)
	add("stab", number, {bars = 1, energy = energy, density = density, tags = tags, comp = comp, name = name})
end
stab(1, "One Hit", 0.4, 0.1, {"stab", "sparse", "minimal"}, "0:1")
stab(2, "Offbeat Stab", 0.6, 0.3, {"stab", "offbeat", "driving"}, "2:1 6:1 10:1 14:1")
stab(3, "Rave Stabs", 0.8, 0.45, {"stab", "aggressive", "syncopated", "bright"}, "0:2! 3:2 6:2 10:2! 12:1?")
stab(4, "Tresillo Stab", 0.7, 0.4, {"stab", "syncopated", "rhythmic"}, "0:2 3:2 6:2 10:1+ 12:1+")
stab(5, "Backbeat", 0.5, 0.2, {"stab", "straight", "driving"}, "4:1 12:1")
stab(6, "Long Chord Hit", 0.55, 0.25, {"stab", "euphoric", "held"}, "0:6 8:2! 14:1?")

-- Arps ---------------------------------------------------------------------------
local function arp(number, name, energy, density, tags, spec)
	spec.id, spec.energy, spec.density, spec.tags, spec.name = nil, energy, density, tags, name
	spec.bars = 1
	add("arp", number, spec)
end
arp(1, "Up", 0.5, 0.5, {"arpeggio", "straight", "bright"}, {order = {1, 2, 3, 4}, rate = 2, gate = 0.7, octave = 1, mask = "XXXXXXXXXXXXXXXX"})
arp(2, "Up Down", 0.6, 0.6, {"arpeggio", "stepwise", "euphoric"}, {order = {1, 2, 3, 4, 3, 2}, rate = 1, gate = 0.6, octave = 1, mask = "XXXXXXXXXXXXXXXX"})
arp(3, "Slow Climb", 0.35, 0.25, {"arpeggio", "dreamy", "sparse", "ambient"}, {order = {1, 2, 3, 4}, rate = 4, gate = 0.9, octave = 1, mask = "XXXXXXXXXXXXXXXX"})
arp(4, "Gated Eighths", 0.65, 0.55, {"arpeggio", "driving", "rhythmic"}, {order = {1, 1, 2, 3}, rate = 2, gate = 0.4, octave = 1, mask = "XXxxXXxxXXxxXXxx"})
arp(5, "Leap", 0.55, 0.4, {"arpeggio", "leap", "playful"}, {order = {1, 3, 2, 4}, rate = 2, gate = 0.5, octave = 2, mask = "XXXXXXXXXXXXXXXX"})
arp(6, "Syncopated", 0.7, 0.5, {"arpeggio", "syncopated", "tense"}, {order = {1, 2, 3, 2, 4}, rate = 1, gate = 0.5, octave = 1, mask = "X..XX.X.X..XX.X."})
arp(7, "Sixteenth Run", 0.8, 0.85, {"arpeggio", "busy", "bright", "euphoric"}, {order = {1, 2, 3, 4, 5, 4, 3, 2}, rate = 1, gate = 0.5, octave = 1, mask = "XXXXXXXXXXXXXXXX"})
arp(8, "Low Pedal", 0.5, 0.4, {"arpeggio", "dark", "hypnotic", "pedal"}, {order = {1, 3, 1, 4}, rate = 1, gate = 0.45, octave = 0, mask = "XxXxXxXxXxXxXxXx"})

-- Textures: drones, fifths and octaves -------------------------------------------------
local function texture(number, name, energy, density, brightness, tags, voices, every)
	add("texture", number, {bars = every, energy = energy, density = density, brightness = brightness, tags = tags, voices = voices, every = every, name = name})
end
texture(1, "Root Drone", 0.2, 0.05, 0.2, {"ambient", "dark", "held", "deep"}, {0}, 8)
texture(2, "Open Fifth", 0.3, 0.1, 0.4, {"ambient", "held", "warm"}, {0, 7}, 4)
texture(3, "Octaves", 0.35, 0.1, 0.55, {"ambient", "held", "hypnotic"}, {0, 12}, 4)
texture(4, "Wide Stack", 0.4, 0.15, 0.7, {"ambient", "dreamy", "bright"}, {0, 7, 12, 19}, 8)
texture(5, "Fifth Slow", 0.25, 0.05, 0.3, {"ambient", "melancholic", "held"}, {0, 7}, 8)
texture(6, "Octave Pulse", 0.45, 0.2, 0.5, {"hypnotic", "tense"}, {0, 12}, 2)

-- Fx ---------------------------------------------------------------------------------
local function fx(number, name, kind, bars, energy, density, brightness, tags)
	add("fx", number, {bars = bars, kind = kind, energy = energy, density = density, brightness = brightness, tags = tags, name = name})
end
fx(1, "Riser Short Dark", "riser", 4, 0.5, 0.4, 0.3, {"tense", "dark"})
fx(2, "Riser Short Bright", "riser", 4, 0.6, 0.5, 0.85, {"bright", "euphoric"})
fx(3, "Riser Long Dark", "riser", 8, 0.55, 0.4, 0.25, {"tense", "dark", "deep"})
fx(4, "Riser Long Bright", "riser", 8, 0.7, 0.6, 0.9, {"bright", "euphoric"})
fx(5, "Riser Noise", "riser", 4, 0.65, 0.5, 0.6, {"tense", "aggressive"})
fx(6, "Impact Deep", "impact", 1, 0.8, 0.2, 0.2, {"deep", "dark"})
fx(7, "Impact Bright", "impact", 1, 0.8, 0.2, 0.75, {"bright"})
fx(8, "Impact Hit", "impact", 1, 0.9, 0.3, 0.5, {"aggressive"})
fx(9, "Downlifter Long", "downlifter", 4, 0.4, 0.3, 0.5, {"dreamy", "warm"})
fx(10, "Downlifter Short", "downlifter", 2, 0.45, 0.3, 0.4, {"dark", "tense"})
fx(11, "Crash Bright", "crash", 1, 0.7, 0.2, 0.9, {"bright"})
fx(12, "Crash Soft", "crash", 1, 0.5, 0.15, 0.7, {"warm"})

return blocks
