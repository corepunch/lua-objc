-- "3, 2, 1, Go!": the clock runs from minus the countdown, the cars wait
-- until it reaches 0, and "Go!" shows for a second after. Each change of
-- what the countdown shows is a `countdown` event, so the HUD renders
-- four times, not every frame.
local Countdown = {}

-- What the countdown shows at `clock` seconds: "3", "2", "1", "Go!" or nil.
function Countdown.shown(clock)
	if clock < 0 then return tostring(math.ceil(-clock)) end
	if clock < 1 then return "Go!" end
	return nil
end

function Countdown.update(world, dt)
	local before = Countdown.shown(world.clock)
	world.clock = world.clock + dt
	world.started = world.clock >= 0
	if Countdown.shown(world.clock) ~= before then world:emit("countdown", world) end
end

return Countdown
