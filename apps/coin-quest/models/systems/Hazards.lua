-- A saw touching the player, or raised spikes under a standing player, hurt
-- it once; the player then recovers for a moment before anything can hurt
-- it again. Hopping over spikes is safe: only a standing player is hit.
local Hazards = {}

function Hazards.update(world, dt)
	local player, rules = world.player, world.rules
	if (player.recovering or 0) > 0 then
		player.recovering = math.max(0, player.recovering - dt)
		return
	end
	local x, _, z = world:playerPosition()
	local hit = false
	for _, saw in ipairs(world.saws) do
		if (saw.x - x) ^ 2 + (saw.z - z) ^ 2 < rules.hitRadius ^ 2 then hit = true end
	end
	if not player.hop then
		for _, spike in ipairs(world.spikes) do
			if spike.raised and spike.x == player.x and spike.z == player.z then hit = true end
		end
	end
	if hit then
		player.recovering = rules.recovery
		world:emit("hurt", player)
	end
end

return Hazards
