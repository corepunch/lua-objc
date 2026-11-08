-- A chase camera, as racing and flying games use: it rides behind
-- `world.player` at a fixed distance and height, looking a little ahead
-- of it. Only its direction lags: the camera swings round after the
-- player's heading, so a turn shows the car turning, yet the car never
-- leaves the screen at speed. It is a system: list it last in a world's
-- SYSTEMS. The stage turns `world.camera` and `world.focus` into the
-- view's camera pose (game.Stage.cameraPose).
--
-- The player's `yaw` is its heading in degrees: it moves along
-- (sin yaw, cos yaw), so yaw 0 drives toward +z.
--
-- World rules it reads: chaseDistance, chaseHeight, chaseAhead (how far
-- past the player the camera looks) and chaseFollow (how quickly the
-- camera's direction catches up with the heading, per second).
local Chase = {}

Chase.RULES = {chaseDistance = 6, chaseHeight = 2.6, chaseAhead = 3, chaseFollow = 4}

local function aim(world)
	local p, rules, yaw = world.player, world.rules, math.rad(world.chaseYaw)
	local fx, fz = math.sin(yaw), math.cos(yaw)
	world.camera = {x = p.x - fx * rules.chaseDistance, y = (p.y or 0) + rules.chaseHeight, z = p.z - fz * rules.chaseDistance}
	world.focus = {x = p.x + fx * rules.chaseAhead, y = p.y or 0, z = p.z + fz * rules.chaseAhead}
end

-- Starts the camera straight behind the player.
function Chase.place(world)
	world.chaseYaw = world.player.yaw or 0
	aim(world)
end

-- The shortest signed turn from angle `a` to angle `b`, in degrees.
function Chase.turn(a, b)
	return (b - a + 180) % 360 - 180
end

function Chase.update(world, dt)
	local k = 1 - math.exp(-world.rules.chaseFollow * dt)
	world.chaseYaw = world.chaseYaw + Chase.turn(world.chaseYaw, world.player.yaw or 0) * k
	aim(world)
end

return Chase
