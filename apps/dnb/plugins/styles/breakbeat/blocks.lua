-- Breakbeat blocks (see apps/dnb/BLOCKS.md). Flavours: bigbeat, nuskool,
-- florida, funky, progressive, electro, rave. Funk-break tempos 120-140:
-- kicks sit on 1, the "and" of 2 and the "and" of 3, the snare keeps beats 2
-- and 4 and ghost notes fill the sixteenths between. Basslines are slap,
-- tresillo (3+3+2), electro or acid; hooks are riffs, not pads.
-- Breakbeat uses no risers: the arranger places none for this genre. The few
-- fx blocks below are crashes, an impact and a downlifter only.

return {
	-- DRUMS ------------------------------------------------------------------
	-- Quiet, mixable openers: a kick and a shaker-ish hat, nothing tonal.
	{id = "breakbeat.drums.001", role = "drums", bars = 2, energy = 0.2, density = 0.2, brightness = 0.6,
		tags = {"minimal", "sparse", "mixable", "break"}, lanes = {
		{"kick", "X.......x.......|X.....x........."},
		{"hat", "x...x...x...x...", gain = 0.35},
		{"rim", "............x...|................", gain = 0.3, light = false},
	}},
	{id = "breakbeat.drums.002", role = "drums", bars = 1, energy = 0.25, density = 0.25, brightness = 0.6,
		tags = {"minimal", "straight", "mixable", "sparse"}, lanes = {
		{"kick", "X.......X......."},
		{"hat", "..x...x...x...x.", gain = 0.4},
		{"conga", "...x.......x....", gain = 0.3, light = false},
	}},
	{id = "breakbeat.drums.003", role = "drums", bars = 1, energy = 0.3, density = 0.35,
		tags = {"minimal", "straight", "mixable", "playful"}, flavours = {"electro", "florida"}, lanes = {
		{"kick", "X.....x........."},
		{"clap", "....o.......o..."},
		{"hat", "xxxxxxxxxxxxxxxx", gain = 0.22},
	}},
	{id = "breakbeat.drums.004", role = "drums", bars = 2, energy = 0.35, density = 0.4,
		tags = {"broken", "shuffle", "mixable", "warm"}, flavours = {"funky", "progressive", "bigbeat"}, lanes = {
		{"kick", "X.......x.......|X.....x...x....."},
		{"snare", "....o.......o..."},
		{"ghost", ".......g........|.......g.....g..", light = false},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.35},
	}},
	-- Half-time breakbeat: the snare on 3 of a slow-feeling bar.
	{id = "breakbeat.drums.005", role = "drums", bars = 2, energy = 0.4, density = 0.35,
		tags = {"halftime", "broken", "mixable", "deep"}, flavours = {"progressive", "nuskool"}, lanes = {
		{"kick", "X.....x.......x.|X.......x.x...x."},
		{"snare", "........X......."},
		{"ghost", "..........g.....|......g.......g.", light = false},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.3},
		{"openHat", "..............x.", gain = 0.25, when = "energy"},
	}},
	{id = "breakbeat.drums.006", role = "drums", bars = 2, energy = 0.45, density = 0.45,
		tags = {"broken", "syncopated", "mixable"}, lanes = {
		{"kick", "X..x......x.....|X.......x..x...."},
		{"snare", "....X.......X..."},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.35},
		{"ghost", ".......g.....g..", when = "complexity"},
	}},
	-- The classic funk break: ghosts on every offbeat sixteenth.
	{id = "breakbeat.drums.007", role = "drums", bars = 2, energy = 0.55, density = 0.55,
		tags = {"break", "broken", "syncopated", "playful"}, lanes = {
		{"kick", "X.x.......x.....|X.x...x...x..x.."},
		{"snare", "....X.......X..."},
		{"ghost", ".......g.g.....g|.......g......g.", light = false},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.45},
		{"openHat", "......x.......x.", gain = 0.4, when = "energy"},
		{"conga", "...x.......x....", gain = 0.4, when = "complexity"},
	}},
	-- Skipping kick: the second kick lands late, the bar leans forward.
	{id = "breakbeat.drums.008", role = "drums", bars = 2, energy = 0.6, density = 0.55,
		tags = {"break", "broken", "syncopated"}, flavours = {"nuskool", "progressive", "bigbeat", "funky"}, lanes = {
		{"kick", "X......x..x.....|X......x..x..x.."},
		{"snare", "....X.......X..."},
		{"ghost", "..........g.....|......g...g.....", light = false},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.45},
		{"ride", "x...x...x...x...", gain = 0.3, when = "energy"},
		{"rim", "...x.......x....", gain = 0.4, when = "complexity"},
	}},
	-- Electro: the 808 pattern, handclap on the snare, cowbell on top.
	{id = "breakbeat.drums.009", role = "drums", bars = 2, energy = 0.65, density = 0.6,
		tags = {"electro", "syncopated", "straight", "playful"}, flavours = {"electro", "florida"}, lanes = {
		{"kick", "X.....x...x.x...|X.....x...x....."},
		{"snare", "....X.......X..."},
		{"clap", "....x.......x...", gain = 0.6},
		{"hat", "xxxxxxxxxxxxxxxx", gain = 0.3},
		{"openHat", "..x...x...x...x.", gain = 0.35, when = "energy"},
		{"cowbell", "x..x..x...x.x...|x..x..x...x..x..", gain = 0.4, light = false},
	}},
	{id = "breakbeat.drums.010", role = "drums", bars = 2, energy = 0.7, density = 0.7,
		tags = {"break", "busy", "syncopated", "swung"}, lanes = {
		{"kick", "X.x...x...x..x..|X.x...x..x...x.."},
		{"snare", "....X.......X..."},
		{"ghost", ".......g......g.|.......g.g....g.", light = false},
		{"hat", "xoxoxoxoxoxoxoxo", gain = 0.35},
		{"openHat", "......x.......x.", gain = 0.4, when = "energy"},
		{"tambourine", "..x...x...x...x.", gain = 0.35, when = "complexity"},
	}},
	-- Big beat stomp: heavy straight snare, kick on the dotted eighths.
	{id = "breakbeat.drums.011", role = "drums", bars = 2, energy = 0.75, density = 0.55,
		tags = {"break", "driving", "aggressive", "straight"}, flavours = {"bigbeat", "rave"}, lanes = {
		{"kick", "X.....x.x.x.....|X.....x.x.x..x.."},
		{"snare", "....X.......X..."},
		{"clap", "....x.......x...", gain = 0.5, light = false},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.5},
		{"crash", "X...............|................", gain = 0.35, when = "energy"},
		{"ghost", ".......g.....g..", when = "complexity"},
	}},
	{id = "breakbeat.drums.012", role = "drums", bars = 2, energy = 0.8, density = 0.7,
		tags = {"break", "driving", "syncopated"}, flavours = {"nuskool", "progressive", "florida"}, lanes = {
		{"kick", "X..x......x.....|X..x......x.x..."},
		{"snare", "....X.......X..."},
		{"ghost", "......g........g|.......g.g..g.g.", light = false},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.45},
		{"openHat", "..x.......x.....", gain = 0.35, when = "energy"},
		{"cowbell", "x.......x.......", gain = 0.3, when = "complexity"},
	}},
	-- Four bars; the last bar is a snare-and-tom turnaround.
	{id = "breakbeat.drums.013", role = "drums", bars = 4, energy = 0.9, density = 0.8,
		tags = {"break", "busy", "syncopated", "aggressive"}, lanes = {
		{"kick", "X.x...x...x..x..|X.x...x..x...x..|X.x...x...x..x..|X.x.....x.......", },
		{"snare", "....X.......X...|....X.......X...|....X.......X...|....X.......X.X."},
		{"ghost", ".......g.g.....g|.......g......g.|.......g.g....g.|.......g........", light = false},
		{"hat", "xoxoxoxoxoxoxoxo", gain = 0.4},
		{"tomHigh", "................|................|................|..........x.....", gain = 0.5, light = false},
		{"tomMid", "................|................|................|...........x....", gain = 0.5, light = false},
		{"tomLow", "................|................|................|............x.x.", gain = 0.55, light = false},
	}},
	{id = "breakbeat.drums.014", role = "drums", bars = 2, energy = 1.0, density = 0.9,
		tags = {"break", "busy", "driving", "aggressive"}, flavours = {"bigbeat", "rave", "nuskool"}, lanes = {
		{"kick", "X.x.x.x...x.x...|X.x...x.x.x.x.x."},
		{"snare", "....X.......X..."},
		{"clap", "....x.......x..."},
		{"ghost", ".g.g...g.g.g...g|.g.g...g.g.g.g.g", light = false},
		{"hat", "xxxxxxxxxxxxxxxx", gain = 0.4},
		{"crash", "X...............|................", gain = 0.5, when = "energy"},
	}},
	-- Rave: kick gallop under the Amen-weight snare.
	{id = "breakbeat.drums.015", role = "drums", bars = 2, energy = 0.85, density = 0.75,
		tags = {"break", "gallop", "driving", "busy"}, flavours = {"rave", "nuskool"}, lanes = {
		{"kick", "X.x...x...x.x...|X.x...x..x..x.x."},
		{"snare", "....X.......X..."},
		{"ghost", "......g.g.....g.|......g.g...g.g.", light = false},
		{"hat", "xoxoxoxoxoxoxoxo", gain = 0.4},
		{"ride", "x...x...x...x...", gain = 0.3, when = "energy"},
	}},
	{id = "breakbeat.drums.016", role = "drums", bars = 2, energy = 0.7, density = 0.6,
		tags = {"electro", "broken", "syncopated", "dark"}, flavours = {"electro", "nuskool"}, lanes = {
		{"kick", "X..x..x...x.....|X.....x..x..x..."},
		{"snare", "....X.......X..."},
		{"clap", "....x.......x...", gain = 0.5},
		{"hat", "x.xxx.xxx.xxx.xx", gain = 0.3},
		{"cowbell", "..x.......x.....", gain = 0.3, when = "complexity"},
	}},

	-- TOPS -------------------------------------------------------------------
	-- Loose shuffled hats over any kit.
	{id = "breakbeat.tops.001", role = "tops", bars = 1, energy = 0.3, density = 0.4, brightness = 0.9,
		tags = {"shuffle", "swung", "mixable", "sparse"}, lanes = {
		{"hat", "x.xx.xx.x.xx.xx.", gain = 0.3},
		{"tambourine", "....x.......x...", gain = 0.25, when = "complexity"},
	}},
	{id = "breakbeat.tops.002", role = "tops", bars = 1, energy = 0.4, density = 0.55, brightness = 0.9,
		tags = {"swung", "playful", "mixable"}, flavours = {"funky", "bigbeat", "florida"}, lanes = {
		{"tambourine", "xoxoxoxoxoxoxoxo", gain = 0.35},
		{"conga", "...x.......x....", gain = 0.35, when = "complexity"},
	}},
	-- Break loop as top: a funk break at its record tempo.
	{id = "breakbeat.tops.003", role = "tops", bars = 2, energy = 0.6, density = 0.65,
		tags = {"break", "syncopated", "swung"}, flavours = {"funky", "florida", "bigbeat"}, kit = "break", bpm = 102, lanes = {
		{"breakKick", "X.x...x...x..x..|X.x...x...x..o.."},
		{"breakSnare", "....X..g.g.gX..g|....X..g.g.gX.g."},
		{"breakHat", "XoxoXoxoXoxoXoxo", gain = 0.5},
	}},
	-- The Amen in the rave style, at its original tempo.
	{id = "breakbeat.tops.004", role = "tops", bars = 4, energy = 0.9, density = 0.85,
		tags = {"break", "busy", "syncopated", "aggressive"}, flavours = {"rave", "bigbeat", "nuskool"}, kit = "break", bpm = 137, lanes = {
		{"breakKick", "X.x.......x.....|X.x.......x.....|X.x.......x.....|..........xo...."},
		{"breakSnare", "....X..o.o..X..o|....X..o.o..X..o|....X..o.o....X.|..o.X..o.o....X."},
		{"breakRide", "x...x...x...x...", gain = 0.55},
		{"crash", "................|................|................|..........X.....", gain = 0.7},
	}},
	{id = "breakbeat.tops.005", role = "tops", bars = 2, energy = 0.5, density = 0.55,
		tags = {"break", "shuffle", "playful"}, flavours = {"funky", "florida"}, kit = "break", bpm = 112, lanes = {
		{"breakKick", "X.....x.x.......|X.....x.x....x.."},
		{"breakSnare", "....X.......X...|....X.......X.g."},
		{"conga", "x.xo.xo.x.xo.xo.", gain = 0.6},
		{"breakHat", "..x...x...x...x.", gain = 0.45},
	}},
	-- Cowbell and clave for the electro grid.
	{id = "breakbeat.tops.006", role = "tops", bars = 2, energy = 0.45, density = 0.45,
		tags = {"electro", "syncopated", "playful"}, flavours = {"electro", "florida"}, lanes = {
		{"cowbell", "x..x..x...x.x...|x..x..x...x..x..", gain = 0.35},
		{"rim", "..x.......x.....|..x.......x...x.", gain = 0.3},
	}},
	{id = "breakbeat.tops.007", role = "tops", bars = 1, energy = 0.55, density = 0.5, brightness = 0.85,
		tags = {"driving", "straight", "aggressive"}, flavours = {"bigbeat", "rave"}, lanes = {
		{"ride", "x...x...x...x...", gain = 0.4},
		{"openHat", "......x.......x.", gain = 0.4},
		{"hat", "x.x.x.x.x.x.x.x.", gain = 0.3, when = "complexity"},
	}},
	-- A tight nu-skool break, kit hits barely a click.
	{id = "breakbeat.tops.008", role = "tops", bars = 2, energy = 0.7, density = 0.7,
		tags = {"break", "busy", "syncopated"}, flavours = {"nuskool", "progressive"}, kit = "break", bpm = 134, lanes = {
		{"breakKick", "X.....x...x.....|X.x.....x.x....."},
		{"breakSnare", "....X..g....X..g|....X..g.g..X.g."},
		{"breakHat", "x.xx.xx.x.xx.xx.", gain = 0.45},
	}},

	-- BASS -------------------------------------------------------------------
	-- Pedal sub: one root under the break, room for the kick.
	{id = "breakbeat.bass.001", role = "bass", bars = 2, energy = 0.2, density = 0.15,
		tags = {"sub", "pedal", "sparse", "deep"}, notes = "0:0:12 12:0:4 | 0:0:10 10:0:3 13:6:3~"},
	-- Tresillo 3+3+2: the grid every breaks track leans on.
	{id = "breakbeat.bass.002", role = "bass", bars = 1, energy = 0.5, density = 0.4,
		tags = {"sub", "syncopated", "driving"}, notes = "0:0:3 3:0:3 6:0:2 8:0:3 11:0:3 14:0:2"},
	{id = "breakbeat.bass.003", role = "bass", bars = 2, energy = 0.65, density = 0.6,
		tags = {"slap", "stab", "syncopated", "playful", "riff"}, flavours = {"funky", "bigbeat", "florida"},
		notes = "0:0:2 3:0:1 4:7:1! 6:0:2 10:6:2 12:4:2 14:2:2? | 0:0:2 3:0:1 4:7:1! 6:0:2 10:4:2 12:6:2~ 14:7:2?"},
	{id = "breakbeat.bass.004", role = "bass", bars = 1, energy = 0.6, density = 0.55,
		tags = {"stab", "syncopated", "riff"}, notes = "0:0:1! 2:0:1 3:7:1 6:0:1! 8:0:1 10:6:1 11:7:1? 14:4:2"},
	{id = "breakbeat.bass.005", role = "bass", bars = 2, energy = 0.4, density = 0.3,
		tags = {"sub", "pedal", "held", "warm"}, flavours = {"progressive", "bigbeat", "funky"},
		notes = "0:0:4 6:0:2? 10:0:2 13:6:3~ | 0:0:4 6:0:2? 10:2:2 13:4:3~"},
	-- Electro: eighth-note 808 run, octave pop on the offbeats.
	{id = "breakbeat.bass.006", role = "bass", bars = 2, energy = 0.7, density = 0.65,
		tags = {"octave", "driving", "straight", "riff"}, flavours = {"electro", "florida"},
		notes = "0:0:1 2:0:1 4:0:1 6:7:1! 8:0:1 10:0:1 12:6:1 14:7:1! | 0:0:1 2:0:1 4:0:1 6:7:1! 8:4:1 10:4:1 12:2:1 14:0:1"},
	{id = "breakbeat.bass.007", role = "bass", bars = 2, energy = 0.75, density = 0.5,
		tags = {"sub", "held", "tense", "aggressive"}, flavours = {"rave", "bigbeat"},
		notes = "0:0:3 3:0:3 6:0:2 8:7:3 11:6:3 14:4:2 | 0:0:3 3:0:3 6:0:2 8:2:3 11:4:3 14:6:2"},
	-- Walking funk: root, third, fourth, fifth, then back down.
	{id = "breakbeat.bass.008", role = "bass", bars = 4, energy = 0.5, density = 0.5,
		tags = {"walking", "warm", "playful", "stepwise"}, flavours = {"funky"},
		notes = "0:0:3 4:2:2 6:3:2 8:4:4 12:3:2 14:2:2 | 0:0:3 4:0:1 6:2:2 8:4:3 12:6:2 14:7:2 | 0:0:3 4:2:2 6:3:2 8:4:4 12:6:2 14:4:2 | 0:0:2 3:0:1 4:4:2 6:3:2 8:2:2 10:1:2 12:0:4"},
	-- Acid line: slides into accents, 303-style for nu skool.
	{id = "breakbeat.bass.009", role = "bass", bars = 2, energy = 0.8, density = 0.7,
		tags = {"acid", "riff", "syncopated", "aggressive"}, flavours = {"nuskool", "florida", "electro"},
		notes = "0:0:1! 1:0:1 3:0:1~ 4:3:1! 6:0:1 7:7:1~ 8:0:1! 10:0:1 11:6:1~ 12:4:1! 14:3:1 | 0:0:1! 1:0:1 3:0:1~ 4:3:1! 6:4:1 7:3:1~ 8:0:1! 10:0:1 12:6:1! 14:7:1~"},
	{id = "breakbeat.bass.010", role = "bass", bars = 1, energy = 0.55, density = 0.45,
		tags = {"octave", "syncopated", "riff", "playful"}, flavours = {"florida", "electro", "nuskool"},
		notes = "0:0:2 3:7:1! 6:0:2 8:0:2 11:7:1! 14:6:1 15:7:1"},
	-- Sixteenth-note riff, big beat style: the line never stops.
	{id = "breakbeat.bass.011", role = "bass", bars = 2, energy = 0.9, density = 0.9,
		tags = {"riff", "busy", "driving", "aggressive", "rolling"}, flavours = {"bigbeat", "rave", "nuskool"},
		notes = "0:0:1! 1:0:1 2:0:1 3:7:1 4:0:1! 5:0:1 6:6:1 7:0:1 8:0:1! 9:0:1 10:0:1 11:7:1 12:4:1! 13:0:1 14:3:1 15:2:1 | 0:0:1! 1:0:1 2:0:1 3:7:1 4:0:1! 5:0:1 6:6:1 7:0:1 8:0:1! 9:0:1 10:4:1 11:3:1 12:2:1! 13:0:1 14:0:1 15:0:1"},
	-- Offbeat pluck for the progressive end: bass as a rhythm, not weight.
	{id = "breakbeat.bass.012", role = "bass", bars = 2, energy = 0.45, density = 0.4,
		tags = {"pluck", "offbeat", "deep", "hypnotic"}, flavours = {"progressive"},
		notes = "2:0:1 6:0:1 10:0:1 14:0:1 | 2:0:1 6:0:1 10:4:1 14:0:1"},
	-- 808 donk: a long boom that glides to the fifth, florida style.
	{id = "breakbeat.bass.013", role = "bass", bars = 2, energy = 0.6, density = 0.25,
		tags = {"sub", "pluck", "sparse", "playful"}, flavours = {"florida", "electro"},
		notes = "0:0:5 6:0:2 8:4:3~ 12:0:3 | 0:0:5 6:0:2 8:2:3~ 12:0:2 14:7:2!"},
	{id = "breakbeat.bass.014", role = "bass", bars = 4, energy = 0.7, density = 0.6,
		tags = {"riff", "syncopated", "swung", "warm"}, flavours = {"funky", "bigbeat"},
		notes = "0:0:2 3:0:1 6:4:2 8:0:2 11:7:2 14:6:2 | 0:0:2 3:0:1 6:4:2 8:0:2 10:2:1 11:4:2 14:3:2 | 0:0:2 3:0:1 6:4:2 8:0:2 11:7:2 14:6:2 | 0:0:1 2:0:1 3:2:1 4:3:2 6:4:2 8:4:2 10:3:1 11:2:1 12:0:4"},
	-- Rave: held fifths and octaves, the bass as a drone with a bounce.
	{id = "breakbeat.bass.015", role = "bass", bars = 2, energy = 0.5, density = 0.35,
		tags = {"sub", "held", "octave", "euphoric"}, flavours = {"rave", "progressive"},
		notes = "0:0:6 6:0:2 8:4:6 14:7:2 | 0:0:6 6:0:2 8:6:4 12:4:4"},
	-- Rolling sixteenths on one pitch: the nu-skool pump.
	{id = "breakbeat.bass.016", role = "bass", bars = 1, energy = 0.85, density = 0.8,
		tags = {"rolling", "driving", "aggressive", "stab"}, flavours = {"nuskool", "bigbeat"},
		notes = "0:0:1! 1:0:1 3:0:1 4:0:1! 6:0:1 7:0:1 8:0:1! 10:0:1 11:7:1 12:0:1! 14:0:1 15:7:1"},

	-- PAD --------------------------------------------------------------------
	{id = "breakbeat.pad.001", role = "pad", bars = 4, energy = 0.2, density = 0.1,
		tags = {"held", "ambient", "dreamy"}, hold = true},
	{id = "breakbeat.pad.002", role = "pad", bars = 4, energy = 0.35, density = 0.15,
		tags = {"held", "dark", "tense"}, flavours = {"nuskool", "electro", "bigbeat"}, hold = true},
	{id = "breakbeat.pad.003", role = "pad", bars = 2, energy = 0.5, density = 0.3,
		tags = {"chordal", "euphoric", "warm"}, flavours = {"progressive", "florida", "rave"}, comp = "0:8 8:8"},
	{id = "breakbeat.pad.004", role = "pad", bars = 2, energy = 0.7, density = 0.45,
		tags = {"chordal", "rhythmic", "euphoric"}, flavours = {"rave", "florida"}, comp = "0:6 6:4 10:6"},
	{id = "breakbeat.pad.005", role = "pad", bars = 4, energy = 0.4, density = 0.2,
		tags = {"held", "soulful", "warm"}, flavours = {"funky", "progressive"}, hold = true},

	-- KEYS -------------------------------------------------------------------
	-- Clavinet chops: short chords on the sixteenths between the snares.
	{id = "breakbeat.keys.001", role = "keys", bars = 1, energy = 0.6, density = 0.55,
		tags = {"chordal", "rhythmic", "playful", "syncopated"}, flavours = {"funky", "bigbeat"},
		comp = "0:1 3:1 6:2 8:1 11:1 14:2"},
	{id = "breakbeat.keys.002", role = "keys", bars = 1, energy = 0.35, density = 0.25,
		tags = {"chordal", "soulful", "warm", "sparse"}, flavours = {"funky", "progressive"},
		comp = "0:6 6:4"},
	{id = "breakbeat.keys.003", role = "keys", bars = 1, energy = 0.7, density = 0.6,
		tags = {"chordal", "rhythmic", "bright", "euphoric"}, flavours = {"rave"},
		comp = "0:3 3:3 6:2 8:3 11:3 14:2"},
	-- Organ bubble: offbeat eighths.
	{id = "breakbeat.keys.004", role = "keys", bars = 1, energy = 0.5, density = 0.5,
		tags = {"offbeat", "chordal", "playful"}, flavours = {"funky", "bigbeat", "florida"},
		comp = "2:2 6:2 10:2 14:2"},
	{id = "breakbeat.keys.005", role = "keys", bars = 1, energy = 0.25, density = 0.2,
		tags = {"chordal", "dreamy", "sparse", "melancholic"}, flavours = {"progressive"},
		comp = "0:8"},
	{id = "breakbeat.keys.006", role = "keys", bars = 1, energy = 0.8, density = 0.7,
		tags = {"chordal", "busy", "syncopated", "bright"}, flavours = {"funky", "florida", "rave"},
		comp = "0:2 3:2 6:1! 8:2 11:2 14:2"},

	-- STAB -------------------------------------------------------------------
	{id = "breakbeat.stab.001", role = "stab", bars = 1, energy = 0.5, density = 0.3,
		tags = {"stab", "syncopated", "sparse"}, flavours = {"bigbeat", "funky"}, comp = "0:1 6:1 10:1"},
	{id = "breakbeat.stab.002", role = "stab", bars = 1, energy = 0.6, density = 0.4,
		tags = {"stab", "syncopated", "aggressive"}, flavours = {"bigbeat", "nuskool"}, comp = "0:1! 3:1 6:1 10:1"},
	{id = "breakbeat.stab.003", role = "stab", bars = 1, energy = 0.7, density = 0.5,
		tags = {"stab", "rhythmic", "euphoric"}, flavours = {"rave", "florida"},
		comp = "0:1 3:1 6:1 10:1"},
	{id = "breakbeat.stab.004", role = "stab", bars = 1, energy = 0.4, density = 0.3,
		tags = {"stab", "offbeat", "playful"}, flavours = {"funky", "florida"}, comp = "3:1 7:1 11:1 15:1"},
	{id = "breakbeat.stab.005", role = "stab", bars = 1, energy = 0.8, density = 0.6,
		tags = {"stab", "tense", "busy", "syncopated"}, flavours = {"nuskool", "electro"},
		comp = "0:1! 2:1 4:1 7:1 10:1"},
	-- Tresillo hits to match the bass.
	{id = "breakbeat.stab.006", role = "stab", bars = 1, energy = 0.55, density = 0.4,
		tags = {"stab", "syncopated", "driving"}, comp = "0:2 3:2 6:2"},
	{id = "breakbeat.stab.007", role = "stab", bars = 1, energy = 0.9, density = 0.7,
		tags = {"stab", "busy", "aggressive"}, flavours = {"bigbeat", "rave", "nuskool"},
		comp = "0:1! 2:1 3:1 6:1! 8:1 10:1 11:1 14:1"},

	-- ARP --------------------------------------------------------------------
	{id = "breakbeat.arp.001", role = "arp", bars = 1, energy = 0.3, density = 0.4,
		tags = {"arpeggio", "stepwise", "dreamy"}, flavours = {"progressive"},
		order = {1, 2, 3, 4, 3, 2}, rate = 2, gate = 0.8, octave = 1, mask = "XXXXXXXXXXXXXXXX"},
	{id = "breakbeat.arp.002", role = "arp", bars = 1, energy = 0.5, density = 0.55,
		tags = {"arpeggio", "driving", "bright"}, flavours = {"florida", "progressive"},
		order = {1, 3, 2, 4}, rate = 1, gate = 0.5, octave = 1, mask = "XXxxXXxxXXxxXXxx"},
	{id = "breakbeat.arp.003", role = "arp", bars = 1, energy = 0.7, density = 0.7,
		tags = {"arpeggio", "driving", "tense"}, flavours = {"electro", "nuskool"},
		order = {1, 1, 3, 1, 4, 1, 3, 1}, rate = 1, gate = 0.4, octave = 1, mask = "XXXXXXXXXXXXXXXX"},
	{id = "breakbeat.arp.004", role = "arp", bars = 1, energy = 0.4, density = 0.3,
		tags = {"arpeggio", "sparse", "syncopated"}, order = {1, 4, 3}, rate = 2, gate = 0.6, octave = 2,
		mask = "XxX.xX.xX.xXx.X."},
	{id = "breakbeat.arp.005", role = "arp", bars = 2, energy = 0.6, density = 0.5,
		tags = {"arpeggio", "rhythmic", "playful"}, flavours = {"florida", "bigbeat"},
		order = {1, 2, 3, 4, 3, 2, 1, 5}, rate = 2, gate = 0.55, octave = 1, mask = "XXXXxxXXXXXXxxXX"},
	{id = "breakbeat.arp.006", role = "arp", bars = 1, energy = 0.85, density = 0.8,
		tags = {"arpeggio", "busy", "euphoric", "bright"}, flavours = {"rave", "florida", "nuskool"},
		order = {1, 3, 5, 3, 4, 2, 5, 4}, rate = 1, gate = 0.6, octave = 2, mask = "XXXXXXXXXXXXXXXX"},
	{id = "breakbeat.arp.007", role = "arp", bars = 1, energy = 0.35, density = 0.35,
		tags = {"arpeggio", "stepwise", "melancholic"}, flavours = {"progressive", "funky"},
		order = {3, 2, 1, 2}, rate = 4, gate = 0.9, octave = 1, mask = "XXXXXXXXXXXXXXXX"},

	-- LEAD -------------------------------------------------------------------
	-- Hooks are four bars: a phrase, its repeat, then a change.
	{id = "breakbeat.lead.001", role = "lead", bars = 4, energy = 0.7, density = 0.5, follow = "key",
		tags = {"hook", "riff", "aggressive", "syncopated"}, flavours = {"bigbeat", "rave"},
		notes = "0:0:2 3:2:2 6:3:2 10:4:3 14:3:2 | 0:2:2 3:3:2 6:4:2 10:3:3 | 0:0:2 3:2:2 6:3:2 10:4:3 14:6:2 | 0:7:3 4:6:2 6:4:2 8:3:2 10:2:2 12:0:4"},
	-- Two-note hoover stab call.
	{id = "breakbeat.lead.002", role = "lead", bars = 2, energy = 0.8, density = 0.45, follow = "key",
		tags = {"hook", "rhythmic", "euphoric", "leap"}, flavours = {"rave", "bigbeat"},
		notes = "0:4:3 4:7:1 6:4:2 8:7:4 | 0:4:3 4:7:1 6:6:2 8:4:4"},
	{id = "breakbeat.lead.003", role = "lead", bars = 4, energy = 0.5, density = 0.4,
		tags = {"hook", "answer", "playful", "soulful"}, flavours = {"funky"},
		notes = "0:4:2 3:6:1 4:7:3 8:6:2 | 0:4:2 3:2:1 4:4:6 | 0:4:2 3:6:1 4:7:2 7:9:1 8:7:2 11:6:2 | 0:4:8"},
	{id = "breakbeat.lead.004", role = "lead", bars = 2, energy = 0.7, density = 0.55,
		tags = {"hook", "rhythmic", "tense", "riff"}, flavours = {"nuskool", "electro"},
		notes = "0:0:1 2:0:1 3:0:1 6:2:1 8:0:1 10:0:1 11:3:1 14:4:2 | 0:0:1 2:0:1 3:0:1 6:2:1 8:4:1 10:3:1 11:2:1 14:0:2"},
	-- Morse-like dotted figure, electro.
	{id = "breakbeat.lead.005", role = "lead", bars = 2, energy = 0.6, density = 0.4,
		tags = {"hook", "rhythmic", "hypnotic", "straight"}, flavours = {"electro"},
		notes = "0:4:1 3:4:1 6:4:1 8:6:1 11:4:1 14:2:2 | 0:4:1 3:4:1 6:4:1 8:7:1 11:6:1 14:4:2"},
	{id = "breakbeat.lead.006", role = "lead", bars = 4, energy = 0.4, density = 0.3,
		tags = {"hook", "stepwise", "melancholic", "dreamy"}, flavours = {"progressive"},
		notes = "0:4:6 6:3:2 8:2:6 | 0:0:6 6:2:2 8:3:4 12:2:4 | 0:4:6 6:6:2 8:7:6 | 0:6:4 4:4:4 8:2:8"},
	{id = "breakbeat.lead.007", role = "lead", bars = 4, energy = 0.85, density = 0.65,
		tags = {"hook", "anthem", "euphoric", "leap"}, flavours = {"rave", "florida"},
		notes = "0:0:2 2:4:2 4:7:4 8:6:2 10:4:2 | 0:0:2 2:4:2 4:7:4 8:9:4 | 0:0:2 2:4:2 4:7:4 8:6:2 10:4:2 | 0:2:2 2:4:2 4:6:2 6:7:10"},
	{id = "breakbeat.lead.008", role = "lead", bars = 2, energy = 0.3, density = 0.25,
		tags = {"vocal", "answer", "sparse", "soulful"}, flavours = {"funky", "progressive", "florida"},
		notes = "0:4:2 4:6:2 8:7:6 | 0:7:2 4:6:2 8:4:6"},
	-- Call-and-question for florida: a rising question, a falling reply.
	{id = "breakbeat.lead.009", role = "lead", bars = 4, energy = 0.65, density = 0.45,
		tags = {"hook", "answer", "vocal", "playful"}, flavours = {"florida", "funky"},
		notes = "0:0:2 3:2:1 4:4:2 8:7:4 | 0:6:4 6:4:2 8:2:4 | 0:0:2 3:2:1 4:4:2 8:7:2 11:9:2 | 0:7:4 4:6:2 6:4:2 8:0:6"},
	{id = "breakbeat.lead.010", role = "lead", bars = 2, energy = 0.9, density = 0.75, follow = "key",
		tags = {"riff", "busy", "aggressive", "hook"}, flavours = {"bigbeat", "nuskool", "electro"},
		notes = "0:0:1 1:0:1 2:2:1 3:3:1 4:4:2 6:3:1 7:2:1 8:0:2 10:0:1 11:2:1 12:3:1 13:4:1 14:6:2 | 0:7:1 1:6:1 2:4:1 3:3:1 4:2:2 6:0:1 7:2:1 8:3:2 10:2:1 11:0:1 12:2:4"},
	{id = "breakbeat.lead.011", role = "lead", bars = 4, energy = 0.55, density = 0.35,
		tags = {"hook", "stepwise", "warm", "held"}, flavours = {"progressive", "funky", "florida"},
		notes = "0:2:4 4:4:4 8:6:4 12:4:4 | 0:2:4 4:4:4 8:3:8 | 0:4:4 4:6:4 8:7:4 12:6:4 | 0:4:6 6:2:2 8:0:8"},
	{id = "breakbeat.lead.012", role = "lead", bars = 1, energy = 0.75, density = 0.5,
		tags = {"riff", "rhythmic", "tense"}, notes = "0:0:2 3:0:1 6:3:2 8:4:2 11:3:1 12:2:2 14:0:2"},
	-- Sirenlike whole-bar bends for big beat (sparse, a gesture not a tune).
	{id = "breakbeat.lead.013", role = "lead", bars = 2, energy = 0.45, density = 0.15,
		tags = {"held", "sparse", "dark", "hypnotic"}, flavours = {"bigbeat", "nuskool", "electro"},
		notes = "0:4:12 12:6:4~ | 0:7:10 10:6:2~ 12:4:4"},

	-- COUNTER ----------------------------------------------------------------
	{id = "breakbeat.counter.001", role = "counter", bars = 2, energy = 0.3, density = 0.2,
		tags = {"answer", "sparse", "stepwise"}, notes = "8:4:2 12:2:2 | 8:3:2 12:4:4"},
	{id = "breakbeat.counter.002", role = "counter", bars = 4, energy = 0.5, density = 0.35,
		tags = {"answer", "playful", "leap"}, flavours = {"funky", "florida"},
		notes = "10:7:2 14:6:2 | 10:4:2 14:2:2 | 10:7:2 14:9:2 | 8:7:2 11:6:1 12:4:4"},
	{id = "breakbeat.counter.003", role = "counter", bars = 2, energy = 0.65, density = 0.5,
		tags = {"answer", "rhythmic", "tense"}, flavours = {"nuskool", "electro", "bigbeat"},
		notes = "6:2:1 8:3:1 10:4:2 14:3:1 | 6:2:1 8:3:1 10:2:2 14:0:2"},
	{id = "breakbeat.counter.004", role = "counter", bars = 4, energy = 0.4, density = 0.25,
		tags = {"answer", "dreamy", "held"}, flavours = {"progressive"},
		notes = "8:6:4 12:4:4 | 8:7:8 | 8:6:4 12:9:4 | 8:7:4 12:4:4"},
	{id = "breakbeat.counter.005", role = "counter", bars = 2, energy = 0.8, density = 0.6,
		tags = {"answer", "busy", "euphoric"}, flavours = {"rave"},
		notes = "8:4:1 9:6:1 10:7:2 12:6:1 13:4:1 14:2:2 | 8:4:1 9:6:1 10:7:2 12:9:4"},

	-- TEXTURE ----------------------------------------------------------------
	{id = "breakbeat.texture.001", role = "texture", bars = 4, energy = 0.2, density = 0.1,
		tags = {"ambient", "dreamy", "held"}, voices = {0, 7}, every = 4},
	{id = "breakbeat.texture.002", role = "texture", bars = 4, energy = 0.35, density = 0.15,
		tags = {"ambient", "dark", "tense"}, flavours = {"nuskool", "electro", "bigbeat"}, voices = {0, 7, 12}, every = 4},
	{id = "breakbeat.texture.003", role = "texture", bars = 8, energy = 0.3, density = 0.15,
		tags = {"ambient", "warm", "dreamy"}, flavours = {"progressive", "funky"}, voices = {0, 4, 7}, every = 8},
	{id = "breakbeat.texture.004", role = "texture", bars = 2, energy = 0.5, density = 0.3,
		tags = {"held", "tense", "hypnotic"}, flavours = {"rave", "bigbeat", "electro"}, voices = {0, 7, 19}, every = 2},
	{id = "breakbeat.texture.005", role = "texture", bars = 4, energy = 0.45, density = 0.2,
		tags = {"ambient", "bright", "euphoric"}, flavours = {"florida", "progressive", "rave"}, voices = {7, 12, 16}, every = 4},

	-- FX (no risers) -----------------------------------------------------------
	{id = "breakbeat.fx.001", role = "fx", bars = 1, energy = 0.8, density = 0.2, brightness = 0.8,
		tags = {"aggressive"}, kind = "crash"},
	{id = "breakbeat.fx.002", role = "fx", bars = 1, energy = 0.9, density = 0.2, brightness = 0.3,
		tags = {"aggressive", "dark"}, kind = "impact"},
	{id = "breakbeat.fx.003", role = "fx", bars = 4, energy = 0.4, density = 0.2, brightness = 0.6,
		tags = {"dreamy"}, kind = "downlifter"},
}
