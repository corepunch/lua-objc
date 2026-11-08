-- Cars do not drive through each other: when the player's car touches a
-- rival, it is pushed back out and loses some speed. Rivals hold their
-- line.
local Bumps = {}

function Bumps.update(world)
	local car, rules = world.player, world.rules
	local reach = rules.carRadius * 2
	for _, rival in ipairs(world.rivals) do
		local dx, dz = car.x - rival.x, car.z - rival.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < reach and d > 1e-6 then
			car.x, car.z = rival.x + dx / d * reach, rival.z + dz / d * reach
			car.speed = car.speed * rules.bump
		end
	end
end

return Bumps
