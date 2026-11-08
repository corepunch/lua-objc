-- The player's car: up (or A) drives, down (or B) brakes and then
-- reverses, left and right steer. The car is fastest on the road; the
-- grass holds it back. Wandering far from the road turns it back toward
-- the track. Nothing moves before the start.
local Track = require("demo.playground.models.Track")

local Driver = {}

local function approach(value, target, amount)
	if value < target then return math.min(target, value + amount) end
	return math.max(target, value - amount)
end

-- Steering and pedals from the input: steer -1 (left) to 1 (right), gas
-- and brake 0 to 1.
function Driver.controls(input)
	local steer, ahead = 0, 0
	if input and input.axis then steer, ahead = input:axis() end
	local gas, brake = math.max(0, -ahead), math.max(0, ahead)
	if input and input.held then
		if input:held("gas") then gas = 1 end
		if input:held("brake") then brake = 1 end
	end
	return steer, gas, brake
end

function Driver.update(world, dt, input)
	local car, rules = world.player, world.rules
	local index, distance = Track.nearest(world.path, car.x, car.z)
	car.s, car.offRoad = world.path.points[index].s, distance > rules.roadHalf
	if not world.started then return end

	local steer, gas, brake = Driver.controls(input)
	local top = car.offRoad and rules.grassSpeed or rules.topSpeed
	if gas > 0 then
		car.speed = approach(car.speed, top * gas, rules.acceleration * dt)
	elseif brake > 0 then
		local rate = car.speed > 0 and rules.braking or rules.acceleration / 2
		car.speed = approach(car.speed, -rules.reverseSpeed * brake, rate * dt)
	else
		car.speed = approach(car.speed, 0, rules.coasting * dt)
	end
	if car.speed > top then car.speed = approach(car.speed, top, rules.grassDrag * dt) end

	-- Steering turns the car in proportion to its speed up to `steerSpeed`,
	-- and the other way when reversing. A right turn lowers the heading.
	local grip = math.min(1, math.abs(car.speed) / rules.steerSpeed)
	local sign = car.speed < 0 and -1 or 1
	car.yaw = (car.yaw - steer * rules.steerRate * grip * sign * dt) % 360
	local yaw = math.rad(car.yaw)
	car.x = car.x + math.sin(yaw) * car.speed * dt
	car.z = car.z + math.cos(yaw) * car.speed * dt

	-- Too far out: back to the edge, slowed, so nobody gets lost.
	if distance > rules.edge then
		local p = world.path.points[index]
		local dx, dz = car.x - p.x, car.z - p.z
		local d = math.sqrt(dx * dx + dz * dz)
		car.x, car.z = p.x + dx / d * rules.edge, p.z + dz / d * rules.edge
		car.speed = car.speed * 0.5
	end
end

return Driver
