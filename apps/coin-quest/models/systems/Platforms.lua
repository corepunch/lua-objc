-- Ferries and lifts run back and forth between their two ends, waiting a
-- moment at each, and carry a hero standing on them. Wooden planks over the
-- water hold for a moment once stood on, then fall, and float back later.
local Level = require("apps.coin-quest.models.Level")
local Terrain = require("apps.coin-quest.models.Terrain")

local Platforms = {}

-- Where along its run (0 to 1) a ferry is at a moment: wait, cross, wait,
-- come back. Smoothstep, so it starts and stops gently.
function Platforms.progress(mover, time, rules)
	local length = math.sqrt((mover.x2 - mover.fromX) ^ 2 + (mover.y2 - mover.fromY) ^ 2 + (mover.z2 - mover.fromZ) ^ 2)
	local travel = math.max(length / rules.ferrySpeed, 1e-6)
	local pause = rules.pause
	local phase = time % (2 * (travel + pause))
	local t
	if phase < pause then t = 0
	elseif phase < pause + travel then t = (phase - pause) / travel
	elseif phase < 2 * pause + travel then t = 1
	else t = 1 - (phase - 2 * pause - travel) / travel end
	return t * t * (3 - 2 * t)
end

function Platforms.update(world, dt)
	local player, rules = world.player, world.rules
	for _, mover in ipairs(world.movers) do
		local t = Platforms.progress(mover, world.time, rules)
		local x = mover.fromX + (mover.x2 - mover.fromX) * t
		local y = mover.fromY + (mover.y2 - mover.fromY) * t
		local z = mover.fromZ + (mover.z2 - mover.fromZ) * t
		if player.standing == mover.solid then
			player.x, player.y, player.z = player.x + x - mover.x, y, player.z + z - mover.z
		end
		mover.x, mover.y, mover.z = x, y, z
		local moved = Terrain.solid(x, y - Level.SIZES.mover.h, z, Level.SIZES.mover)
		for k, v in pairs(moved) do mover.solid[k] = v end
	end
	for _, plank in ipairs(world.planks) do
		if plank.gone then
			if world.time - plank.goneAt > rules.plankReturn then
				plank.gone, plank.steppedAt, plank.vy, plank.y = nil, nil, nil, plank.restY
			end
		else
			if player.standing == plank.solid and not plank.steppedAt then plank.steppedAt = world.time end
			if plank.steppedAt and world.time - plank.steppedAt > rules.plankHold then
				if not plank.vy then
					plank.vy = 0
					world:emit("crumbled", plank)
				end
				plank.vy = plank.vy - rules.gravity * dt
				plank.y = plank.y + plank.vy * dt
				if player.standing == plank.solid then player.y = plank.y end
				if plank.y < rules.water - 1 then plank.gone, plank.goneAt = true, world.time end
			end
		end
		local moved = Terrain.solid(plank.x, plank.y - Level.SIZES.plank.h, plank.z, Level.SIZES.plank)
		for k, v in pairs(moved) do plank.solid[k] = v end
	end
end

return Platforms
