-- Procedural animation for the hero and the flag. The asset pack is static
-- OBJ models, so life comes from poses: every value here is a pure function
-- of the world's clock and the timestamps the systems leave on the player
-- (`landedAt`, `hurtAt`, `clearedAt`). Nothing is stored between frames, so
-- the same world always poses the same way and tests can ask for any moment.
local Animation = {}

-- Seconds, degrees and unit fractions.
Animation.RULES = {
	stretch = 0.22, -- taller at the top of a hop
	squash = 0.3, -- how flat a landing starts
	squashTime = 0.18,
	breath = 0.03, -- idle breathing depth
	breathRate = 4, -- radians per second
	wobble = 28, -- degrees of shake when hurt
	wobbleTime = 0.55,
	wobbleRate = 42, -- radians per second
	spinRate = 540, -- victory spin, degrees per second
	wave = 14, -- how far the flag sways
	waveRate = 3, -- radians per second
}

local function age(now, since)
	return since and now - since or math.huge
end

-- Height factor: above 1 stretched, below 1 squashed. Width and depth take
-- the inverse square root, so the hero keeps its volume.
function Animation.height(world)
	local player, rules = world.player, Animation.RULES
	if player.hop then return 1 + rules.stretch * math.sin(math.pi * player.hop) end
	local since = age(world.time, player.landedAt)
	if since < rules.squashTime then return 1 - rules.squash * (1 - since / rules.squashTime) end
	return 1 + rules.breath * math.sin(world.time * rules.breathRate)
end

-- Turning on the spot: a shake decaying after a hit, a spin after the flag.
function Animation.yaw(world)
	local player, rules = world.player, Animation.RULES
	local yaw = player.yaw or 0
	local hurt = age(world.time, player.hurtAt)
	if hurt < rules.wobbleTime then
		yaw = yaw + rules.wobble * math.sin(hurt * rules.wobbleRate) * (1 - hurt / rules.wobbleTime)
	end
	if player.clearedAt then yaw = yaw + rules.spinRate * (world.time - player.clearedAt) end
	return yaw
end

function Animation.player(world)
	local height = Animation.height(world)
	local width = 1 / math.sqrt(height)
	return {scaleX = width, scaleY = height, scaleZ = width, yaw = Animation.yaw(world)}
end

function Animation.flag(world)
	return {yaw = Animation.RULES.wave * math.sin(world.time * Animation.RULES.waveRate)}
end

return Animation
