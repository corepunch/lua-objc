-- A grass bridge holds while the hero stands on it and falls once they
-- leave, or if they stay too long. Falling out from under the hero hurts.
local Crumble = {}

function Crumble.update(world)
	local player, rules = world.player, world.rules
	local id = player.x .. ":" .. player.z
	if player.landed and world.level.crumbles[id] and not world.gone[id] then
		player.bridge = id
		player.bridgeAt = world.time
	end
	local function fall(cell)
		if world.gone[cell] or not world.level.crumbles[cell] then return end
		world.gone[cell] = true
		world.level.gone[cell] = true
		world:emit("crumbled")
		if not player.hop and (player.x .. ":" .. player.z) == cell then world:emit("hurt", player) end
	end
	if player.bridge and (player.hop or (player.x .. ":" .. player.z) ~= player.bridge) then
		fall(player.bridge)
		player.bridge = nil
	elseif player.bridge and world.time - player.bridgeAt > rules.bridgeHold then
		fall(player.bridge)
		player.bridge = nil
	end
end

return Crumble
