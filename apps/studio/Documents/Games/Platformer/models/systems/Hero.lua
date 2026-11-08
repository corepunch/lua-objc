-- The hero runs where the stick or keys point, as seen from the camera,
-- jumps with a little forgiveness (a jump still counts just after running
-- off an edge, and a press just before landing), stands on the highest
-- solid surface under them and is stopped by anything too tall to step
-- onto. Falling below the level costs a life. The hero's animation clip
-- (idle, walk, jump) follows what they are doing.
local Ground = require("demo.playground.models.Ground")
local Leash = require("game.cameras.Leash")

local Hero = {}

local function approach(value, target, amount)
	if value < target then return math.min(target, value + amount) end
	return math.max(target, value - amount)
end

function Hero.update(world, dt, input)
	local p, rules, solids = world.player, world.rules, world.level.solids
	-- Input is camera-relative: up runs away from the camera.
	local sx, sz = 0, 0
	if input and input.axis then sx, sz = input:axis() end
	local fx, fz = Leash.forward(world)
	local wx, wz = -fz * sx + fx * -sz, fx * sx + fz * -sz
	local length = math.sqrt(wx * wx + wz * wz)
	if length > 1 then wx, wz = wx / length, wz / length end
	local control = (p.grounded and 1 or rules.airControl) * rules.acceleration * dt
	p.vx = approach(p.vx, wx * rules.runSpeed, control)
	p.vz = approach(p.vz, wz * rules.runSpeed, control)
	if wx ~= 0 or wz ~= 0 then p.yaw = math.deg(math.atan(wx, wz)) end

	-- Move one axis at a time, so a wall stops only the way into it.
	local feet, head = p.y, p.y + rules.height
	local nx = p.x + p.vx * dt
	if Ground.blocked(solids, nx, p.z, feet, head, rules.radius, rules.step) then p.vx = 0 else p.x = nx end
	local nz = p.z + p.vz * dt
	if Ground.blocked(solids, p.x, nz, feet, head, rules.radius, rules.step) then p.vz = 0 else p.z = nz end

	-- Jumping.
	if input and input.take and input:take("jump") then p.jumpPressedAt = world.time end
	local canJump = p.grounded or (p.airborneAt and world.time - p.airborneAt <= rules.coyoteTime)
	if canJump and p.jumpPressedAt and world.time - p.jumpPressedAt <= rules.jumpBuffer then
		p.vy, p.grounded, p.airborneAt, p.jumpPressedAt = rules.jumpSpeed, false, nil, nil
	end

	-- Falling and landing.
	p.vy = math.max(-rules.terminalSpeed, p.vy - rules.gravity * dt)
	local y = p.y + p.vy * dt
	local ground = Ground.height(solids, p.x, p.z, p.y + rules.step)
	if ground and y <= ground and p.vy <= 0 then
		p.y, p.vy = ground, 0
		if not p.grounded then p.grounded, p.landedAt = true, world.time end
	else
		p.y = y
		if p.grounded then p.grounded, p.airborneAt = false, world.time end
	end
	if p.y < world.level.fall then world:emit("hurt", p) return end

	local animation = not p.grounded and "jump" or ((p.vx * p.vx + p.vz * p.vz) > 0.5 and "walk" or "idle")
	if animation ~= p.animation then
		p.animation = animation
		world:emit("animation", p)
	end
end

return Hero
