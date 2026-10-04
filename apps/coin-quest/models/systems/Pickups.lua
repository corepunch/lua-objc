-- Landing on a coin takes it; a leap also takes coins it passed, including
-- coins hung over water. Taking the last coin raises the flag, and landing
-- on the raised flag clears the level. The key is a coin that opens gates.
local Pickups = {}

local function take(world, coin)
	if coin.taken then return end
	coin.taken = true
	world:emit("coin", coin)
	if world:coinsLeft() == 0 then
		world.flag.raised = true
		world:emit("flagRaised", world.flag)
	end
end

function Pickups.update(world)
	local player = world.player
	if not player.landed then return end
	local function visit(x, z)
		local coin = world:coinAt(x, z)
		if coin then take(world, coin) end
		local key = world:keyAt(x, z)
		if key and not key.taken then
			key.taken = true
			world.hasKey = true
			world:emit("key", key)
		end
	end
	local span = math.max(math.abs(player.x - player.fromX), math.abs(player.z - player.fromZ))
	local dx = span == 0 and 0 or (player.x - player.fromX) / span
	local dz = span == 0 and 0 or (player.z - player.fromZ) / span
	for step = 0, span do visit(player.fromX + dx * step, player.fromZ + dz * step) end
	if world.flag.raised and player.x == world.flag.x and player.z == world.flag.z then
		player.clearedAt = world.time
		world:emit("cleared", world.flag)
	end
end

return Pickups
