-- The camera follows the hero the way Mario 64's does: on a leash. It keeps
-- between `near` and `far` from the point it looks at, so running away
-- pulls it along behind and running sideways swings it round, while running
-- at it backs it away. The player can also turn it round the hero. The
-- stage turns `world.camera` and `world.focus` into the view's camera pose.
local Camera = {}

-- Starts the camera behind the hero, looking the way the level faces.
function Camera.place(world)
	local p, rules = world.player, world.rules
	world.focus = {x = p.x, y = p.y, z = p.z}
	local yaw = math.rad(world.level.facing or 0)
	world.camera = {x = p.x + math.sin(yaw) * rules.cameraFar, y = p.y + rules.cameraHeight,
		z = p.z + math.cos(yaw) * rules.cameraFar}
end

-- The camera's horizontal direction of view, as a unit vector.
function Camera.forward(world)
	local fx, fz = world.focus.x - world.camera.x, world.focus.z - world.camera.z
	local length = math.sqrt(fx * fx + fz * fz)
	if length < 1e-6 then return 0, -1 end
	return fx / length, fz / length
end

function Camera.update(world, dt, input)
	local p, rules, focus, camera = world.player, world.rules, world.focus, world.camera
	local k = 1 - math.exp(-rules.follow * dt)
	focus.x = focus.x + (p.x - focus.x) * k
	focus.y = focus.y + (p.y - focus.y) * k
	focus.z = focus.z + (p.z - focus.z) * k
	local cx, cz = camera.x - focus.x, camera.z - focus.z
	local turn = input and input.turn and input:turn() or 0
	if turn ~= 0 then
		local a = math.rad(turn * rules.cameraTurn * dt)
		cx, cz = cx * math.cos(a) - cz * math.sin(a), cx * math.sin(a) + cz * math.cos(a)
	end
	local distance = math.sqrt(cx * cx + cz * cz)
	if distance < 1e-6 then cx, cz, distance = 0, 1, 1 end
	local wanted = math.max(rules.cameraNear, math.min(rules.cameraFar, distance))
	camera.x, camera.z = focus.x + cx / distance * wanted, focus.z + cz / distance * wanted
	camera.y = camera.y + (focus.y + rules.cameraHeight - camera.y) * k
end

return Camera
