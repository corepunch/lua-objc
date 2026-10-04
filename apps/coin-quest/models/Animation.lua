-- Procedural animation for the hero and the flag. The asset pack is static
-- OBJ models, so life comes from poses: every value here is a pure function
-- of the world's clock, the hero's speed and the timestamps the systems leave
-- on the player (`landedAt`, `hurtAt`, `clearedAt`). Nothing is stored between frames, so
-- the same world always poses the same way and tests can ask for any moment.
local Animation = {}

-- Seconds, degrees and unit fractions.
Animation.RULES = {
	stretch = 0.22, -- taller while flying fast
	stretchSpeed = 12, -- at this vertical speed
	squash = 0.3, -- how flat a landing starts
	squashTime = 0.18,
	breath = 0.03, -- idle breathing depth
	breathRate = 4, -- radians per second
	wobble = 28, -- degrees of shake when hurt
	wobbleTime = 0.55,
	wobbleRate = 42, -- radians per second
	spinRate = 540, -- victory spin, degrees per second
	springSquash = 0.45, -- how far a spring compresses as it throws
	springTime = 0.3,
	wave = 14, -- how far the flag sways
	waveRate = 3, -- radians per second
}

local function age(now, since)
	return since and now - since or math.huge
end

-- Height factor: above 1 stretched, below 1 squashed. Width and depth take
-- the inverse square root, so the hero keeps its volume. In the air the
-- hero stretches with its speed; a landing starts squashed.
function Animation.height(world)
	local player, rules = world.player, Animation.RULES
	if not player.grounded then
		return 1 + rules.stretch * math.min(1, math.abs(player.vy or 0) / rules.stretchSpeed)
	end
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

-- A spring's height factor: pressed down as it throws, then springing back.
function Animation.spring(world, spring)
	local rules = Animation.RULES
	local since = age(world.time, spring.firedAt)
	if since >= rules.springTime then return 1 end
	return 1 - rules.springSquash * (1 - since / rules.springTime)
end

function Animation.flag(world)
	return {yaw = Animation.RULES.wave * math.sin(world.time * Animation.RULES.waveRate)}
end

return Animation
