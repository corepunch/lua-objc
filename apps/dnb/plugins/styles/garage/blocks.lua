-- UK garage blocks. Flavours: twostep, speed, future, bassline, dark.
--
-- The genre in one paragraph: the kick skips (1 and the "and" of 3, ghost
-- kicks around them) and leaves beats 2 and 4 to a snare or rim; hats are
-- shuffled, never straight sixteenths; the bass is syncopated and weighty,
-- never rolling; chords are minor 7ths/9ths stabbed off the beat on organ
-- or Rhodes; the hook is a pitched, vocal-sounding phrase. Speed garage and
-- bassline go back to four on the floor, bassline on a donk bass; future
-- garage thins everything into half-time rim and sub; dark garage is all
-- sub and square stabs. Garage uses risers rarely (a short sweep into the
-- drop, mostly a drum-and-vocal gap), so the fx set is small, dubby and has
-- only a few of them.
local list = {}

local function add(role, number, spec)
	spec.id = string.format("garage.%s.%03d", role, number)
	spec.role = role
	table.insert(list, spec)
end

-- Drums ----------------------------------------------------------------------
-- Quiet loops first (the first and last bars of a DJ mix), then the grooves
-- of each flavour up to the full kit.

-- One bar, kick and a shuffled hat: enough to mix a record in.
add("drums", 1, {bars = 1, energy = 0.2, density = 0.2, tags = {"twostep", "shuffle", "minimal", "sparse", "mixable"},
	lanes = {
		{"kick", "X.........x....."},
		{"hat", ".x.x.x.x.x.x.x.x", gain = 0.3},
		{"rim", "............x...", gain = 0.3},
	}})
-- Kick, snare on 2 and 4 and a skipped hat: the 2-step skeleton.
add("drums", 2, {bars = 2, energy = 0.28, density = 0.3, tags = {"twostep", "swung", "sparse", "mixable"},
	lanes = {
		{"kick", "X.........x.....|X.........x..x.."},
		{"snare", "....X.......X...", gain = 0.8},
		{"hat", "..x...x...x...x.|..x...x...x.x.x.", gain = 0.28},
	}})
-- Future garage: only a rim on 2 and a distant kick, the air does the rest.
add("drums", 3, {bars = 2, energy = 0.3, density = 0.25, tags = {"twostep", "minimal", "sparse", "dreamy", "mixable"},
	flavours = {"future"},
	lanes = {
		{"kick", "X......x........|X.........x....."},
		{"rim", "....x...........|....x.......x...", gain = 0.5},
		{"hat", ".x...x.x.x...x.x", gain = 0.25},
		{"shaker", "..x...x...x...x.", gain = 0.2, when = "complexity"},
	}})
-- Dark garage: tight clipped hats on a sparse sub-led kick.
add("drums", 4, {bars = 2, energy = 0.35, density = 0.35, tags = {"twostep", "dark", "swung", "mixable"},
	flavours = {"dark"},
	lanes = {
		{"kick", "X.....x...x.....|X.........x.x..."},
		{"snare", "....x.......x...", gain = 0.7},
		{"hat", "x.xxx.xxx.xxx.xx", gain = 0.22},
	}})
-- Four kicks and offbeat hats, nothing else: speed garage as a DJ tool.
add("drums", 5, {bars = 1, energy = 0.4, density = 0.3, tags = {"fourfloor", "straight", "minimal", "driving", "mixable"},
	flavours = {"speed", "bassline"},
	lanes = {
		{"kick", "X...X...X...X..."},
		{"hat", "..x...x...x...x.", gain = 0.35},
		{"clap", "....x.......x...", gain = 0.45, light = false},
	}})
-- Ghost snares and a swung rim around the two-step kick.
add("drums", 6, {bars = 2, energy = 0.45, density = 0.45, tags = {"twostep", "shuffle", "swung", "syncopated", "mixable"},
	flavours = {"twostep"},
	lanes = {
		{"kick", "X..x......x.....|X.........x.x..."},
		{"snare", "....X.......X...", gain = 0.85},
		{"ghost", "..........g..g..|.......g..g...g.", gain = 0.5, when = "complexity"},
		{"hat", ".x.x.x.x.x.x.x.x", gain = 0.33},
		{"rim", ".......x........|.......x.....x..", gain = 0.35},
	}})
-- The classic 2-step: skipping kick, backbeat snare, swung hats.
add("drums", 7, {bars = 2, energy = 0.52, density = 0.5, tags = {"twostep", "swung", "shuffle", "syncopated"},
	lanes = {
		{"kick", "X.........x.....|X.........x..x.."},
		{"snare", "....X.......X...", gain = 0.9},
		{"clap", "....x.......x...", gain = 0.5, light = false},
		{"hat", ".x.x.x.x.x.x.x.x", gain = 0.4},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.22, when = "energy"},
		{"openHat", "..............x.", gain = 0.45, light = false},
	}})
-- Kick that skips twice a bar, a late snare on the "a" of 4.
add("drums", 8, {bars = 2, energy = 0.58, density = 0.55, tags = {"twostep", "syncopated", "swung"},
	flavours = {"twostep", "dark"},
	lanes = {
		{"kick", "X......x..x.....|X.x.......x....."},
		{"snare", "....X.......X...|....X.......X..x", gain = 0.9},
		{"hat", ".x.x.x.x.x.x.x.x", gain = 0.38},
		{"openHat", "......x.......x.", gain = 0.4, light = false},
		{"rim", "...x.....x.....x", gain = 0.4, when = "complexity"},
	}})
-- Half-time feel: the snare lands on 3, a rim on 2 holds the swing.
add("drums", 9, {bars = 2, energy = 0.5, density = 0.4, tags = {"twostep", "halftime", "swung", "dreamy"},
	flavours = {"future", "dark"},
	lanes = {
		{"kick", "X......x..x.....|X.........x....."},
		{"snare", "........X.......", gain = 0.85},
		{"rim", "....x...........|....x.......x...", gain = 0.5},
		{"hat", ".x...x.x.x...x.x", gain = 0.33},
		{"openHat", "..........x.....", gain = 0.3, when = "energy"},
		{"ghost", ".........g.....g", when = "complexity"},
	}})
-- Speed garage: four kicks, clap on 2 and 4, open hats on the offbeat.
add("drums", 10, {bars = 2, energy = 0.65, density = 0.55, tags = {"fourfloor", "driving", "straight", "shuffle"},
	flavours = {"speed", "bassline"},
	lanes = {
		{"kick", "X...X...X...X..."},
		{"clap", "....X.......X...", gain = 0.85, light = false},
		{"snare", "....x.......x...", gain = 0.5},
		{"hat", ".x.x.x.x.x.x.x.x", gain = 0.4},
		{"openHat", "..x...x...x...x.", gain = 0.5},
		{"rim", ".......x.......x|.......x.....x.x", gain = 0.35, when = "complexity"},
	}})
-- Bassline: four kicks, claps, a shaker pushing the offbeat.
add("drums", 11, {bars = 2, energy = 0.72, density = 0.62, tags = {"fourfloor", "driving", "bright", "playful"},
	flavours = {"bassline"},
	lanes = {
		{"kick", "X...X...X...X..."},
		{"clap", "....X.......X...", gain = 0.9, light = false},
		{"hat", "..x...x...x...x.", gain = 0.5},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.22, when = "energy"},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.25, when = "energy"},
		{"snare", "...............x", gain = 0.5, when = "complexity"},
	}})
-- Full 2-step: skipping kick, rim fills, conga and shaker under it.
add("drums", 12, {bars = 2, energy = 0.76, density = 0.75, tags = {"twostep", "busy", "swung", "syncopated", "playful"},
	flavours = {"twostep"},
	lanes = {
		{"kick", "X.........x.....|X.x.......x..x.."},
		{"snare", "....X.......X...", gain = 0.9},
		{"clap", "....x.......x...", gain = 0.55},
		{"hat", ".x.x.x.x.x.x.x.x", gain = 0.4},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.25},
		{"openHat", "..............x.", gain = 0.45},
		{"rim", ".......x.......x|.......x.x.....x", gain = 0.4},
		{"shaker", "..x...x...x...x.", gain = 0.35},
		{"conga", "...x.....x..x...|.x...x......x...", gain = 0.35, when = "complexity"},
	}})
-- Dark garage at full weight: 16th hats crushed under a stuttering kick.
add("drums", 13, {bars = 2, energy = 0.82, density = 0.8, tags = {"twostep", "dark", "busy", "tense", "syncopated"},
	flavours = {"dark"},
	lanes = {
		{"kick", "X.....x...x.....|X.....x...x.x.x."},
		{"snare", "....X.......X...", gain = 0.95},
		{"clap", "....x.......x...", gain = 0.5},
		{"hat", "x.xxx.xxx.xxx.xx", gain = 0.32},
		{"openHat", "..x.......x.....", gain = 0.38},
		{"rim", ".......x.....x..", gain = 0.4},
		{"ghost", ".g.....g....g...", gain = 0.5},
	}})
-- Speed garage with ghost snares and a kick that dips in the last beat.
add("drums", 14, {bars = 2, energy = 0.86, density = 0.78, tags = {"fourfloor", "busy", "driving", "shuffle"},
	flavours = {"speed"},
	lanes = {
		{"kick", "X...X...X...X...|X...X...X...X.x."},
		{"clap", "....X.......X...", gain = 0.9},
		{"snare", "....x.......x..x|....x.......x.xx", gain = 0.55},
		{"hat", ".x.x.x.x.x.x.x.x", gain = 0.42},
		{"openHat", "..x...x...x...x.", gain = 0.5},
		{"tambourine", "x.o.x.o.x.o.x.o.", gain = 0.3, when = "energy"},
		{"ghost", "..g...g...g...g.", gain = 0.4, when = "complexity"},
	}})
-- Bassline peak: claps stacked on snares, a rim skip and open hats.
add("drums", 15, {bars = 2, energy = 0.92, density = 0.88, tags = {"fourfloor", "busy", "driving", "bright", "playful"},
	flavours = {"bassline", "speed"},
	lanes = {
		{"kick", "X...X...X...X..."},
		{"clap", "....X.......X...", gain = 0.95},
		{"snare", "....x.......x...|....x.......x.xx", gain = 0.6},
		{"hat", ".x.x.x.x.x.x.x.x", gain = 0.45},
		{"openHat", "..x...x...x...x.", gain = 0.55},
		{"rim", ".......x.......x|.x.....x.....x..", gain = 0.4},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.3},
		{"cowbell", "...........x....", gain = 0.25, when = "complexity"},
	}})
-- Four bars: the 2-step groove, then a turnaround of snare skips into the
-- next phrase. The one drum block that is always at the top of the range.
add("drums", 16, {bars = 4, energy = 1.0, density = 0.95, tags = {"twostep", "busy", "syncopated", "swung", "driving"},
	lanes = {
		{"kick", "X.........x.....|X.........x..x..|X......x..x.....|X.x.....x.x..x.x"},
		{"snare", "....X.......X...|....X.......X...|....X.......X...|....X..x....X.xX", gain = 0.95},
		{"clap", "....x.......x...", gain = 0.5},
		{"hat", ".x.x.x.x.x.x.x.x|.x.x.x.x.x.x.x.x|.x.x.x.x.x.x.x.x|xxxxxxxxxxxxxxxx", gain = 0.42},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.25},
		{"openHat", "..............x.|......x.......x.|..............x.|................", gain = 0.45},
		{"rim", ".......x.......x|.......x.x.....x", gain = 0.4},
		{"shaker", "..x...x...x...x.", gain = 0.35},
		{"ghost", ".......g..g...g.", gain = 0.5, when = "complexity"},
	}})

-- Tops -----------------------------------------------------------------------
-- A second layer over the kit: the shuffle lives here.

-- Skipped hats on the swung grid.
add("tops", 1, {bars = 1, energy = 0.3, density = 0.3, tags = {"shuffle", "swung", "sparse", "mixable"},
	lanes = {{"hat", "x..x.xx..x.xx.x.", gain = 0.3}}})
-- Shaker on the offbeat sixteenths, the cheapest way to open a groove.
add("tops", 2, {bars = 1, energy = 0.4, density = 0.45, tags = {"shuffle", "swung", "mixable"},
	lanes = {{"shaker", "..x...x...x...x.", gain = 0.3}, {"hat", ".o.o.o.o.o.o.o.o", gain = 0.2}}})
-- Open hat after every other quaver: the 4x4 bounce.
add("tops", 3, {bars = 1, energy = 0.5, density = 0.4, tags = {"offbeat", "straight", "fourfloor", "driving"},
	flavours = {"speed", "bassline"},
	lanes = {{"openHat", "..x...x...x...x.", gain = 0.5}, {"hat", "x.x.x.x.x.x.x.x.", gain = 0.2}}})
-- Rimshots and woodblock-like claves scattered across two bars.
add("tops", 4, {bars = 2, energy = 0.5, density = 0.4, tags = {"syncopated", "playful", "sparse"},
	flavours = {"twostep", "future"},
	lanes = {
		{"rim", ".......x.......x|.......x.x.....x", gain = 0.4},
		{"clave", "...x.....x......|.x.....x...x....", gain = 0.3, when = "complexity"},
	}})
-- Congas answering the hats, a house-flavoured tops loop.
add("tops", 5, {bars = 2, energy = 0.6, density = 0.6, tags = {"swung", "playful", "busy", "warm"},
	flavours = {"twostep", "speed"},
	lanes = {
		{"conga", "...x.....x..x...|.x...x......x...", gain = 0.4},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.25},
		{"tambourine", "....x.......x...", gain = 0.3, when = "energy"},
	}})
-- Sixteenth hats with an open hat on the "a" of 2 (dark garage tick).
add("tops", 6, {bars = 1, energy = 0.65, density = 0.7, tags = {"dark", "tense", "busy", "syncopated"},
	flavours = {"dark"},
	lanes = {{"hat", "x.xxx.xxx.xxx.xx", gain = 0.3}, {"openHat", "......x.......x.", gain = 0.35}}})
-- Triplet-ish ride and cowbell for bassline's party feel.
add("tops", 7, {bars = 2, energy = 0.75, density = 0.7, tags = {"playful", "bright", "busy", "swung"},
	flavours = {"bassline"},
	lanes = {
		{"ride", "x.x.x.x.x.x.x.x.", gain = 0.3},
		{"cowbell", "...x.......x....|...x.......x..x.", gain = 0.3},
		{"tambourine", "..x...x...x...x.", gain = 0.3},
	}})
-- Hat flutter into the next bar: a one-bar fill layer for dense phrases.
add("tops", 8, {bars = 2, energy = 0.85, density = 0.9, tags = {"busy", "swung", "driving", "bright"},
	lanes = {
		{"hat", "x.xxx.xxx.xxx.xx|xxxxxxxxxxxxxxxx", gain = 0.35},
		{"openHat", "..x...x...x...x.|..x.....x.....x.", gain = 0.4},
		{"shaker", "xoxoxoxoxoxoxoxo", gain = 0.25},
	}})

-- Bass -----------------------------------------------------------------------
-- Syncopated, weighty and never rolling: notes land off the beat and the
-- space between them is the groove.

-- A held sub with one late push into the next bar.
add("bass", 1, {bars = 1, energy = 0.25, density = 0.15, brightness = 0.1, tags = {"sub", "pedal", "sparse", "deep", "dreamy"},
	flavours = {"future", "dark", "twostep"}, notes = "0:0:6 10:0:5 15:0:1?"})
-- Two-bar bounce: root, quaver pick-up, octave slide, fifth to land on.
add("bass", 2, {bars = 2, energy = 0.5, density = 0.45, brightness = 0.3, tags = {"sub", "syncopated", "swung", "warm"},
	flavours = {"twostep", "future"},
	notes = "0:0:3 3:0:1 6:7:2~ 10:0:2 13:4:3~ | 0:0:3 3:0:1 6:7:2~ 10:0:2 12:2:2 14:4:2"})
-- The third in the offbeat: a skip that sits between two kicks.
add("bass", 3, {bars = 2, energy = 0.45, density = 0.4, brightness = 0.3, tags = {"sub", "syncopated", "soulful"},
	notes = "0:0:2 2:7:2~ 7:0:2? 10:2:4~ | 0:0:3 3:0:2 7:4:2~ 10:2:2 13:0:3"})
-- Lazy roll: a long root, a ghost note and a fifth lifting into the chord.
add("bass", 4, {bars = 2, energy = 0.4, density = 0.35, brightness = 0.25, tags = {"sub", "syncopated", "pedal", "warm"},
	flavours = {"twostep", "future", "speed"},
	notes = "0:0:4 6:0:1 7:7:2~ 11:6:1? 12:4:4~ | 0:0:5 7:0:2 10:0:2 13:-1:3~"})
-- Donk: a short filtered pluck on every skipped eighth, octave pops accented.
add("bass", 5, {bars = 1, energy = 0.8, density = 0.7, brightness = 0.6, tags = {"pluck", "stab", "syncopated", "playful"},
	flavours = {"bassline"},
	notes = "2:0:1 3:0:1? 6:0:1 7:7:1! 10:0:1 11:0:1? 14:6:1 15:7:1!"})
-- Donk, two bars: the second bar turns around on the fifth.
add("bass", 6, {bars = 2, energy = 0.72, density = 0.6, brightness = 0.6, tags = {"pluck", "stab", "syncopated", "bright"},
	flavours = {"bassline"},
	notes = "0:0:1 2:0:1 6:0:1 8:7:1! 10:0:1 14:7:1 | 0:0:1 2:0:1 6:4:1 8:7:1! 10:4:1 12:0:1 14:7:1!"})
-- Speed garage reese: long wobbling notes that drop and climb under the chord.
add("bass", 7, {bars = 2, energy = 0.75, density = 0.45, brightness = 0.45, tags = {"reese", "wobble", "syncopated", "dark"},
	flavours = {"speed", "dark"},
	notes = "0:0:6w2 6:0:2w4 8:7:4w3~ 12:0:4w2? | 0:0:6w2 6:0:2w4 8:6:4w3~ 12:4:4w2?"})
-- Four-bar reese phrase with a warble that speeds up and a fifth for relief.
add("bass", 8, {bars = 4, energy = 0.8, density = 0.5, brightness = 0.45, tags = {"reese", "wobble", "driving", "tense"},
	flavours = {"speed"},
	notes = "0:0:6w2 8:0:2w4 10:0:2 13:7:3w3~ | 0:0:6w2 8:4:4w3 12:0:4w2 | 0:0:6w2 6:0:2w4 8:7:4w3~ 12:6:2 14:7:2w4 | 0:0:4w2 4:0:4w3 8:-1:4w3~ 12:0:4w4"})
-- Dark sub: whole notes, the flat seventh underneath for tension.
add("bass", 9, {bars = 2, energy = 0.55, density = 0.3, brightness = 0.1, tags = {"sub", "pedal", "dark", "deep", "minimal"},
	flavours = {"dark", "future"},
	notes = "0:0:6 7:0:1 10:-1:3~ 13:0:2? | 0:0:6 7:0:1? 10:0:2 13:-1:3~"})
-- Organ-style walking bass: a quarter-note-ish line through the chord tones.
add("bass", 10, {bars = 4, energy = 0.55, density = 0.5, brightness = 0.4, tags = {"walking", "soulful", "warm", "stepwise"},
	flavours = {"twostep"},
	notes = "0:0:3 4:2:2 8:4:3 12:2:2 | 0:0:3 4:4:2 8:7:3 12:4:2 | 0:0:3 4:2:2 8:4:3 12:6:2~ | 0:7:3 4:4:2 8:2:3 12:0:3~"})
-- 808 slides: a long note that glides down a fifth and up again.
add("bass", 11, {bars = 2, energy = 0.4, density = 0.25, brightness = 0.15, tags = {"sub", "pedal", "deep", "melancholic", "sparse"},
	flavours = {"future"},
	notes = "0:0:7 8:0:1 10:-2:4~ 14:0:2~ | 0:0:5 6:2:2 8:0:4 12:-1:4~"})
-- Octave jump: root, a high pop on the offbeat, root. Speed garage staple.
add("bass", 12, {bars = 1, energy = 0.65, density = 0.55, brightness = 0.5, tags = {"octave", "syncopated", "driving", "playful"},
	flavours = {"speed", "bassline"},
	notes = "0:0:2 3:7:2 6:0:2 8:0:2 11:7:2 14:0:2"})
-- A pump of short notes that leaves the kick its space.
add("bass", 13, {bars = 1, energy = 0.6, density = 0.6, brightness = 0.4, tags = {"pluck", "syncopated", "swung", "rhythmic"},
	notes = "0:0:1 3:0:2 6:0:1 10:0:1 12:0:2 14:7:1?"})
-- Notes only while Energy is up: the verse is just the root.
add("bass", 14, {bars = 2, energy = 0.5, density = 0.4, brightness = 0.3, tags = {"sub", "syncopated", "soulful"},
	flavours = {"twostep", "speed", "future"},
	notes = "0:0:4 5:0:1? 7:7:2~ 10:0:3 13:2:3?~ | 0:0:4 5:0:1? 7:0:2 10:-1:3~ 13:4:3?"})
-- Dotted rhythm over four bars: root, flat seventh, fifth and back.
add("bass", 15, {bars = 4, energy = 0.65, density = 0.5, brightness = 0.35, tags = {"syncopated", "dark", "rhythmic", "tense"},
	flavours = {"dark", "speed"},
	notes = "0:0:3 3:0:3 6:0:2 10:-1:3 14:0:2 | 0:0:3 3:0:3 6:0:2 10:4:3 14:0:2 | 0:0:3 3:0:3 6:0:2 10:-1:3 14:-1:2 | 0:0:3 3:4:3 6:2:2 10:0:4~"})
-- Bassline gallop: a stuttering 16th pulse, the most aggressive line here.
add("bass", 16, {bars = 2, energy = 0.95, density = 0.9, brightness = 0.7, tags = {"pluck", "stab", "driving", "busy", "aggressive"},
	flavours = {"bassline"},
	notes = "0:0:1 2:0:1 3:0:1 6:0:1 7:7:1! 8:0:1 10:0:1 11:0:1 14:6:1 15:7:1! | 0:0:1 2:0:1 3:0:1 6:0:1 7:7:1! 8:0:1 10:4:1 11:4:1 14:2:1 15:0:1!"})
-- One-bar dark stab bass: tight 16ths that never settle.
add("bass", 17, {bars = 1, energy = 0.85, density = 0.8, brightness = 0.5, tags = {"stab", "dark", "tense", "syncopated", "busy"},
	flavours = {"dark"},
	notes = "0:0:1 2:0:1 3:0:1 5:0:1 7:0:1 10:-1:1 11:-1:1 14:0:1"})
-- A long root that pickups into the next chord's root by a slide.
add("bass", 18, {bars = 2, energy = 0.35, density = 0.2, brightness = 0.2, tags = {"sub", "pedal", "held", "warm", "sparse"},
	notes = "0:0:12 14:-1:2~ | 0:0:10 11:0:1? 12:2:2 14:4:2~"})
-- Reese on a single repeated skip: the whole line is two notes and the swing.
add("bass", 19, {bars = 1, energy = 0.7, density = 0.35, brightness = 0.4, tags = {"reese", "syncopated", "minimal", "dark"},
	flavours = {"speed", "dark"},
	notes = "0:0:5w2 6:0:3w3 10:7:2~ 13:0:3w2"})

-- Pad ------------------------------------------------------------------------
-- Warm, soft and mostly sustained; garage chords are rich (7ths, 9ths).

add("pad", 1, {bars = 4, energy = 0.2, density = 0.1, brightness = 0.35, tags = {"held", "warm", "dreamy", "ambient"}, hold = true})
add("pad", 2, {bars = 4, energy = 0.3, density = 0.15, brightness = 0.6, tags = {"held", "dreamy", "melancholic", "deep"},
	flavours = {"future", "twostep"}, hold = true})
-- A swell and release on each bar: a pad that breathes with the kick.
add("pad", 3, {bars = 2, energy = 0.45, density = 0.3, brightness = 0.4, tags = {"chordal", "warm", "soulful"}, comp = "0:12"})
add("pad", 4, {bars = 4, energy = 0.4, density = 0.1, brightness = 0.25, tags = {"held", "dark", "deep", "tense"},
	flavours = {"dark", "future"}, hold = true})
-- Two pulses a bar: a short chord on the one, another on the "and" of 3.
add("pad", 5, {bars = 2, energy = 0.55, density = 0.4, brightness = 0.5, tags = {"chordal", "rhythmic", "syncopated", "warm"},
	comp = "0:5 10:5"})
add("pad", 6, {bars = 4, energy = 0.75, density = 0.3, brightness = 0.75, tags = {"held", "bright", "euphoric", "warm"},
	flavours = {"speed", "bassline", "twostep"}, hold = true})

-- Keys -----------------------------------------------------------------------
-- Rhodes, Wurlitzer, organ and piano: the chord rhythm is the groove's other half.

add("keys", 1, {bars = 1, energy = 0.25, density = 0.15, brightness = 0.4, tags = {"chordal", "sparse", "soulful", "warm"},
	comp = "0:6"})
add("keys", 2, {bars = 2, energy = 0.35, density = 0.25, brightness = 0.5, tags = {"chordal", "syncopated", "soulful", "dreamy"},
	flavours = {"future", "twostep"}, comp = "3:3 10:5 | 3:3 11:4"})
-- Rhodes on the skip: the bar's first chord lands just before beat 2.
add("keys", 3, {bars = 2, energy = 0.45, density = 0.4, brightness = 0.5, tags = {"chordal", "syncopated", "swung", "soulful"},
	comp = "3:2 6:2 10:4 | 3:2 6:2 10:2 13:3"})
add("keys", 4, {bars = 1, energy = 0.5, density = 0.45, brightness = 0.55, tags = {"chordal", "rhythmic", "swung", "warm"},
	flavours = {"twostep", "speed"}, comp = "2:2 5:1 8:3 11:2 14:2?"})
-- Organ chops: held chord on the one, a stab on the "and" of 4.
add("keys", 5, {bars = 2, energy = 0.6, density = 0.5, brightness = 0.6, tags = {"chordal", "rhythmic", "playful", "bright"},
	flavours = {"speed", "bassline"}, comp = "0:3 4:1 7:2! 10:2 14:2 | 0:3 4:1 7:2! 10:4"})
add("keys", 6, {bars = 4, energy = 0.4, density = 0.2, brightness = 0.3, tags = {"chordal", "held", "dark", "deep", "sparse"},
	flavours = {"dark", "future"}, comp = "0:8 | 0:8 10:4 | 0:8 | 6:2 10:6"})
-- Piano house chords hit on every offbeat: bassline-meets-house.
add("keys", 7, {bars = 1, energy = 0.75, density = 0.65, brightness = 0.7, tags = {"chordal", "offbeat", "driving", "bright"},
	flavours = {"bassline", "speed"}, comp = "2:2 6:2! 10:2 14:2!"})
add("keys", 8, {bars = 2, energy = 0.85, density = 0.8, brightness = 0.7, tags = {"chordal", "busy", "syncopated", "euphoric", "playful"},
	comp = "0:2 3:1 6:2! 8:1 10:2 12:1 14:2! | 0:2 3:1 6:2! 10:3 13:1 14:1!"})

-- Stab -----------------------------------------------------------------------
-- Chopped organ, pizzicato, brass and square stabs: short, off the beat.

add("stab", 1, {bars = 1, energy = 0.3, density = 0.1, brightness = 0.5, tags = {"stab", "sparse", "syncopated", "soulful"},
	comp = "6:1"})
add("stab", 2, {bars = 2, energy = 0.4, density = 0.2, brightness = 0.5, tags = {"stab", "syncopated", "playful", "swung"},
	flavours = {"twostep", "future"}, comp = "3:1 6:1 | 6:1 14:1"})
add("stab", 3, {bars = 2, energy = 0.5, density = 0.3, brightness = 0.55, tags = {"stab", "syncopated", "warm", "soulful"},
	comp = "0:1 3:1 10:1 | 0:1 6:1 10:1 13:1"})
add("stab", 4, {bars = 2, energy = 0.55, density = 0.35, brightness = 0.6, tags = {"stab", "offbeat", "bright", "playful"},
	flavours = {"speed", "bassline"}, comp = "2:1 6:1 10:1 14:1 | 2:1 6:1 10:1 13:1 14:1!"})
add("stab", 5, {bars = 1, energy = 0.65, density = 0.45, brightness = 0.6, tags = {"stab", "syncopated", "dark", "tense"},
	flavours = {"dark"}, comp = "0:1 3:1 7:1 10:1 11:1?"})
-- Organ shot that falls on the "a" of 2 and rings: the speed garage skank.
add("stab", 6, {bars = 2, energy = 0.7, density = 0.5, brightness = 0.65, tags = {"stab", "syncopated", "driving", "playful"},
	flavours = {"speed", "bassline"}, comp = "3:2 6:1! 10:2 | 3:2 6:1! 10:1 14:1!"})
add("stab", 7, {bars = 4, energy = 0.6, density = 0.4, brightness = 0.55, tags = {"stab", "swung", "soulful", "syncopated"},
	flavours = {"twostep"}, comp = "3:1 6:1 | 6:1 14:1 | 3:1 6:1 10:1 | 6:1 10:1 13:1!"})
-- A hit on every offbeat 16th: busy, urgent, the dark garage stutter.
add("stab", 8, {bars = 1, energy = 0.9, density = 0.8, brightness = 0.7, tags = {"stab", "busy", "aggressive", "dark", "rhythmic"},
	flavours = {"dark", "bassline"}, comp = "0:1 2:1 3:1 6:1 7:1! 10:1 11:1 14:1!"})

-- Arp ------------------------------------------------------------------------
-- Plucked, bell and marimba lines running the chord on a swung grid.

add("arp", 1, {energy = 0.25, density = 0.2, brightness = 0.7, tags = {"arpeggio", "sparse", "dreamy", "ambient"},
	flavours = {"future"}, order = {1, 3, 5, 3}, rate = 4, gate = 0.8, mask = "XxxxXxxxXxxxXxxx", octave = 2})
add("arp", 2, {energy = 0.35, density = 0.3, brightness = 0.65, tags = {"arpeggio", "swung", "warm", "playful"},
	order = {1, 2, 3, 4, 3, 2}, rate = 2, gate = 0.6, mask = "XxXxXxXxXxXxXxXx", octave = 1})
add("arp", 3, {energy = 0.45, density = 0.4, brightness = 0.7, tags = {"arpeggio", "syncopated", "bright", "soulful"},
	flavours = {"twostep", "future"}, order = {1, 3, 2, 4, 5}, rate = 2, gate = 0.5, mask = "X.xX.xX.xX.xX.xX", octave = 2})
add("arp", 4, {energy = 0.5, density = 0.5, brightness = 0.6, tags = {"arpeggio", "stepwise", "dreamy", "melancholic"},
	order = {1, 2, 3, 2, 4, 3, 5, 4}, rate = 2, gate = 0.8, mask = "XXXxXXXxXXXxXXXx", octave = 1})
add("arp", 5, {energy = 0.6, density = 0.6, brightness = 0.7, tags = {"arpeggio", "driving", "bright", "playful"},
	flavours = {"speed", "bassline"}, order = {1, 3, 5, 3, 1, 3, 5, 4}, rate = 1, gate = 0.4, mask = "XxxXxxXxXxxXxxXx", octave = 2})
add("arp", 6, {energy = 0.7, density = 0.7, brightness = 0.6, tags = {"arpeggio", "dark", "tense", "rhythmic"},
	flavours = {"dark"}, order = {1, 1, 3, 1, 5, 3, 1, 4}, rate = 1, gate = 0.5, mask = "XxXxxXxxXxXxxXxx", octave = 1})
add("arp", 7, {energy = 0.8, density = 0.8, brightness = 0.8, tags = {"arpeggio", "busy", "euphoric", "bright"},
	order = {1, 3, 5, 4, 6, 5, 3, 4}, rate = 1, gate = 0.55, mask = "XXxXXxXXXxXXXxXX", octave = 2})
add("arp", 8, {energy = 0.4, density = 0.35, brightness = 0.55, tags = {"arpeggio", "sparse", "soulful", "swung"},
	flavours = {"twostep"}, order = {1, 4, 3, 5}, rate = 4, gate = 0.9, mask = "XXXxXXXxXXXxXXXx", octave = 1})

-- Lead -----------------------------------------------------------------------
-- Four-bar hooks. Pitches are scale steps (0 the root, 2 the third, 4 the
-- fifth, 7 the octave); a hook sung over a changing chord moves with it.

-- A call and a lower answer, long notes slid into like a held vocal.
add("lead", 1, {bars = 4, energy = 0.45, density = 0.3, brightness = 0.5, tags = {"hook", "vocal", "soulful", "stepwise", "held"},
	flavours = {"twostep", "future"},
	notes = "0:7:3 3:6:1~ 4:4:4 | 8:2:2 10:3:2 12:4:4 | 0:7:3 3:6:1~ 4:4:4 | 8:4:2 10:2:2 12:0:4"})
-- A sigh: two notes a bar, each slid into, falling to the root.
add("lead", 2, {bars = 4, energy = 0.3, density = 0.15, brightness = 0.45, tags = {"hook", "vocal", "melancholic", "dreamy", "held"},
	flavours = {"future", "dark"},
	notes = "0:4:6 6:3:2~ 8:2:8 | 0:6:6 6:5:2~ 8:4:8 | 0:4:6 6:3:2~ 8:2:4 12:1:4 | 0:0:12"})
-- Rising third and fifth, a late pickup into the chord change.
add("lead", 3, {bars = 4, energy = 0.5, density = 0.35, brightness = 0.55, tags = {"hook", "vocal", "soulful", "leap"},
	flavours = {"twostep"},
	notes = "2:2:2 4:4:4 10:7:2 12:6:4 | 2:2:2 4:4:4 10:9:4 14:7:2 | 2:2:2 4:4:4 10:7:2 12:6:4 | 0:4:4 6:2:2 10:0:6"})
-- A syncopated hook in 16ths that skips like the kick underneath it.
add("lead", 4, {bars = 2, energy = 0.6, density = 0.5, brightness = 0.6, tags = {"hook", "riff", "syncopated", "playful"},
	notes = "0:4:1 3:4:2 6:6:2 10:4:2 13:2:3 | 0:4:1 3:4:2 6:7:2 10:6:2 13:4:3"})
-- Hoover-style riff held still against the chord changes.
add("lead", 5, {bars = 4, energy = 0.75, density = 0.55, brightness = 0.7, tags = {"hook", "riff", "rhythmic", "driving", "bright"},
	flavours = {"speed", "bassline"}, follow = "key",
	notes = "0:4:1 2:4:1 3:4:2 6:6:2 8:4:2 11:2:2 14:4:2 | 0:4:1 2:4:1 3:4:2 6:7:2 8:6:2 11:4:4 | 0:4:1 2:4:1 3:4:2 6:6:2 8:4:2 11:2:2 14:4:2 | 0:2:1 2:2:1 3:2:2 6:3:2 8:0:6"})
-- A pentatonic tune that sits in the middle and answers itself.
add("lead", 6, {bars = 4, energy = 0.55, density = 0.4, brightness = 0.55, tags = {"hook", "answer", "playful", "stepwise"},
	notes = "0:2:2 3:4:2 6:7:3 10:4:4 | 0:2:2 3:4:2 6:6:3 10:4:4 | 0:4:2 3:7:2 6:9:3 10:7:4 | 0:6:2 3:4:2 6:2:2 10:0:6"})
-- Morse-like repeated notes, dark garage's one-note insistence.
add("lead", 7, {bars = 2, energy = 0.65, density = 0.45, brightness = 0.55, tags = {"hook", "riff", "rhythmic", "dark", "tense", "minimal"},
	flavours = {"dark"}, follow = "key",
	notes = "0:4:1 1:4:1 3:4:1 6:4:2 10:3:1 11:3:1 13:2:3 | 0:4:1 1:4:1 3:4:1 6:4:2 10:3:1 11:3:1 13:0:3"})
-- Octave bounce: the same note high and low, a bassline party favourite.
add("lead", 8, {bars = 2, energy = 0.8, density = 0.6, brightness = 0.7, tags = {"hook", "rhythmic", "leap", "bright", "playful"},
	flavours = {"bassline"}, follow = "key",
	notes = "0:0:2 2:7:2 4:0:2 6:7:2 8:4:2 10:7:2 12:0:2 14:9:2 | 0:0:2 2:7:2 4:0:2 6:7:2 8:6:2 10:7:2 12:4:4"})
-- Space: one slow phrase, a long gap, a held note. For a reverb-washed drop.
add("lead", 9, {bars = 4, energy = 0.25, density = 0.1, brightness = 0.4, tags = {"hook", "vocal", "dreamy", "melancholic", "sparse", "held"},
	flavours = {"future"},
	notes = "0:4:8 8:2:8 | 0:0:16 | 0:2:6 6:4:2~ 8:7:8 | 0:6:4 4:4:4 8:2:8"})
-- A pitched vocal chop riff: quick sixteenths up, then a held sigh down.
add("lead", 10, {bars = 2, energy = 0.7, density = 0.6, brightness = 0.65, tags = {"hook", "vocal", "syncopated", "leap", "playful"},
	flavours = {"twostep", "speed"},
	notes = "3:7:1 4:9:1 6:7:1 8:6:2 11:4:1 13:2:3 | 3:7:1 4:9:1 6:11:1 8:9:2 11:7:2 13:4:3"})
-- Descending step by step: a lament that returns to the root on the last bar.
add("lead", 11, {bars = 4, energy = 0.4, density = 0.25, brightness = 0.5, tags = {"hook", "stepwise", "melancholic", "soulful", "held"},
	notes = "0:7:4 4:6:4 8:5:4 12:4:4 | 0:4:8 10:2:2 12:3:4 | 0:6:4 4:5:4 8:4:4 12:2:4 | 0:2:4 4:1:4 8:0:8"})
-- Arpeggiated hook: the chord sung on a swung grid, a gentle climbing line.
add("lead", 12, {bars = 4, energy = 0.5, density = 0.45, brightness = 0.6, tags = {"hook", "arpeggio", "soulful", "dreamy"},
	flavours = {"twostep", "future"},
	notes = "0:0:2 3:2:2 6:4:2 9:7:2 12:4:4 | 0:0:2 3:2:2 6:4:2 9:9:4 | 0:0:2 3:2:2 6:4:2 9:7:2 12:4:4 | 0:7:2 3:4:2 6:2:2 9:0:7"})
-- A brass-like shout, three hits then a slide off the end.
add("lead", 13, {bars = 2, energy = 0.85, density = 0.5, brightness = 0.75, tags = {"hook", "riff", "bright", "aggressive", "rhythmic"},
	flavours = {"speed", "bassline"}, follow = "key",
	notes = "0:4:2 3:4:2! 6:4:2 10:6:2~ 13:7:3! | 0:4:2 3:4:2! 6:4:2 10:2:2~ 13:0:3!"})
-- A call that waits: two bars of tune, two bars of nothing, then the answer.
add("lead", 14, {bars = 4, energy = 0.35, density = 0.2, brightness = 0.5, tags = {"hook", "answer", "sparse", "vocal", "soulful"},
	notes = "0:7:3 3:6:1 4:4:4 8:2:6~ | | 4:2:2 6:4:2 8:6:6~ | 0:4:4 4:2:4 8:0:8"})

-- Counter --------------------------------------------------------------------
-- Short answers to the lead, a vocal-chop echo in the gaps.

add("counter", 1, {bars = 2, energy = 0.25, density = 0.15, brightness = 0.55, tags = {"answer", "sparse", "vocal", "dreamy"},
	flavours = {"future", "twostep"},
	notes = "12:7:2~ | 4:4:4 12:2:4~"})
add("counter", 2, {bars = 2, energy = 0.4, density = 0.3, brightness = 0.55, tags = {"answer", "stepwise", "soulful", "playful"},
	notes = "10:2:2 12:4:2 14:6:2 | 10:4:2 12:2:2 14:0:2"})
add("counter", 3, {bars = 2, energy = 0.5, density = 0.4, brightness = 0.6, tags = {"answer", "syncopated", "vocal", "playful"},
	flavours = {"twostep", "speed"},
	notes = "5:7:1 6:9:1 8:7:2 11:4:3 | 5:7:1 6:9:1 8:11:2 11:9:3"})
add("counter", 4, {bars = 4, energy = 0.35, density = 0.2, brightness = 0.45, tags = {"answer", "held", "melancholic", "sparse"},
	flavours = {"future", "dark"},
	notes = "8:2:8 | | 8:0:8 | "})
add("counter", 5, {bars = 2, energy = 0.7, density = 0.5, brightness = 0.7, tags = {"answer", "rhythmic", "dark", "tense"},
	flavours = {"dark", "bassline"}, follow = "key",
	notes = "10:4:1 11:4:1 13:2:1 14:4:2 | 10:3:1 11:3:1 13:2:1 14:0:2"})
add("counter", 6, {bars = 2, energy = 0.8, density = 0.6, brightness = 0.7, tags = {"answer", "bright", "leap", "driving"},
	flavours = {"speed", "bassline"},
	notes = "6:7:1 7:9:1 10:7:2 13:4:1 14:7:2 | 6:7:1 7:9:1 10:11:2 13:9:1 14:7:2"})

-- Texture --------------------------------------------------------------------
-- Held fifths and octaves: tape hiss's tonal cousin; garage keeps them low.

add("texture", 1, {bars = 4, energy = 0.1, density = 0.05, brightness = 0.3, tags = {"held", "ambient", "dreamy"}, voices = {0, 7}, every = 4})
add("texture", 2, {bars = 4, energy = 0.2, density = 0.1, brightness = 0.4, tags = {"held", "ambient", "dark", "deep"},
	flavours = {"dark", "future"}, voices = {0, 7, 12}, every = 8})
add("texture", 3, {bars = 4, energy = 0.3, density = 0.1, brightness = 0.6, tags = {"held", "ambient", "warm", "bright"},
	voices = {0, 7, 10}, every = 4})
add("texture", 4, {bars = 4, energy = 0.4, density = 0.15, brightness = 0.5, tags = {"held", "ambient", "melancholic", "dreamy"},
	flavours = {"future", "twostep"}, voices = {0, 3, 7}, every = 2})
add("texture", 5, {bars = 4, energy = 0.5, density = 0.2, brightness = 0.55, tags = {"held", "tense", "dark", "hypnotic"},
	flavours = {"dark", "speed"}, voices = {0, 6, 7}, every = 2})

-- Fx -------------------------------------------------------------------------
-- Dub-style sweeps and sirens. Risers are short; the drop is a gap and a
-- kick, so impacts are small.

add("fx", 1, {bars = 4, energy = 0.5, density = 0.4, brightness = 0.8, tags = {"riser", "tense"}, kind = "riser"})
add("fx", 2, {bars = 8, energy = 0.7, density = 0.5, brightness = 0.9, tags = {"riser", "euphoric", "driving"},
	flavours = {"speed", "bassline"}, kind = "riser"})
add("fx", 3, {bars = 2, energy = 0.4, density = 0.3, brightness = 0.7, tags = {"riser", "dreamy"},
	flavours = {"future", "twostep"}, kind = "riser"})
add("fx", 4, {bars = 4, energy = 0.4, density = 0.3, brightness = 0.4, tags = {"downlifter", "deep"}, kind = "downlifter"})
add("fx", 5, {bars = 2, energy = 0.3, density = 0.2, brightness = 0.5, tags = {"downlifter", "dreamy"},
	flavours = {"future", "dark"}, kind = "downlifter"})
add("fx", 6, {bars = 1, energy = 0.6, density = 0.3, brightness = 0.4, tags = {"impact", "deep"}, kind = "impact"})
add("fx", 7, {bars = 1, energy = 0.8, density = 0.4, brightness = 0.5, tags = {"impact", "aggressive"},
	flavours = {"speed", "bassline", "dark"}, kind = "impact"})
add("fx", 8, {bars = 1, energy = 0.4, density = 0.2, brightness = 0.6, tags = {"impact", "dreamy"},
	flavours = {"future", "twostep"}, kind = "impact"})
add("fx", 9, {bars = 1, energy = 0.7, density = 0.3, brightness = 0.9, tags = {"crash", "bright"}, kind = "crash"})
add("fx", 10, {bars = 1, energy = 0.5, density = 0.2, brightness = 0.8, tags = {"crash", "swung"},
	flavours = {"twostep", "future"}, kind = "crash"})

return list
