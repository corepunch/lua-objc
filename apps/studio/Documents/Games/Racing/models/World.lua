-- One running race (a game.World): the player's car, the rivals, the
-- countdown, the clock and the step's events.
--
-- Each rule is a system in models/systems/, run in SYSTEMS order: the
-- countdown, the player's driving, the rivals' driving, bumps between
-- cars, the race (laps, places, the finish), and the camera. Systems emit
-- events (countdown, lap, place, finished) and Model.lua's REACTIONS say
-- what they mean.
local Chase = require("game.cameras.Chase")
local Track = require("demo.playground.models.Track")

-- Tuning, in seconds and scene units (a road is 4 units wide).
local RULES = {
	countdown = 3, -- seconds of "3, 2, 1" before the start
	topSpeed = 16, -- units per second on the road
	grassSpeed = 6, -- and on the grass
	reverseSpeed = 5,
	acceleration = 9,
	braking = 24,
	coasting = 5, -- how quickly a car slows with nothing pressed
	grassDrag = 18, -- how quickly the grass slows a fast car
	steerRate = 150, -- degrees per second at full lock
	steerSpeed = 4, -- below this speed steering weakens, as a real car's
	roadHalf = 2.0, -- how far from the road's middle the tarmac and kerbs reach
	edge = 14, -- how far from the road a car may wander before it is turned back
	carRadius = 0.55,
	bump = 0.7, -- of its speed a car keeps after a bump
}
for key, value in pairs(Chase.RULES) do RULES[key] = value end

local World = require("game.World"):extend({
	RULES = RULES,
	SYSTEMS = {
		(require("demo.playground.models.systems.Countdown")),
		(require("demo.playground.models.systems.Driver")),
		(require("demo.playground.models.systems.Rivals")),
		(require("demo.playground.models.systems.Bumps")),
		(require("demo.playground.models.systems.Race")),
		Chase,
	},
})

-- Places on the start grid, front first: how far past the line and how
-- far right of the road's middle. The player starts at the back.
local GRID = {{s = 6, lane = -0.8}, {s = 6, lane = 0.8}, {s = 2.5, lane = -0.8}, {s = 2.5, lane = 0.8}}

function World.new(level, rules)
	local self = World.create(level, rules, World)
	self.path = level.path
	self.rivals = {}
	for index, rival in ipairs(level.rivals) do
		local slot = GRID[index]
		local car = {id = "rival-" .. index, model = rival.model, pace = rival.pace, s = slot.s, lane = slot.lane, speed = 0}
		car.x, car.z, car.yaw, car.hint = Track.at(self.path, car.s, car.lane)
		table.insert(self.rivals, car)
	end
	local slot = GRID[#level.rivals + 1]
	local player = {id = "player", model = level.car, speed = 0, lap = 0, checkpoint = 0, place = #self.rivals + 1}
	player.x, player.z, player.yaw = Track.at(self.path, slot.s, slot.lane)
	player.y = 0
	self.player = player
	self.clock = -self.rules.countdown -- the race starts when the clock reaches 0
	self.started = false
	Chase.place(self)
	return self
end

-- A race has no lives to lose; the session never asks for a respawn.
function World:respawn() end

-- What moves every frame, keyed by the ids the stage gives their nodes.
function World:poses()
	local p = self.player
	local poses = {{id = "player", x = p.x, y = 0, z = p.z, yaw = p.yaw}}
	for _, car in ipairs(self.rivals) do
		table.insert(poses, {id = car.id, x = car.x, y = 0, z = car.z, yaw = car.yaw})
	end
	return poses
end

return World
