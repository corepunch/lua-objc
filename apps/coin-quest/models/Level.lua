-- A level built from its authored description (catalog/levels/*.lua): the
-- blocks, the props on them, and where everything starts.
--
-- Blocks are placed in the order written: `{kind, x, z}` centred on x, z,
-- with optional `yaw` (degrees, any angle), `w`, `d`, `h` (world dimensions) and
-- `y`. `facing` turns where the camera starts, in degrees round the hero
-- (0 looks from +z). A block without `y` sits on whatever is already under its centre, or
-- on the sea floor, so a level is built the way the kit's sample scene is:
-- a tall block, a ledge beside it, a low step in front. Items and props sit on the ground under them,
-- raised by `lift`; ferries, planks and anything over water give their
-- heights.
local Blocks = require("apps.coin-quest.catalog.Blocks")
local Props = require("apps.coin-quest.catalog.Props")
local Terrain = require("apps.coin-quest.models.Terrain")

local Level = {}
Level.__index = Level

-- Item sizes the world collides with, in scene units.
Level.SIZES = {
	spring = {w = 0.76, d = 0.76, h = 0.28}, -- low enough to run onto
	mover = {w = 1.6, d = 1.6, h = 0.5},
	plank = {w = 1.4, d = 1.4, h = 0.2},
	gate = {w = 0.84, d = 0.84, h = 1.68}, -- two crates: higher than a jump
}

-- How far a block whose top overlaps an earlier one at the same height is
-- raised, so the two never flicker through each other.
Level.LIFT = 0.004

local ITEMS = {"coins", "stars", "hearts", "keys", "checkpoints", "spikes", "springs"}

-- Parses a level description; raises a message naming the level for a
-- malformed one, so a typo in the catalog fails its test.
function Level.parse(def)
	local self = setmetatable({id = def.id, title = def.title, about = def.about, biome = def.biome or "grass",
		facing = def.facing or 0,
		blocks = {}, props = {}, solids = {}, spawns = {}}, Level)
	-- What items sit on: blocks and perches, never the top of a tree.
	local perches = {}
	local function fail(message) error("level " .. tostring(def.id) .. ": " .. message, 0) end
	-- The ground under (x, z) among the blocks and perches placed so far.
	local function groundAt(x, z)
		return Terrain.ground(perches, x, z, math.huge, 0) or 0
	end
	for index, block in ipairs(def.blocks or {}) do
		local size = Blocks[block[1]] or fail(string.format("block %d: unknown kind %q", index, tostring(block[1])))
		local x, z = block[2] or fail("block " .. index .. " has no position"), block[3]
		local y = block.y or groundAt(x, z)
		-- `h` stretches the piece to another height, so a column is one
		-- piece with one grass top rather than a stack of them.
		local height = block.h or size.h
		local width, depth = block.w or size.w, block.d or size.d
		if width <= 0 or depth <= 0 or height <= 0 then fail("block " .. index .. " needs positive dimensions") end
		local shaped = setmetatable({w = width, d = depth, h = height,
			low = size.low and size.low * height / size.h}, {__index = size})
		local solid = Terrain.solid(x, y, z, shaped, block.yaw)
		table.insert(self.solids, solid)
		table.insert(perches, solid)
		table.insert(self.blocks, {kind = block[1], x = x, y = y, z = z, yaw = block.yaw or 0,
			scaleX = width / size.w, scaleZ = depth / size.d, stretch = height / size.h, solid = solid})
	end
	if #self.blocks == 0 then fail("no blocks") end
	-- A block with another standing on its top is buried: it shows the
	-- plain model, the top block the one with the overhang. Blocks are
	-- turned freely and may overlap, as in the kit's own scenes; where two
	-- tops at one height overlap, the later is lifted a hair so the two
	-- never flicker through each other.
	for index, block in ipairs(self.blocks) do
		local s = block.solid
		block.lift = 0
		for other, o in ipairs(self.blocks) do
			o = o.solid
			if o ~= s and math.abs(o.y0 - s.y1) < 1e-6 and Terrain.contains(o, block.x, block.z) then block.buried = true end
			if other < index and math.abs(o.y1 - s.y1) < 1e-6 and o.x0 < s.x1 and s.x0 < o.x1 and o.z0 < s.z1 and s.z0 < o.z1 then
				block.lift = block.lift + Level.LIFT
			end
		end
	end
	-- Props: `{kind, x, z}` with optional `yaw`, `scale` and `y`; without `y`
	-- a prop stands on what is under it.
	for index, prop in ipairs(def.props or {}) do
		local kind = Props[prop[1]] or fail(string.format("prop %d: unknown kind %q", index, tostring(prop[1])))
		local x, z = prop[2], prop[3]
		local scale = prop.scale or kind.scale or 1
		local item = {kind = prop[1], x = x, y = prop.y or groundAt(x, z), z = z, yaw = prop.yaw, scale = scale}
		table.insert(self.props, item)
		if kind.solid then
			local f, size = scale / (kind.scale or 1), kind.solid
			local solid = Terrain.solid(x, item.y, z, {w = size.w * f, d = size.d * f, h = size.h * f,
				low = size.low and size.low * f, shape = size.shape, ox = (size.ox or 0) * f, oz = (size.oz or 0) * f},
				prop.yaw or 0)
			solid.trunk = not kind.perch
			table.insert(self.solids, solid)
			if kind.perch then table.insert(perches, solid) end
		end
	end
	local function place(entry)
		local x, z = entry[1], entry[2]
		return {x = x, z = z, y = entry.y or (groundAt(x, z) + (entry.lift or 0))}
	end
	for _, name in ipairs(ITEMS) do
		self.spawns[name] = {}
		for _, entry in ipairs(def[name] or {}) do table.insert(self.spawns[name], place(entry)) end
	end
	for _, spring in ipairs(self.spawns.springs) do
		spring.solid = Terrain.solid(spring.x, spring.y, spring.z, Level.SIZES.spring)
		table.insert(self.solids, spring.solid)
	end
	-- A saw runs between two points on one ledge.
	self.spawns.saws = {}
	for _, saw in ipairs(def.saws or {}) do
		local from = place(saw)
		table.insert(self.spawns.saws, {x = from.x, y = from.y, z = from.z, x2 = saw[3] or from.x, z2 = saw[4] or from.z})
	end
	-- Ferries and lifts: block-moving pieces between two points, `y` their
	-- top. Planks float over the water at `y` and fall once stood on.
	self.spawns.movers = {}
	for _, mover in ipairs(def.movers or {}) do
		local from, to = mover.from, mover.to
		table.insert(self.spawns.movers, {x = from[1], y = from[2], z = from[3], x2 = to[1], y2 = to[2], z2 = to[3]})
	end
	self.spawns.planks = {}
	for _, plank in ipairs(def.planks or {}) do
		table.insert(self.spawns.planks, {x = plank[1], y = plank.y or fail("a plank needs its height"), z = plank[2]})
	end
	self.spawns.gates = {}
	for _, gate in ipairs(def.gates or {}) do table.insert(self.spawns.gates, place(gate)) end
	if not def.start then fail("no start") end
	if not def.flag then fail("no flag") end
	if #self.spawns.coins == 0 then fail("no coins") end
	self.spawns.player = place(def.start)
	self.spawns.flag = place(def.flag)
	return self
end

return Level
