-- Saws run back and forth between the two ends of their run at a steady
-- speed.
local Patrol = {}

function Patrol.update(world, dt)
	local rules = world.rules
	for _, saw in ipairs(world.saws) do
		local length = math.sqrt((saw.x2 - saw.fromX) ^ 2 + (saw.z2 - saw.fromZ) ^ 2)
		if length > 0 then
			saw.t = saw.t + saw.direction * rules.sawSpeed * dt / length
			if saw.t > 1 or saw.t < 0 then
				saw.direction = -saw.direction
				saw.t = math.max(0, math.min(1, saw.t))
			end
			saw.x = saw.fromX + (saw.x2 - saw.fromX) * saw.t
			saw.z = saw.fromZ + (saw.z2 - saw.fromZ) * saw.t
		end
	end
end

return Patrol
