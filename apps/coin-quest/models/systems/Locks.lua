-- A locked crate is solid until the hero has taken the key. Opening it is
-- one event, so the stage redraws without the crate.
local Locks = {}

function Locks.update(world)
	if world.unlocked or not world.hasKey then return end
	world.unlocked = true
	for _, gate in ipairs(world.gates) do
		gate.open = true
		world.level.solid[gate.x .. ":" .. gate.z] = nil
	end
	world:emit("unlocked")
end

return Locks
