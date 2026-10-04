-- The player hops one cell at a time, and leaps two when the neighbour is
-- water but the cell beyond is ground. A hop starts only from standing, in
-- the direction the input asks for next (or the launch a pad left), and
-- only onto standable ground; the player turns to face the direction even
-- when the way is blocked, and tells the input, which may have been running
-- that way (see `blocked`).
local Movement = {}

local function start(player, x, z, span)
	player.fromX, player.fromZ, player.x, player.z = player.x, player.z, x, z
	player.hop, player.span = 0, span
	player.dx, player.dz = x - player.fromX, z - player.fromZ
	if player.span ~= 0 then
		player.dx, player.dz = player.dx / math.abs(player.span), player.dz / math.abs(player.span)
	end
end

function Movement.update(world, dt, input)
	local player, rules = world.player, world.rules
	player.landed = false
	if player.hop then
		player.hop = player.hop + dt / (rules.hopTime * (player.span > 1 and 1.35 or 1))
		if player.hop < 1 then return end
		player.hop, player.landed = nil, true
		player.landedAt = world.time
		player.riding = nil
	end
	local direction, span = input and input:nextDirection(), 1
	if player.boost then
		direction, span = {x = player.boostX, z = player.boostZ}, player.boost
		player.boost = nil
	end
	if not direction then return end
	player.yaw = math.deg(math.atan(direction.x, direction.z))
	local function landing(distance)
		local x, z = player.x + direction.x * distance, player.z + direction.z * distance
		for step = 1, distance - 1 do
			local mx, mz = player.x + direction.x * step, player.z + direction.z * step
			if world.level.solid[mx .. ":" .. mz] and not world:gateOpen(mx, mz) then return nil end
		end
		if world:standable(x, z) then return x, z end
	end
	local x, z = landing(span)
	if not x and span == 1 then x, z, span = landing(2) end
	if x then
		start(player, x, z, span == 1 and math.abs(x - player.x + z - player.z) or span)
	elseif input.blocked then
		input:blocked(direction)
	end
end

return Movement
