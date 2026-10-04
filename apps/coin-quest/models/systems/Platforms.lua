-- Crate ferries run back and forth along their track, including over water,
-- and carry a hero who is standing on them.
local Platforms = {}

function Platforms.update(world, dt)
	local player = world.player
	for _, platform in ipairs(world.platforms) do
		local axis = platform.axis
		local next = platform[axis] + platform.direction * world.rules.ferrySpeed * dt
		if next < platform.min or next > platform.max then
			platform.direction = -platform.direction
			next = math.max(platform.min, math.min(platform.max, next))
		end
		platform[axis] = next
		local cell = math.floor(next + 0.5)
		if axis == "x" then platform.cx = cell else platform.cz = cell end
	end
	if player.hop then return end
	player.riding = nil
	for _, platform in ipairs(world.platforms) do
		if platform.cx == player.x and platform.cz == player.z then
			player.riding = platform.id
			player.x, player.z = platform.cx, platform.cz
		end
	end
end

return Platforms
