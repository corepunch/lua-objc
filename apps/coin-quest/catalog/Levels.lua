-- The authored levels, in play order. Each map row is a row of ground
-- cells seen from the camera; a space is a gap in the ground.
--
--   @ start   $ coin   F flag (rises once every coin is taken)
--   ^ spike trap   H saw running along its row   V saw running along its column
--   T tree   P pine   R rocks   C crate      (solid)
--   * flowers   , grass   m mushrooms   . ground   (walkable)
return {
	{
		id = "meadow",
		title = "Sunny Meadow",
		map = {
			"T.,..$...*T",
			".$..R....$.",
			"...,...,...",
			"@.....$...F",
			"..*.....,..",
			".$...C...$.",
			"T..m....,.P",
		},
	},
	{
		id = "sawmill",
		title = "The Sawmill",
		map = {
			"P..$.....$..P",
			"..H.......H..",
			"$.....,.....$",
			"..C..@.*.C...",
			"$....F......$",
			"...V.....V...",
			"P..$..m..$..P",
		},
	},
	{
		id = "garden",
		title = "Spike Garden",
		map = {
			"$.^.$   $.^.$",
			".^.^.   .^.^.",
			"^.H.^...^.H.^",
			".^.^..@..^.^.",
			"$.^.$.,.$.^.$",
			"T....mFm....T",
		},
	},
}
