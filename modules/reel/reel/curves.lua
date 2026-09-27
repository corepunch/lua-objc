-- Pure functions of time: progress, easing, springs and beat-driven pulses.
-- Every frame of a reel is computed from `t` alone, so a still at any time,
-- a sub-frame for motion blur and a scrubbed preview all agree exactly.
local Curves = {}

local exp, sin, cos, pow, sqrt, pi = math.exp, math.sin, math.cos, math.pow or function(a, b) return a ^ b end, math.sqrt, math.pi

function Curves.clamp01(x)
	if x < 0 then return 0 end
	if x > 1 then return 1 end
	return x
end
local clamp01 = Curves.clamp01

-- 0 before `a`, 1 after `b`, linear between.
function Curves.progress(t, a, b)
	return clamp01((t - a) / (b - a))
end

function Curves.mix(a, b, p)
	return a + (b - a) * p
end

-- Interpolates scales in log space, so zooming feels even at every size.
function Curves.mixScale(a, b, p)
	return exp(math.log(a) + (math.log(b) - math.log(a)) * p)
end

-- Robert Penner's curves, named as in CSS and After Effects.
Curves.easing = {
	linear = function(x) return x end,
	inCubic = function(x) return x * x * x end,
	inQuart = function(x) return x * x * x * x end,
	outCubic = function(x) return 1 - (1 - x) ^ 3 end,
	outQuart = function(x) return 1 - (1 - x) ^ 4 end,
	outQuint = function(x) return 1 - (1 - x) ^ 5 end,
	outExpo = function(x) return x >= 1 and 1 or 1 - pow(2, -10 * x) end,
	inOutCubic = function(x) return x < 0.5 and 4 * x * x * x or 1 - (-2 * x + 2) ^ 3 / 2 end,
	inOutQuint = function(x) return x < 0.5 and 16 * x ^ 5 or 1 - (-2 * x + 2) ^ 5 / 2 end,
	inOutExpo = function(x)
		if x <= 0 then return 0 end
		if x >= 1 then return 1 end
		return x < 0.5 and pow(2, 20 * x - 10) / 2 or (2 - pow(2, -20 * x + 10)) / 2
	end,
}

-- Eased progress from `a` to `b`: ease(t, a, b, "outQuart").
function Curves.ease(t, a, b, name)
	local curve = Curves.easing[name or "linear"]
	if not curve then error("unknown easing " .. tostring(name), 2) end
	return curve(clamp01((t - a) / (b - a)))
end

-- A damped spring from 0 to 1, `dt` seconds after release, with SwiftUI's
-- parameters: `response` is the undamped period in seconds and `damping`
-- the damping fraction (below 1 overshoots). Matches
-- `Animation.spring(response:dampingFraction:)`.
Curves.defaultSpring = { response = 0.45, damping = 0.45 }
function Curves.spring(dt, response, damping)
	if dt <= 0 then return 0 end
	response = response or Curves.defaultSpring.response
	damping = damping or Curves.defaultSpring.damping
	local w = 2 * pi / response
	if damping >= 1 then
		return 1 - exp(-w * dt) * (1 + w * dt)
	end
	local wd = w * sqrt(1 - damping * damping)
	return 1 - exp(-damping * w * dt) * (cos(wd * dt) + damping * w / wd * sin(wd * dt))
end

-- A decaying bump after the most recent of `hits` (seconds): 1 on the hit,
-- falling by e every `decay` seconds.
function Curves.pulse(t, hits, decay)
	decay = decay or 0.12
	local best = 0
	for _, hit in ipairs(hits) do
		if t >= hit then
			local value = exp(-(t - hit) / decay)
			if value > best then best = value end
		end
	end
	return best
end

-- A camera shake after each of `hits`, as an offset in pixels.
function Curves.shake(t, hits, amount)
	local dx, dy = 0, 0
	for _, hit in ipairs(hits) do
		local dt = t - hit
		if dt >= 0 and dt < 0.4 then
			local e = exp(-dt / 0.08) * amount
			dx = dx + sin(dt * 97) * e
			dy = dy + cos(dt * 83) * e
		end
	end
	return dx, dy
end

-- A beat grid: grid.beat and grid.bar in seconds, grid(n) the time of beat n.
function Curves.grid(bpm)
	local beat = 60 / bpm
	return setmetatable({ bpm = bpm, beat = beat, bar = beat * 4 }, {
		__call = function(_, n) return n * beat end,
	})
end

-- Times from `from` (inclusive) to `to` (exclusive) every `step` seconds.
function Curves.every(step, from, to)
	local times = {}
	local n = 0
	while from + n * step < to - 1e-9 do
		table.insert(times, from + n * step)
		n = n + 1
	end
	return times
end

return Curves
