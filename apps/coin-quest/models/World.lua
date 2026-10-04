-- The running state of one level: its entities, the clock and the events of
-- the current step.
--
-- Entities are plain tables grouped by kind. Behaviour lives in systems
-- (models/systems/), each a module with `update(world, dt, input)` run in a
-- fixed order every step, so a rule is one small file that can be tested
-- alone with a hand-built world. Systems talk to the session through events
-- (`coin`, `star`, `heart`, `key`, `unlocked`, `checkpoint`, `flagRaised`,
-- `cleared`, `hurt`, `sprung`, `crumbled`) instead of calling it.
local Animation = require("apps.coin-quest.models.Animation")
local Level = require("apps.coin-quest.models.Level")
local Terrain = require("apps.coin-quest.models.Terrain")
local Camera = require("apps.coin-quest.models.systems.Camera")

local World = {}
World.__index = World

-- Tuning, in seconds and scene units.
World.RULES = {
	runSpeed = 5, -- units per second
	acceleration = 40, -- how quickly the hero reaches running speed
	airControl = 0.6, -- of which this much in the air
	gravity = 26,
	jumpSpeed = 9, -- a jump rises v² / 2g, about 1.55 units
	springSpeed = 15, -- a spring's throw rises about 4.3 units
	coyoteTime = 0.1, -- a jump still counts this long after running off an edge
	jumpBuffer = 0.12, -- and a press this long before landing
	terminalSpeed = 20,
	radius = 0.28, -- the hero's body
	height = 0.85,
	step = 0.3, -- what the hero walks up without jumping
	water = -0.6, -- below this the hero has fallen in
	reach = 0.65, -- how close a pickup must be
	sawSpeed = 1.8,
	sawRadius = 0.55,
	ferrySpeed = 1.4,
	pause = 0.8, -- a ferry or lift waits this long at each end
	spikeCycle = 2.4, -- one raise-and-lower
	spikeRaised = 1.0, -- of which the spikes stand up
	spikeSpeed = 8,
	spikeDepth = 0.24,
	spikeSize = 0.42, -- half the trap's width
	plankHold = 0.6, -- a plank falls this long after it is stood on
	plankReturn = 3, -- and is back this long after it fell
	recovery = 1.5, -- invulnerable time after a hit
	follow = 6, -- how quickly the camera's focus catches up, per second
	cameraNear = 5, -- the camera's leash: never closer than this
	cameraFar = 7.5, -- nor further
	cameraHeight = 3.4, -- above the hero
	cameraTurn = 120, -- degrees per second when the player turns it
}

-- The order is the rules' order: ferries and planks move and carry their
-- rider, the hero runs and jumps, saws and spikes move, what the hero
-- touches counts before anything can hurt them, and the camera follows.
-- (Parenthesised: `require` returns a second value that would join the
-- list.)
World.SYSTEMS = {
	(require("apps.coin-quest.models.systems.Platforms")),
	(require("apps.coin-quest.models.systems.Hero")),
	(require("apps.coin-quest.models.systems.Patrol")),
	(require("apps.coin-quest.models.systems.Traps")),
	(require("apps.coin-quest.models.systems.Locks")),
	(require("apps.coin-quest.models.systems.Pickups")),
	(require("apps.coin-quest.models.systems.Hazards")),
	Camera,
}

local function spawnAll(list, prefix, extra)
	local entities = {}
	for index, spawn in ipairs(list) do
		local entity = {id = prefix .. "-" .. index}
		for k, v in pairs(spawn) do entity[k] = v end
		if extra then extra(entity) end
		table.insert(entities, entity)
	end
	return entities
end

function World.new(level, rules)
	local self = setmetatable({level = level, rules = rules or World.RULES, time = 0, events = {}}, World)
	local spawns = level.spawns
	self.coins = spawnAll(spawns.coins, "coin")
	self.stars = spawnAll(spawns.stars, "star")
	self.hearts = spawnAll(spawns.hearts, "heart")
	self.keys = spawnAll(spawns.keys, "key")
	self.checkpoints = spawnAll(spawns.checkpoints, "checkpoint")
	self.springs = spawnAll(spawns.springs, "spring")
	self.gates = spawnAll(spawns.gates, "gate", function(e)
		e.solid = Terrain.solid(e.x, e.y, e.z, Level.SIZES.gate)
	end)
	self.saws = spawnAll(spawns.saws, "saw", function(e)
		e.fromX, e.fromZ, e.t, e.direction = e.x, e.z, 0, 1
	end)
	self.spikes = spawnAll(spawns.spikes, "spikes", function(e) e.raised, e.lift = false, 0 end)
	self.movers = spawnAll(spawns.movers, "mover", function(e)
		e.fromX, e.fromY, e.fromZ = e.x, e.y, e.z
		e.solid = Terrain.solid(e.x, e.y - Level.SIZES.mover.h, e.z, Level.SIZES.mover)
	end)
	self.planks = spawnAll(spawns.planks, "plank", function(e)
		e.restY = e.y
		e.solid = Terrain.solid(e.x, e.y - Level.SIZES.plank.h, e.z, Level.SIZES.plank)
	end)
	self.flag = {id = "flag", x = spawns.flag.x, y = spawns.flag.y, z = spawns.flag.z, raised = false}
	self.player = {id = "player"}
	self:respawn()
	Camera.place(self)
	return self
end

-- Puts the player on the last checkpoint it touched, or the start, facing
-- the camera, standing still.
function World:respawn()
	local start, player = self.checkpoint or self.level.spawns.player, self.player
	player.x, player.y, player.z = start.x, start.y, start.z
	player.vx, player.vy, player.vz = 0, 0, 0
	player.grounded, player.standing, player.airborneAt = true, nil, nil
	player.yaw, player.landedAt, player.jumpedAt = 0, nil, nil
end

function World:emit(name, entity)
	table.insert(self.events, {name = name, entity = entity})
end

-- Everything solid this frame: the level, the ferries and planks where
-- they are, and the gates still locked.
function World:solids()
	local solids = {}
	for _, solid in ipairs(self.level.solids) do table.insert(solids, solid) end
	for _, mover in ipairs(self.movers) do table.insert(solids, mover.solid) end
	for _, plank in ipairs(self.planks) do
		if not plank.gone then table.insert(solids, plank.solid) end
	end
	for _, gate in ipairs(self.gates) do
		if not gate.open then table.insert(solids, gate.solid) end
	end
	return solids
end

-- Advances every system by `dt` seconds and returns the events it raised.
function World:step(dt, input)
	self.events = {}
	self.time = self.time + dt
	for _, system in ipairs(World.SYSTEMS) do system.update(self, dt, input) end
	return self.events
end

-- Time passes on a finished level, so the hero can celebrate: nothing else
-- moves.
function World:idle(dt)
	self.time = self.time + dt
end

function World:coinsLeft()
	local count = 0
	for _, coin in ipairs(self.coins) do if not coin.taken then count = count + 1 end end
	return count
end

function World:playerPosition()
	local player = self.player
	return player.x, player.y, player.z
end

-- Every moving entity's pose for the SceneView, keyed by the ids the stage
-- template gives their nodes. Static entities keep their template pose.
function World:poses()
	local player = self.player
	local look = Animation.player(self)
	local poses = {{id = "player", x = player.x, y = player.y, z = player.z, yaw = look.yaw,
		scaleX = look.scaleX, scaleY = look.scaleY, scaleZ = look.scaleZ,
		-- Blinks while recovering from a hit.
		opacity = (player.recovering or 0) > 0 and (math.floor(self.time * 10) % 2 == 0 and 0.35 or 1) or 1}}
	for _, saw in ipairs(self.saws) do table.insert(poses, {id = saw.id, x = saw.x, z = saw.z}) end
	for _, spike in ipairs(self.spikes) do
		table.insert(poses, {id = spike.id, y = spike.y + (spike.lift - 1) * self.rules.spikeDepth})
	end
	for _, mover in ipairs(self.movers) do
		table.insert(poses, {id = mover.id, x = mover.x, y = mover.y, z = mover.z})
	end
	for _, plank in ipairs(self.planks) do
		table.insert(poses, {id = plank.id, y = plank.y, opacity = plank.gone and 0 or 1})
	end
	for _, spring in ipairs(self.springs) do
		table.insert(poses, {id = spring.id, scaleY = Animation.spring(self, spring)})
	end
	table.insert(poses, {id = self.flag.id, yaw = Animation.flag(self).yaw})
	return poses
end

return World
