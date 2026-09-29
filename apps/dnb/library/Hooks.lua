-- The hooks: four-bar tunes a track's lead may take as its own. A hook is
-- what a track is remembered by, so each has one idea (a rhythm and a
-- shape) stated, repeated, turned and brought home. host/Library.lua
-- documents the notation: "step:pitch:length", pitch in scale steps (0 the
-- root, 2 the third, 4 the fifth, 7 the octave), bars split by "|"; "~"
-- slides into a note and "+" plays it while Complexity is up.
--
-- `follow = "chord"` (the default) moves the hook with the harmony, as a
-- sequence does; `follow = "key"` holds it still while the chords change
-- under it, as a riff does. A track plays its hook in its own key, mode
-- and patch, and later drops vary it (host/Motif.lua), so one hook is many
-- tunes. The generator also writes hooks of its own ("@motif").
return {
	-- Long notes that climb to the ninth and come home: the trance anthem.
	{id = "hook.anthem", name = "Anthem", notes = [[
		0:4:6 6:5:2 8:4:4 12:2:4 | 0:4:6 6:5:2 8:6:4 12:7:4 |
		0:8:6 6:7:2 8:6:4 12:4:4 | 0:4:4 4:2:4 8:0:8~]]},
	{id = "hook.ascent", name = "Ascent", notes = [[
		0:0:4 4:2:4 8:4:6 14:6:2 | 0:7:8 8:6:4 12:4:4 |
		0:2:4 4:4:4 8:6:6 14:7:2 | 0:9:6 6:8:2 8:7:8~]]},
	-- A pentatonic riff that sits still while the chords move.
	{id = "hook.riff", name = "Riff", follow = "key", notes = [[
		0:0:2 3:2:2 6:3:2 10:4:3 14:6:2 | 0:4:3 3:3:2 6:2:2 10:0:4 |
		0:0:2 3:2:2 6:3:2 10:4:3 14:6:2 | 0:4:3 3:6:2 6:7:2 10:4:6]]},
	{id = "hook.jack", name = "Jack", follow = "key", notes = [[
		0:4:1 2:4:1 3:4:2 6:6:2 8:4:2 11:2:2 14:4:2 | 0:4:1 2:4:1 3:4:2 6:7:2 8:6:2 11:4:4 |
		0:4:1 2:4:1 3:4:2 6:6:2 8:4:2 11:2:2 14:4:2 | 0:2:1 2:2:1 3:2:2 6:3:2 8:0:6]]},
	-- A call, and an answer that waits for it.
	{id = "hook.call", name = "Call", notes = [[
		0:7:3 3:6:1 4:4:4 | 8:2:2 10:3:2 12:4:4 |
		0:7:3 3:6:1 4:4:4 | 8:4:2 10:2:2 12:0:4]]},
	{id = "hook.question", name = "Question", notes = [[
		0:0:2 2:2:2 4:4:3 8:6:6~ | 4:4:2 6:2:2 8:0:6 |
		0:0:2 2:2:2 4:4:3 8:7:6~ | 4:6:2 6:4:2 8:2:2+ 10:0:6]]},
	-- Step by step down the scale: a lament.
	{id = "hook.lament", name = "Lament", notes = [[
		0:7:4 4:6:4 8:5:4 12:4:4 | 0:4:8 10:2:2 12:3:4 |
		0:6:4 4:5:4 8:4:4 12:2:4 | 0:2:4 4:1:4 8:0:8]]},
	{id = "hook.sigh", name = "Sigh", notes = [[
		0:4:6 6:3:2~ 8:2:8 | 0:6:6 6:5:2~ 8:4:8 |
		0:4:6 6:3:2~ 8:2:4 12:1:4 | 0:0:12]]},
	-- The chord, climbed and descended.
	{id = "hook.arpeggio", name = "Arpeggio", notes = [[
		0:0:2 2:2:2 4:4:2 6:7:2 8:4:2 10:2:2 12:4:4 | 0:0:2 2:2:2 4:4:2 6:7:2 8:9:4 12:7:4 |
		0:0:2 2:2:2 4:4:2 6:7:2 8:4:2 10:2:2 12:4:4 | 0:7:2 2:4:2 4:2:2 6:0:2 8:0:8]]},
	{id = "hook.cascade", name = "Cascade", notes = [[
		0:9:2 2:7:2 4:4:2 6:2:2 8:7:2 10:4:2 12:2:2 14:0:2 | 0:8:2 2:6:2 4:4:2 6:1:2 8:4:8 |
		0:9:2 2:7:2 4:4:2 6:2:2 8:7:2 10:4:2 12:2:2 14:0:2 | 0:2:4 4:4:4 8:0:8]]},
	-- Two notes to a bar, each slid into: almost sung.
	{id = "hook.voice", name = "Voice", notes = [[
		0:4:8 8:6:6~ | 0:7:10 12:6:4~ |
		0:4:8 8:2:6~ | 0:0:12]]},
	{id = "hook.lullaby", name = "Lullaby", notes = [[
		0:2:6 6:4:2~ 8:2:4 12:0:4 | 0:2:6 6:4:2~ 8:6:8 |
		0:7:6 6:6:2~ 8:4:4 12:2:4 | 0:1:4 4:2:4~ 8:0:8]]},
	-- Off the beat throughout.
	{id = "hook.offbeat", name = "Offbeat", follow = "key", notes = [[
		2:7:2 6:6:2 10:4:2 14:6:2 | 2:7:2 6:9:2 10:7:2 14:4:2 |
		2:7:2 6:6:2 10:4:2 14:6:2 | 2:4:2 6:2:2 10:0:6]]},
	{id = "hook.skank", name = "Skank", follow = "key", notes = [[
		2:4:1 6:4:1 10:6:1 14:4:1 | 2:4:1 6:4:1 10:7:2 13:6:2 |
		2:4:1 6:4:1 10:6:1 14:4:1 | 2:2:1 6:2:1 10:0:4]]},
	-- Root and octave thrown about.
	{id = "hook.octaves", name = "Octaves", notes = [[
		0:0:2 2:7:2 4:0:2 6:7:2 8:6:2 10:4:4 | 0:0:2 2:7:2 4:0:2 6:7:2 8:9:2 10:7:4 |
		0:0:2 2:7:2 4:0:2 6:7:2 8:6:2 10:4:4 | 0:4:2 2:2:2 4:0:2 6:7:2 8:0:8]]},
	-- The tresillo as a tune.
	{id = "hook.tresillo", name = "Tresillo", notes = [[
		0:4:3 3:6:3 6:7:2 10:6:2 12:4:4 | 0:4:3 3:6:3 6:7:2 10:9:2 12:7:4 |
		0:4:3 3:6:3 6:7:2 10:6:2 12:4:4 | 0:2:3 3:1:3 6:0:10]]},
	{id = "hook.dotted", name = "Dotted", follow = "key", notes = [[
		0:0:3 3:2:3 6:4:3 9:2:3 12:0:4 | 0:0:3 3:2:3 6:4:3 9:6:3 12:4:4 |
		0:0:3 3:2:3 6:4:3 9:2:3 12:0:4 | 0:6:3 3:4:3 6:2:3 9:0:7]]},
	-- One note insisted on, then let go.
	{id = "hook.insist", name = "Insist", follow = "key", notes = [[
		0:4:2 2:4:2 4:4:2 6:4:1 7:6:1 8:4:4 | 0:4:2 2:4:2 4:4:2 6:4:1 7:2:1 8:4:4 |
		0:4:2 2:4:2 4:4:2 6:4:1 7:6:1 8:7:4 14:6:2 | 0:4:4 4:2:4 8:0:8]]},
	{id = "hook.morse", name = "Morse", follow = "key", notes = [[
		0:7:1 1:7:1 3:7:1 6:7:2 10:6:1 11:6:1 14:4:2 | 0:7:1 1:7:1 3:7:1 6:9:2 10:7:4 |
		0:7:1 1:7:1 3:7:1 6:7:2 10:6:1 11:6:1 14:4:2 | 0:4:1 1:4:1 3:4:1 6:2:2 10:0:6]]},
	-- A wide leap, filled in by step: the oldest shape a melody has.
	{id = "hook.leap", name = "Leap", notes = [[
		0:0:4 4:7:4 8:6:2 10:5:2 12:4:4 | 0:4:4 4:3:2+ 6:2:2 8:4:8 |
		0:0:4 4:9:4 8:8:2 10:7:2 12:6:4 | 0:4:4 4:2:4 8:0:8]]},
	{id = "hook.bounce", name = "Bounce", notes = [[
		0:0:2 3:4:1 4:0:2 7:4:1 8:0:2 11:6:1 12:4:4 | 0:0:2 3:4:1 4:0:2 7:4:1 8:7:4 12:6:4 |
		0:0:2 3:4:1 4:0:2 7:4:1 8:0:2 11:6:1 12:4:4 | 0:2:2 3:4:1 4:2:2 7:1:1 8:0:8]]},
	-- Sparse: one phrase, and room after it.
	{id = "hook.space", name = "Space", notes = [[
		0:4:2 3:6:2 6:7:6 | 12:6:2 14:4:2 |
		0:4:2 3:6:2 6:9:6 | 12:7:2~ 14:4:2]]},
	{id = "hook.echo", name = "Echo", follow = "key", notes = [[
		0:7:2 4:7:2+ 8:4:2 12:4:2+ | 0:6:2 4:6:2+ 8:2:2 12:2:2+ |
		0:7:2 4:7:2+ 8:4:2 12:4:2+ | 0:4:2 4:2:2 8:0:8]]},
	-- Neighbour notes circling the fifth.
	{id = "hook.circle", name = "Circle", notes = [[
		0:4:2 2:5:2 4:4:2 6:3:2 8:4:4 12:2:4 | 0:4:2 2:5:2 4:4:2 6:3:2 8:4:4 12:6:4 |
		0:4:2 2:5:2 4:4:2 6:3:2 8:4:4 12:7:4 | 0:6:2 2:4:2 4:2:2 6:1:2 8:0:8]]},
}
