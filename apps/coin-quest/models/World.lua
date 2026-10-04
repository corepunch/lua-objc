-- The running state of one level: its entities, the clock and the events of
-- the current step.
--
-- Entities are plain tables grouped by kind. Behaviour lives in systems
-- (models/systems/), each a module with `update(world, dt, input)` run in a
-- fixed order every step, so a rule is one small file that can be tested
-- alone with a hand-built world. Systems talk to the session through events
-- (`coin`, `flagRaised`, `hurt`, `cleared`, `key`, `unlocked`, `crumbled`)
-- instead of calling it.
local Animation = require("apps.coin-quest.models.Animation")

local World = {}
World.__index = World

-- Tuning, in seconds and scene units (one unit per map cell).
World.RULES = {
	hopTime = 0.16, -- one cell's hop; a leap takes a little longer
	hopHeight = 0.35,
	leapHeight = 0.72, -- a jump over water
	sawSpeed = 1.8, -- cells per second
	sawReach = 0.5, -- a saw turns where its leading edge would leave the ground
	ferrySpeed = 1.4,
	spikeCycle = 2.4, -- one raise-and-lower
	spikeRaised = 1.0, -- of which the spikes stand up
	spikeStagger = 0.3, -- phase offset per cell, so a field ripples
	spikeSpeed = 8, -- how fast the spikes travel between up and down
	spikeDepth = 0.24, -- how far lowered spikes sink into the ground
	bridgeHold = 0.85, -- a crumbling bridge falls if you stand this long
	hitRadius = 0.6, -- saw contact distance
	recovery = 1.5, -- invulnerable time after a hit
}

-- The order is the rules' order: a pad launches, then the hero moves, then
-- ferries carry, then hazards move, then what the hero landed on counts
-- before anything can hurt them. (Parenthesised: `require` returns a second
-- value that would join the list.)
World.SYSTEMS = {
	(require("apps.coin-quest.models.systems.Springs")),
	(require("apps.coin-quest.models.systems.Movement")),
	(require("apps.coin-quest.models.systems.Platforms")),
	(require("apps.coin-quest.models.systems.Patrol")),
	(require("apps.coin-quest.models.systems.Traps")),
	(require("apps.coin-quest.models.systems.Crumble")),
	(require("apps.coin-quest.models.systems.Locks")),
	(require("apps.coin-quest.models.systems.Pickups")),
	(require("apps.coin-quest.models.systems.Hazards")),
}

function World.new(level, rules)
	local self = setmetatable({level = level, rules = rules or World.RULES, time = 0, events = {},
		coins = {}, saws = {}, spikes = {}, springs = {}, crumbles = {}, keys = {}, gates = {},
		platforms = {}, gone = {}}, World)
	level.gone = self.gone
	level.crumbles = {}
	local spawns = level.spawns
	self.player = {id = "player"}
	self:respawn()
	for index, spawn in ipairs(spawns.coins) do
		table.insert(self.coins, {id = "coin-" .. index, x = spawn.x, z = spawn.z})
	end
	for index, spawn in ipairs(spawns.aerial or {}) do
		table.insert(self.coins, {id = "aerial-" .. index, x = spawn.x, z = spawn.z, aerial = true})
	end
	for index, spawn in ipairs(spawns.saws) do
		table.insert(self.saws, {id = "saw-" .. index, x = spawn.x, z = spawn.z, axis = spawn.axis, direction = 1})
	end
	for index, spawn in ipairs(spawns.spikes) do
		table.insert(self.spikes, {id = "spikes-" .. index, x = spawn.x, z = spawn.z, raised = false, lift = 0})
	end
	for index, spawn in ipairs(spawns.keys or {}) do
		table.insert(self.keys, {id = "key-" .. index, x = spawn.x, z = spawn.z})
	end
	for index, spawn in ipairs(spawns.gates or {}) do
		table.insert(self.gates, {id = "gate-" .. index, x = spawn.x, z = spawn.z})
	end
	for index, spawn in ipairs(spawns.platforms or {}) do
		local platform = {id = "ferry-" .. index, x = spawn.x, z = spawn.z, axis = spawn.axis,
			direction = 1, min = spawn.min, max = spawn.max, cx = spawn.x, cz = spawn.z}
		table.insert(self.platforms, platform)
	end
	for _, spawn in ipairs(spawns.crumbles or {}) do level.crumbles[spawn.x .. ":" .. spawn.z] = true end
	self.flag = {id = "flag", x = spawns.flag.x, z = spawns.flag.z, raised = false}
	return self
end

-- Puts the player back on the start cell, facing the camera.
function World:respawn()
	local start, player = self.level.spawns.player, self.player
	player.x, player.z, player.fromX, player.fromZ = start.x, start.z, start.x, start.z
	player.hop, player.span, player.yaw, player.landed, player.landedAt = nil, 1, 0, false, nil
	player.dx, player.dz, player.boost, player.riding, player.bridge = nil, nil, nil, nil, nil
end

function World:emit(name, entity)
	table.insert(self.events, {name = name, entity = entity})
end

function World:gateOpen(x, z)
	for _, gate in ipairs(self.gates) do
		if gate.x == x and gate.z == z then return gate.open == true end
	end
end

-- Ground, or a ferry currently on this cell.
function World:standable(x, z)
	if self.level:walkable(x, z) then return true end
	for _, platform in ipairs(self.platforms) do
		if platform.cx == x and platform.cz == z then return true end
	end
	return false
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

function World:coinAt(x, z)
	for _, coin in ipairs(self.coins) do
		if not coin.taken and coin.x == x and coin.z == z then return coin end
	end
end

function World:keyAt(x, z)
	for _, key in ipairs(self.keys) do
		if not key.taken and key.x == x and key.z == z then return key end
	end
end

function World:coinsLeft()
	local count = 0
	for _, coin in ipairs(self.coins) do if not coin.taken then count = count + 1 end end
	return count
end

-- Where the player is drawn: between its cells while hopping, lifted on an
-- arc, or riding a ferry.
function World:playerPosition()
	local player = self.player
	if player.riding and not player.hop then
		for _, platform in ipairs(self.platforms) do
			if platform.id == player.riding then return platform.x, 0.2, platform.z end
		end
	end
	local t = player.hop or 1
	local height = (player.span or 1) > 1 and self.rules.leapHeight or self.rules.hopHeight
	return player.fromX + (player.x - player.fromX) * t,
		math.sin(math.pi * t) * height * (player.hop and 1 or 0),
		player.fromZ + (player.z - player.fromZ) * t
end

-- Every moving entity's pose for the SceneView, keyed by the ids the stage
-- template gives their nodes. Static entities keep their template pose.
function World:poses()
	local x, y, z = self:playerPosition()
	local player = self.player
	local look = Animation.player(self)
	local poses = {{id = "player", x = x, y = y, z = z, yaw = look.yaw,
		scaleX = look.scaleX, scaleY = look.scaleY, scaleZ = look.scaleZ,
		-- Blinks while recovering from a hit.
		opacity = (player.recovering or 0) > 0 and (math.floor(self.time * 10) % 2 == 0 and 0.35 or 1) or 1}}
	for _, saw in ipairs(self.saws) do table.insert(poses, {id = saw.id, x = saw.x, z = saw.z}) end
	for _, spike in ipairs(self.spikes) do
		table.insert(poses, {id = spike.id, y = (spike.lift - 1) * self.rules.spikeDepth})
	end
	for _, platform in ipairs(self.platforms) do
		table.insert(poses, {id = platform.id, x = platform.x, z = platform.z})
	end
	table.insert(poses, {id = self.flag.id, yaw = Animation.flag(self).yaw})
	return poses
end

return World
