-- Sample-accurate Lua synthesizer for the Composer's bars. `render(out, n)`
-- writes n interleaved stereo frames into `out`; it has no IO, so the same
-- code feeds the speakers and the headless tests. Drums are one-shots
-- rendered once at construction; bass, pads and stabs are running voices.
-- Tempo and swing are read at each bar boundary, sound controls every block.
local Synth = {}
Synth.__index = Synth

local sin, exp, floor, pi = math.sin, math.exp, math.floor, math.pi
local TAU = 2 * pi

-- Mix and voice constants in one place so the balance can be tuned by ear.
local MIX = {
	drums = 0.9, sub = 0.55, reese = 0.34, pad = 0.05, stab = 0.07, riser = 0.18,
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
	shot("shaker", 0.09, function(t, s)
		local n = noise()
		local hp = n - (s.prev or 0)
		s.prev = n
		return hp * math.min(1, t / 0.012) * exp(-t / 0.03) * 0.5
	end)
	drums.ghost = drums.snare
	return drums
end

-- Stereo placement per drum voice: {pan (0 left, 1 right), effect send}.
local DRUM_PLACE = {
	kick = {0.5, 0}, snare = {0.5, 0.35}, ghost = {0.46, 0.25}, hat = {0.62, 0.05},
	openHat = {0.62, 0.15}, ride = {0.36, 0.2}, crash = {0.44, 0.3},
	rim = {0.3, 0.3}, conga = {0.7, 0.25}, shaker = {0.76, 0.2},
}

function Synth.new(settings, sampleRate)
	local sr = sampleRate or 44100
	local self = setmetatable({
		settings = settings, sr = sr,
		drums = renderDrums(sr),
		frame = 0,           -- next frame to render
		nextBarFrame = 0,    -- where the next bar starts
		barNumber = 0,       -- timeline bar count across track changes
		composerBar = 0,     -- bar index within the current composer
		timeline = {},       -- recent {frame, bar} for the playhead
		events = {},         -- scheduled, sorted by frame
		voices = {},         -- active one-shot and chord voices
		bass = {freq = 55, target = 55, gate = false, env = 0, p1 = 0, p2 = 0, p3 = 0, sub = 0,
			lp = 0, bp = 0, coef = 0.1, lfo = 0, tick = 0, id = 0},
		duck = 0,
		bus = {dryL = {}, dryR = {}, duckL = {}, duckR = {}, sendL = {}, sendR = {},
			revInL = {}, revInR = {}, wetL = {}, wetR = {}, echoL = {}, echoR = {}},
	}, Synth)
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
	local function at(s)
		return start + floor(s * step + ((s % 2 == 1) and swing or 0) + 0.5)
	end
	bar.frame, bar.frames, bar.number = start, floor(16 * step + 0.5), self.barNumber
	bar.kicks = {} -- absolute frames, for the visualizer's kick flashes
	for _, h in ipairs(bar.hits) do
		insertEvent(self.events, {frame = at(h.step), kind = "drum", voice = h.voice, gain = h.gain})
		if h.voice == "kick" then table.insert(bar.kicks, at(h.step)) end
	end
	table.sort(bar.kicks)
	for _, b in ipairs(bar.bass) do
		insertEvent(self.events, {frame = at(b.step), kind = "bass", note = b.note, glide = b.glide,
			subOnly = b.subOnly, length = floor(b.length * step - step * 0.15)})
	end
	for _, s in ipairs(bar.stabs) do
		insertEvent(self.events, {frame = at(s.step), kind = "stab", notes = s.notes})
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
			gl = g * (1 - place[1]) * 2, gr = g * place[1] * 2, send = place[2]})
		if e.voice == "kick" then self.duck = 1 end
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
		b.gate, b.subOnly = true, e.subOnly
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
		table.insert(self.voices, {kind = "stab", osc = osc, t = 0, lp = 0})
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
	local voices = self.voices
	local i = 1
	while i <= #voices do
		local v = voices[i]
		local done = false
		if v.kind == "sample" then
			local data, pos, gl, gr, send = v.data, v.pos, v.gl, v.gr, v.send
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
				t = t + dt
			end
			v.t, v.lp = t, lp
			done = t > STAB.decay * 8
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
			s = softClip(lp * drive) * driveNorm * MIX.reese
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
	local sendL, sendR = bus.sendL, bus.sendR
	local revInL, revInR, wetL, wetR = bus.revInL, bus.revInR, bus.wetL, bus.wetR
	local echoesL, echoesR = bus.echoL, bus.echoR
	-- Ping-pong delay: the feedback crosses channels each sample.
	for k = 1, count do
		local ri = wi - delayFrames
		if ri < 1 then ri = ri + n end
		local echoL, echoR = bufL[ri], bufR[ri]
		dlp = dlp + 0.35 * (echoR - dlp)
		bufL[wi] = sendL[k] * delaySend + dlp * feedback
		bufR[wi] = sendR[k] * delaySend * 0.3 + echoL * feedback
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
	for k = 1, count do
		duck = duck * duckRelease
		local g = 1 - depth * duck
		out[2 * k - 1] = softClip((dryL[k] + duckL[k] * g + echoesL[k] + wetL[k]) * volume)
		out[2 * k] = softClip((dryR[k] + duckR[k] * g + echoesR[k] + wetR[k]) * volume)
	end
	self.duck = duck
end

-- Renders `frames` interleaved stereo frames into out[1 .. 2 * frames].
function Synth:render(out, frames)
	assert(self.composer, "Synth:render requires a composer")
	local bus = self.bus
	for k = 1, frames do
		bus.dryL[k], bus.dryR[k], bus.duckL[k], bus.duckR[k], bus.sendL[k], bus.sendR[k] = 0, 0, 0, 0, 0, 0
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
