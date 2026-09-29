-- The beats every style shares: breaks, played as a record's drum solo is
-- (a loop at the record's tempo, sped up or slowed to the track's and cut
-- into 16th slices), and the fills a phrase ends on. A style's own grooves
-- live in its plugin. host/Library.lua documents the notation: 16 steps to
-- a bar, "X" an accent, "x" a hit, "o" a soft hit, "g" a ghost.
--
-- A fill is one bar, of which only the steps from `from` are played: the
-- track's groove runs up to it and the fill takes the bar from there.
return {
	-- The Amen break, recreated: the four-bar drum solo from The Winstons'
	-- "Amen, Brother" (1969) that jungle and drum & bass were built on. Bars
	-- one and two are the straight groove, bar three delays the last snare,
	-- bar four is the famous syncopated turn with the crash.
	{id = "break.amen", name = "Amen", kit = "break", bpm = 137, bars = 4, send = 0.12, lanes = {
		{"breakKick", "X.x.......x.....|X.x.......x.....|X.x.......x.....|..........xo...."},
		{"breakSnare", "....X..o.o..X..o|....X..o.o..X..o|....X..o.o....X.|..o.X..o.o....X."},
		{"breakRide", "x...x...x...x...", gain = 0.62},
		{"breakRide", "..x...x...x...x.", gain = 0.45},
		{"crash", "................|................|................|..........X.....", gain = 0.8},
	}},
	-- A funk break on sixteenth hats, the ghost notes doing the talking.
	{id = "break.funk", name = "Funk Break", kit = "break", bpm = 102, bars = 2, send = 0.12, lanes = {
		{"breakKick", "X.x...x...x..x..|X.x...x...x..o.."},
		{"breakSnare", "....X..g.g.gX..g|....X..g.g.gX.g."},
		{"breakHat", "XoxoXoxoXoxoXoxo", gain = 0.55},
	}},
	-- A break carried by its tambourine.
	{id = "break.tambourine", name = "Tambourine", kit = "break", bpm = 116, bars = 2, send = 0.14, lanes = {
		{"breakKick", "X.x.......x.x...|X.x....x..x....."},
		{"breakSnare", "....X.......X...|....X.....g.X..g"},
		{"tambourine", "xoxoxoxoxoxoxoxo", gain = 0.6},
	}},
	-- Bongos running over a simple kick and snare.
	{id = "break.bongo", name = "Bongo Break", kit = "break", bpm = 112, bars = 2, send = 0.14, lanes = {
		{"breakKick", "X.....x.x.......|X.....x.x....x.."},
		{"breakSnare", "....X.......X...|....X.......X.g."},
		{"conga", "x.xo.xo.x.xo.xo.", gain = 0.7},
		{"breakHat", "..x...x...x...x.", gain = 0.5},
	}},
	-- A shuffled break, the kick pushing every dotted eighth.
	{id = "break.shuffle", name = "Shuffle Break", kit = "break", bpm = 110, bars = 2, send = 0.12, lanes = {
		{"breakKick", "X..x..x...x..x..|X..x..x...x....."},
		{"breakSnare", "....X..g....X..g|....X..g.g..X.g."},
		{"breakHat", "x.xx.xx.x.xx.xx.", gain = 0.5},
	}},
	-- A hard, straight break for big beat.
	{id = "break.stomp", name = "Stomp Break", kit = "break", bpm = 120, bars = 2, send = 0.1, lanes = {
		{"breakKick", "X.....x.x.x.....|X.....x.x.x..x.."},
		{"breakSnare", "....X.......X...|....X.......X.o."},
		{"breakHat", "x.x.x.x.x.x.x.x.", gain = 0.55},
		{"breakRide", "x...x...x...x...", gain = 0.3},
	}},

	-- Fills --------------------------------------------------------------------
	-- A snare roll in 32nds, rising into the next phrase.
	{id = "fill.roll", name = "Roll", from = 12, lanes = {
		{"snare", "........................ggooxxXX", div = 32},
	}},
	{id = "fill.snares", name = "Snares", from = 12, lanes = {
		{"snare", ".............oxX"},
	}},
	-- Down the toms, the snare landing on the last beat.
	{id = "fill.toms", name = "Toms", from = 10, lanes = {
		{"tomHigh", "..........xx...."},
		{"tomMid", "............xx.."},
		{"tomLow", "..............xx"},
		{"snare", "............x..."},
	}},
	{id = "fill.tomsDown", name = "Tom Run", from = 12, lanes = {
		{"tomHigh", "............x..."},
		{"tomMid", ".............xx."},
		{"tomLow", "...............X"},
	}},
	-- Kick and snare trading 16ths.
	{id = "fill.stutter", name = "Stutter", from = 12, lanes = {
		{"kick", "............x.x."},
		{"snare", ".........................o.x.x.X", div = 32},
	}},
	{id = "fill.claps", name = "Claps", from = 12, lanes = {
		{"clap", ".............oxX"},
	}},
	-- The last kick gives way to a clap flam.
	{id = "fill.flam", name = "Flam", from = 12, lanes = {
		{"clap", "..............ox"},
	}},
	{id = "fill.kicks", name = "Kick Run", from = 12, lanes = {
		{"kick", "............ooxX"},
		{"openHat", "..............x.", gain = 0.6},
	}},
	-- Snare triplets across the last two beats.
	{id = "fill.triplets", name = "Triplets", from = 8, lanes = {
		{"snare", "............o.o.x.x.X.X.", div = 24},
		{"kick", "........x......."},
	}},
	{id = "fill.rims", name = "Rims", from = 12, lanes = {
		{"rim", "............xxox"},
		{"kick", "..............x."},
	}},
	{id = "fill.congas", name = "Congas", from = 10, lanes = {
		{"conga", "..........x.xxox"},
		{"cowbell", "............x...", gain = 0.6},
	}},
}
