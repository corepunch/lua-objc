-- The player hops one cell at a time. A hop starts only from standing, in
-- the direction the input asks for next, and only onto walkable ground; the
-- player turns to face the direction even when the way is blocked, and
-- tells the input, which may have been running that way (see `blocked`).
local Movement = {}

function Movement.update(world, dt, input)
	local player, rules = world.player, world.rules
	player.landed = false
	if player.hop then
		player.hop = player.hop + dt / rules.hopTime
		if player.hop < 1 then return end
		player.hop, player.fromX, player.fromZ, player.landed = nil, player.x, player.z, true
		player.landedAt = world.time
	end
	local direction = input and input:nextDirection()
	if not direction then return end
	player.yaw = math.deg(math.atan(direction.x, direction.z))
	local x, z = player.x + direction.x, player.z + direction.z
	if world.level:walkable(x, z) then
		player.fromX, player.fromZ, player.x, player.z, player.hop = player.x, player.z, x, z, 0
	elseif input.blocked then
		input:blocked(direction)
	end
end

return Movement
