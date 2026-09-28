-- Sample-accurate Lua synthesizer for the Composer's bars. `render(out, n)`
-- writes n interleaved stereo frames into `out`; it has no IO, so the same
-- code feeds the speakers and the headless tests. Drums are one-shots
-- rendered once at construction; bass, pads and stabs are running voices.
-- Tempo and swing are read at each bar boundary, sound controls every block.
local Amen = require("apps.dnb.models.Amen")

local Synth = {}
Synth.__index = Synth

local sin, exp, floor, pi = math.sin, math.exp, math.floor, math.pi
local TAU = 2 * pi

-- Mix and voice constants in one place so the balance can be tuned by ear.
local MIX = {
	drums = 0.9, sub = 0.55, reese = 0.34, pad = 0.05, stab = 0.07, riser = 0.18,
	arp = 0.075, lead = 0.07, throw = 0.9, -- throw: dub echo send, independent of Space
	amen = 0.85, amenSend = 0.12, keys = 0.055, keysSend = 0.35,
	duckDepth = 0.45, duckRelease = 0.12, -- sidechain pump from each kick
	delaySend = 0.55, reverbSend = 0.8, delayFeedback = 0.38,
	master = 0.9,
}
local BASS = {
	detune = 0.0045, glide = 0.0025, attack = 0.004, release = 0.03,
	minCutoff = 70, cutoffOctaves = 6.2, wobbleOctaves = 3, controlRate = 32,
}
local PAD = {detune = 0.006, attack = 0.45, release = 0.9, brightness = 0.06}
local STAB = {decay = 0.16, attack = 0.002}
-- The break's sampler: a slice cut short fades over a few milliseconds, as a
-- sampler's declick does, instead of clicking.
local BREAK = {fade = 0.003, slack = 16, room = {0.019, 0.027}, roomFeedback = 0.32, roomMix = 0.3, tone = 0.55, drive = 1.3}
-- FM electric piano: a sine carrier over a sine modulator at the same
-- ratio for the bark, a fast high "tine", and the suitcase autopan.
local KEYS = {
	index = 1.6, indexFloor = 0.3, indexDecay = 0.25, tine = 0.15, tineRatio = 14, tineDecay = 0.03,
	attack = 0.003, decay = 1.2, release = 0.15, tail = 2.5, autopanRate = 4.5, autopanDepth = 0.35,
}
local PLUCK = {detune = 0.004, attack = 0.002, decay = 0.1, sweep = 0.035, tail = 0.6, send = 0.9} -- tail: -60 dB; the delay carries the rest
local LEAD = {
	detune = 0.003, glide = 0.0016, attack = 0.008, release = 0.12,
	vibratoRate = 5.4, vibratoDepth = 0.007, vibratoDelay = 0.18, -- vibrato blooms on held notes
	brightness = 0.1, sweep = 0.22, sweepTime = 0.15, square = 0.35, send = 0.5,
}
local SINE_SIZE = 4096
local SINE = {}
for i = 0, SINE_SIZE do SINE[i] = sin(TAU * i / SINE_SIZE) end

local function softClip(x)
	if x > 3 then return 1 elseif x < -3 then return -1 end
	local x2 = x * x
	return x * (27 + x2) / (27 + 9 * x2)
end

local function midiHz(m) return 440 * 2 ^ ((m - 69) / 12) end

-- Deterministic white noise so rendered drums, and therefore tests, are
-- identical on every run.
local function noiseSource(seed)
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) & 0x7FFFFFFF
		return state / 0x3FFFFFFF - 1
	end
end

-- TR-808 style metal: six detuned square waves.
local METAL = {205.3, 304.4, 369.6, 522.7, 540.0, 800.0}

local function renderDrums(sr)
	local noise = noiseSource(7)
	local drums = {}
	local function shot(name, seconds, fn)
		local data, n = {}, floor(seconds * sr)
		local state = {}
		for i = 1, n do data[i] = fn((i - 1) / sr, state) end
		-- Declick the tail.
		local fade = math.min(n, floor(0.004 * sr))
		for i = 0, fade - 1 do data[n - i] = data[n - i] * i / fade end
		drums[name] = data
	end
	shot("kick", 0.42, function(t, s)
		s.phase = (s.phase or 0) + TAU * (46 + 115 * exp(-t / 0.026)) / sr
		local click = t < 0.003 and noise() * 0.35 * (1 - t / 0.003) or 0
		return softClip(1.6 * sin(s.phase) * exp(-t / 0.2)) * 0.95 + click
	end)
	shot("snare", 0.32, function(t, s)
		local body = sin(TAU * 188 * t) * exp(-t / 0.055) * 0.55 + sin(TAU * 332 * t) * exp(-t / 0.035) * 0.25
		local n = noise()
		local hp = n - (s.prev or 0)
		s.prev = n
		return body + hp * exp(-t / 0.1) * 0.42
	end)
	local function metal(t, s, scale)
		local v = 0
		for _, f in ipairs(METAL) do v = v + ((t * f * scale) % 1 < 0.5 and 1 or -1) end
		-- Two differences act as a steep high-pass on the metallic cluster.
		local d1 = v - (s.a or 0); s.a = v
		local d2 = d1 - (s.b or 0); s.b = d1
		return d2 / 12 + noise() * 0.12
	end
	shot("hat", 0.07, function(t, s) return metal(t, s, 1.6) * exp(-t / 0.016) end)
	shot("openHat", 0.4, function(t, s) return metal(t, s, 1.6) * exp(-t / 0.12) * 0.8 end)
	shot("ride", 1.1, function(t, s)
		local v = metal(t, s, 2.9) * 0.5 + sin(TAU * 3100 * t) * 0.08
		return v * exp(-t / 0.45) * (t < 0.002 and 1.6 or 1)
	end)
	shot("crash", 2.0, function(t, s)
		local n = noise()
		local hp = n - (s.prev or 0)
		s.prev = n
		return (hp * 0.5 + metal(t, s, 2.3) * 0.35) * exp(-t / 0.6)
	end)
	shot("rim", 0.06, function(t)
		return (sin(TAU * 1720 * t) * 0.6 + sin(TAU * 830 * t) * 0.4) * exp(-t / 0.009)
	end)
	shot("conga", 0.28, function(t, s)
		s.phase = (s.phase or 0) + TAU * (310 + 60 * exp(-t / 0.01)) / sr
		return sin(s.phase) * exp(-t / 0.075) * 0.8
	end)
	-- Toms for fills: a pitched sine that bends down as it decays.
	for name, pitch in pairs({tomHigh = 196, tomMid = 147, tomLow = 104}) do
		shot(name, 0.45, function(t, s)
			s.phase = (s.phase or 0) + TAU * pitch * (1 + 0.5 * exp(-t / 0.03)) / sr
			return softClip(1.3 * sin(s.phase)) * exp(-t / 0.16) * 0.8
		end)
	end
	shot("shaker", 0.09, function(t, s)
		local n = noise()
		local hp = n - (s.prev or 0)
		s.prev = n
		return hp * math.min(1, t / 0.012) * exp(-t / 0.03) * 0.5
	end)
	drums.ghost = drums.snare
	-- The break's kit: a 1960s funk kit, tuned and roomy — a round kick with
	-- a felt beater, a snare with a ringing head and loose wires, and a ride
	-- with its bell.
	shot("breakKick", 0.3, function(t, s)
		s.phase = (s.phase or 0) + TAU * (58 + 70 * exp(-t / 0.018)) / sr
		local thump = t < 0.006 and noise() * 0.25 * (1 - t / 0.006) or 0
		return sin(s.phase) * exp(-t / 0.11) * 0.9 + thump
	end)
	shot("breakSnare", 0.36, function(t, s)
		local head = sin(TAU * 196 * t) * exp(-t / 0.07) * 0.5 + sin(TAU * 287 * t) * exp(-t / 0.12) * 0.22
		local n = noise()
		s.lp = (s.lp or 0) + 0.45 * (n - (s.lp or 0))
		local wires = (n - s.lp * 0.6) * exp(-t / 0.13) * 0.5
		return head + wires
	end)
	shot("breakRide", 0.9, function(t, s)
		local bell = sin(TAU * 2280 * t) * 0.1 + sin(TAU * 3420 * t) * 0.05
		return (metal(t, s, 2.6) * 0.55 + bell) * exp(-t / 0.4)
	end)
	return drums
end

-- The Amen loop at the record's tempo, one sample for the whole break, so a
-- slice holds everything that rang into it: a snare tail under the next
-- kick, the ride's wash. Tails wrap round the loop, as a looped record's do.
-- A short room, a little tape drive and a dull top give it its age.
local function renderAmen(sr, drums)
	local step = sr * 60 / Amen.bpm / 4
	local n = floor(Amen.slices * step + 0.5)
	local data = {}
	for i = 1, n do data[i] = 0 end
	local function place(shot, at, gain)
		for i = 1, #shot do
			local j = (at + i - 1) % n + 1
			data[j] = data[j] + shot[i] * gain
		end
	end
	local kit = {kick = drums.breakKick, snare = drums.breakSnare, crash = drums.crash}
	for bar, hits in ipairs(Amen.pattern) do
		local barStart = (bar - 1) * 16
		for _, h in ipairs(hits) do place(kit[h[2]], floor((barStart + h[1]) * step), h[3]) end
		for s = 0, 14, 2 do place(drums.breakRide, floor((barStart + s) * step), s % 4 == 0 and 0.5 or 0.36) end
	end
	local combs = {}
	for _, seconds in ipairs(BREAK.room) do table.insert(combs, {buf = {}, n = floor(seconds * sr), i = 1}) end
	for _, c in ipairs(combs) do for i = 1, c.n do c.buf[i] = 0 end end
	local lp = 0
	for i = 1, n do
		local x = data[i]
		local room = 0
		for _, c in ipairs(combs) do
			local y = c.buf[c.i]
			c.buf[c.i] = x + y * BREAK.roomFeedback
			c.i = c.i % c.n + 1
			room = room + y
		end
		lp = lp + BREAK.tone * (x + room * BREAK.roomMix - lp)
		data[i] = softClip(lp * BREAK.drive) / BREAK.drive
	end
	return data, step
end

-- Stereo placement per drum voice: {pan (0 left, 1 right), effect send}.
local DRUM_PLACE = {
	kick = {0.5, 0}, snare = {0.5, 0.35}, ghost = {0.46, 0.25}, hat = {0.62, 0.05},
	openHat = {0.62, 0.15}, ride = {0.36, 0.2}, crash = {0.44, 0.3},
	rim = {0.3, 0.3}, conga = {0.7, 0.25}, shaker = {0.76, 0.2},
	tomHigh = {0.66, 0.25}, tomMid = {0.5, 0.25}, tomLow = {0.34, 0.25},
}

function Synth.new(settings, sampleRate)
	local sr = sampleRate or 44100
	local self = setmetatable({
		settings = settings, sr = sr,
		drums = renderDrums(sr),
		breakVoice = nil,    -- the slice voice the next in-order slice continues
		frame = 0,           -- next frame to render
		nextBarFrame = 0,    -- where the next bar starts
		barNumber = 0,       -- timeline bar count across track changes
		composerBar = 0,     -- bar index within the current composer
		timeline = {},       -- recent {frame, bar} for the playhead
		events = {},         -- scheduled, sorted by frame
		voices = {},         -- active one-shot and chord voices
		bass = {freq = 55, target = 55, gate = false, env = 0, reeseGain = 1, p1 = 0, p2 = 0, p3 = 0, sub = 0,
			lp = 0, bp = 0, coef = 0.1, lfo = 0, tick = 0, id = 0},
		lead = {freq = 440, target = 440, gate = false, env = 0, p1 = 0, p2 = 0, sq = 0,
			lp1 = 0, lp2 = 0, vib = 0, t = 0, sweep = 1, id = 0, gain = 1, throw = 0},
		duck = 0,
		duckHits = {},       -- block-relative frames where a kick restarts the pump
		bus = {dryL = {}, dryR = {}, duckL = {}, duckR = {}, sendL = {}, sendR = {},
			revInL = {}, revInR = {}, wetL = {}, wetR = {}, echoL = {}, echoR = {}, throwL = {}, throwR = {}},
	}, Synth)
	self.amen, self.amenStep = renderAmen(sr, self.drums)
	self:initEffects()
	return self
end

function Synth:setComposer(composer)
	-- A new track starts from its own first bar at the next bar line; the
	-- audio already rendered keeps playing, so the change is seamless.
	self.composer = composer
	self.composerBar = 0
end

function Synth:initEffects()
	local sr = self.sr
	local function line(n)
		local t = {}
		for i = 1, n do t[i] = 0 end
		return {buf = t, n = n, i = 1, store = 0}
	end
	local scale = sr / 44100
	self.delay = {l = line(floor(0.4 * sr)), r = line(floor(0.4 * sr)), lp = 0}
	-- Freeverb-style tunings, right channel offset for width.
	self.combs, self.allpasses = {}, {}
	for _, n in ipairs({1116, 1188, 1277, 1356}) do
		table.insert(self.combs, {line(floor(n * scale)), line(floor((n + 23) * scale))})
	end
	for _, n in ipairs({556, 441}) do
		table.insert(self.allpasses, {line(floor(n * scale)), line(floor((n + 23) * scale))})
	end
end

-- Frames per 16th note and the swing delay applied to off-16ths.
function Synth:stepFrames()
	return self.sr * 60 / self.settings:value("tempo") / 4
end

local function insertEvent(events, event)
	local i = #events
	while i > 0 and events[i].frame > event.frame do i = i - 1 end
	table.insert(events, i + 1, event)
end

function Synth:scheduleBar()
	local bar = self.composer:bar(self.composerBar, self.settings)
	local start = self.nextBarFrame
	local step = self:stepFrames()
	local swing = self.settings:value("swing") * step
	-- Swing delays the off-16ths; rolls between 16ths swing with their 16th.
	-- A humanize nudge is a fraction of a step, never before the bar start.
	local function at(s, nudge)
		return math.max(start, start + floor((s + (nudge or 0)) * step + ((floor(s) % 2 == 1) and swing or 0) + 0.5))
	end
	bar.frame, bar.frames, bar.number = start, floor(16 * step + 0.5), self.barNumber
	bar.kicks, bar.snares = {}, {} -- absolute frames, for the visualizer's flashes
	for _, h in ipairs(bar.hits) do
		local frame = at(h.step, h.nudge)
		insertEvent(self.events, {frame = frame, kind = "drum", voice = h.voice, gain = h.gain, throw = h.throw})
		if h.voice == "kick" then table.insert(bar.kicks, frame) end
		if h.voice == "snare" then table.insert(bar.snares, frame) end
	end
	table.sort(bar.kicks)
	table.sort(bar.snares)
	-- Break slices sit on the straight grid: the loop carries its own feel.
	for _, b in ipairs(bar.breaks or {}) do
		insertEvent(self.events, {frame = start + floor(b.step * step + 0.5), kind = "break", slice = b.slice,
			gain = b.gain, length = floor(step + 0.5)})
	end
	for _, k in ipairs(bar.keys or {}) do
		insertEvent(self.events, {frame = at(k.step), kind = "keys", notes = k.notes, gain = k.gain,
			length = floor(k.length * step)})
	end
	for _, a in ipairs(bar.arp or {}) do
		insertEvent(self.events, {frame = at(a.step), kind = "arp", note = a.note, gain = a.gain, pan = a.pan,
			length = floor(a.length * step)})
	end
	for _, l in ipairs(bar.lead or {}) do
		insertEvent(self.events, {frame = at(l.step), kind = "lead", note = l.note, glide = l.glide, gain = l.gain,
			throw = l.throw, length = floor(l.length * step - step * 0.1)})
	end
	for _, b in ipairs(bar.bass) do
		insertEvent(self.events, {frame = at(b.step), kind = "bass", note = b.note, glide = b.glide,
			subOnly = b.subOnly, length = floor(b.length * step - step * 0.15)})
	end
	for _, s in ipairs(bar.stabs) do
		insertEvent(self.events, {frame = at(s.step), kind = "stab", notes = s.notes, throw = s.throw})
	end
	if bar.pad then
		insertEvent(self.events, {frame = start, kind = "pad", notes = bar.pad, length = 2 * bar.frames})
	end
	if bar.riser then
		insertEvent(self.events, {frame = start, kind = "riser", from = bar.riser.from, to = bar.riser.to,
			length = bar.frames})
	end
	table.insert(self.timeline, bar)
	if #self.timeline > 64 then table.remove(self.timeline, 1) end
	self.nextBarFrame = start + bar.frames
	self.barNumber = self.barNumber + 1
	self.composerBar = self.composerBar + 1
end

-- The bar sounding at an absolute frame, for the now-playing display.
function Synth:barAt(frame)
	for i = #self.timeline, 1, -1 do
		local bar = self.timeline[i]
		if frame >= bar.frame then return bar end
	end
	return self.timeline[1]
end

function Synth:startEvent(e)
	local sr = self.sr
	if e.kind == "drum" then
		local place = DRUM_PLACE[e.voice]
		local data = self.drums[e.voice]
		local g = e.gain * MIX.drums
		table.insert(self.voices, {kind = "sample", data = data, pos = 1,
			gl = g * (1 - place[1]) * 2, gr = g * place[1] * 2, send = place[2], throw = e.throw and MIX.throw or 0})
		-- The pump restarts on the kick's own frame within the block.
		if e.voice == "kick" then table.insert(self.duckHits, e.frame - self.frame + 1) end
		if e.voice == "openHat" or e.voice == "hat" then
			-- A new hat chokes a ringing open hat, like one physical cymbal.
			for _, v in ipairs(self.voices) do
				if v.data == self.drums.openHat and v.pos > 1 then v.choke = true end
			end
		end
	elseif e.kind == "bass" then
		local b = self.bass
		b.target = midiHz(e.note)
		if not e.glide or not b.gate then b.freq = b.target end
		b.gate, b.subOnly, b.reeseGain = true, e.subOnly, e.reese or 1
		b.id = b.id + 1
		insertEvent(self.events, {frame = e.frame + e.length, kind = "bassOff", id = b.id})
	elseif e.kind == "bassOff" then
		if self.bass.id == e.id then self.bass.gate = false end
	elseif e.kind == "pad" then
		for _, v in ipairs(self.voices) do
			if v.kind == "pad" then v.releasing = true end
		end
		local osc = {}
		for i, note in ipairs(e.notes) do
			local f = midiHz(note)
			table.insert(osc, {inc = f * (1 + PAD.detune) / sr, p = (i * 0.37) % 1, pan = 0.2})
			table.insert(osc, {inc = f * (1 - PAD.detune) / sr, p = (i * 0.71) % 1, pan = 0.8})
		end
		table.insert(self.voices, {kind = "pad", osc = osc, env = 0, lpL = 0, lpR = 0,
			remaining = e.length})
	elseif e.kind == "stab" then
		local osc = {}
		for i, note in ipairs(e.notes) do
			local f = midiHz(note + 12)
			table.insert(osc, {inc = f / sr, p = i * 0.21 % 1})
			table.insert(osc, {inc = f * 1.008 / sr, p = i * 0.43 % 1})
		end
		table.insert(self.voices, {kind = "stab", osc = osc, t = 0, lp = 0, throw = e.throw and MIX.throw or 0})
	elseif e.kind == "break" then
		-- Pitched to tempo like a sped-up record: a slice lasts one 16th.
		local rate = self.settings:value("tempo") / Amen.bpm
		local gain = e.gain * MIX.amen
		local v = self.breakVoice
		if v and v.next == e.slice and v.left > -BREAK.slack then
			-- The next slice in order: the loop just keeps playing. Slack
			-- absorbs the frame rounding between 16ths.
			v.left, v.gain, v.rate, v.fade = v.left + e.length, gain, rate, 1
		else
			if v then v.left = math.min(v.left, 0) end
			v = {kind = "slice", pos = e.slice * self.amenStep, rate = rate, gain = gain, left = e.length, fade = 1}
			table.insert(self.voices, v)
			self.breakVoice = v
		end
		v.next = (e.slice + 1) % Amen.slices
	elseif e.kind == "keys" then
		for _, other in ipairs(self.voices) do
			if other.kind == "keys" then other.hold = 0 end
		end
		local osc = {}
		for _, note in ipairs(e.notes) do
			local f = midiHz(note)
			table.insert(osc, {inc = f / sr, c = 0, m = 0})
		end
		table.insert(self.voices, {kind = "keys", osc = osc, t = 0, hold = e.length / sr, env = 0, rel = 1,
			gain = e.gain * MIX.keys / #osc * 2, pan = 0})
	elseif e.kind == "arp" then
		local f = midiHz(e.note)
		table.insert(self.voices, {kind = "pluck", t = 0, lp = 0, amp = 0, env = 1, sweep = 1, gain = e.gain * MIX.arp, pan = e.pan,
			hold = e.length / sr, osc = {{inc = f * (1 + PLUCK.detune) / sr, p = 0}, {inc = f * (1 - PLUCK.detune) / sr, p = 0.5}}})
	elseif e.kind == "lead" then
		local l = self.lead
		l.target = midiHz(e.note)
		if not e.glide or not l.gate then l.freq, l.t, l.sweep = l.target, 0, 1 end
		l.gate, l.gain, l.throw = true, e.gain, e.throw and MIX.throw or 0
		l.id = l.id + 1
		insertEvent(self.events, {frame = e.frame + e.length, kind = "leadOff", id = l.id})
	elseif e.kind == "leadOff" then
		if self.lead.id == e.id then self.lead.gate = false end
	elseif e.kind == "riser" then
		table.insert(self.voices, {kind = "riser", t = 0, length = e.length, from = e.from, to = e.to,
			noise = noiseSource(e.frame % 65521 + 1), lp = 0, hp = 0})
	end
end

-- Renders frames [first, last] of the bus arrays (1-based within the block).
function Synth:renderVoices(first, last)
	local sr = self.sr
	local bus = self.bus
	local dryL, dryR, duckL, duckR, sendL, sendR = bus.dryL, bus.dryR, bus.duckL, bus.duckR, bus.sendL, bus.sendR
	local throwL, throwR = bus.throwL, bus.throwR
	local voices = self.voices
	local i = 1
	while i <= #voices do
		local v = voices[i]
		local done = false
		if v.kind == "sample" then
			local data, pos, gl, gr, send, throw = v.data, v.pos, v.gl, v.gr, v.send, v.throw
			local n = #data
			local fade = v.choke and 0.995 or 1
			for k = first, last do
				if pos > n then break end
				local s = data[pos]
				if v.choke then gl, gr = gl * fade, gr * fade end
				dryL[k] = dryL[k] + s * gl
				dryR[k] = dryR[k] + s * gr
				if send > 0 then
					sendL[k] = sendL[k] + s * gl * send
					sendR[k] = sendR[k] + s * gr * send
				end
				if throw > 0 then
					throwL[k] = throwL[k] + s * gl * throw
					throwR[k] = throwR[k] + s * gr * throw
				end
				pos = pos + 1
			end
			v.pos, v.gl, v.gr = pos, gl, gr
			done = pos > n or (v.choke and gl < 1e-4)
		elseif v.kind == "pad" then
			local attack = 1 / (PAD.attack * sr)
			local release = exp(-1 / (PAD.release * sr / 5))
			local osc = v.osc
			local env, lpL, lpR = v.env, v.lpL, v.lpR
			local bright = PAD.brightness
			local g = MIX.pad
			for k = first, last do
				v.remaining = v.remaining - 1
				if v.releasing or v.remaining <= 0 then env = env * release
				elseif env < 1 then env = math.min(1, env + attack) end
				local l, r = 0, 0
				for j = 1, #osc do
					local o = osc[j]
					local p = o.p + o.inc
					if p >= 1 then p = p - 1 end
					o.p = p
					local saw = 2 * p - 1
					l = l + saw * (1 - o.pan)
					r = r + saw * o.pan
				end
				lpL = lpL + bright * (l - lpL)
				lpR = lpR + bright * (r - lpR)
				local sl, sr_ = lpL * env * g, lpR * env * g
				duckL[k] = duckL[k] + sl
				duckR[k] = duckR[k] + sr_
				sendL[k] = sendL[k] + sl * 0.6
				sendR[k] = sendR[k] + sr_ * 0.6
			end
			v.env, v.lpL, v.lpR = env, lpL, lpR
			done = (v.releasing or v.remaining <= 0) and env < 1e-4
		elseif v.kind == "stab" then
			local osc, t, lp = v.osc, v.t, v.lp
			local dt = 1 / sr
			for k = first, last do
				local env = math.min(1, t / STAB.attack) * exp(-t / STAB.decay)
				local cutoff = 0.04 + 0.5 * exp(-t / 0.05)
				local x = 0
				for j = 1, #osc do
					local o = osc[j]
					local p = o.p + o.inc
					if p >= 1 then p = p - 1 end
					o.p = p
					x = x + 2 * p - 1
				end
				lp = lp + cutoff * (x - lp)
				local s = lp * env * MIX.stab
				duckL[k] = duckL[k] + s * 0.8
				duckR[k] = duckR[k] + s * 1.2
				sendL[k] = sendL[k] + s * 1.1
				sendR[k] = sendR[k] + s * 1.1
				if v.throw > 0 then
					throwL[k] = throwL[k] + s * v.throw
					throwR[k] = throwR[k] + s * v.throw
				end
				t = t + dt
			end
			v.t, v.lp = t, lp
			done = t > STAB.decay * 8
		elseif v.kind == "slice" then
			-- Linear-interpolated resampling of the Amen loop.
			local data, n = self.amen, #self.amen
			local pos, rate, g, left, fade = v.pos, v.rate, v.gain, v.left, v.fade
			local fadeCoef = exp(-1 / (BREAK.fade * sr))
			local send = MIX.amenSend
			for k = first, last do
				if left <= 0 then
					fade = fade * fadeCoef
					if fade < 1e-3 then break end
				end
				local i = floor(pos)
				local a = data[i + 1]
				local b = data[i + 2 <= n and i + 2 or 1]
				local x = (a + (b - a) * (pos - i)) * g * fade
				dryL[k] = dryL[k] + x
				dryR[k] = dryR[k] + x
				sendL[k] = sendL[k] + x * send
				sendR[k] = sendR[k] + x * send
				pos = pos + rate
				if pos >= n then pos = pos - n end
				left = left - 1
			end
			v.pos, v.left, v.fade = pos, left, fade
			done = fade < 1e-3
			if done and self.breakVoice == v then self.breakVoice = nil end
		elseif v.kind == "keys" then
			local osc, t, env, rel = v.osc, v.t, v.env, v.rel
			local dt = 1 / sr
			local attackInc = 1 / (KEYS.attack * sr)
			local decay, release = exp(-1 / (KEYS.decay * sr)), exp(-1 / (KEYS.release * sr))
			local indexFall, tineFall = exp(-1 / (KEYS.indexDecay * sr)), exp(-1 / (KEYS.tineDecay * sr))
			local index, tine = v.index or KEYS.index, v.tine or KEYS.tine
			local panInc = KEYS.autopanRate / sr
			local pan, g, hold = v.pan, v.gain, v.hold
			local depth, ratio = KEYS.autopanDepth, KEYS.tineRatio
			local send = MIX.keysSend
			for k = first, last do
				if t < KEYS.attack then env = math.min(1, env + attackInc) else env = env * decay end
				if t >= hold then rel = rel * release end
				index, tine = index * indexFall, tine * tineFall
				local depthNow = (index + KEYS.indexFloor) / TAU
				local x = 0
				for j = 1, #osc do
					local o = osc[j]
					local m = o.m + o.inc
					if m >= 1 then m = m - 1 end
					local c = o.c + o.inc
					if c >= 1 then c = c - 1 end
					o.m, o.c = m, c
					local mod = SINE[floor(m * SINE_SIZE)]
					local phase = c + depthNow * mod
					phase = phase - floor(phase)
					x = x + SINE[floor(phase * SINE_SIZE)] + tine * SINE[floor((m * ratio) % 1 * SINE_SIZE)]
				end
				pan = pan + panInc
				if pan >= 1 then pan = pan - 1 end
				local swing = depth * SINE[floor(pan * SINE_SIZE)]
				local y = x * env * rel * g
				duckL[k] = duckL[k] + y * (1 - swing)
				duckR[k] = duckR[k] + y * (1 + swing)
				sendL[k] = sendL[k] + y * send
				sendR[k] = sendR[k] + y * send
				t = t + dt
			end
			v.t, v.env, v.rel, v.index, v.tine, v.pan = t, env, rel, index, tine, pan
			done = t > KEYS.tail or rel < 1e-3
		elseif v.kind == "pluck" then
			-- Arp pluck: two detuned saws through a low-pass that snaps shut,
			-- held for its gate then let ring into the delay. Envelopes are
			-- running products, so a pluck costs no exp() per sample.
			local o1, o2 = v.osc[1], v.osc[2]
			local p1, p2, inc1, inc2 = o1.p, o2.p, o1.inc, o2.inc
			local t, lp, amp, env, sweep = v.t, v.lp, v.amp, v.env, v.sweep
			local gl, gr = v.gain * (1 - v.pan) * 2, v.gain * v.pan * 2
			local attackInc = 1 / (PLUCK.attack * sr)
			local held, free = exp(-1 / (2 * PLUCK.decay * sr)), exp(-1 / (PLUCK.decay * sr))
			local sweepFall = exp(-1 / (PLUCK.sweep * sr))
			local hold, dt = v.hold, 1 / sr
			local sendGain = PLUCK.send
			for k = first, last do
				if amp < 1 then amp = math.min(1, amp + attackInc) end
				env = env * (t < hold and held or free)
				sweep = sweep * sweepFall
				p1, p2 = p1 + inc1, p2 + inc2
				if p1 >= 1 then p1 = p1 - 1 end
				if p2 >= 1 then p2 = p2 - 1 end
				lp = lp + (0.03 + 0.45 * sweep) * (p1 + p2 - 1 - lp)
				local x = lp * env * amp
				local xl, xr = x * gl, x * gr
				duckL[k] = duckL[k] + xl
				duckR[k] = duckR[k] + xr
				sendL[k] = sendL[k] + xl * sendGain
				sendR[k] = sendR[k] + xr * sendGain
				t = t + dt
			end
			o1.p, o2.p = p1, p2
			v.t, v.lp, v.amp, v.env, v.sweep = t, lp, amp, env, sweep
			done = t > PLUCK.tail
		elseif v.kind == "riser" then
			local noise, lp, hp = v.noise, v.lp, v.hp
			for k = first, last do
				local progress = v.from + (v.to - v.from) * (v.t / v.length)
				local n = noise()
				-- A rising low-pass over a fixed high-pass sweeps the wash upward.
				local c = 0.01 + 0.5 * progress * progress
				lp = lp + c * (n - lp)
				hp = hp + 0.02 * (lp - hp)
				local s = (lp - hp) * progress * MIX.riser
				dryL[k] = dryL[k] + s
				dryR[k] = dryR[k] + s
				sendL[k] = sendL[k] + s
				sendR[k] = sendR[k] + s
				v.t = v.t + 1
				if v.t >= v.length then break end
			end
			v.lp, v.hp = lp, hp
			done = v.t >= v.length
		end
		if done then table.remove(voices, i) else i = i + 1 end
	end
	self:renderBass(first, last)
	self:renderLead(first, last)
end

-- Monophonic lead: two detuned saws over a square an octave down, gliding
-- between tied notes, with delayed vibrato and a filter that opens on each
-- attack.
function Synth:renderLead(first, last)
	local l = self.lead
	if not l.gate and l.env < 1e-5 then return end
	local sr = self.sr
	local bus = self.bus
	local duckL, duckR, sendL, sendR, throwL, throwR = bus.duckL, bus.duckR, bus.sendL, bus.sendR, bus.throwL, bus.throwR
	local attack = 1 - exp(-1 / (LEAD.attack * sr))
	local release = exp(-1 / (LEAD.release * sr))
	local vibInc = LEAD.vibratoRate / sr
	local dt = 1 / sr
	local freq, target, env, p1, p2, sq, lp1, lp2, vib, t = l.freq, l.target, l.env, l.p1, l.p2, l.sq, l.lp1, l.lp2, l.vib, l.t
	local sweep, sweepFall = l.sweep, exp(-1 / (LEAD.sweepTime * sr))
	local g, throw = l.gain * MIX.lead, l.throw
	for k = first, last do
		freq = freq + (target - freq) * LEAD.glide
		if l.gate then env = env + (1 - env) * attack else env = env * release end
		vib = vib + vibInc
		if vib >= 1 then vib = vib - 1 end
		local bloom = (t - LEAD.vibratoDelay) * 3
		local depth = bloom <= 0 and 0 or (bloom >= 1 and LEAD.vibratoDepth or LEAD.vibratoDepth * bloom)
		local f = freq * (1 + depth * SINE[floor(vib * SINE_SIZE)]) / sr
		p1 = p1 + f * (1 + LEAD.detune)
		if p1 >= 1 then p1 = p1 - 1 end
		p2 = p2 + f * (1 - LEAD.detune)
		if p2 >= 1 then p2 = p2 - 1 end
		sq = sq + f * 0.5
		if sq >= 1 then sq = sq - 1 end
		local x = p1 + p2 - 1 + (sq < 0.5 and LEAD.square or -LEAD.square)
		sweep = sweep * sweepFall
		local c = LEAD.brightness + LEAD.sweep * sweep
		lp1 = lp1 + c * (x - lp1)
		lp2 = lp2 + c * (lp1 - lp2)
		local s = lp2 * env * g
		duckL[k] = duckL[k] + s * 0.9
		duckR[k] = duckR[k] + s * 1.1
		sendL[k] = sendL[k] + s * LEAD.send
		sendR[k] = sendR[k] + s * LEAD.send
		if throw > 0 then
			throwL[k] = throwL[k] + s * throw
			throwR[k] = throwR[k] + s * throw
		end
		t = t + dt
	end
	l.freq, l.env, l.p1, l.p2, l.sq, l.lp1, l.lp2, l.vib, l.t, l.sweep = freq, env, p1, p2, sq, lp1, lp2, vib, t, sweep
end

function Synth:renderBass(first, last)
	local b = self.bass
	if not b.gate and b.env < 1e-5 then return end
	local sr = self.sr
	local settings = self.settings
	local reeseOn = settings:enabled("reese") and not b.subOnly
	local subOn = settings:enabled("sub")
	local cutoff = settings:value("cutoff")
	local wobble = settings:value("wobble")
	local drive = 1 + settings:value("drive") * 7
	local driveNorm = 1 / softClip(drive)
	-- Wobble LFO at an eighth-note rate, synced to the tempo.
	local lfoInc = settings:value("tempo") / 60 * 2 / sr
	local attack = 1 - exp(-1 / (BASS.attack * sr))
	local release = exp(-1 / (BASS.release * sr))
	local duckL, duckR = self.bus.duckL, self.bus.duckR
	local freq, target, env, p1, p2, sub = b.freq, b.target, b.env, b.p1, b.p2, b.sub
	local lp, bp, coef, lfo, tick = b.lp, b.bp, b.coef, b.lfo, b.tick
	local base = BASS.minCutoff * 2 ^ (cutoff * BASS.cutoffOctaves)
	for k = first, last do
		freq = freq + (target - freq) * BASS.glide
		if b.gate then env = env + (1 - env) * attack else env = env * release end
		lfo = lfo + lfoInc
		if lfo >= 1 then lfo = lfo - 1 end
		-- A running tick, not the block index, keeps any block split identical.
		tick = tick + 1
		if tick >= BASS.controlRate then
			tick = 0
			local mod = wobble * BASS.wobbleOctaves * (SINE[floor(lfo * SINE_SIZE)] - 1) * 0.5
			local fc = math.min(base * 2 ^ mod, sr * 0.2)
			coef = 2 * sin(pi * fc / sr)
		end
		local s = 0
		if reeseOn then
			p1 = p1 + freq * (1 + BASS.detune) / sr
			if p1 >= 1 then p1 = p1 - 1 end
			p2 = p2 + freq * (1 - BASS.detune) / sr
			if p2 >= 1 then p2 = p2 - 1 end
			local x = p1 + p2 - 1
			-- Chamberlin state-variable low-pass.
			lp = lp + coef * bp
			local hp = x - lp - 0.7 * bp
			bp = bp + coef * hp
			s = softClip(lp * drive) * driveNorm * MIX.reese * b.reeseGain
		end
		sub = sub + freq / sr
		if sub >= 1 then sub = sub - 1 end
		if subOn then s = s + SINE[floor(sub * SINE_SIZE)] * MIX.sub end
		s = s * env
		duckL[k] = duckL[k] + s
		duckR[k] = duckR[k] + s
	end
	b.freq, b.env, b.p1, b.p2, b.sub, b.lp, b.bp, b.coef, b.lfo, b.tick = freq, env, p1, p2, sub, lp, bp, coef, lfo, tick
end

-- Runs one delay line over a block. Combs are parallel and all-passes are
-- in series, so each can process the whole block in turn with its state in
-- locals, which is several times faster than interleaving them per sample.
local function comb(line, input, output, count)
	local buf, n, i, store = line.buf, line.n, line.i, line.store
	for k = 1, count do
		local y = buf[i]
		store = y * 0.6 + store * 0.4
		buf[i] = input[k] + store * 0.82
		i = i + 1
		if i > n then i = 1 end
		output[k] = output[k] + y
	end
	line.i, line.store = i, store
end

local function allpass(line, signal, count)
	local buf, n, i = line.buf, line.n, line.i
	for k = 1, count do
		local b = buf[i]
		local x = signal[k]
		buf[i] = x + b * 0.5
		i = i + 1
		if i > n then i = 1 end
		signal[k] = b - x
	end
	line.i = i
end

-- Master section: sidechain, send effects, soft clip and volume.
function Synth:mixdown(out, count)
	local sr = self.sr
	local bus = self.bus
	local settings = self.settings
	local space = settings:value("space")
	local volume = settings:value("volume") * MIX.master
	local duckRelease = exp(-1 / (MIX.duckRelease * sr))
	local delay = self.delay
	local dl, dr = delay.l, delay.r
	local bufL, bufR, n, wi, dlp = dl.buf, dr.buf, dl.n, dl.i, delay.lp
	local delayFrames = math.min(n - 1, floor(self:stepFrames() * 3 + 0.5)) -- dotted eighth
	local delaySend, reverbSend = space * MIX.delaySend, space * MIX.reverbSend * 0.1
	local feedback = MIX.delayFeedback
	local sendL, sendR, throwL, throwR = bus.sendL, bus.sendR, bus.throwL, bus.throwR
	local revInL, revInR, wetL, wetR = bus.revInL, bus.revInR, bus.wetL, bus.wetR
	local echoesL, echoesR = bus.echoL, bus.echoR
	-- Ping-pong delay: the feedback crosses channels each sample.
	for k = 1, count do
		local ri = wi - delayFrames
		if ri < 1 then ri = ri + n end
		local echoL, echoR = bufL[ri], bufR[ri]
		dlp = dlp + 0.35 * (echoR - dlp)
		-- Throws enter the delay whatever the Space setting: a dub echo on
		-- one snare or phrase end is an arrangement move, not ambience.
		bufL[wi] = sendL[k] * delaySend + throwL[k] + dlp * feedback
		bufR[wi] = sendR[k] * delaySend * 0.3 + throwR[k] * 0.5 + echoL * feedback
		wi = wi + 1
		if wi > n then wi = 1 end
		echoesL[k], echoesR[k] = echoL, echoR
		revInL[k] = (sendL[k] + echoL * 0.3) * reverbSend
		revInR[k] = (sendR[k] + echoR * 0.3) * reverbSend
		wetL[k], wetR[k] = 0, 0
	end
	dl.i, dr.i, delay.lp = wi, wi, dlp
	for _, pair in ipairs(self.combs) do
		comb(pair[1], revInL, wetL, count)
		comb(pair[2], revInR, wetR, count)
	end
	for _, pair in ipairs(self.allpasses) do
		allpass(pair[1], wetL, count)
		allpass(pair[2], wetR, count)
	end
	local dryL, dryR, duckL, duckR = bus.dryL, bus.dryR, bus.duckL, bus.duckR
	local depth = MIX.duckDepth
	local duck = self.duck
	local hits, nextHit = self.duckHits, 1
	for k = 1, count do
		duck = duck * duckRelease
		while hits[nextHit] and hits[nextHit] <= k do duck, nextHit = 1, nextHit + 1 end
		local g = 1 - depth * duck
		out[2 * k - 1] = softClip((dryL[k] + duckL[k] * g + echoesL[k] + wetL[k]) * volume)
		out[2 * k] = softClip((dryR[k] + duckR[k] * g + echoesR[k] + wetR[k]) * volume)
	end
	self.duck = duck
	for i = #hits, 1, -1 do hits[i] = nil end
end

-- Renders `frames` interleaved stereo frames into out[1 .. 2 * frames].
function Synth:render(out, frames)
	assert(self.composer, "Synth:render requires a composer")
	local bus = self.bus
	for k = 1, frames do
		bus.dryL[k], bus.dryR[k], bus.duckL[k], bus.duckR[k], bus.sendL[k], bus.sendR[k] = 0, 0, 0, 0, 0, 0
		bus.throwL[k], bus.throwR[k] = 0, 0
	end
	local blockStart = self.frame
	local blockEnd = blockStart + frames
	local cursor = 1
	while true do
		while self.nextBarFrame < blockEnd do self:scheduleBar() end
		local event = self.events[1]
		local stop = (event and event.frame < blockEnd) and (event.frame - blockStart + 1) or (frames + 1)
		if stop > cursor then
			self:renderVoices(cursor, stop - 1)
			cursor = stop
		end
		if not event or event.frame >= blockEnd then break end
		table.remove(self.events, 1)
		self:startEvent(event)
	end
	self:mixdown(out, frames)
	self.frame = blockEnd
end

return Synth
