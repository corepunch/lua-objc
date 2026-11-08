-- A spring under the hero's feet throws them high: landing on one sets the
-- vertical speed to the spring's.
local Springs = {}

-- How close to a spring's centre the hero's feet must land.
local SPRING = {radius = 0.4, height = 0.2}

function Springs.update(world)
	local p = world.player
	if not p.grounded then return end
	for _, spring in ipairs(world.springs) do
		local dx, dz = p.x - spring.x, p.z - spring.z
		if dx * dx + dz * dz <= SPRING.radius * SPRING.radius and math.abs(p.y - spring.y) <= SPRING.height then
			p.vy, p.grounded, p.airborneAt = world.rules.springSpeed, false, nil
			world:emit("sprung", spring)
			return
		end
	end
end

return Springs
