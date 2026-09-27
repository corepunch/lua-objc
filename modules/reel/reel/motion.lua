-- The motion vocabulary used in `motion="…"` attributes.
--
-- A modifier changes a node's transform as a function of time: it offsets
-- (dx, dy, in the parent's units), scales, turns or fades the node around its
-- anchor. Modifiers compose in the order written. Each one also lists the
-- sound events it implies (a pop, a slam, a whoosh), so a score can be
-- generated from the same timeline the picture uses.
local Curves = require("reel.curves")

local spring, progress, mix, clamp01, ease = Curves.spring, Curves.progress, Curves.mix, Curves.clamp01, Curves.ease
local exp, sin, pi = math.exp, math.sin, math.pi

local Motion = {}

local function modifier(apply, events)
	return { apply = apply, events = events or {} }
end

-- The sound a modifier implies: `default` unless options.sound names another
-- or is false (a second copy of a node that should not sound twice).
local function sound(time, options, default)
	local kind = options.sound
	if kind == false or (kind == nil and default == nil) then return {} end
	return { { time = time, kind = kind or default } }
end

-- pop(at, {response, damping, from, turn, fade}): grows from `from` (0) to
-- full size on a spring, turning `turn` radians into place and fading in
-- over `fade` seconds. Hidden before `at`.
function Motion.pop(at, options)
	options = options or {}
	local response, damping = options.response or 0.43, options.damping or 0.5
	local from, turn, fade = options.from or 0, options.turn or 0, options.fade or 0.06
	return modifier(function(state, t)
		if t < at then state.alpha = 0; return end
		local k = spring(t - at, response, damping)
		state.scale = state.scale * mix(from, 1, k)
		state.rotation = state.rotation + turn * (1 - k)
		state.alpha = state.alpha * clamp01((t - at) / fade)
	end, sound(at, options, "pop"))
end

-- slam(at, {from, response, damping, drop, fade}): lands from `from` (1.75)
-- times its size onto its place, dropping `drop` points as it settles.
function Motion.slam(at, options)
	options = options or {}
	local response, damping = options.response or 0.43, options.damping or 0.5
	local from, drop, fade = options.from or 1.75, options.drop or 0, options.fade or 0.07
	return modifier(function(state, t)
		if t < at then state.alpha = 0; return end
		local k = spring(t - at, response, damping)
		state.scale = state.scale * mix(from, 1, k)
		state.dy = state.dy - drop * (1 - k)
		state.alpha = state.alpha * clamp01((t - at) / fade)
	end, sound(at, options, "slam"))
end

-- enter{at, x, y, response, damping, fade, sound}: springs in from an
-- offset, fading in over `fade` seconds when given.
function Motion.enter(options)
	local at = options.at
	local response, damping = options.response or 0.53, options.damping or 0.68
	local x, y, fade = options.x or 0, options.y or 0, options.fade
	return modifier(function(state, t)
		if t < at then state.alpha = 0; return end
		local k = spring(t - at, response, damping)
		state.dx = state.dx + x * (1 - k)
		state.dy = state.dy + y * (1 - k)
		if fade then state.alpha = state.alpha * clamp01((t - at) / fade) end
	end, sound(at, options))
end

-- leave{at, duration, x, y, scale, curve, fade, stay, sound}: travels by an
-- offset (and to a scale) and is gone afterwards unless `stay`.
function Motion.leave(options)
	local at, duration = options.at, options.duration or 0.3
	local x, y, curve = options.x or 0, options.y or 0, options.curve or "inQuart"
	local toScale, fadeOut = options.scale, options.fade
	return modifier(function(state, t)
		local p = ease(t, at, at + duration, curve)
		if p >= 1 and not options.stay then state.alpha = 0; return end
		state.dx = state.dx + x * p
		state.dy = state.dy + y * p
		if toScale then state.scale = state.scale * mix(1, toScale, p) end
		if fadeOut then state.alpha = state.alpha * (1 - p) end
	end, sound(at, options))
end

-- fadeIn(at, duration) / fadeOut(at, duration)
function Motion.fadeIn(at, duration)
	duration = duration or 0.12
	return modifier(function(state, t) state.alpha = state.alpha * progress(t, at, at + duration) end)
end

function Motion.fadeOut(at, duration)
	duration = duration or 0.12
	return modifier(function(state, t) state.alpha = state.alpha * (1 - progress(t, at, at + duration)) end)
end

-- punch(at, {amount, frequency, decay}): a quick wobble in scale on a hit,
-- as if the beat knocked it.
function Motion.punch(at, options)
	options = options or {}
	local amount, frequency, decay = options.amount or 0.028, options.frequency or 3.2, options.decay or 0.16
	return modifier(function(state, t)
		if t < at then return end
		state.scale = state.scale * (1 + amount * sin((t - at) * 2 * pi * frequency) * exp(-(t - at) / decay))
	end)
end

-- spinOut(at, duration, turns): shrinks away while turning, then is gone.
function Motion.spinOut(at, duration, turns)
	duration, turns = duration or 0.33, turns or 1.6
	return modifier(function(state, t)
		local gone = ease(t, at, at + duration, "inQuart")
		if gone >= 1 then state.alpha = 0; return end
		state.scale = state.scale * (1 - gone)
		state.rotation = state.rotation + gone * turns
	end)
end

-- beat(hits, {amount, decay}): swells on each hit, like a speaker cone.
function Motion.beat(hits, options)
	options = options or {}
	local amount, decay = options.amount or 0.014, options.decay or 0.14
	return modifier(function(state, t)
		state.scale = state.scale * (1 + amount * Curves.pulse(t, hits, decay))
	end)
end

-- Exposed for templates that stagger: stagger(start, i, step) is the i-th
-- (1-based) time after `start`.
function Motion.stagger(start, i, step)
	return start + (i - 1) * (step or 0.125)
end

return Motion
