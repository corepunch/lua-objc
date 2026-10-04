-- Touching a coin takes it; taking the last coin raises the flag, and
-- touching the raised flag clears the level. Stars are a bonus the flag
-- does not wait for. A key opens the gates, a heart gives back a life, and a
-- checkpoint becomes where the hero comes back after a hit.
local Pickups = {}

-- How far above its base an item's middle is, and how far the hero's is.
local CENTRE = {item = 0.3, hero = 0.4, height = 0.8}

local function touching(world, item)
	local p, rules = world.player, world.rules
	return (item.x - p.x) ^ 2 + (item.z - p.z) ^ 2 < rules.reach ^ 2
		and math.abs(item.y + CENTRE.item - (p.y + CENTRE.hero)) < CENTRE.height
end

local function take(world, list, event)
	for _, item in ipairs(list) do
		if not item.taken and touching(world, item) then
			item.taken = true
			world:emit(event, item)
		end
	end
end

function Pickups.update(world)
	local before = world:coinsLeft()
	take(world, world.coins, "coin")
	if before > 0 and world:coinsLeft() == 0 then
		world.flag.raised = true
		world:emit("flagRaised", world.flag)
	end
	take(world, world.stars, "star")
	take(world, world.hearts, "heart")
	for _, key in ipairs(world.keys) do
		if not key.taken and touching(world, key) then
			key.taken, world.hasKey = true, true
			world:emit("key", key)
		end
	end
	for _, checkpoint in ipairs(world.checkpoints) do
		if not checkpoint.active and touching(world, checkpoint) then
			for _, other in ipairs(world.checkpoints) do other.active = false end
			checkpoint.active, world.checkpoint = true, checkpoint
			world:emit("checkpoint", checkpoint)
		end
	end
	if world.flag.raised and not world.player.clearedAt and touching(world, world.flag) then
		world.player.clearedAt = world.time
		world:emit("cleared", world.flag)
	end
end

return Pickups
