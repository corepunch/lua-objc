-- The authored levels, in play order. Each map row is a row of ground cells
-- seen from the camera; a space is water.
--
--   @ start   $ coin   o coin over water   F flag (rises once every coin is taken)
--   ^ spike trap   H saw along its row   V saw along its column
--   T tree   P pine   R rocks   C crate   L locked crate (opens with a key)
--   * flowers   , grass   m mushroom pad   M big pad   ~ crumbling bridge
--   K key   = crate ferry   - ferry track
--   . ground
--
-- A hop onto a neighbour is a step. A leap clears one cell of water onto the
-- cell beyond. Landing on a pad launches you onward the way you arrived
-- (three cells, four from a big pad). Ferries are the only way across a
-- wider canal. These are the verbs in Kenney's own 3D platformer starter
-- kit — jump, jump pad, falling platform, coins, flag — played on this grid.
return {
	{
		id = "leap",
		title = "First Leap",
		about = "Three islands. A hop stops at a canal; the landing two cells on is a leap.",
		map = {
			"T.$ *.. $..",
			"@.. .$. ..F",
			".$. ... .$.",
			".,. .., .*.",
			"..$ $.. $..",
			"P.. ... ..P",
		},
	},
	{
		id = "pads",
		title = "Mushroom Pads",
		about = "Pads launch the way you arrived. The big mushroom throws you further.",
		map = {
			"P$.  .$.. $P",
			"@.m  ...F ..",
			".$.  .$m. ..",
			"..m  .... .$",
			"$..  $... ..",
			".$M  ...$ $.",
		},
	},
	{
		id = "saws",
		title = "Saw Bridges",
		about = "Leap the canals, then cross the saws while they are on the far side.",
		map = {
			"@.$. .H.. $.F",
			",... ..$. ...",
			".$.. V..$ $..",
			"P... .... .$.",
			"...$ .H.. ..P",
		},
	},
	{
		id = "spikes",
		title = "Spike Isles",
		about = "Spikes only bite a hero who is standing. Leap, or wait until they sink.",
		map = {
			"@.$. .^.. .$F",
			".... ^$^. ...",
			".^^. ^..^ ..^",
			".... .$.. $..",
			"...$ ..$. .$.",
		},
	},
	{
		id = "crumble",
		title = "Crumbling Orchard",
		about = "Grass bridges fall once you leave them. Don't stand still on them.",
		map = {
			"@.$   .$. .$F",
			"T..   ... ...",
			"...~~~$.. .$.",
			"..~   .~. $..",
			".$.   ..$ ..P",
		},
	},
	{
		id = "ferries",
		title = "Crate Ferries",
		about = "The canal is wider than a leap. Ride the crates.",
		map = {
			"@.$.        $.F.",
			"T...=-------....",
			".$..        .$..",
			"....=-------...P",
			"...$        ...$",
		},
	},
	{
		id = "locks",
		title = "Locked Garden",
		about = "The key is on the far island. The crate gate opens when you have it.",
		map = {
			"..$. .K.. ...",
			"@... ...* L.F",
			"T... ..$. ...",
			".$.. .... .$.",
			".... $... ..P",
			"...$ .... $..",
		},
	},
	{
		id = "arcs",
		title = "Coin Arcs",
		about = "Some coins hang over the water. A leap collects what it passes.",
		map = {
			".$.o...o.$.o$",
			"...o.$.o...o.",
			"@..o...o...oF",
			"...o$..o...o.",
			"..$o...o$..o.",
		},
	},
	{
		id = "gauntlet",
		title = "The Gauntlet",
		about = "Pad, saws, then a crate across the last canal.",
		map = {
			"@..  .H..    .$...",
			"..m  ...$    ..F..",
			".$.  ..$.=---.$...",
			".,.  V...    ...$.",
			"..$  ....    ....P",
			"T..  ...$    $....",
		},
	},
	{
		id = "spire",
		title = "Flagspire",
		about = "Every trick at once: arcs, a crumbling bridge, a key, a ferry, the flag.",
		map = {
			"T$.o.$..    ...$..",
			"...o..K.    L....F",
			"@.. ....    .$..$.",
			"~~~~~       ....$.",
			".$. ... =---..M...",
			"... .$.     ..$...",
			"..$ ...     $....P",
		},
	},
}
