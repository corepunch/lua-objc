-- The hues a ring draws its sectors in. Catalog categories carry identity
-- colors that repeat (Games and Documents are both green, four categories
-- are blue), and a ring where neighbours share a hue reads as one sector,
-- or as one color. So every ring claims its hues from one Palette: a sector
-- keeps its own color while that hue is free and otherwise takes the next
-- free one. Neutral colors stand for "the rest" (folded categories, free
-- space, what was not attributed) and are never claimed or handed out.
local Palette = {}
Palette.__index = Palette

-- Ordered so consecutive hues are far apart on the color wheel: sectors
-- that fall back to the palette sit next to each other in the ring.
Palette.hues = {"systemBlue", "systemOrange", "systemPurple", "systemGreen", "systemPink", "systemTeal",
	"systemYellow", "systemIndigo", "systemRed", "systemMint", "systemCyan", "systemBrown"}

local NEUTRAL = {systemGray = true, secondary = true, tertiary = true, quaternaryLabel = true}
-- Hues that read as one in a ring, small and side by side: Videos in pink
-- beside Music in red looked like one red sector. Each pair is claimed
-- together.
local LOOK_ALIKE = {systemPink = "systemRed", systemCyan = "systemTeal"}
local function family(hue) return LOOK_ALIKE[hue] or hue end

-- How many sectors one ring can color so that no two look alike.
Palette.distinct = 0
do
	local seen = {}
	for _, hue in ipairs(Palette.hues) do
		if not seen[family(hue)] then seen[family(hue)] = true; Palette.distinct = Palette.distinct + 1 end
	end
end

-- Whether a color stands for "the rest" and is never claimed.
function Palette.neutral(color) return NEUTRAL[color] == true end

function Palette.new() return setmetatable({used = {}}, Palette) end

-- The hue for a sector that wants `color` (nil for "any"). Once every hue
-- is taken the palette starts over; a ring has far fewer named sectors.
function Palette:take(color)
	if color and NEUTRAL[color] then return color end
	if color and not self.used[family(color)] then self.used[family(color)] = true; return color end
	for _, hue in ipairs(Palette.hues) do
		if not self.used[family(hue)] then self.used[family(hue)] = true; return hue end
	end
	self.used = {}
	return self:take(color)
end

return Palette
