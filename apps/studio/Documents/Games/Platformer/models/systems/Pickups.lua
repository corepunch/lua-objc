-- Coins are taken by touching them. When the last coin is gone the flag
-- rises; touching the raised flag clears the level.
local Pickups = {}

local function touching(world, thing)
	local p, reach = world.player, world.rules.reach
	local dx, dz = p.x - thing.x, p.z - thing.z
	return dx * dx + dz * dz <= reach * reach and thing.y - p.y <= world.rules.height + 0.2 and p.y - thing.y <= 0.8
end

function Pickups.update(world)
	local left = 0
	for _, coin in ipairs(world.coins) do
		if not coin.taken then
			if touching(world, coin) then
				coin.taken = true
				world:emit("coin", coin)
			else
				left = left + 1
			end
		end
	end
	local flag = world.flag
	if left == 0 and not flag.raised then
		flag.raised = true
		world:emit("flagRaised", flag)
	end
	if flag.raised and not world.cleared and touching(world, flag) then
		world.cleared = true
		world:emit("cleared", flag)
	end
end

return Pickups
