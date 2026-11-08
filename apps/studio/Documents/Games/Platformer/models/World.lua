-- One running level (a game.World): the hero, coins, springs, spikes and
-- the flag, the clock and the step's events.
--
-- Each rule is a system in models/systems/, run in SYSTEMS order: the hero
-- moves, springs throw, pickups count, hazards hurt, and the camera
-- follows. Systems emit events (coin, flagRaised, cleared, hurt, sprung,
-- animation) and Model.lua's REACTIONS say what they mean.
local Leash = require("game.cameras.Leash")

-- Tuning, in seconds and scene units. Level.parse checks every level
-- against these, so a stronger jump makes wider gaps legal.
local RULES = {
	runSpeed = 5, -- units per second
	acceleration = 40, -- how quickly the hero reaches running speed
	airControl = 0.6, -- of which this much in the air
	gravity = 26,
	jumpSpeed = 9, -- a jump rises v² / 2g, about 1.55 units
	springSpeed = 14, -- a spring's throw rises about 3.8 units
	coyoteTime = 0.1, -- a jump still counts this long after running off an edge
	jumpBuffer = 0.12, -- and a press this long before landing
	terminalSpeed = 20,
	radius = 0.28, -- the hero's body
	height = 0.85,
	step = 0.3, -- what the hero walks up without jumping
	reach = 0.6, -- how close a coin or the flag must be
	recovery = 1.5, -- invulnerable time after a hit
}
for key, value in pairs(Leash.RULES) do RULES[key] = value end

local World = require("game.World"):extend({
	RULES = RULES,
	SYSTEMS = {
		(require("demo.playground.models.systems.Hero")),
		(require("demo.playground.models.systems.Springs")),
		(require("demo.playground.models.systems.Pickups")),
		(require("demo.playground.models.systems.Hazards")),
		Leash,
	},
})

function World.new(level, rules)
	local self = World.create(level, rules, World)
	local spawns = level.spawns
	self.coins = World.spawnAll(spawns.coins, "coin")
	self.springs = World.spawnAll(spawns.springs, "spring")
	self.spikes = World.spawnAll(spawns.spikes, "spikes")
	self.flag = {id = "flag", x = spawns.flag.x, y = spawns.flag.y, z = spawns.flag.z, raised = #self.coins == 0}
	self.player = {id = "player"}
	self:respawn()
	Leash.place(self)
	return self
end

-- Back to the start, standing still, briefly safe from hazards.
function World:respawn()
	local start, player = self.level.start, self.player
	player.x, player.y, player.z = start.x, start.y, start.z
	player.vx, player.vy, player.vz = 0, 0, 0
	player.grounded, player.airborneAt, player.jumpPressedAt = true, nil, nil
	player.yaw, player.animation = 0, "idle"
	player.safeUntil = self.time + self.rules.recovery
end

-- What moves every frame, keyed by the ids the stage gives their nodes.
function World:poses()
	local p = self.player
	local blinking = self.time < (p.safeUntil or 0) and math.floor(self.time * 10) % 2 == 0
	return {{id = "player", x = p.x, y = p.y, z = p.z, yaw = p.yaw, opacity = blinking and 0.35 or 1}}
end

return World
