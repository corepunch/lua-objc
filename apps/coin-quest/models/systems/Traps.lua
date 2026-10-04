-- Spike traps rise and sink on a shared cycle, each a little later than the
-- one to its left, so a row of them ripples. `lift` eases between 0 (sunk)
-- and 1 (up) for the stage; only `raised` hurts.
local Traps = {}

Traps.STAGGER = 0.3 -- seconds per unit along x

function Traps.update(world, dt)
	local rules = world.rules
	for _, spike in ipairs(world.spikes) do
		local phase = (world.time + (spike.x + spike.z) * Traps.STAGGER) % rules.spikeCycle
		spike.raised = phase < rules.spikeRaised
		local target = spike.raised and 1 or 0
		local step = rules.spikeSpeed * dt
		spike.lift = spike.lift < target and math.min(target, spike.lift + step) or math.max(target, spike.lift - step)
	end
end

return Traps
