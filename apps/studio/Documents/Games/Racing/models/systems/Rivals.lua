-- The rival cars drive the road's middle line in their lane, each at its
-- `pace` (a share of the player's top speed). They slow for corners as
-- the player's car must: no faster than its steering can turn on that
-- corner. A rival never drives into a car just ahead of it (another
-- rival or the player): it holds back to that car's speed, and moves
-- across to the other lane to pass when that lane is clear. They keep
-- driving after the finish.
local Track = require("demo.playground.models.Track")

local Rivals = {}

-- How far ahead a rival looks for a corner to slow for, in units.
local LOOKAHEAD = 6

local function approach(value, target, amount)
	if value < target then return math.min(target, value + amount) end
	return math.max(target, value - amount)
end

-- How far ahead along the road a rival watches for a car in its way, and
-- the gap it keeps behind one (a car is about 1.9 long).
local FOLLOW = {watch = 12, gap = 3, laneChange = 1.5}

-- The fastest `car` may go and still stop short of a car `gap` ahead of
-- it along the road going at `speed`; closer than the gap it drops back.
-- (The gap is along the road's middle: on the inside of a tight corner
-- the cars are nearer than that.)
local function behind(rules, gap, speed)
	speed = math.max(0, speed)
	if gap < FOLLOW.gap then return speed * gap / FOLLOW.gap end
	return speed + math.sqrt(2 * rules.braking * (gap - FOLLOW.gap))
end

-- Whether no other rival is near `s` in a lane overlapping `lane`.
local function clear(world, car, lane)
	for _, other in ipairs(world.rivals) do
		if other ~= car and math.abs(other.s - car.s) < FOLLOW.gap * 1.5
			and math.abs(other.lane - lane) < world.rules.carRadius * 2 then
			return false
		end
	end
	return true
end

-- Caps `target` for the cars in `car`'s way: rivals ahead in an
-- overlapping lane, and the player's car just ahead of it.
local function blocked(world, car, target)
	local rules = world.rules
	local width = rules.carRadius * 2
	for _, other in ipairs(world.rivals) do
		local gap = other.s - car.s
		if other ~= car and gap > 0 and gap < FOLLOW.watch and math.abs(other.lane - car.lane) < width then
			local limit = behind(rules, gap, other.speed)
			-- Held up: pull out into the other lane if nobody is there.
			if limit < target and car.goal == car.lane and clear(world, car, -car.lane) then car.goal = -car.lane end
			target = math.min(target, limit)
		end
	end
	local p = world.player
	local dx, dz = p.x - car.x, p.z - car.z
	local yaw = math.rad(car.yaw)
	local ahead = dx * math.sin(yaw) + dz * math.cos(yaw)
	local aside = math.abs(dx * math.cos(yaw) - dz * math.sin(yaw))
	if ahead > 0 and ahead < FOLLOW.watch and aside < width then
		target = math.min(target, behind(rules, ahead, p.speed))
	end
	return target
end

-- The fastest a car can take a bend of radius `radius`.
function Rivals.cornerSpeed(rules, radius)
	return math.rad(rules.steerRate) * radius
end

function Rivals.update(world, dt)
	if not world.started then return end
	local rules, path = world.rules, world.path
	for _, car in ipairs(world.rivals) do
		local target = rules.topSpeed * car.pace
		for _, ahead in ipairs({0, LOOKAHEAD / 2, LOOKAHEAD}) do
			local _, _, _, index = Track.at(path, car.s + ahead, 0, car.hint)
			target = math.min(target, Rivals.cornerSpeed(rules, path.points[index].radius) * car.pace)
		end
		target = blocked(world, car, target)
		local rate = target < car.speed and rules.braking or rules.acceleration
		car.speed = approach(car.speed, target, rate * dt)
		car.goal = car.goal or car.lane
		car.lane = approach(car.lane, car.goal, FOLLOW.laneChange * dt)
		car.s = car.s + car.speed * dt
		car.x, car.z, car.yaw, car.hint = Track.at(path, car.s, car.lane, car.hint)
	end
end

return Rivals
