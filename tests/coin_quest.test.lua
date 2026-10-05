_G.__headless = true

-- Coin Quest: every layer on its own (terrain shapes, level building, the
-- hero's physics against the level checker's promises, each world system
-- with a hand-built level, the camera, the session's state machine, input,
-- view data) and then the whole game driven through its SceneView without a
-- window.

local t = require("TestKit")
local bridge = require("AppKitNative")
local Terrain = require("apps.coin-quest.models.Terrain")
local Level = require("apps.coin-quest.models.Level")
local Reach = require("apps.coin-quest.models.Reach")
local World = require("apps.coin-quest.models.World")
local Animation = require("apps.coin-quest.models.Animation")
local Platforms = require("apps.coin-quest.models.systems.Platforms")
local Camera = require("apps.coin-quest.models.systems.Camera")
local Model = require("apps.coin-quest.Model")
local Levels = require("apps.coin-quest.catalog.Levels")
local InputController = require("apps.coin-quest.controllers.InputController")
local StageController = require("apps.coin-quest.controllers.StageController")
local HudController = require("apps.coin-quest.controllers.HudController")
local Controller = require("apps.coin-quest.Controller")

local function near(a, b, tolerance) return math.abs(a - b) < (tolerance or 1e-6) end

-- Scripted input: a direction held as seen from the camera, and jumps on
-- request.
local function pad(x, z)
	local input = {x = x or 0, z = z or 0, jumps = 0}
	function input.axis() return input.x, input.z end
	function input.takeJump()
		if input.jumps > 0 then
			input.jumps = input.jumps - 1
			return true
		end
		return false
	end
	return input
end

-- Runs the world for `seconds` and returns the names of the events raised.
local function run(world, input, seconds)
	local events = {}
	for _ = 1, math.floor((seconds or 1) * 60 + 0.5) do
		for _, event in ipairs(world:step(1 / 60, input)) do table.insert(events, event.name) end
	end
	return events
end

local function has(list, name)
	for _, item in ipairs(list) do if item == name then return true end end
	return false
end

-- A level built from blocks alone, for the system tests.
local function level(def)
	def.id, def.title = def.id or "test", def.title or "Test"
	def.start = def.start or {0, 0}
	def.flag = def.flag or {0, 0}
	def.coins = def.coins or {{0, -0.9}}
	return Level.parse(def)
end

-- ── Terrain ────────────────────────────────────────────────────────────
local box = Terrain.solid(0, 0, 0, {w = 2, d = 1, h = 1})
t.expect(box.x0 == -1 and box.x1 == 1 and box.z0 == -0.5 and box.y1 == 1, "a solid is centred on its position")
local turned = Terrain.solid(0, 0, 0, {w = 2, d = 1, h = 1}, 90)
t.expect(near(turned.x1, 0.5) and near(turned.z1, 1), "a quarter turn swaps width and depth")
local angled = Terrain.solid(0, 0, 0, {w = 2, d = 0.4, h = 1}, 45)
t.expect(Terrain.contains(angled, 0.6, -0.6) and not Terrain.contains(angled, 0.6, 0.6), "a block turns to any angle")
t.expect(near(angled.x1, (2 + 0.4) / 2 * math.sqrt(0.5), 1e-9), "and its bounds hold its turned corners")
local offset = Terrain.solid(0, 0, 0, {w = 1, d = 0.2, h = 0.5, oz = 0.4}, 90)
t.expect(near(offset.cx, 0.4) and near(offset.cz, 0), "a box set to one side of its piece turns with it")
local turnedRamp = Terrain.solid(0, 0, 0, {w = 2, d = 2, h = 1, low = 0, shape = "ramp"}, 45)
t.expect(Terrain.top(turnedRamp, -0.7, -0.7) > 0.9 and Terrain.top(turnedRamp, 0.7, 0.7) < 0.1,
	"a turned ramp rises the way it faces")
local ramp = Terrain.solid(0, 0, 0, {w = 2, d = 2, h = 1, low = 0, shape = "ramp"})
t.expect(near(Terrain.top(ramp, 0, 1), 0) and near(Terrain.top(ramp, 0, -1), 1), "a ramp rises towards -z")
t.expect(near(Terrain.top(ramp, 0, 0), 0.5), "halfway up a ramp is half its height")
local east = Terrain.solid(0, 0, 0, {w = 2, d = 2, h = 1, low = 0, shape = "ramp"}, 270)
t.expect(near(Terrain.top(east, 1, 0), 1), "a ramp turned three quarters rises towards +x")
local arch = Terrain.solid(0, 0, 0, {w = 2, d = 1, h = 1, low = 0.25, shape = "arch"})
t.expect(near(Terrain.top(arch, 0, 0), 1) and near(Terrain.top(arch, 1, 0), 0.25), "an arch bows up in the middle")
local solids = {box, Terrain.solid(0, 1, 0, {w = 1, d = 1, h = 0.5})}
t.assertEqual(Terrain.ground(solids, 0, 0, 5, 0), 1.5, "ground is the highest top under a point")
t.assertEqual(Terrain.ground(solids, 0, 0, 1.2, 0), 1, "no higher than asked")
t.expect(Terrain.ground(solids, 5, 5, 5, 0) == nil, "nothing under a point is water")
t.expect(Terrain.blocked(solids, 0.8, 0, 0, 0.3, 0.8, 0.3), "a body walks into a block")
t.expect(not Terrain.blocked(solids, 0.9, 1, 0, 0.3, 0.8, 0.3), "but not standing on top of it")

-- ── Level ──────────────────────────────────────────────────────────────
local built = Level.parse({id = "b", title = "B", start = {0, 0}, flag = {3, 0}, coins = {{0, 0}, {3, 0, lift = 1}},
	blocks = {{"large", 0, 0}, {"low", 0, 0}, {"tall", 3, 0, h = 3}, {"large", 5.2, 0, h = 3, yaw = 30}},
	props = {{"tree", 3.5, 0.5}, {"crate", -0.6, -0.6}, {"platform", 0, 3, y = 0.5, yaw = 20, scale = 3}}})
t.assertEqual(built.blocks[2].y, 1, "a block without y sits on the block under it")
t.expect(built.blocks[1].buried and not built.blocks[2].buried, "a block with another on top is buried")
t.expect(near(built.blocks[3].solid.y1, 3) and near(built.blocks[3].stretch, 1.5), "h stretches a block to a height")
t.assertEqual(built.spawns.player.y, 1.5, "the start stands on the ground")
t.assertEqual(built.spawns.coins[2].y, 4, "lift raises an item above the ground")
t.assertEqual(built.props[2].y, 1, "props stand on the ground")
t.expect(built.blocks[4].lift > 0 and built.blocks[3].lift == 0, "a block overlapping another top at its height is lifted a hair")
local deck = built.solids[#built.solids]
t.expect(near(deck.y1, 0.5 + 0.6) and near(deck.hw, 1.5), "a scaled prop's collision box grows with it")
t.assertEqual(Terrain.ground(built.solids, 0, 3, 5, 0), deck.y1, "a bridge plank over the water is ground")
local onTree = Level.parse({id = "t", title = "T", start = {0, 0}, flag = {0, 0}, coins = {{0, 0}},
	blocks = {{"large", 0, 0}}, props = {{"tree", 0, 0}}})
t.assertEqual(onTree.spawns.coins[1].y, 1, "items never sit on top of a tree")
local wide = level({blocks = {{"large", 0, 0, w = 12, d = 8, h = 0.8, y = -0.8},
	{"slope", 0, 0, w = 4, d = 6, h = 1, yaw = 90}}, coins = {{4, 2}}})
t.assertEqual(wide.blocks[1].solid.y1, 0, "a recovery lawn has a solid top at zero")
t.expect(wide.blocks[1].scaleX == 6 and wide.blocks[1].scaleZ == 4,
	"wide terrain scales the Kenney mesh with its collision footprint")
t.assertEqual(wide.spawns.coins[1].y, 0, "items can be placed directly on the lawn")
t.expect(near(wide.blocks[2].solid.x1, 3) and near(wide.blocks[2].solid.z1, 2),
	"a wide ramp turns its scaled footprint")
t.expect(Terrain.top(wide.blocks[2].solid, -2.9, 0) > 0.95,
	"a scaled ramp keeps its climb direction")
for _, bad in ipairs({
	{def = {blocks = {}}, message = "no blocks"},
	{def = {blocks = {{"castle", 0, 0}}}, message = "unknown kind"},
	{def = {blocks = {{"large", 0, 0, w = 0}}}, message = "positive dimensions"},
	{def = {blocks = {{"large", 0, 0, d = -1}}}, message = "positive dimensions"},
	{def = {blocks = {{"large", 0, 0, h = 0}}}, message = "positive dimensions"},
	{def = {blocks = {{"large", 0, 0}}, props = {{"statue", 0, 0}}}, message = "unknown kind"},
	{def = {blocks = {{"large", 0, 0}}, start = false}, message = "no start"},
	{def = {blocks = {{"large", 0, 0}}, coins = {}}, message = "no coins"},
	{def = {blocks = {{"large", 0, 0}}, planks = {{1, 1}}}, message = "plank needs its height"},
}) do
	local def = bad.def
	def.id, def.title = "bad", "Bad"
	if def.start == nil then def.start = {0, 0} end
	if def.start == false then def.start = nil end
	def.flag = {0, 0}
	def.coins = def.coins or {{0, 0}}
	local ok, err = pcall(Level.parse, def)
	t.expect(not ok and tostring(err):find(bad.message, 1, true), "a malformed level fails: " .. bad.message)
end

-- ── The hero's jump keeps the checker's promises ───────────────────────
-- Reach allows a jump only where the real hero, running and jumping, lands.
-- The hero runs straight away from the camera, north, so its way stays put.
local function leap(gap, rise, spring)
	local def = {blocks = {{"large", 0, 0}, {"large", 0, -(2 + gap), h = 1 + rise}}, start = {0, 0.9}, coins = {{0.9, 0.9}}}
	if spring then def.springs = {{0, -0.6}} end
	local world = World.new(level(def))
	local input = pad(0, -1)
	-- Run to the far edge of the first block, then jump.
	for _ = 1, 600 do
		world:step(1 / 60, input)
		if world.player.z < -0.98 or (spring and not world.player.grounded) then break end
	end
	if not spring then input.jumps = 1 end
	for _ = 1, 120 do
		world:step(1 / 60, input)
		if world.player.grounded and world.player.z < -1 - gap then break end
	end
	return world.player.grounded and world.player.z < -1 - gap and near(world.player.y, 1 + rise, 0.01)
end
t.expect(leap(Reach.JUMP.gap, 0), "the hero clears the widest gap the checker allows")
t.expect(leap(Reach.JUMP.gap - Reach.JUMP.risePenalty * Reach.JUMP.rise, Reach.JUMP.rise),
	"and the highest ledge it allows, as far off as it allows")
t.expect(leap(Reach.JUMP.springGap, Reach.JUMP.springRise - 0.4, true), "a spring throws as high as the checker says")
t.expect(not leap(0.5, 2), "a ledge two blocks up is out of a jump's reach")

-- ── Every level ────────────────────────────────────────────────────────
t.assertEqual(#Levels, 10, "the game has ten levels")
for _, def in ipairs(Levels) do
	local parsed = Level.parse(def)
	local problems = Reach.problems(parsed)
	t.expect(#problems == 0, def.id .. ": " .. (problems[1] or "every coin, star and the flag are reachable"))
	t.assertEqual(#parsed.spawns.stars, 3, def.id .. " hides three stars")
	local start, clear = parsed.spawns.player, true
	for _, coin in ipairs(parsed.spawns.coins) do
		if (coin.x - start.x) ^ 2 + (coin.z - start.z) ^ 2 < 1 then clear = false end
	end
	t.expect(clear, def.id .. ": no coin is taken by standing at the start")
	-- The course and a generous landing margin are above real terrain.
	local lawn = parsed.blocks[1].solid
	t.assertEqual(lawn.y1, 0, def.id .. ": the recovery ground stays above the death threshold")
	for index = 2, #parsed.blocks do
		for _, corner in ipairs(Terrain.corners(parsed.blocks[index].solid)) do
			t.expect(Terrain.contains(lawn, corner[1], corner[2], -2), def.id .. ": two units of land beyond ledges")
		end
	end
	for _, mover in ipairs(parsed.spawns.movers) do
		t.expect(Terrain.contains(lawn, mover.x, mover.z, -2) and Terrain.contains(lawn, mover.x2, mover.z2, -2),
			def.id .. ": ground below both ends of each moving platform")
	end
	-- Drop through the former gaps on a coarse grid using the real physics
	-- and session, so this catches a decorative floor with no collision.
	local session = Model.new({def})
	for x = lawn.x0 + 1, lawn.x1 - 1, 3 do
		for z = lawn.z0 + 1, lawn.z1 - 1, 3 do
			local safe = true
			for _, list in ipairs({parsed.spawns.saws, parsed.spawns.spikes, parsed.spawns.springs}) do
				for _, item in ipairs(list) do
					if (x - item.x) ^ 2 + (z - item.z) ^ 2 < 4 then safe = false end
				end
			end
			if safe and Terrain.ground(parsed.solids, x, z, math.huge, World.RULES.radius) == 0 then
				session:load(1)
				local p = session.world.player
				p.x, p.y, p.z, p.vx, p.vy, p.vz, p.grounded = x, 8, z, 0, 0, 0, false
				for _ = 1, 20 do session:step(0.1, pad()) end
				t.expect(p.grounded and p.y >= 0 and session.lives == Model.RULES.lives,
					def.id .. ": a missed jump lands without losing a life")
			end
		end
	end
end
local function problem(def, pattern)
	for _, message in ipairs(Reach.problems(level(def))) do
		if message:find(pattern) then return true end
	end
end
t.expect(problem({blocks = {{"large", 0, 0}, {"large", 6, 0}}, coins = {{6, 0}}}, "cannot be reached"),
	"a coin across too wide a gap is caught")
t.expect(not problem({blocks = {{"large", 0, 0}, {"large", 4.2, 0, yaw = 45}}, coins = {{4.2, 0}}}, "cannot be reached"),
	"a turned block's corner reaches nearer than its centre")
t.expect(not problem({blocks = {{"large", 0, 0}, {"large", 7, 0}}, coins = {{7, 0}},
	props = {{"platform", 2.4, 0, y = 0.7}, {"platform", 3.8, 0, y = 0.7}, {"platform", 5.2, 0, y = 0.7}}}, "cannot be reached"),
	"a bridge of planks joins two islands")
t.expect(problem({blocks = {{"tall", 0, 0, h = 3}, {"large", 2.5, 0}}, start = {0, 0}, coins = {{0, 0}}}, "dead end"),
	"a drop with no way back up is caught")
t.expect(not problem({blocks = {{"tall", 0, 0, h = 3}, {"large", 2.5, 0}}, springs = {{2.5, 0}}, start = {0, 0},
	coins = {{0, 0}}}, "dead end"), "a spring makes the drop safe")

-- Walk the meadow's recovery approaches with the actual hero, without
-- jumping. World directions keep these checks independent of camera turns.
local function direction(world, x, z)
	return {axis = function()
		local fx, fz = Camera.forward(world)
		return -fz * x + fx * z, -fx * x - fz * z
	end}
end
for _, def in ipairs(Levels) do
	local parsed, ramps = Level.parse(def), 0
	for _, block in ipairs(parsed.blocks) do
		-- Broad authored slopes are the recovery approaches. Original
		-- narrow climbing pieces may deliberately start above ground.
		if block.kind == "slope" and block.scaleX > 1 then
			ramps = ramps + 1
			local s = block.solid
			local world = World.new(parsed)
			local p = world.player
			p.x, p.z = s.cx + s.s * (s.hd + 0.2), s.cz + s.c * (s.hd + 0.2)
			p.y = Terrain.ground(world:solids(), p.x, p.z, math.huge, 0)
			Camera.place(world)
			run(world, direction(world, -s.s, -s.c), (s.hd * 2 + 0.3) / world.rules.runSpeed + 0.06)
			local progress = (p.x - s.cx) * -s.s + (p.z - s.cz) * -s.c
			t.expect(progress >= s.hd - 0.3 and p.y >= s.y1 - world.rules.step,
				def.id .. ": ramp at " .. block.x .. ", " .. block.z .. " can be walked up without hitting a prop or ledge")
		end
	end
	t.expect(ramps > 0, def.id .. ": has a broad approach from the recovery ground")
	for _, prop in ipairs(parsed.props) do
		t.expect(Terrain.contains(parsed.blocks[1].solid, prop.x, prop.z), def.id .. ": scenery stays on land")
	end
end
for _, route in ipairs({
	{x = 0, z = 8.2, dx = 0, dz = -1, seconds = 0.8, height = 0.5},
	{x = -9, z = 7.2, dx = 0, dz = -1, seconds = 0.65, height = 0.8},
	{x = 5, z = -2, dx = -1, dz = 0, seconds = 0.65, height = 1},
}) do
	local meadow = World.new(Level.parse(Levels[1]))
	local p = meadow.player
	p.x, p.y, p.z = route.x, 0, route.z
	Camera.place(meadow)
	local events = run(meadow, direction(meadow, route.dx, route.dz), route.seconds)
	t.expect(p.grounded and near(p.y, route.height) and not has(events, "hurt"),
		"the meadow's ramps rejoin the course from the lawn without a jump")
end

local keep = World.new(Level.parse(Levels[6]))
for z = -7.5, 0, 0.5 do
	for _, x in ipairs({-4.5, 4.5}) do
		t.expect(Terrain.blocked(keep:solids(), x, Reach.JUMP.rise, z, keep.rules.radius, keep.rules.height, keep.rules.step),
			"the keep cannot be entered from the lawn round its side")
	end
end
for x = -4.5, 4.5, 0.5 do
	t.expect(Terrain.blocked(keep:solids(), x, Reach.JUMP.rise, -8, keep.rules.radius, keep.rules.height, keep.rules.step),
		"the keep cannot be entered from its back")
end
keep.player.x, keep.player.y, keep.player.z = 0, 1, 2.6
Camera.place(keep)
run(keep, direction(keep, 0, -1), 1)
t.expect(keep.player.z > 0.4, "the gate stops the hero in the front corridor")
keep.hasKey = true
run(keep, direction(keep, 0, -1), 1)
t.expect(keep.player.z < -1, "the key opens the same corridor")
run(keep, direction(keep, 0, -1), 0.5)
t.expect(keep.player.z < -3, "courtyard props leave the route beyond the unlocked gate clear")

-- ── Running and jumping ────────────────────────────────────────────────
local field = level({blocks = {{"large", 0, 0}, {"large", 2, 0}, {"low", 4.5, 0}}})
local world = World.new(field)
t.expect(world.player.grounded and near(world.player.y, 1), "the hero starts standing")
run(world, pad(1, 0), 0.5)
t.expect(world.player.x > 1 and near(world.player.y, 1), "up runs away from the camera, right runs right")
t.expect(math.abs(world.player.yaw - 90) < 20, "the hero faces the way it runs")
local input = pad()
input.jumps = 1
world:step(1 / 60, input)
t.expect(not world.player.grounded and world.player.vy > 0, "a jump leaves the ground")
run(world, pad(), 1)
t.expect(world.player.grounded and world.player.landedAt, "and lands again")
local wall = World.new(level({blocks = {{"large", 0, 0}, {"tall", 2, 0, h = 3}}}))
run(wall, pad(1, 0), 1)
t.expect(wall.player.x < 1 - wall.rules.radius + 0.1, "a wall stops the hero")
local off = World.new(level({blocks = {{"large", 0, 0}}}))
local events = run(off, pad(1, 0), 2)
t.expect(has(events, "hurt"), "running off into the water hurts")
local late = World.new(level({blocks = {{"large", 0, 0}, {"large", 3, 0}}}))
local press = pad(1, 0)
for _ = 1, 120 do
	late:step(1 / 60, press)
	if not late.player.grounded then break end
end
late:step(1 / 60, press)
press.jumps = 1
late:step(1 / 60, press)
t.expect(late.player.vy > 0, "a jump just after running off the edge still counts")
local slope = World.new(level({blocks = {{"large", 0, 2}, {"slope", 0, 0}, {"large", 0, -2, h = 0.75}}, start = {0, 2}}))
run(slope, pad(0, -1), 0.75)
t.expect(slope.player.z < -0.8 and slope.player.grounded and slope.player.y > 0.7, "a slope is walked up")

-- ── The camera ─────────────────────────────────────────────────────────
world = World.new(field)
local fx, fz = Camera.forward(world)
t.expect(near(fx, 0) and near(fz, -1), "the camera starts behind the hero, looking north")
local distance = math.sqrt((world.camera.x - world.focus.x) ^ 2 + (world.camera.z - world.focus.z) ^ 2)
t.expect(near(distance, world.rules.cameraFar), "on its leash")
local faced = World.new(level({blocks = {{"large", 0, 0}}, facing = 90}))
fx = Camera.forward(faced)
t.expect(near(fx, -1), "a level's facing turns where the camera starts")
local turner = pad()
function turner.turn() return 1 end
run(world, turner, 0.75)
fx, fz = Camera.forward(world)
t.expect(math.abs(fx) > 0.9, "turning swings the camera round the hero")
run(world, pad(0, -1), 0.3)
t.expect(world.player.vx * fx + world.player.vz * fz > 0, "and up still runs away from the camera")

-- ── Springs, ferries and planks ────────────────────────────────────────
world = World.new(level({blocks = {{"large", 0, 0}}, springs = {{0, 0}}, start = {0.9, 0}}))
events = run(world, pad(-1, 0), 0.4)
t.expect(has(events, "sprung") and world.player.vy > 0, "a spring throws the hero")
t.expect(world.springs[1].firedAt, "and remembers it, for its squash")
local ferry = World.new(level({blocks = {{"large", 0, 0}, {"large", 7, 0}},
	movers = {{from = {2.6, 1, 0}, to = {4.4, 1, 0}}}}))
local mover = ferry.movers[1]
t.assertEqual(Platforms.progress(mover, 0, ferry.rules), 0, "a ferry waits at its start")
ferry.player.x, ferry.player.y = 2.6, 1
run(ferry, nil, ferry.rules.pause + 2)
t.expect(ferry.player.x > 4, "a ferry carries the hero standing on it")
local plank = World.new(level({blocks = {{"large", 0, 0}}, planks = {{2, 0, y = 1}}}))
plank.player.x = 2
events = run(plank, nil, plank.rules.plankHold + 0.6)
t.expect(has(events, "crumbled"), "a plank falls a moment after it is stood on")
events = run(plank, nil, 1)
t.expect(has(events, "hurt"), "and takes the hero into the water")
run(plank, nil, plank.rules.plankReturn)
t.expect(not plank.planks[1].gone and near(plank.planks[1].y, 1), "then floats back")

-- ── Pickups ────────────────────────────────────────────────────────────
local shop = level({blocks = {{"long", 0.5, 0}}, coins = {{1.4, 0}}, stars = {{0.4, 0.3}}, hearts = {{-0.3, 0.3}},
	checkpoints = {{0.4, -0.3}}, flag = {1.4, 0}, start = {-0.4, -0.2}})
world = World.new(shop)
events = run(world, nil, 0.1)
t.expect(has(events, "heart") and not has(events, "star"), "touching an item takes it")
world.player.x = 0.4
events = run(world, nil, 0.1)
t.expect(has(events, "star") and has(events, "checkpoint"), "stars and checkpoints are touched too")
t.expect(not world.flag.raised, "the flag does not wait for stars")
world.player.x = 1.4
events = run(world, nil, 0.1)
t.expect(has(events, "coin") and has(events, "flagRaised") and has(events, "cleared"),
	"the last coin raises the flag, and touching it clears the level")
world:respawn()
t.expect(near(world.player.x, 0.4), "a hero comes back at the last checkpoint")
local locked = World.new(level({blocks = {{"long", 0.5, 0}}, keys = {{1, 0}}, gates = {{0, 0}}, start = {-0.5, 0}}))
t.expect(#locked:solids() == #locked.level.solids + 1, "a locked gate is solid")
locked.player.x = 1
events = run(locked, nil, 0.1)
t.expect(has(events, "key") and has(events, "unlocked") and locked.gates[1].open, "the key opens the gate")
t.assertEqual(#locked:solids(), #locked.level.solids, "an open gate is not")

-- ── Saws and spikes ────────────────────────────────────────────────────
local mill = level({blocks = {{"long", 0.5, 0}, {"long", 0.5, -2}}, saws = {{0, -2, 1.4, -2}}})
world = World.new(mill)
local turnedBack = false
for _ = 1, 240 do
	world:step(1 / 60)
	t.expect(world.saws[1].x >= -0.01 and world.saws[1].x <= 1.41, "a saw stays on its run")
	if world.saws[1].direction < 0 then turnedBack = true end
end
t.expect(turnedBack, "a saw turns at the end of its run")
world.player.x, world.player.y, world.player.z = world.saws[1].x, world.saws[1].y, world.saws[1].z
events = world:step(1 / 60)
t.expect(has({events[1] and events[1].name}, "hurt"), "a saw touching the hero hurts")
t.expect(#world:step(1 / 60) == 0, "a recovering hero cannot be hurt again")
world = World.new(level({blocks = {{"large", 0, 0}}, spikes = {{0, 0}}}))
world.time = 0
events = run(world, nil, 0.05)
local spike = world.spikes[1]
t.expect(spike.raised == has(events, "hurt"), "raised spikes hurt a hero standing on them")
local pose
for _, p in ipairs(world:poses()) do if p.id == "spikes-1" then pose = p end end
t.expect(pose and pose.y ~= nil, "spikes are posed by their lift")

-- ── Session ────────────────────────────────────────────────────────────
local function oneCoin(id) return {id = id, title = id, blocks = {{"large", 0, 0}}, start = {-0.6, 0}, flag = {0.6, 0}, coins = {{0.6, 0}}} end
local session = Model.new({oneCoin("one"), oneCoin("two")})
t.assertEqual(session.state, "playing", "a session starts playing")
t.assertEqual(session:status().stage, "Level 1 of 2", "status names the level position")
local revision = session.revision
session:step(1 / 60, pad())
t.assertEqual(session.revision, revision, "standing still changes nothing but poses")
for _ = 1, 30 do session:step(1 / 60, pad(1, 0)) end
t.expect(session.score == 1 and session.revision > revision, "a coin scores and bumps the revision")
t.assertEqual(session.state, "cleared", "the risen flag under the hero clears the level")
t.assertEqual(session:status().message.title, "Level Complete", "the HUD message follows the state")
local x0 = session.world.player.x
session:step(1 / 60, pad(-1, 0))
t.assertEqual(session.world.player.x, x0, "nothing moves once the level ends")
session:advance()
t.expect(session.levelIndex == 2 and session.state == "playing", "advance loads the next level")
t.assertEqual(session.score, 1, "the score carries to the next level")
for _ = 1, 30 do session:step(1 / 60, pad(1, 0)) end
t.assertEqual(session.state, "won", "clearing the last level wins")
session:advance()
t.expect(session.levelIndex == 1 and session.score == 0 and session.lives == 3, "advance after winning restarts")

session = Model.new({{id = "fall", title = "Fall", blocks = {{"large", 0, 0}}, start = {0, 0}, flag = {0, 0},
	coins = {{0.8, 0.8}}, hearts = {{-0.8, -0.8}}}, oneCoin("next")})
local function fall()
	local lives = session.lives
	for _ = 1, 120 do
		session:step(1 / 60, pad(0, 1))
		if session.lives ~= lives then break end
	end
	session:step(1 / 60)
end
fall()
t.expect(session.lives == 2 and session.state == "playing", "falling in the water costs a life")
t.expect(near(session.world.player.z, 0) and session.world.player.grounded, "and puts the hero back at the start")
session.world.player.x, session.world.player.z = -0.8, -0.8
session:step(1 / 60)
t.assertEqual(session.lives, 3, "a heart gives a life back")
session.lives = 1
fall()
t.expect(session.lives == 0 and session.state == "over", "the last life ends the try")
t.assertEqual(session:status().message.title, "Out of Lives", "running out shows its message")
session:advance()
t.expect(session.levelIndex == 1 and session.lives == 3 and session.state == "playing",
	"advance tries the same level again with full lives")
t.assertEqual(session:status().totalStars, 0, "status knows the level's stars")

-- ── Input ──────────────────────────────────────────────────────────────
local commands = {}
input = InputController.new({advance = function() table.insert(commands, "advance") end,
	restart = function() table.insert(commands, "restart") end})
t.expect(input:key("left", true), "arrow keys are handled")
local ax, az = input:axis()
t.expect(ax == -1 and az == 0, "a held key runs")
input:key("up", true)
ax, az = input:axis()
t.expect(ax == -1 and az == -1, "two held keys run diagonally")
input:key("left", false); input:key("up", false)
ax, az = input:axis()
t.expect(ax == 0 and az == 0, "nothing held, standing still")
t.expect(input:key("space", true) and input:takeJump() and not input:takeJump(), "space jumps once per press")
t.expect(input:key("return", true) and input:key("r", true), "command keys are handled")
t.expect(commands[1] == "advance" and commands[2] == "restart", "command keys run their commands")
t.expect(not input:key("p", true), "other keys are left to the system")
input:key("e", true)
t.assertEqual(input:turn(), 1, "E turns the camera")
input:key("e", false)
t.assertEqual(input:turn(), 0, "and letting go stops it")
input:swipe("right")
ax = input:axis()
t.assertEqual(ax, 1, "a swipe runs")
input:swipe("left")
ax = input:axis()
t.assertEqual(ax, 0, "a swipe the other way stops")
input:gamepad({stickX = 0.5, stickY = 0.8, a = true})
ax, az = input:axis()
t.expect(near(ax, 0.5) and near(az, -0.8) and input:takeJump(), "the stick runs, y up, and A jumps")
input:gamepad({stickX = 0.05, stickY = 0.05, a = true, x = true})
ax, az = input:axis()
t.expect(ax == 0 and az == 0 and not input:takeJump(), "a resting stick is still, and a held A jumps once")
t.assertEqual(input:turn(), -1, "X turns the camera the other way")
input:gamepad(nil)
t.assertEqual(input:turn(), 0, "no controller, no turning")
input:jump(); input:reset()
t.expect(not input:takeJump(), "reset forgets a queued jump")

-- ── Animation ──────────────────────────────────────────────────────────
local function volume(look) return look.scaleX * look.scaleY * look.scaleZ end
local anim = World.new(level({blocks = {{"large", 0, 0}}, springs = {{0.5, 0.5}}}))
anim.time = 0.4
local idle = Animation.player(anim)
t.expect(math.abs(idle.scaleY - 1) <= Animation.RULES.breath + 1e-9, "a standing hero only breathes")
anim.player.grounded, anim.player.vy = false, Animation.RULES.stretchSpeed
local flying = Animation.player(anim)
t.expect(near(flying.scaleY, 1 + Animation.RULES.stretch), "a hero flying fast stretches")
t.expect(near(volume(flying), 1), "squash and stretch keep the hero's volume")
anim.player.grounded, anim.player.landedAt = true, anim.time
local landing = Animation.player(anim)
t.expect(near(landing.scaleY, 1 - Animation.RULES.squash), "a landing starts squashed")
anim.time = anim.time + Animation.RULES.squashTime * 2
t.expect(math.abs(Animation.player(anim).scaleY - 1) <= Animation.RULES.breath + 1e-9, "then the hero breathes again")
anim.player.hurtAt = anim.time - 0.01
t.expect(Animation.player(anim).yaw ~= anim.player.yaw, "a hit shakes the hero")
anim.player.hurtAt = nil
anim.player.clearedAt = anim.time - 0.5
t.expect(near(Animation.player(anim).yaw, anim.player.yaw + Animation.RULES.spinRate * 0.5), "the hero spins at the flag")
local spring = anim.springs[1]
t.assertEqual(Animation.spring(anim, spring), 1, "an idle spring stands tall")
spring.firedAt = anim.time
t.expect(Animation.spring(anim, spring) < 1, "a spring squashes as it throws")
local poses = anim:poses()
t.expect(poses[1].scaleX and poses[1].scaleY and poses[#poses].id == "flag", "poses carry the hero's squash and the flag's sway")

-- ── View data ──────────────────────────────────────────────────────────
local scene = Model.new(Levels):scene()
local data = StageController.viewData(scene)
t.assertEqual(#data.blocks, #scene.blocks, "every block is drawn")
t.expect(StageController.blockModel({kind = "large"}, "grass") == "block-grass-overhang-large.obj",
	"a top block drapes its grass over the edge")
t.expect(StageController.blockModel({kind = "large", buried = true}, "snow") == "block-snow-large.obj",
	"a buried block is plain, in its biome")
t.expect(StageController.propModel("pine", "snow") == "tree-pine-snow.obj", "a snow level has snowy trees")
t.expect(data.coins[1] ~= scene.coins[1], "templates receive copies, never live entities")
t.expect(data.flag == nil, "the flag is not drawn until it rises")
local cameraPose = StageController.cameraPose({position = {x = 0, y = 4, z = 6}, focus = {x = 0, y = 1, z = 0}})
t.expect(cameraPose.id == "camera" and cameraPose.lookX == 0 and cameraPose.lookZ == 0, "the camera is aimed at its focus")
local hud = HudController.viewData({level = "L", stage = "Level 1 of 3", coins = 2, totalCoins = 5, score = 2,
	levelStars = 1, totalStars = 3, lives = 1, maxLives = 3, state = "playing"})
t.assertEqual(hud.coins, "2 / 5", "the HUD counts coins taken")
t.assertEqual(hud.stars, "1 / 3", "the HUD counts stars")
t.expect(hud.hearts[1].filled and not hud.hearts[2].filled, "hearts show lives left")
t.expect(hud.message == nil, "no message while playing")
t.expect(hud.hint:find("Arrows"), "the HUD hints at keys by default")
t.expect(HudController.viewData({level = "L", stage = "s", coins = 0, totalCoins = 1, score = 0, lives = 1, maxLives = 1,
	state = "playing", totalStars = 0}, "Stick runs").hint == "Stick runs", "the HUD takes the touch hint")

-- ── The whole game, headless ───────────────────────────────────────────
local app = Controller.new({levels = {oneCoin("mini"), oneCoin("next")}})
app:createWindow()
local view = app.stage.view
local nodes = bridge._sceneNodes(view)
t.expect(nodes.player and nodes["coin-1"] and nodes["level-mini"], "the stage template builds the level")
t.expect(nodes["coin-1"].spinning, "coins spin natively, not from Lua")
t.expect(nodes.flag == nil, "the flag is absent until every coin is taken")
t.expect(app.hud.refs.level.text == "mini", "the HUD names the level")
t.expect(bridge._sceneSend(view, "key", "right", true), "the stage forwards keys to input")
for _ = 1, 30 do bridge._sceneSend(view, "frame", 1 / 60) end
bridge._sceneSend(view, "key", "right", false)
nodes = bridge._sceneNodes(view)
t.expect(nodes.player.x > -0.5, "frames step the game and pose the player")
t.expect(near(nodes.camera.roll, 0, 1e-3) and nodes.camera.pitch < 0, "the camera looks down at the hero, level")
t.expect(nodes["coin-1"] == nil, "a taken coin leaves the scene")
t.assertEqual(app.model.state, "cleared", "reaching the flag clears the level")
t.assertEqual(app.hud.refs.messageTitle.text, "Level Complete", "the HUD announces it")
bridge._sceneSend(view, "key", "space", true)
bridge._sceneSend(view, "frame", 1 / 60)
nodes = bridge._sceneNodes(view)
t.expect(nodes["level-next"] and not nodes["level-mini"], "a jump after the level swaps in the next one")
t.expect(rawequal(view, app.stage.view), "levels reuse the same SceneView")
t.expect(app.hud.refs.messageTitle == nil, "the message leaves once play resumes")
-- Touch: a tap jumps; after the game it plays again.
local touch = Controller.new({levels = {oneCoin("tap")}})
touch:createWindow()
local touchView = touch.stage.view
bridge._sceneSend(touchView, "tap")
bridge._sceneSend(touchView, "frame", 1 / 60)
t.expect(touch.model.world.player.vy > 0, "a tap jumps")
bridge._sceneSend(touchView, "swipe", "right")
for _ = 1, 60 do bridge._sceneSend(touchView, "frame", 1 / 60) end
t.assertEqual(touch.model.state, "won", "a swipe runs the hero to the coin and the flag")
bridge._sceneSend(touchView, "tap")
t.assertEqual(touch.model.state, "playing", "a tap after the game ends plays again")
t.expect(touch.stage:gamepad() == nil, "no game controller is connected in a test")
-- Every level of the game builds through the real stage template.
local full = Controller.new()
full:createWindow()
for index = 1, #full.model.levels do
	full.model:load(index)
	full:render()
	local levelId = "level-" .. full.model:level().id
	local rendered = bridge._sceneNodes(full.stage.view)
	t.expect(rendered[levelId], "level " .. index .. " renders")
	local base = rendered[levelId .. "/1"]
	local block = full.model:level().blocks[1]
	local stageData = StageController.viewData(full.model:scene())
	local viewBlock = stageData.blocks[1]
	local sun = rendered.sun
	t.expect(sun.castsShadow and sun.shadowMapSize == 2048 and sun.shadowSampleCount == 4 and sun.shadowRadius == 1,
		"level " .. index .. ": one crisp 2048 shadow map")
	t.expect(not sun.automaticallyAdjustsShadowProjection and near(sun.orthographicScale, stageData.sun.orthographicScale),
		"level " .. index .. ": a fixed shadow projection covers the ground")
	local halfWidth, halfDepth = (block.solid.x1 - block.solid.x0) / 2, (block.solid.z1 - block.solid.z0) / 2
	t.expect(sun.orthographicScale > math.sqrt(halfWidth * halfWidth + halfDepth * halfDepth),
		"level " .. index .. ": shadow coverage includes the ground diagonal and a caster margin")
	full.stage:pose(full.model:poses(), {position = {x = 14, y = 18, z = 20}, focus = {x = 0, y = 0, z = 0}})
	local posedSun = bridge._sceneNodes(full.stage.view).sun
	t.expect(posedSun.x == sun.x and posedSun.y == sun.y and posedSun.z == sun.z and posedSun.orthographicScale == sun.orthographicScale,
		"level " .. index .. ": camera motion leaves the shadow map stable")
	t.expect(base and near(base.scale, block.scaleX) and near(viewBlock.scaleZ, block.scaleZ)
		and near(base.scaleY, block.stretch) and near(base.y, block.y),
		"level " .. index .. ": the rendered recovery ground matches its collision dimensions")
end

local frameBefore = app.model.world.time
app:tick(5)
t.expect(near(app.model.world.time - frameBefore, 0.1), "a stalled frame is capped")

os.exit(t.summary() and 0 or 1)
