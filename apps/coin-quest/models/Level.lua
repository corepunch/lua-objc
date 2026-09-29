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
-- it is ground cover; every character except a space is standing ground.
local LEGEND = {
	["."] = {},
	["@"] = {spawn = "player"},
	["$"] = {spawn = "coins"},
	["F"] = {spawn = "flag"},
	["^"] = {spawn = "spikes"},
	["H"] = {spawn = "saws", axis = "x"},
	["V"] = {spawn = "saws", axis = "z"},
	["T"] = {scenery = "tree", solid = true},
	["P"] = {scenery = "pine", solid = true},
	["R"] = {scenery = "rocks", solid = true},
	["C"] = {scenery = "crate", solid = true},
	["*"] = {scenery = "flowers"},
	[","] = {scenery = "grass"},
	["m"] = {scenery = "mushrooms"},
}

local function key(x, z) return x .. ":" .. z end

-- Parses `def = {id, title, map = {rows}}`; raises a message naming the
-- level for a malformed map, so a typo in the catalog fails its test.
function Level.parse(def)
	local self = setmetatable({id = def.id, title = def.title, width = 0, depth = #def.map,
		tiles = {}, scenery = {}, spawns = {coins = {}, saws = {}, spikes = {}}, ground = {}, solid = {}}, Level)
	local function fail(message) error("level " .. tostring(def.id) .. ": " .. message, 0) end
	if self.depth == 0 then fail("map is empty") end
	for z, row in ipairs(def.map) do
		z = z - 1
		self.width = math.max(self.width, #row)
		for x = 0, #row - 1 do
			local char = row:sub(x + 1, x + 1)
			if char ~= " " then
				local cell = LEGEND[char] or fail(string.format("unknown map character %q at %d,%d", char, x, z))
				self.ground[key(x, z)] = true
				table.insert(self.tiles, {x = x, z = z})
				if cell.scenery then
					table.insert(self.scenery, {kind = cell.scenery, x = x, z = z})
					if cell.solid then self.solid[key(x, z)] = true end
				end
				if cell.spawn == "player" or cell.spawn == "flag" then
					if self.spawns[cell.spawn] then fail("more than one " .. cell.spawn) end
					self.spawns[cell.spawn] = {x = x, z = z}
				elseif cell.spawn then
					table.insert(self.spawns[cell.spawn], {x = x, z = z, axis = cell.axis})
				end
			end
		end
	end
	if not self.spawns.player then fail("no player start (@)") end
	if not self.spawns.flag then fail("no flag (F)") end
	if #self.spawns.coins == 0 then fail("no coins ($)") end
	return self
end

-- Whether something standing on the ground can enter the cell.
function Level:walkable(x, z)
	return self.ground[key(x, z)] == true and not self.solid[key(x, z)]
end

return Level
