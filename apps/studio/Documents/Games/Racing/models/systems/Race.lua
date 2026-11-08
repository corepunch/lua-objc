-- Laps, places and the finish. The track is split into four quarters; a
-- lap counts when the player's car crosses the line after passing through
-- every quarter in order, so a short cut across the grass does not count.
-- The place is the player's rank by distance raced; when the last lap is
-- done the race is `finished`, in the place the player crossed the line.
local Race = {}

-- How far a car has raced from the line, counting laps.
function Race.distance(world, car)
	if car ~= world.player then return car.s end
	local length, s = world.path.length, car.s or 0
	-- Still behind the line (reversing over it at the start).
	if car.checkpoint == 0 and s > length / 2 then s = s - length end
	return car.lap * length + s
end

function Race.update(world)
	if not world.started then return end
	local car, length, laps = world.player, world.path.length, world.level.laps
	local quarter = math.min(3, math.floor(car.s / length * 4))
	if quarter == car.checkpoint + 1 then
		car.checkpoint = quarter
	elseif quarter == 0 and car.checkpoint == 3 then
		car.checkpoint, car.lap = 0, car.lap + 1
		local time = world.clock - (car.lapStarted or 0)
		car.lapStarted = world.clock
		if not car.bestLap or time < car.bestLap then car.bestLap = time end
		if car.lap == laps then
			local ahead = 0
			for _, rival in ipairs(world.rivals) do
				if rival.s >= laps * length then ahead = ahead + 1 end
			end
			car.place = ahead + 1
			world:emit("finished", car)
			return
		end
		world:emit("lap", car)
	end
	local mine, place = Race.distance(world, car), 1
	for _, rival in ipairs(world.rivals) do
		if rival.s > mine then place = place + 1 end
	end
	if place ~= car.place then
		car.place = place
		world:emit("place", car)
	end
end

return Race
