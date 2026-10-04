-- A saw touching the hero, raised spikes under a hero standing on them, or
-- the water hurt; after a hit the hero recovers for a moment before a saw or
-- spikes can hurt them again. Hopping over spikes is safe: only a standing
-- hero is hit. The water always counts: the session sends the hero back.
local Hazards = {}

function Hazards.update(world, dt)
	local p, rules = world.player, world.rules
	if p.y < rules.water then
		world:emit("hurt", p)
		return
	end
	if (p.recovering or 0) > 0 then
		p.recovering = math.max(0, p.recovering - dt)
		return
	end
	local hit = false
	for _, saw in ipairs(world.saws) do
		if (saw.x - p.x) ^ 2 + (saw.z - p.z) ^ 2 < rules.sawRadius ^ 2 and p.y < saw.y + 0.8 and p.y + rules.height > saw.y then
			hit = true
		end
	end
	if p.grounded then
		for _, spike in ipairs(world.spikes) do
			if spike.raised and math.abs(spike.x - p.x) < rules.spikeSize and math.abs(spike.z - p.z) < rules.spikeSize
				and math.abs(spike.y - p.y) < 0.2 then
				hit = true
			end
		end
	end
	if hit then
		p.recovering, p.hurtAt = rules.recovery, world.time
		world:emit("hurt", p)
	end
end

return Hazards
