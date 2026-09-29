-- One instrument for every pitched channel. A patch (library/Patches.lua)
-- is plain data, as an instrument is in a tracker module or a preset in a
-- synthesizer: oscillators, a resonant filter with its envelope and LFO, an
-- amplitude envelope, drive, a sub and how wide it sits. A voice plays one
-- note or a chord through one filter; a mono patch keeps one voice and
-- glides between notes. Every track of a set picks its own patches, so the
-- bass, the pad and the lead of one tune are not those of the next.
--
--   {id = "reese", name = "Reese", role = "bass", mono = true, glide = 0.06,
--    osc = {{wave = "saw", detune = 0.0045}, {wave = "saw", detune = -0.0045}},
--    filter = {cutoff = 480, resonance = 0.7, lfo = 3, rate = 2},
--    amp = {attack = 0.004, release = 0.03}, sub = 1.6, drive = 0.35, level = 0.3}
--
-- Oscillator waves: saw, square, pulse (`width`), triangle, sine (with
-- `fm = {ratio, index, decay, floor}` a two-operator FM pair), noise and
-- string (a plucked string: a delay line one period long, fed a burst of
-- noise). `pitch` bends a note onto its pitch (`env` semitones, falling
-- over `decay`) or up through a rise; `swell` and the filter's `sweep`
-- follow a rise too, which a riser is made of. Pitch, the filter and slow envelopes move at control rate, every
-- CONTROL frames counted from the voice's first, so a render is the same in
-- blocks of any size.
local Instrument = {}

local sin, exp, floor, pi = math.sin, math.exp, math.floor, math.pi
local TAU = 2 * pi
local CONTROL = 32
local SINE_SIZE = 4096
local SINE = {}
for i = 0, SINE_SIZE do SINE[i] = sin(TAU * i / SINE_SIZE) end
Instrument.sine, Instrument.sineSize = SINE, SINE_SIZE

-- The filter stays stable below a fifth of the sample rate, and while its
-- coefficient and its damping together stay under `stable`.
local LIMITS = {cutoff = 0.2, floor = 20, silence = 1e-3, tail = 12, stable = 1.8}

local WAVES = {saw = true, square = true, pulse = true, triangle = true, sine = true, noise = true, string = true}
local FILTERS = {lowpass = true, bandpass = true, highpass = true}

local FIELDS = {
	patch = {id = "string", name = "string", role = "string", osc = "table", filter = "table", amp = "table",
		pitch = "table", vibrato = "table", autopan = "table", mono = "boolean", glide = "number", drive = "number",
		sub = "number", subOctave = "number", spread = "number", level = "number", send = "number",
		octave = "number", swell = "boolean"},
	osc = {wave = "string", octave = "number", semi = "number", detune = "number", level = "number",
		width = "number", decay = "number", fm = "table", ring = "number", bright = "number"},
	fm = {ratio = "number", index = "number", decay = "number", floor = "number"},
	filter = {kind = "string", cutoff = "number", track = "number", resonance = "number", env = "number",
		decay = "number", lfo = "number", rate = "number", retrigger = "boolean", sweep = "number"},
	amp = {attack = "number", decay = "number", sustain = "number", release = "number"},
	pitch = {env = "number", decay = "number", rise = "number"},
	vibrato = {rate = "number", depth = "number", delay = "number"},
	autopan = {rate = "number", depth = "number"},
}

local function softClip(x)
	if x > 3 then return 1 elseif x < -3 then return -1 end
	local x2 = x * x
	return x * (27 + x2) / (27 + 9 * x2)
end

local function midiHz(m) return 440 * 2 ^ ((m - 69) / 12) end
Instrument.midiHz = midiHz

local function check(where, fields, kinds)
	for key, value in pairs(fields) do
		local kind = kinds[key]
		if not kind then error(where .. " has unknown field " .. tostring(key), 0) end
		if type(value) ~= kind then error(where .. " field " .. key .. " must be a " .. kind, 0) end
	end
end

--- Checks a patch and fills in what it leaves out. Patches are plain data;
--- the result is a new table, the one voices play.
function Instrument.patch(spec)
	local where = "patch " .. tostring(spec.id)
	check(where, spec, FIELDS.patch)
	assert(type(spec.id) == "string", "a patch needs an id")
	local patch = {id = spec.id, name = spec.name or spec.id, role = spec.role,
		mono = spec.mono == true, glide = spec.glide or 0, drive = spec.drive or 0,
		sub = spec.sub or 0, subOctave = spec.subOctave or 0, spread = spec.spread or 0,
		level = spec.level or 1, send = spec.send or 0, octave = spec.octave or 0, swell = spec.swell == true,
		osc = {}}
	assert(#(spec.osc or {}) > 0 or patch.sub > 0, where .. " needs an oscillator")
	for i, osc in ipairs(spec.osc or {}) do
		check(where .. " oscillator " .. i, osc, FIELDS.osc)
		assert(WAVES[osc.wave], where .. " has unknown wave " .. tostring(osc.wave))
		local o = {wave = osc.wave, level = osc.level or 1, width = osc.width or 0.5, decay = osc.decay,
			ratio = 2 ^ ((osc.octave or 0) + (osc.semi or 0) / 12) * (1 + (osc.detune or 0)),
			ring = osc.ring or 1.2, bright = osc.bright or 0.6}
		-- Oscillators of a wide patch sit alternately left and right.
		o.right = patch.spread > 0 and i % 2 == 0
		if osc.fm then
			assert(osc.wave == "sine", where .. ": only a sine takes FM")
			check(where .. " FM", osc.fm, FIELDS.fm)
			o.fm = {ratio = osc.fm.ratio or 1, index = osc.fm.index or 1, decay = osc.fm.decay,
				floor = osc.fm.floor or 0}
		end
		table.insert(patch.osc, o)
	end
	patch.stereo = patch.spread > 0 and #patch.osc > 1
	if spec.filter then
		check(where .. " filter", spec.filter, FIELDS.filter)
		local f = spec.filter
		assert(f.kind == nil or FILTERS[f.kind], where .. " has unknown filter " .. tostring(f.kind))
		assert((f.resonance or 1) > 0 and (f.resonance or 1) <= 1.4, where .. " filter damping lies within 0…1.4")
		patch.filter = {kind = f.kind or "lowpass", cutoff = f.cutoff or 2000, track = f.track or 0,
			resonance = f.resonance or 1, env = f.env or 0, decay = f.decay or 0.2, lfo = f.lfo or 0,
			rate = f.rate or 2, retrigger = f.retrigger == true, sweep = f.sweep or 0}
	end
	local amp = spec.amp or {}
	check(where .. " amp", amp, FIELDS.amp)
	patch.amp = {attack = amp.attack or 0.004, decay = amp.decay or 0.3, sustain = amp.sustain or 1,
		release = amp.release or 0.08}
	if spec.pitch then
		check(where .. " pitch", spec.pitch, FIELDS.pitch)
		patch.pitch = {env = spec.pitch.env or 0, decay = spec.pitch.decay or 0.05, rise = spec.pitch.rise or 0}
	end
	if spec.vibrato then
		check(where .. " vibrato", spec.vibrato, FIELDS.vibrato)
		patch.vibrato = {rate = spec.vibrato.rate or 5, depth = spec.vibrato.depth or 0.006,
			delay = spec.vibrato.delay or 0.15}
	end
	if spec.autopan then
		check(where .. " autopan", spec.autopan, FIELDS.autopan)
		patch.autopan = {rate = spec.autopan.rate or 4, depth = spec.autopan.depth or 0.3}
		patch.stereo = true
	end
	return patch
end

-- A reproducible noise state for a voice.
local function seedOf(n) return (n * 2654435761 + 12345) & 0x7FFFFFFF end

local function fall(seconds, sr, frames)
	return exp(-(frames or 1) / (math.max(seconds, 1e-4) * sr))
end

local function oscillator(o, freq, sr, seed)
	local state = {wave = o.wave, spec = o, base = freq, p = (seed % 97) / 97, env = 1, gain = o.level,
		right = o.right, width = o.width,
		fall = o.decay and fall(o.decay, sr, CONTROL) or 1, step = freq * o.ratio / sr}
	if o.fm then
		state.wave = "fm"
		state.mp, state.ienv = 0, 1
		state.ifall = o.fm.decay and fall(o.fm.decay, sr, CONTROL) or 1
		state.idx = (o.fm.index + o.fm.floor) / TAU
	elseif o.wave == "noise" then
		state.noise = seedOf(seed + 17)
	elseif o.wave == "string" then
		-- The loop's averaging filter delays by half a frame; the line
		-- holds the rest of the period, read between two frames.
		local period = sr / (freq * o.ratio) - 0.5
		local n = math.max(2, floor(period))
		state.n, state.frac, state.i = n, period - n, 1
		-- Level lost per period, for a ring of `ring` seconds to −60 dB.
		state.loss = 0.001 ^ (1 / (freq * o.ratio * o.ring))
		local buf, noise, lp = {}, seedOf(seed + 5), 0
		for i = 1, n + 1 do
			noise = (noise * 1103515245 + 12345) & 0x7FFFFFFF
			lp = lp + o.bright * (noise / 0x3FFFFFFF - 1 - lp)
			buf[i] = lp
		end
		state.buf = buf
	end
	return state
end

--- A voice of `patch` playing `notes` (MIDI numbers: one, or a chord
--- through one filter). `options`: `sr`; `hold`, the frames until it is
--- released; `gain`; `seed` (the frame it starts on, for its noise);
--- `accent` (opens the filter envelope further); `rate` (the LFO's cycles
--- per beat, over the patch's); `from` and `to`, how far through a rise it
--- starts and ends (a riser over several bars); `phase`, where a
--- free-running LFO stands.
function Instrument.voice(patch, notes, options)
	local sr = options.sr
	local v = {patch = patch, sr = sr, tick = 0, hold = options.hold, gain = (options.gain or 1) * patch.level,
		env = 0, stage = "attack", lp = 0, bp = 0, lp2 = 0, bp2 = 0, f = 0.1, fenv = 1, penv = 1, vib = 0,
		pan = 0, panL = 1, panR = 1, subp = 0, accent = options.accent and 2 or 1, boost = options.accent and 1.3 or 1,
		rate = options.rate, from = options.from or 0, to = options.to or 1, progress = options.from or 0,
		throw = options.throw or 0, oscs = {}, mult = 1, seed = options.seed or 0}
	local transpose = 12 * patch.octave
	v.note = notes[1] + transpose
	v.freq = midiHz(v.note)
	v.target = v.freq
	for j, note in ipairs(notes) do
		local freq = midiHz(note + transpose)
		for i, o in ipairs(patch.osc) do
			table.insert(v.oscs, oscillator(o, freq, sr, (options.seed or 0) + j * 31 + i * 7))
		end
	end
	-- Several notes share the voice's level, so a chord is no louder than a note.
	v.gain = v.gain / math.sqrt(#notes)
	local amp = patch.amp
	v.attack = 1 / math.max(1, amp.attack * sr)
	v.decay = fall(amp.decay, sr)
	v.release = fall(amp.release, sr)
	local filter = patch.filter
	if filter then
		v.ffall = fall(filter.decay, sr, CONTROL)
		v.lfo = filter.retrigger and 0.75 or (options.phase or 0) % 1
	end
	if patch.pitch then v.pfall = fall(patch.pitch.decay, sr, CONTROL) end
	if patch.glide > 0 then v.glide = 1 - fall(patch.glide, sr, CONTROL) else v.glide = 1 end
	return v
end

--- A mono voice takes its next note: tied (`glide`) it slides to the pitch
--- and plays on; otherwise the envelopes start again from where they are.
function Instrument.retarget(v, note, options)
	local patch = v.patch
	local sounding = v.tick < v.hold or v.env > LIMITS.silence
	v.note = note + 12 * patch.octave
	v.target = midiHz(v.note)
	if not (options.glide and sounding) then
		v.freq = v.target
		v.stage, v.fenv, v.penv = "attack", 1, 1
		v.accent = options.accent and 2 or 1
		if patch.filter and patch.filter.retrigger then v.lfo = 0.75 end
		v.started = v.tick
	end
	v.boost = options.accent and 1.3 or 1
	v.rate = options.rate
	v.gain = (options.gain or 1) * patch.level
	v.throw = options.throw or 0
	v.hold = v.tick + options.hold
	v.from, v.to = options.from or 0, options.to or 1
end

--- Whether a voice still sounds.
function Instrument.sounding(v)
	return v.tick < v.hold or v.env > LIMITS.silence
end

-- The values that move slowly, every CONTROL frames.
local function control(v, ctx)
	local patch, sr = v.patch, v.sr
	local span = v.hold - (v.started or 0)
	local through = span > 0 and math.min(1, (v.tick - (v.started or 0)) / span) or 1
	v.progress = v.from + (v.to - v.from) * through
	if patch.mono then v.freq = v.freq + (v.target - v.freq) * v.glide end
	local mult = 1
	if patch.pitch then
		mult = 2 ^ ((patch.pitch.env * v.penv + patch.pitch.rise * v.progress) / 12)
		v.penv = v.penv * v.pfall
	end
	local vibrato = patch.vibrato
	if vibrato then
		local since = (v.tick - (v.started or 0)) / sr
		local bloom = math.max(0, math.min(1, (since - vibrato.delay) * 3))
		v.vib = (v.vib + vibrato.rate * CONTROL / sr) % 1
		mult = mult * (1 + vibrato.depth * bloom * SINE[v.vib * SINE_SIZE // 1])
	end
	for _, o in ipairs(v.oscs) do
		o.step = (patch.mono and v.freq or o.base) * o.spec.ratio * mult / sr
		o.gain = o.spec.level * o.env
		o.env = o.env * o.fall
		-- A partial that has died away (an electric piano's tine) costs
		-- nothing more.
		o.spent = o.env < LIMITS.silence
		if o.wave == "fm" then
			o.idx = (o.spec.fm.index * o.ienv + o.spec.fm.floor) / TAU
			o.ienv = o.ienv * o.ifall
		end
	end
	local filter = patch.filter
	if filter then
		local octaves = filter.track * (v.note - 60) / 12 + filter.env * v.fenv * v.accent
			+ filter.sweep * v.progress + (ctx.shift or 0)
		if filter.lfo ~= 0 then
			octaves = octaves + filter.lfo * (ctx.wobble or 1) * (SINE[v.lfo * SINE_SIZE // 1] - 1) * 0.5
			v.lfo = (v.lfo + ctx.tempo / 60 * (v.rate or filter.rate) * CONTROL / sr) % 1
		end
		v.fenv = v.fenv * v.ffall
		local fc = math.max(LIMITS.floor, math.min(filter.cutoff * 2 ^ octaves, sr * LIMITS.cutoff))
		v.f = math.min(2 * sin(pi * fc / sr), LIMITS.stable - filter.resonance)
	end
	local autopan = patch.autopan
	if autopan then
		v.pan = (v.pan + autopan.rate * CONTROL / sr) % 1
		local swing = autopan.depth * SINE[v.pan * SINE_SIZE // 1]
		v.panL, v.panR = 1 - swing, 1 + swing
	end
	v.swell = patch.swell and v.progress or 1
end

-- One oscillator over frames [first, last] of a scratch buffer.
local function run(o, out, first, last)
	local wave = o.wave
	local p, step, gain = o.p, o.step, o.gain
	if wave == "saw" then
		for k = first, last do
			p = p + step
			if p >= 1 then p = p - 1 end
			out[k] = out[k] + (2 * p - 1) * gain
		end
	elseif wave == "square" or wave == "pulse" then
		local width = wave == "square" and 0.5 or o.width
		for k = first, last do
			p = p + step
			if p >= 1 then p = p - 1 end
			out[k] = out[k] + (p < width and gain or -gain)
		end
	elseif wave == "triangle" then
		for k = first, last do
			p = p + step
			if p >= 1 then p = p - 1 end
			out[k] = out[k] + (p < 0.5 and 4 * p - 1 or 3 - 4 * p) * gain
		end
	elseif wave == "sine" then
		for k = first, last do
			p = p + step
			if p >= 1 then p = p - 1 end
			out[k] = out[k] + SINE[p * SINE_SIZE // 1] * gain
		end
	elseif wave == "fm" then
		local mp, mstep, idx = o.mp, step * o.spec.fm.ratio, o.idx
		for k = first, last do
			p = p + step
			if p >= 1 then p = p - 1 end
			mp = mp + mstep
			if mp >= 1 then mp = mp - mp // 1 end
			local phase = p + idx * SINE[mp * SINE_SIZE // 1]
			phase = phase - phase // 1
			out[k] = out[k] + SINE[phase * SINE_SIZE // 1] * gain
		end
		o.mp = mp
	elseif wave == "noise" then
		local noise = o.noise
		for k = first, last do
			noise = (noise * 1103515245 + 12345) & 0x7FFFFFFF
			out[k] = out[k] + (noise / 0x3FFFFFFF - 1) * gain
		end
		o.noise = noise
	elseif wave == "string" then
		local buf, n, i, frac, loss = o.buf, o.n, o.i, o.frac, o.loss
		for k = first, last do
			local j = i + 1
			if j > n + 1 then j = 1 end
			local a, b = buf[i], buf[j]
			buf[i] = (a + b) * 0.5 * loss
			i = j
			out[k] = out[k] + (a + (b - a) * frac) * gain
		end
		o.i = i
	end
	o.p = p
end

-- A stretch of at most CONTROL frames: the oscillators into the scratch
-- buffers (one, or one a side for a wide patch), then the filter, drive,
-- sub and envelope into the channel.
local function stretch(v, ctx, first, last, out)
	local patch, sr = v.patch, v.sr
	local left, right = ctx.scratchL, ctx.scratchR
	local stereo = patch.stereo
	for k = first, last do left[k] = 0 end
	if stereo then
		for k = first, last do right[k] = 0 end
	end
	for _, o in ipairs(v.oscs) do
		if not o.spent then run(o, (stereo and o.right) and right or left, first, last) end
	end
	local filter = patch.filter
	local kind = filter and filter.kind
	local f, q = v.f, filter and filter.resonance or 1
	local lp, bp, lp2, bp2 = v.lp, v.bp, v.lp2, v.bp2
	local drive = patch.drive * (ctx.drive or 1)
	local gainIn = 1 + drive * 7
	local norm = drive > 0 and 1 / softClip(gainIn) or 1
	local sub, subStep = patch.sub, 0
	local subp = v.subp
	if sub > 0 then subStep = (patch.mono and v.freq or v.oscs[1] and v.oscs[1].base or v.freq) * 2 ^ patch.subOctave / sr end
	local env, stage, tick, hold = v.env, v.stage, v.tick, v.hold
	local attack, decay, release, sustain = v.attack, v.decay, v.release, patch.amp.sustain
	local gain = v.gain * v.boost * v.swell
	local gl, gr = gain * v.panL, gain * v.panR
	-- How far apart the two sides of a wide patch sit.
	local near, far = 1 + patch.spread, 1 - patch.spread
	local outL, outR, throwL, throwR, throw = out.left, out.right, out.throwL, out.throwR, v.throw
	for k = first, last do
		if tick >= hold then
			env = env * release
		elseif stage == "attack" then
			env = env + attack
			if env >= 1 then env, stage = 1, "decay" end
		else
			env = sustain + (env - sustain) * decay
		end
		tick = tick + 1
		local l = left[k]
		local r
		if filter then
			lp = lp + f * bp
			local hp = l - lp - q * bp
			bp = bp + f * hp
			l = kind == "lowpass" and lp or (kind == "bandpass" and bp or hp)
		end
		if stereo then
			r = right[k]
			if filter then
				lp2 = lp2 + f * bp2
				local hp2 = r - lp2 - q * bp2
				bp2 = bp2 + f * hp2
				r = kind == "lowpass" and lp2 or (kind == "bandpass" and bp2 or hp2)
			end
			l, r = l * near + r * far, r * near + l * far
			if drive > 0 then l, r = softClip(l * gainIn) * norm, softClip(r * gainIn) * norm end
		else
			if drive > 0 then l = softClip(l * gainIn) * norm end
			r = l
		end
		if sub > 0 then
			subp = subp + subStep
			if subp >= 1 then subp = subp - 1 end
			local s = SINE[subp * SINE_SIZE // 1] * sub
			l, r = l + s, r + s
		end
		l, r = l * env * gl, r * env * gr
		outL[k] = outL[k] + l
		outR[k] = outR[k] + r
		if throw > 0 then
			throwL[k] = throwL[k] + l * throw
			throwR[k] = throwR[k] + r * throw
		end
	end
	v.env, v.stage, v.tick = env, stage, tick
	v.lp, v.bp, v.lp2, v.bp2, v.subp = lp, bp, lp2, bp2, subp
end

--- Renders frames [first, last] of a voice into `out` ({left, right,
--- throwL, throwR}, added to). `ctx` carries `tempo` (for a synced LFO),
--- the scratch buffers and, for the bass, what the Sound sliders ask:
--- `shift` (octaves of cutoff), `wobble` and `drive` (scales). Returns
--- whether the voice has finished.
function Instrument.render(v, first, last, out, ctx)
	local k = first
	while k <= last do
		local phase = v.tick % CONTROL
		if phase == 0 then control(v, ctx) end
		local stop = math.min(last, k + CONTROL - phase - 1)
		stretch(v, ctx, k, stop, out)
		k = stop + 1
	end
	if v.tick < v.hold then return false end
	return v.env < LIMITS.silence or v.tick > v.hold + LIMITS.tail * v.sr
end

return Instrument
