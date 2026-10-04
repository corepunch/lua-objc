-- A level parsed from its authored map (catalog/Levels.lua).
--
-- Each map character is one ground cell; x grows along a row and z down the
-- rows, one scene unit per cell. The map is the only place a level's layout
-- lives: the world spawns entities from `spawns`, the stage template draws
-- `tiles` and `scenery`, and movement asks `walkable`.
local Level = {}
Level.__index = Level

-- What each map character puts in its cell: a singular spawn (player,
-- flag) or one more entry in a spawn list. Scenery blocks movement unless
-- it is ground cover; every character except a space, a ferry track or a
-- coin over water is standing ground.
local LEGEND = {
	["."] = {},
	["@"] = {spawn = "player"},
	["$"] = {spawn = "coins"},
	["o"] = {spawn = "aerial", ground = false},
	["F"] = {spawn = "flag"},
	["^"] = {spawn = "spikes"},
	["H"] = {spawn = "saws", axis = "x"},
	["V"] = {spawn = "saws", axis = "z"},
	["T"] = {scenery = "tree", solid = true},
	["P"] = {scenery = "pine", solid = true},
	["R"] = {scenery = "rocks", solid = true},
	["C"] = {scenery = "crate", solid = true},
	["L"] = {scenery = "crate", solid = true, spawn = "gates"},
	["*"] = {scenery = "flowers"},
	[","] = {scenery = "grass"},
	["m"] = {scenery = "mushrooms", spawn = "springs", span = 3},
	["M"] = {scenery = "mega", spawn = "springs", span = 4},
	["~"] = {scenery = "grass", spawn = "crumbles"},
	["K"] = {spawn = "keys"},
	["="] = {spawn = "platforms", axis = "x", track = true, ground = false},
	["-"] = {track = "x", ground = false},
	["|"] = {spawn = "platforms", axis = "z", track = true, ground = false},
	[":"] = {track = "z", ground = false},
}

local function key(x, z) return x .. ":" .. z end

-- The ferry's run: every track cell sharing its row or column, contiguous.
local function trackRun(track, origin, axis)
	local function has(x, z) return track[key(x, z)] == true end
	local cross = axis == "x" and "z" or "x"
	local fixed = origin[cross]
	local function cell(along) return axis == "x" and {x = along, z = fixed} or {x = fixed, z = along} end
	local along = origin[axis]
	local min, max = along, along
	while has(cell(min - 1).x, cell(min - 1).z) do min = min - 1 end
	while has(cell(max + 1).x, cell(max + 1).z) do max = max + 1 end
	return min, max
end

-- Parses `def = {id, title, map = {rows}}`; raises a message naming the
-- level for a malformed map, so a typo in the catalog fails its test.
function Level.parse(def)
	local self = setmetatable({id = def.id, title = def.title, about = def.about, width = 0, depth = #def.map,
		tiles = {}, scenery = {}, spawns = {coins = {}, aerial = {}, saws = {}, spikes = {}, springs = {},
			crumbles = {}, keys = {}, gates = {}, platforms = {}}, ground = {}, solid = {}, spring = {}, track = {}}, Level)
	local function fail(message) error("level " .. tostring(def.id) .. ": " .. message, 0) end
	if self.depth == 0 then fail("map is empty") end
	for z, row in ipairs(def.map) do
		z = z - 1
		self.width = math.max(self.width, #row)
		for x = 0, #row - 1 do
			local char = row:sub(x + 1, x + 1)
			if char ~= " " then
				local cell = LEGEND[char] or fail(string.format("unknown map character %q at %d,%d", char, x, z))
				if cell.ground ~= false then
					self.ground[key(x, z)] = true
					table.insert(self.tiles, {x = x, z = z})
				end
				if cell.track then self.track[key(x, z)] = true end
				if cell.scenery then
					table.insert(self.scenery, {kind = cell.scenery, x = x, z = z})
					if cell.solid then self.solid[key(x, z)] = true end
				end
				if cell.span then self.spring[key(x, z)] = cell.span end
				if cell.spawn == "player" or cell.spawn == "flag" then
					if self.spawns[cell.spawn] then fail("more than one " .. cell.spawn) end
					self.spawns[cell.spawn] = {x = x, z = z}
				elseif cell.spawn then
					table.insert(self.spawns[cell.spawn], {x = x, z = z, axis = cell.axis, span = cell.span})
				end
			end
		end
	end
	for _, platform in ipairs(self.spawns.platforms) do
		platform.min, platform.max = trackRun(self.track, platform, platform.axis)
	end
	if not self.spawns.player then fail("no player start (@)") end
	if not self.spawns.flag then fail("no flag (F)") end
	if #self.spawns.coins + #self.spawns.aerial == 0 then fail("no coins ($)") end
	return self
end

-- Whether something standing on the ground can enter the cell. A gone
-- crumbling bridge is water. Ferries are not ground; the world asks
-- `standable` for those.
function Level:walkable(x, z)
	local id = key(x, z)
	return self.ground[id] == true and not self.solid[id] and not (self.gone and self.gone[id])
end

-- Launch distance of a pad on this cell, or nil.
function Level:springAt(x, z)
	return self.spring[key(x, z)]
end

return Level
