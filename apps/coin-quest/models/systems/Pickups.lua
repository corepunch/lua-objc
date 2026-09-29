-- Landing on a coin takes it; taking the last coin raises the flag, and
-- landing on the raised flag clears the level.
local Pickups = {}

function Pickups.update(world)
	local player = world.player
	if not player.landed then return end
	local coin = world:coinAt(player.x, player.z)
	if coin then
		coin.taken = true
		world:emit("coin", coin)
		if world:coinsLeft() == 0 then
			world.flag.raised = true
			world:emit("flagRaised", world.flag)
		end
	end
	if world.flag.raised and player.x == world.flag.x and player.z == world.flag.z then
		world:emit("cleared", world.flag)
	end
end

return Pickups
