-- Studio's colors, as gradient stops of semantic system colors so every
-- surface follows light and dark appearance.
local Theme = {}

-- The brand gradient: the mark on the rail, the selected rail item, the
-- agent's avatar, and the user's bubble all run through these colors, so
-- the workspace reads as one product rather than a set of grey panes.
Theme.brand = "systemIndigo,systemPurple,systemPink"

-- Studio's own controls take this accent, so Run, Deploy, and Send belong to
-- the brand gradient. The previewed app keeps its own.
Theme.tint = "systemIndigo"

-- The canvas behind the rail, stage, and agent card: a wash of the brand
-- colors warming toward orange, crossed by a cooler glow.
Theme.canvas = {
	wash = "systemIndigo,systemPurple,systemPink,systemOrange",
	glow = "systemTeal,systemBlue,systemPurple",
}

return Theme
