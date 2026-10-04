-- The hero runs where the input points, as seen from the camera: up on the
-- stick runs away from it. The hero jumps, falls, and stops against
-- whatever is solid. Ground is the highest top under the hero's feet within
-- a small step, so ramps, arches and low steps are walked; anything taller
-- is jumped. A jump pressed a moment before landing, or a moment after
-- running off an edge, still counts. Landing on a spring throws the hero
-- high.
local Terrain = require("apps.coin-quest.models.Terrain")
local Camera = require("apps.coin-quest.models.systems.Camera")

local Hero = {}

local function approach(value, target, step)
	if value < target then return math.min(target, value + step) end
	return math.max(target, value - step)
end

function Hero.update(world, dt, input)
	local p, rules = world.player, world.rules
	local solids = world:solids()
	-- Running.
	local sx, sz = 0, 0
	if input and input.axis then sx, sz = input:axis() end
	local length = math.sqrt(sx * sx + sz * sz)
	if length > 1 then sx, sz = sx / length, sz / length end
	-- From the screen to the world: up (-z) is the camera's forward.
	local fx, fz = Camera.forward(world)
	local ax, az = -fz * sx - fx * sz, fx * sx - fz * sz
	local accel = rules.acceleration * (p.grounded and 1 or rules.airControl) * dt
	p.vx = approach(p.vx, ax * rules.runSpeed, accel)
	p.vz = approach(p.vz, az * rules.runSpeed, accel)
	if ax ~= 0 or az ~= 0 then p.yaw = math.deg(math.atan(ax, az)) end
	-- Jumping.
	if input and input.takeJump and input:takeJump() then p.jumpPressedAt = world.time end
	local coyote = p.airborneAt and not p.jumpedAt and world.time - p.airborneAt <= rules.coyoteTime
	if p.jumpPressedAt and world.time - p.jumpPressedAt <= rules.jumpBuffer and (p.grounded or coyote) then
		p.vy, p.grounded, p.standing = rules.jumpSpeed, false, nil
		p.jumpedAt, p.jumpPressedAt = world.time, nil
	end
	p.vy = math.max(p.vy - rules.gravity * dt, -rules.terminalSpeed)
	-- Across, one axis at a time, so a wall stops one and the hero slides
	-- along it.
	local nx = p.x + p.vx * dt
	if Terrain.blocked(solids, nx, p.y, p.z, rules.radius, rules.height, rules.step) then p.vx = 0 else p.x = nx end
	local nz = p.z + p.vz * dt
	if Terrain.blocked(solids, p.x, p.y, nz, rules.radius, rules.height, rules.step) then p.vz = 0 else p.z = nz end
	-- Up and down.
	local ny = p.y + p.vy * dt
	if p.vy > 0 and Terrain.ceiling(solids, p.x, p.z, p.y + rules.height, ny + rules.height, rules.radius * 0.7) then
		p.vy, ny = 0, p.y
	end
	local ground, owner = Terrain.ground(solids, p.x, p.z, p.y + rules.step, rules.radius * 0.6)
	local snap = p.grounded and ground and p.y - ground <= rules.step
	if ground and p.vy <= 0 and (ny <= ground or snap) then
		if not p.grounded then p.landedAt = world.time end
		p.y, p.vy, p.grounded, p.standing, p.jumpedAt, p.airborneAt = ground, 0, true, owner, nil, nil
		for _, spring in ipairs(world.springs) do
			if spring.solid == owner then
				p.vy, p.grounded, p.standing = rules.springSpeed, false, nil
				p.jumpedAt, spring.firedAt = world.time, world.time
				world:emit("sprung", spring)
			end
		end
	else
		if p.grounded then p.airborneAt = world.time end
		p.y, p.grounded, p.standing = ny, false, nil
	end
end

return Hero
