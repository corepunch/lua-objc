--[[
  ui/animation.lua — SwiftUI animation for native views.

  Platform-neutral values and math, installed on a platform module by
  `Animation.install(ns, bridge)`; the Core Animation engine lives in
  src/shared/motion.m.

    ns.Animation            animation values, as SwiftUI's `Animation`:
                            linear, easeIn, easeOut, easeInOut, timingCurve,
                            spring, smooth, snappy, bouncy, interactiveSpring,
                            interpolatingSpring, default; modifiers :delay,
                            :speed, :repeatCount, :repeatForever.
    ns.withAnimation(a, body, completion)
                            runs `body` in a transaction: every frame,
                            opacity, transform, colour and content change it
                            causes animates with `a`; inserted and removed
                            views play their transitions.
    ns.withTransaction(t, body)
                            the same with a `Transaction`
                            ({animation, disablesAnimations}).
    ns.AnyTransition        transitions: opacity, scale, slide, move, offset,
                            push, identity, drawOn, asymmetric, :combined.
    ns.transition(view, t), ns.matchedGeometry(view, id, namespace),
    ns.contentTransition(view, kind)
                            the per-view modifiers behind the XML attributes.
    ns.keyframeAnimation(view, spec, completion), ns.phaseAnimation(view, spec)
                            SwiftUI's KeyframeAnimator and PhaseAnimator.
    ns.reduceMotion()       whether the user asked to reduce motion.

  Templates reconcile inside the current transaction (see ui/template.lua),
  so `ns.withAnimation(a, function() template:update(data) end)` animates a
  state change exactly as SwiftUI's `withAnimation { state = … }` does.
]]

local M = {}

local DEFAULTS = {
	duration = 0.35,
	springDuration = 0.5,
	smoothBounce = 0,
	snappyBounce = 0.15,
	bouncyBounce = 0.3,
	interactiveResponse = 0.15,
	interactiveDamping = 0.86,
	keyframeRate = 60,
	drawOnStagger = 0.03,
}

-- ── Animation values ────────────────────────────────────────────────────

-- Values are immutable. Fields: kind ("timing" or "spring"), the curve's
-- control points x1…y2 and duration, or the spring's mass, stiffness,
-- damping and initialVelocity (with response, dampingFraction and bounce as
-- SwiftUI states them); startDelay, speedFactor, repeats (-1 forever) and
-- autoreverses, set by the modifier methods of the same SwiftUI names.

local Value = {}
Value.__index = Value

local function value(fields)
	local result = setmetatable({startDelay = 0, speedFactor = 1, repeats = 0, autoreverses = false}, Value)
	for key, field in pairs(fields) do result[key] = field end
	return result
end

local function copy(animation, changes)
	local result = setmetatable({}, Value)
	for key, field in pairs(animation) do result[key] = field end
	for key, field in pairs(changes) do result[key] = field end
	return result
end

--- Delays the start by `seconds`.
function Value:delay(seconds) return copy(self, {startDelay = self.startDelay + assert(tonumber(seconds), "delay requires seconds")}) end
--- Plays `multiplier` times faster.
function Value:speed(multiplier)
	local speed = assert(tonumber(multiplier), "speed requires a multiplier")
	assert(speed > 0, "speed must be positive")
	return copy(self, {speedFactor = self.speedFactor * speed})
end
--- Plays `count` times; reverses on alternate plays unless `autoreverses` is false.
function Value:repeatCount(count, autoreverses)
	return copy(self, {repeats = assert(tonumber(count), "repeatCount requires a count"), autoreverses = autoreverses ~= false})
end
--- Repeats until the view changes again; reverses unless `autoreverses` is false.
function Value:repeatForever(autoreverses)
	return copy(self, {repeats = -1, autoreverses = autoreverses ~= false})
end

local Animation = {}
M.Animation = Animation

local function timing(x1, y1, x2, y2, duration)
	return value({kind = "timing", x1 = x1, y1 = y1, x2 = x2, y2 = y2, duration = duration or DEFAULTS.duration})
end

function Animation.linear(duration) return timing(0, 0, 1, 1, duration) end
function Animation.easeIn(duration) return timing(0.42, 0, 1, 1, duration) end
function Animation.easeOut(duration) return timing(0, 0, 0.58, 1, duration) end
function Animation.easeInOut(duration) return timing(0.42, 0, 0.58, 1, duration) end
--- A cubic Bézier timing curve through (x1, y1) and (x2, y2).
function Animation.timingCurve(x1, y1, x2, y2, duration)
	for _, v in ipairs({x1, y1, x2, y2}) do assert(type(v) == "number", "timingCurve requires four control values") end
	return timing(x1, y1, x2, y2, duration)
end

-- SwiftUI's spring model: a response (period) and a damping fraction, or a
-- perceptual duration and bounce, become physical parameters.
local function physical(response, dampingFraction, mass)
	mass = mass or 1
	assert(response > 0, "spring response must be positive")
	return {
		kind = "spring", mass = mass,
		stiffness = (2 * math.pi / response) ^ 2 * mass,
		damping = 4 * math.pi * dampingFraction * mass / response,
		initialVelocity = 0,
		response = response, dampingFraction = dampingFraction,
		duration = response,
	}
end

--- A spring. `{duration, bounce}` (SwiftUI's perceptual form, bounce from
--- -1 to 1) or `{response, dampingFraction}`; positional `(duration, bounce)`.
function Animation.spring(options, bounce)
	if type(options) == "number" or options == nil then options = {duration = options, bounce = bounce} end
	local fields
	if options.response or options.dampingFraction then
		fields = physical(options.response or DEFAULTS.springDuration, options.dampingFraction or 0.825)
	else
		local b = options.bounce or 0
		assert(b > -1 and b < 1, "spring bounce must be between -1 and 1")
		fields = physical(options.duration or DEFAULTS.springDuration, b >= 0 and 1 - b or 1 / (1 + b))
		fields.bounce = b
	end
	fields.initialVelocity = options.initialVelocity or 0
	return value(fields)
end

--- A spring from stiffness and damping, like SwiftUI's interpolatingSpring.
function Animation.interpolatingSpring(options, damping)
	if type(options) == "number" then options = {stiffness = options, damping = damping} end
	assert(type(options.stiffness) == "number" and type(options.damping) == "number", "interpolatingSpring requires stiffness and damping")
	local mass = options.mass or 1
	local period = 2 * math.pi / math.sqrt(options.stiffness / mass)
	return value({kind = "spring", mass = mass, stiffness = options.stiffness, damping = options.damping,
		initialVelocity = options.initialVelocity or 0, response = period, duration = period})
end

local function preset(bounce)
	return function(options, extraBounce)
		if type(options) == "number" or options == nil then options = {duration = options, extraBounce = extraBounce} end
		return Animation.spring({duration = options.duration or DEFAULTS.springDuration, bounce = bounce + (options.extraBounce or 0)})
	end
end
--- A spring with no bounce.
Animation.smooth = preset(DEFAULTS.smoothBounce)
--- A spring with a small bounce that settles quickly.
Animation.snappy = preset(DEFAULTS.snappyBounce)
--- A spring with a visible bounce.
Animation.bouncy = preset(DEFAULTS.bouncyBounce)
--- A short, stiff spring for tracking direct manipulation.
function Animation.interactiveSpring(options)
	options = options or {}
	return Animation.spring({response = options.response or DEFAULTS.interactiveResponse,
		dampingFraction = options.dampingFraction or DEFAULTS.interactiveDamping})
end
--- SwiftUI's default animation: a spring without bounce.
Animation.default = Animation.spring()

function Animation.isAnimation(candidate) return getmetatable(candidate) == Value end

-- ── Parsing, for XML attributes ─────────────────────────────────────────

-- Splits `a(b, c).d(e)` into calls {{name = "a", args = {"b", "c"}}, …}.
-- Arguments may nest calls, as in `asymmetric(move(top), opacity)`.
local function calls(text)
	local result, position = {}, 1
	text = text:gsub("%s+", "")
	while position <= #text do
		local name, after = text:match("^([%a_][%w_]*)()", position)
		if not name then error("cannot parse '" .. text .. "'") end
		position = after
		local args = {}
		if text:sub(position, position) == "(" then
			local depth, from, closed = 0, position + 1, false
			for index = position, #text do
				local c = text:sub(index, index)
				if c == "(" then
					depth = depth + 1
				elseif c == ")" then
					depth = depth - 1
					if depth == 0 then
						local arg = text:sub(from, index - 1)
						if arg ~= "" then table.insert(args, arg) end
						position, closed = index + 1, true
						break
					end
				elseif c == "," and depth == 1 then
					table.insert(args, text:sub(from, index - 1))
					from = index + 1
				end
			end
			if not closed then error("unbalanced parentheses in '" .. text .. "'") end
		end
		table.insert(result, {name = name, args = args})
		if position <= #text then
			if text:sub(position, position) ~= "." then error("cannot parse '" .. text .. "'") end
			position = position + 1
		end
	end
	return result
end

local function literals(args)
	local result = {}
	for index, arg in ipairs(args) do
		if arg == "true" or arg == "false" then result[index] = arg == "true"
		else result[index] = assert(tonumber(arg), "expected a number, got '" .. arg .. "'") end
	end
	return table.unpack(result, 1, #args)
end

local PARSEABLE = {linear = true, easeIn = true, easeOut = true, easeInOut = true, timingCurve = true, spring = true,
	interpolatingSpring = true, smooth = true, snappy = true, bouncy = true, interactiveSpring = true, default = true}

--- Parses `spring`, `easeInOut(0.3)`, `bouncy(0.6).delay(0.1)`,
--- `linear(1).repeatForever(false)`, … into an animation value.
function Animation.parse(text)
	if Animation.isAnimation(text) then return text end
	assert(type(text) == "string" and text ~= "", "animation requires a name")
	local chain = calls(text)
	local first = table.remove(chain, 1)
	assert(PARSEABLE[first.name], "unknown animation '" .. first.name .. "'")
	local result = Animation[first.name]
	if not Animation.isAnimation(result) then result = result(literals(first.args))
	else assert(#first.args == 0, first.name .. " takes no arguments") end
	for _, call in ipairs(chain) do
		local modifier = Value[call.name]
		assert(type(modifier) == "function", "unknown animation modifier '" .. call.name .. "'")
		result = modifier(result, literals(call.args))
	end
	return result
end

-- The native engine's view of an animation value.
local function spec(animation)
	if animation == nil then return nil end
	assert(Animation.isAnimation(animation), "expected an Animation value")
	return {kind = animation.kind, x1 = animation.x1, y1 = animation.y1, x2 = animation.x2, y2 = animation.y2,
		duration = animation.duration, mass = animation.mass, stiffness = animation.stiffness, damping = animation.damping,
		initialVelocity = animation.initialVelocity, delay = animation.startDelay, speed = animation.speedFactor,
		repeatCount = animation.repeats, autoreverses = animation.autoreverses}
end
M.spec = spec

-- ── Timing and spring math (keyframes sample with these) ────────────────

-- Solves a cubic Bézier timing curve for y at x, as CAMediaTimingFunction.
function M.bezier(x1, y1, x2, y2, x)
	if x <= 0 then return 0 end
	if x >= 1 then return 1 end
	local function curve(a, b, t) return 3 * a * (1 - t) ^ 2 * t + 3 * b * (1 - t) * t ^ 2 + t ^ 3 end
	local low, high, t = 0, 1, x
	for _ = 1, 40 do
		local current = curve(x1, x2, t)
		if math.abs(current - x) < 1e-7 then break end
		if current < x then low = t else high = t end
		t = (low + high) / 2
	end
	return curve(y1, y2, t)
end

-- A spring's normalized step response at time t: 0 at rest, 1 at target.
function M.springProgress(animation, t)
	if t <= 0 then return 0 end
	local mass, stiffness, damping = animation.mass or 1, animation.stiffness, animation.damping
	local omega = math.sqrt(stiffness / mass)
	local zeta = damping / (2 * math.sqrt(stiffness * mass))
	local v0 = -(animation.initialVelocity or 0)
	if zeta < 1 then
		local omegaD = omega * math.sqrt(1 - zeta * zeta)
		local envelope = math.exp(-zeta * omega * t)
		return 1 - envelope * (math.cos(omegaD * t) + (zeta * omega - v0) / omegaD * math.sin(omegaD * t))
	end
	return 1 - math.exp(-omega * t) * (1 + (omega - v0) * t)
end

-- Progress of an animation value at `t` seconds, ignoring delay and repeats.
function M.progress(animation, t)
	if animation.kind == "spring" then return M.springProgress(animation, t) end
	if animation.duration <= 0 then return 1 end
	return M.bezier(animation.x1, animation.y1, animation.x2, animation.y2, t / animation.duration)
end

-- ── Transitions ─────────────────────────────────────────────────────────

local TransitionValue = {}
TransitionValue.__index = TransitionValue

local function transition(insertion, removal)
	return setmetatable({insertion = insertion or {}, removal = removal or insertion or {}}, TransitionValue)
end

local function merge(a, b)
	local result = {}
	for key, v in pairs(a) do result[key] = v end
	for key, v in pairs(b) do
		if key == "opacity" or key == "scale" then result[key] = (result[key] or 1) * v
		elseif key == "offsetX" or key == "offsetY" or key == "rotation" then result[key] = (result[key] or 0) + v
		elseif result[key] == nil then result[key] = v end
	end
	return result
end

--- Combines two transitions, like SwiftUI's `.combined(with:)`.
function TransitionValue:combined(other)
	return transition(merge(self.insertion, other.insertion), merge(self.removal, other.removal))
end

local AnyTransition = {}
M.AnyTransition = AnyTransition

local OPPOSITE = {leading = "trailing", trailing = "leading", top = "bottom", bottom = "top"}
local function edge(name)
	assert(OPPOSITE[name], "unknown edge '" .. tostring(name) .. "'")
	return name
end

AnyTransition.identity = transition({}, {})
AnyTransition.opacity = transition({opacity = 0})
--- Moves in from the leading edge and out to the trailing edge.
AnyTransition.slide = transition({edge = "leading"}, {edge = "trailing"})
--- Arcs stroke themselves in, one after another; SectorChart uses it.
AnyTransition.drawOn = transition({strokeEnd = 0, stagger = DEFAULTS.drawOnStagger}, {strokeEnd = 0})
--- Scales from `scale` (0 by default) about the centre.
function AnyTransition.scale(scale) return transition({scale = scale or 0}) end
--- Moves in from and out to `edge`.
function AnyTransition.move(name) return transition({edge = edge(name)}) end
--- Moves in from and out to an offset.
function AnyTransition.offset(x, y) return transition({offsetX = x or 0, offsetY = y or 0}) end
--- Pushes in from `edge` and out toward the opposite edge, fading.
function AnyTransition.push(name)
	edge(name)
	return transition({edge = name, opacity = 0}, {edge = OPPOSITE[name], opacity = 0})
end
--- Separate insertion and removal transitions.
function AnyTransition.asymmetric(insertion, removal)
	return transition(insertion.insertion, removal.removal)
end

function AnyTransition.isTransition(candidate) return getmetatable(candidate) == TransitionValue end

local NAMED = {identity = true, opacity = true, slide = true, drawOn = true}
local CALLED = {scale = true, offset = true}

--- Parses `opacity`, `scale(0.8)`, `move(top)`, `offset(0, 20)`,
--- `push(trailing)`, `slide`, `drawOn`, `opacity+scale(0.9)` and
--- `asymmetric(move(top), opacity)`.
function AnyTransition.parse(text)
	if AnyTransition.isTransition(text) then return text end
	assert(type(text) == "string" and text ~= "", "transition requires a name")
	text = text:gsub("%s+", "")
	local parts, depth, from = {}, 0, 1
	for index = 1, #text + 1 do
		local c = text:sub(index, index)
		if c == "(" then depth = depth + 1 elseif c == ")" then depth = depth - 1 end
		if (c == "+" and depth == 0) or index == #text + 1 then
			table.insert(parts, text:sub(from, index - 1))
			from = index + 1
		end
	end
	local result
	for _, part in ipairs(parts) do
		local chain = calls(part)
		assert(#chain == 1, "cannot parse transition '" .. part .. "'")
		local call, item = chain[1], nil
		if call.name == "asymmetric" then
			assert(#call.args == 2, "asymmetric requires an insertion and a removal")
			item = AnyTransition.asymmetric(AnyTransition.parse(call.args[1]), AnyTransition.parse(call.args[2]))
		elseif call.name == "move" or call.name == "push" then
			assert(#call.args == 1, call.name .. " requires an edge")
			item = AnyTransition[call.name](call.args[1])
		elseif NAMED[call.name] then
			assert(#call.args == 0, call.name .. " takes no arguments")
			item = AnyTransition[call.name]
		elseif CALLED[call.name] then
			item = AnyTransition[call.name](literals(call.args))
		else
			error("unknown transition '" .. call.name .. "'")
		end
		result = result and result:combined(item) or item
	end
	return result
end

-- ── Keyframes ───────────────────────────────────────────────────────────

-- Tracks animate these view properties; each starts from its resting value.
local TRACK_REST = {opacity = 1, scaleEffect = 1, rotationEffect = 0, offsetX = 0, offsetY = 0}
M.keyframeProperties = TRACK_REST

local function trackDuration(track)
	local total = 0
	for _, frame in ipairs(track) do total = total + (frame.duration or 0) end
	return total
end

-- The value of one track at time t. Keyframes are SwiftUI's: `linear`
-- (with an optional timing `curve`), `spring` (with an optional `spring`
-- animation that settles over the keyframe by default), `cubic` (a smooth
-- Catmull-Rom curve through neighbouring values) and `move` (a jump).
function M.trackValue(track, rest, t)
	local previous, elapsed = rest, 0
	for index, frame in ipairs(track) do
		local duration = frame.duration or 0
		local target = assert(tonumber(frame.value), "keyframe requires a value")
		local kind = frame.type or "linear"
		if kind == "move" and t >= elapsed and duration == 0 then
			previous = target
		elseif t < elapsed + duration then
			local p = (t - elapsed) / duration
			if kind == "linear" then
				local curve = frame.curve and Animation.parse(frame.curve) or Animation.linear(duration)
				return previous + (target - previous) * M.bezier(curve.x1, curve.y1, curve.x2, curve.y2, p)
			elseif kind == "spring" then
				local spring = frame.spring and Animation.parse(frame.spring) or Animation.spring({duration = duration})
				return previous + (target - previous) * M.springProgress(spring, t - elapsed)
			elseif kind == "cubic" then
				local before = index > 1 and (index > 2 and track[index - 2].value or rest) or previous
				local after = track[index + 1] and track[index + 1].value or target
				local p2, p3 = p * p, p * p * p
				return 0.5 * ((2 * previous) + (-before + target) * p + (2 * before - 5 * previous + 4 * target - after) * p2
					+ (-before + 3 * previous - 3 * target + after) * p3)
			elseif kind == "move" then
				return target
			end
			error("unknown keyframe type '" .. tostring(kind) .. "'")
		else
			previous = target
		end
		elapsed = elapsed + duration
	end
	return previous
end

--- Samples keyframe tracks into evenly spaced values for the native engine.
--- `spec.tracks` maps a property (opacity, scaleEffect, rotationEffect,
--- offsetX, offsetY) to an array of keyframes `{type, value, duration}`.
function M.sampleKeyframes(spec)
	assert(type(spec) == "table" and type(spec.tracks) == "table", "keyframes require tracks")
	local duration = 0
	for name, track in pairs(spec.tracks) do
		assert(TRACK_REST[name] ~= nil, "cannot animate '" .. tostring(name) .. "' with keyframes")
		duration = math.max(duration, trackDuration(track))
	end
	assert(duration > 0, "keyframes require a positive duration")
	local count = math.max(2, math.ceil(duration * (spec.rate or DEFAULTS.keyframeRate)) + 1)
	local samples = {count = count, duration = duration}
	for name, track in pairs(spec.tracks) do
		local values, rest = {}, (spec.initial and spec.initial[name]) or TRACK_REST[name]
		for index = 0, count - 1 do
			table.insert(values, M.trackValue(track, rest, duration * index / (count - 1)))
		end
		samples[name] = values
	end
	if spec.repeating then samples.repeatCount = -1 end
	return samples
end

-- ── Installation on a platform module ───────────────────────────────────

local stack = {}

--- The animation of the innermost transaction, or nil outside one or in a
--- transaction that disables animation.
function M.current()
	local top = stack[#stack]
	return top and top.animation or nil
end

--- Whether a transaction is open.
function M.inTransaction() return #stack > 0 end

local function run(bridge, transaction, body, completion)
	assert(type(body) == "function", "withAnimation requires a function")
	local animation = not transaction.disablesAnimations and transaction.animation or nil
	table.insert(stack, {animation = animation})
	local results = table.pack(pcall(bridge._motionTransaction, spec(animation), body, completion))
	table.remove(stack)
	if not results[1] then error(results[2], 0) end
	return table.unpack(results, 2, results.n)
end

function M.install(ns, bridge)
	ns.Animation = Animation
	ns.AnyTransition = AnyTransition

	--- A transaction value: `{animation = …, disablesAnimations = false}`.
	function ns.Transaction(fields)
		fields = fields or {}
		return {animation = fields.animation and Animation.parse(fields.animation), disablesAnimations = fields.disablesAnimations == true}
	end

	--- Runs `body` so that the changes it makes animate together, then runs
	--- `completion` when they finish. `withAnimation(body)` uses the default
	--- animation; `withAnimation(nil, body)` applies changes without one.
	function ns.withAnimation(...)
		local first, second, third = ...
		if type(first) == "function" then
			return run(bridge, {animation = Animation.default}, first, second)
		end
		assert(select("#", ...) >= 2, "withAnimation requires a body")
		return run(bridge, {animation = first and Animation.parse(first)}, second, third)
	end

	--- Runs `body` in `transaction`.
	function ns.withTransaction(transaction, body)
		assert(type(transaction) == "table", "withTransaction requires a Transaction")
		return run(bridge, transaction, body)
	end

	--- Sets the transition a view plays when inserted or removed in an
	--- animated transaction (SwiftUI's `.transition`). nil removes it.
	function ns.transition(view, t)
		if t == nil then bridge._motionSetTransition(view, nil, nil); return end
		t = AnyTransition.parse(t)
		bridge._motionSetTransition(view, t.insertion, t.removal)
	end

	--- Links views that represent the same thing (SwiftUI's
	--- `.matchedGeometryEffect`): when one appears as another leaves, it
	--- grows from where the other was.
	function ns.matchedGeometry(view, id, namespace)
		bridge._motionSetMatched(view, id and ((namespace or "default") .. "/" .. tostring(id)) or nil)
	end

	--- How a view's content (text, title, image) changes inside an animated
	--- transaction: `opacity`, `interpolate`, `numericText` or `identity`.
	function ns.contentTransition(view, kind)
		bridge._motionSetContentTransition(view, kind)
	end

	--- Plays keyframe tracks on a view (SwiftUI's KeyframeAnimator);
	--- `completion` runs when a non-repeating animation ends.
	function ns.keyframeAnimation(view, keyframes, completion)
		bridge._keyframeAnimation(view, M.sampleKeyframes(keyframes), completion)
	end

	--- Cycles a view through phases (SwiftUI's PhaseAnimator). Each phase is
	--- a table of view properties; `animation` is an animation value, a name
	--- or a function(phase, index) returning one. Repeats until cancelled
	--- unless `repeating` is false. Returns a handle with `cancel()`, which
	--- the current Scope also calls when it is disposed.
	function ns.phaseAnimation(view, options)
		local phases = assert(options and options.phases, "phaseAnimation requires phases")
		assert(#phases >= 2, "phaseAnimation requires at least two phases")
		local handle = {cancelled = false}
		function handle.cancel()
			if handle.cancelled then return end
			handle.cancelled = true
			bridge._motionStop(view)
		end
		function handle:dispose() handle.cancel() end
		function handle:isDisposed() return handle.cancelled end
		local function apply(phase) for key, v in pairs(phase) do view[key] = v end end
		local function animation(phase, index)
			local a = options.animation
			if type(a) == "function" then a = a(phase, index) end
			return a and Animation.parse(a) or Animation.default
		end
		local function advance(index)
			if handle.cancelled then return end
			if index > #phases then
				if options.repeating == false then return end
				index = 1
			end
			ns.withAnimation(animation(phases[index], index), function() apply(phases[index]) end,
				function() advance(index + 1) end)
		end
		ns.withAnimation(nil, function() apply(phases[1]) end)
		advance(2)
		local scope = ns.Scope and ns.Scope.current()
		if scope then scope:add(handle) end
		return handle
	end

	--- Plays an SF Symbol effect on a SystemImage (SwiftUI's
	--- `.symbolEffect`): bounce, bounceUp, bounceDown, pulse, variableColor,
	--- scale, appear, disappear, wiggle, rotate or breathe. Options:
	--- `repeating`, `repeatCount`, `speed`. A nil effect removes them all.
	function ns.symbolEffect(view, effect, options)
		bridge._symbolEffect(view, effect, options)
	end

	--- Whether the user asked to reduce motion. Movement then becomes fades.
	function ns.reduceMotion()
		return bridge._motionReduced()
	end
end

return M
