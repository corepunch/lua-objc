-- The levels, in play order. Each is a file in catalog/levels/ describing a
-- scene built from the kit's blocks (see models/Level.lua for the format).
local LEVELS = {"meadow", "springs", "saws", "bay", "lagoon", "keep", "frost", "glacier", "avalanche", "flagspire"}

local levels = {}
for _, name in ipairs(LEVELS) do
	table.insert(levels, (require("apps.coin-quest.catalog.levels." .. name)))
end
return levels
