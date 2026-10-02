-- The fills a phrase ends on, shared by every style: one bar each, of
-- which only the steps from `from` are played (the track's groove runs up
-- to it and the fill takes the bar from there). Notation as in a block's
-- drum lanes (host/Library.lua): 16 steps to a bar, "X" an accent, "x" a
-- hit, "o" a soft hit, "g" a ghost.
return {
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
