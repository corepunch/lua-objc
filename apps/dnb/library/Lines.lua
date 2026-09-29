-- Bass lines every style may play. host/Library.lua documents the notation:
-- "step:pitch:length", pitch in scale steps above the chord's root (0 the
-- root, 4 the fifth, 6 the seventh, 7 the octave), bars split by "|". "~"
-- slides into a note, "!" accents it, "?" plays while Energy is up and "+"
-- while Complexity is. A style's own lines live in its plugin.
return {
	-- The root, once a bar: under a breakdown, or a tune that needs nothing more.
	{id = "line.root", name = "Root", notes = "0:0:14"},
	-- Root and octave in eighths.
	{id = "line.octaves", name = "Octaves", notes = "0:0:2 2:7:2 4:0:2 6:7:2 8:0:2 10:7:2 12:0:2 14:7:2?"},
	-- A walk up to the fifth and home again, over two bars.
	{id = "line.walk", name = "Walk", notes = "0:0:4 4:2:4 8:3:4 12:4:4 | 0:4:4 4:3:4 8:2:4 12:1:4"},
	-- The tresillo in the bass.
	{id = "line.tresillo", name = "Tresillo", notes = "0:0:3 3:0:3 6:0:2 8:7:2? 10:4:2+ 12:0:3 | 0:0:3 3:0:3 6:4:2 8:6:3 12:4:2? 14:2:2+"},
	-- One long note, then a late push into the next bar.
	{id = "line.push", name = "Push", notes = "0:0:10 11:0:1? 12:6:2 14:7:2~"},
}
