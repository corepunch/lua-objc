-- A mushroom pad launches the hero the way they arrived, on the frame after
-- they land. A big pad throws one cell further. The launch is a hop the
-- movement system takes instead of reading input.
local Springs = {}

function Springs.update(world)
	local player = world.player
	if not player.landed or not player.dx then return end
	local span = world.level:springAt(player.x, player.z)
	if not span then return end
	player.boost, player.boostX, player.boostZ = span, player.dx, player.dz
end

return Springs
