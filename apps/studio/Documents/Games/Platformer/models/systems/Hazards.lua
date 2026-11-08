-- Spikes hurt. After a hit (or a fall) the hero is safe for a moment, and
-- blinks while they are.
local Hazards = {}

local SPIKES = {radius = 0.45, height = 0.3}

function Hazards.update(world)
	local p = world.player
	if world.time < (p.safeUntil or 0) then return end
	for _, spikes in ipairs(world.spikes) do
		local dx, dz = p.x - spikes.x, p.z - spikes.z
		if dx * dx + dz * dz <= SPIKES.radius * SPIKES.radius and p.y - spikes.y <= SPIKES.height then
			world:emit("hurt", spikes)
			return
		end
	end
end

return Hazards
