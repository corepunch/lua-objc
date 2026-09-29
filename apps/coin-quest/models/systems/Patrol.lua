-- Saws run back and forth along their row or column at a steady speed and
-- turn around where the ground ends or something solid stands.
local Patrol = {}

function Patrol.update(world, dt)
	local rules = world.rules
	for _, saw in ipairs(world.saws) do
		local axis = saw.axis
		local next = saw[axis] + saw.direction * rules.sawSpeed * dt
		local ahead = math.floor(next + saw.direction * rules.sawReach + 0.5)
		local x, z = saw.x, saw.z
		if axis == "x" then x = ahead else z = ahead end
		if world.level:walkable(x, z) then
			saw[axis] = next
		else
			saw.direction = -saw.direction
		end
	end
end

return Patrol
