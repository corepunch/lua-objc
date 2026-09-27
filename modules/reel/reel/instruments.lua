-- Synthesised voices for reel scores: one call per note or hit, writing into
-- an Audio mix (reel/audio.lua). Scores sequence them from the reel's
-- events and their own musical data.
--
-- Hot loops write the buses directly instead of calling mix:add per sample.
local Audio = require("reel.audio")

local sin, exp, pi, min, max = math.sin, math.exp, math.pi, math.min, math.max
local TAU = 2 * pi
local hz = Audio.midiHz

local Instruments = {}

-- pad(mix, t0, length, notes, {tail, last, level(t), bright(t)}): detuned
-- additive saws, three voices per note spread across the field; `tail`
-- seconds of crossfade after `length` unless `last` (rings to the end).
function Instruments.pad(mix, t0, length, notes, o)
	local sr = mix.sr
	local tail = o.tail or 0.6
	local first, last = mix:range(t0, o.last and (mix.duration - t0) or (length + tail))
	local duckL, duckR, sendL, sendR = mix.duckL, mix.duckR, mix.sendL, mix.sendR
	local level, bright = o.level, o.bright
	local detune = { { -8.0, 0.8 }, { 0.0, 0.5 }, { 8.0, 0.2 } }
	local freqs, weights = {}, {}
	for _, note in ipairs(notes) do
		for _, d in ipairs(detune) do
			table.insert(freqs, hz(note + d[1] / 100))
			table.insert(weights, d[2])
		end
	end
	local voices = #freqs
	for i = first, last do
		local t = i / sr
		local localT = t - t0
		local env = min(1, localT / 0.12)
		if not o.last and localT > length then env = env * max(0, 1 - (localT - length) / tail) end
		local b = bright(t)
		local exponent = 2.3 - 0.9 * b
		local l, r = 0.0, 0.0
		for v = 1, voices do
			local f, pl = freqs[v], weights[v]
			local s = 0.0
			for k = 1, 6 do s = s + sin(TAU * f * k * t + k) / k ^ exponent end
			l = l + s * pl
			r = r + s * (1 - pl)
		end
		local g = 0.011 * env * level(t)
		local k = i + 1
		duckL[k] = duckL[k] + l * g
		duckR[k] = duckR[k] + r * g
		sendL[k] = sendL[k] + l * g * 0.7
		sendR[k] = sendR[k] + r * g * 0.7
	end
end

-- pluck(mix, t, f, {level, bright, pan, send}): a plucked note with fading
-- upper partials, on the ducked bus.
function Instruments.pluck(mix, t0, f, o)
	local sr, level, bright, pan, send = mix.sr, o.level, o.bright or 1, o.pan or 0.5, o.send or 0.5
	local first, last = mix:range(t0, 0.9)
	local duckL, duckR, sendL, sendR = mix.duckL, mix.duckR, mix.sendL, mix.sendR
	local gl, gr = (1 - pan) * 2, pan * 2
	for i = first, last do
		local dt = i / sr - t0
		local env = exp(-dt / 0.16) * (1 - exp(-dt / 0.002))
		local ph = TAU * f * dt
		local v = (sin(ph) + 0.45 * bright * sin(2 * ph) * exp(-dt / 0.07) + 0.2 * bright * sin(3 * ph) * exp(-dt / 0.04)) * env * level
		local k = i + 1
		local l, r = v * gl, v * gr
		duckL[k] = duckL[k] + l
		duckR[k] = duckR[k] + r
		sendL[k] = sendL[k] + l * send
		sendR[k] = sendR[k] + r * send
	end
end

local function addDuck(mix, i, v)
	local k = i + 1
	mix.duckL[k] = mix.duckL[k] + v
	mix.duckR[k] = mix.duckR[k] + v
end

-- bass(mix, t, f, length): a pumping note of five harmonics.
function Instruments.bass(mix, t0, f, length, level)
	local sr = mix.sr
	local first, last = mix:range(t0, length)
	for i = first, last do
		local dt = i / sr - t0
		local env = min(1, dt / 0.004) * exp(-dt / 0.35)
		local v = 0.0
		for k = 1, 5 do v = v + sin(TAU * f * k * dt) / (k * k) end
		addDuck(mix, i, v * env * (level or 0.2))
	end
end

-- bassSustain(mix, t, f, length): a long, soft note for breakdowns.
function Instruments.bassSustain(mix, t0, f, length, level)
	local sr = mix.sr
	local first, last = mix:range(t0, length)
	for i = first, last do
		local dt = i / sr - t0
		local env = min(1, dt / 0.02) * exp(-dt / 1.4)
		addDuck(mix, i, (sin(TAU * f * dt) + 0.3 * sin(2 * TAU * f * dt)) * env * (level or 0.16))
	end
end

-- kick(mix, t): a pitch-swept sine with a noise click.
function Instruments.kick(mix, t0)
	local sr, phase = mix.sr, 0.0
	local first, last = mix:range(t0, 0.45)
	for i = first, last do
		local dt = i / sr - t0
		phase = phase + TAU * (46 + 120 * exp(-dt / 0.03)) / sr
		local click = dt < 0.004 and mix:noise() * 0.25 * (1 - dt / 0.004) or 0
		mix:add(i, sin(phase) * exp(-dt / 0.26) * 0.62 + click)
	end
end

-- clap(mix, t): three noise bursts, high-passed.
function Instruments.clap(mix, t0)
	local sr, prev = mix.sr, 0.0
	local first, last = mix:range(t0, 0.3)
	for i = first, last do
		local dt = i / sr - t0
		local bursts = 0.0
		for _, o in ipairs({ 0.0, 0.011, 0.022 }) do
			if dt >= o then bursts = bursts + exp(-(dt - o) / (o == 0.022 and 0.09 or 0.008)) end
		end
		local x = mix:noise()
		local h = x - prev
		prev = x
		mix:add(i, h * bursts * 0.16, 0.52, 0.6)
	end
end

-- hat(mix, t, open, level, pan): doubly high-passed noise.
function Instruments.hat(mix, t0, open, level, pan)
	local sr, p1, p2 = mix.sr, 0.0, 0.0
	local first, last = mix:range(t0, open and 0.2 or 0.05)
	local decay = open and 0.07 or 0.015
	for i = first, last do
		local dt = i / sr - t0
		local x = mix:noise()
		local h1 = x - p1
		p1 = x
		local h2 = h1 - p2
		p2 = h1
		mix:add(i, h2 * exp(-dt / decay) * level, pan)
	end
end

-- crash(mix, t, big): a long noise wash.
function Instruments.crash(mix, t0, big)
	local sr, p1 = mix.sr, 0.0
	local first, last = mix:range(t0, big and 2.4 or 1.6)
	for i = first, last do
		local dt = i / sr - t0
		local x = mix:noise()
		local h = x - p1
		p1 = x
		mix:add(i, h * exp(-dt / (big and 0.9 or 0.55)) * (big and 0.11 or 0.07), 0.5, 0.4)
	end
end

-- roll(mix, a, b): a snare roll accelerating and swelling from a to b.
function Instruments.roll(mix, a, b)
	local sr, hit = mix.sr, a
	while hit < b do
		local x = math.min(1, math.max(0, (hit - a) / (b - a)))
		local p1 = 0.0
		local first, last = mix:range(hit, 0.08)
		for i = first, last do
			local dt = i / sr - hit
			local nz = mix:noise()
			local h = nz - p1
			p1 = nz
			mix:add(i, (h * 0.8 + sin(TAU * 190 * dt) * 0.4) * exp(-dt / 0.03) * (0.03 + 0.12 * x * x), 0.5, 0.3)
		end
		hit = hit + (0.125 + (0.031 - 0.125) * x)
	end
end

-- riser(mix, a, b): filtered noise and a rising tone into a drop.
function Instruments.riser(mix, a, b)
	local sr, lp, phase = mix.sr, 0.0, 0.0
	local first, last = mix:range(a, b - a)
	for i = first, last do
		local x = math.min(1, math.max(0, (i / sr - a) / (b - a)))
		lp = lp + (mix:noise() - lp) * (0.01 + 0.35 * x * x)
		phase = phase + TAU * (180 * 8 ^ x) / sr
		mix:add(i, (lp * 0.2 + sin(phase) * 0.03) * x ^ 2.2, 0.5, 0.5)
	end
end

-- whoosh(mix, a, b): a swell of filtered noise panning left to right.
function Instruments.whoosh(mix, a, b)
	local sr, lp = mix.sr, 0.0
	local first, last = mix:range(a, b - a + 0.15)
	for i = first, last do
		local x = math.min(1, math.max(0, (i / sr - a) / (b + 0.15 - a)))
		local bell = sin(pi * x)
		lp = lp + (mix:noise() - lp) * (0.04 + 0.4 * bell)
		mix:add(i, lp * bell * bell * 0.22, 0.15 + 0.7 * x, 0.35)
	end
end

-- slam(mix, t): a thump with a click, for words and cards landing.
function Instruments.slam(mix, t0)
	local sr, phase = mix.sr, 0.0
	local first, last = mix:range(t0, 0.35)
	for i = first, last do
		local dt = i / sr - t0
		phase = phase + TAU * (70 + 160 * exp(-dt / 0.02)) / sr
		local click = dt < 0.006 and mix:noise() * 0.35 * (1 - dt / 0.006) or 0
		mix:add(i, sin(phase) * exp(-dt / 0.14) * 0.42 + click, 0.5, 0.2)
	end
end

-- boom(mix, t, decay): a sub drop.
function Instruments.boom(mix, t0, decay)
	local sr, phase = mix.sr, 0.0
	local first, last = mix:range(t0, 1.6)
	for i = first, last do
		local dt = i / sr - t0
		phase = phase + TAU * (34 + 70 * exp(-dt / 0.06)) / sr
		mix:add(i, sin(phase) * exp(-dt / (decay or 0.9)) * 0.7)
	end
end

-- blip(mix, t, f, pan): a UI pop with a quick downward chirp.
function Instruments.blip(mix, t0, f, pan)
	local sr = mix.sr
	local first, last = mix:range(t0, 0.18)
	for i = first, last do
		local dt = i / sr - t0
		local ff = f * (1 + 0.6 * exp(-dt / 0.012))
		mix:add(i, sin(TAU * ff * dt) * exp(-dt / 0.05) * 0.075, pan, 0.35)
	end
end

-- tone(mix, t, f, {length, decay, level, pan, send}): a plain decaying sine.
function Instruments.tone(mix, t0, f, o)
	local sr = mix.sr
	local first, last = mix:range(t0, o.length or 0.8)
	for i = first, last do
		local dt = i / sr - t0
		mix:add(i, sin(TAU * f * dt) * exp(-dt / (o.decay or 0.3)) * (o.level or 0.05), o.pan, o.send or 0.6)
	end
end

-- bell(mix, t, f, pan): a struck bell with an inharmonic partial, ringing
-- to the end of the mix.
function Instruments.bell(mix, t0, f, pan)
	local sr = mix.sr
	local first, last = mix:range(t0, mix.duration - t0)
	for i = first, last do
		local dt = i / sr - t0
		local env = exp(-dt / 2.6) * (1 - exp(-dt / 0.002))
		mix:add(i, (sin(TAU * f * dt) + 0.3 * sin(TAU * f * 2.76 * dt) * exp(-dt / 0.35)) * env * 0.055, pan, 0.8)
	end
end

return Instruments
