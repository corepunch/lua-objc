-- The player: a tracker's eight channels, sample-accurate, in Lua. It asks
-- the composer for one bar of score at a time (the format is documented in
-- host/StyleKit.lua) and plays it on the track's channels: drum channels
-- play slices of a loop and one-shots from the kit (models/Drums.lua),
-- pitched channels play voices of the track's patches
-- (models/Instrument.lua). Every channel ends in a strip, as on a mixing
-- desk: the fade or filter sweep its block rides, its fader, then the mix
-- bus, the sidechain, the sends and the delay throw.
--
-- `render(out, n)` writes n interleaved stereo frames into `out`; it has no
-- IO, so the same code feeds the speakers and the headless tests. Tempo and
-- swing belong to the track and are read at each bar line; the Pitch fader
-- moves the tempo as a turntable's does, and a loop's pitch with it.
local Drums = require("apps.dnb.models.Drums")
local Instrument = require("apps.dnb.models.Instrument")
local Model = require("apps.dnb.Model")

local Synth = {}
Synth.__index = Synth

local exp, floor = math.exp, math.floor
local TAU = 2 * math.pi
local softClip = Drums.softClip

-- The balance every style starts from; a style's `mix` overrides any field
-- and keeps the rest. A role's level scales its channel over the patch's own.
local DEFAULT_MIX = {
	drums = 0.9, tops = 0.85, bass = 1, pad = 1, keys = 1, stab = 1, arp = 1, lead = 1, counter = 1,
	texture = 1, fx = 1,
	throw = 0.9,                          -- dub echo send, independent of Space
	drumSend = 0.1,                       -- a drum channel's share of the effects
	duckDepth = 0.45, duckRelease = 0.12, -- sidechain pump from each kick
	delaySend = 0.55, reverbSend = 0.8, delayFeedback = 0.38,
	delaySteps = 3,                       -- a dotted eighth
	master = 0.9,
}

-- A block's filter sweep (host/Arrangement.lua) as a one-pole filter on the
-- channel: the corner each kind reaches fully closed, and the octaves to
-- wide open. Its corner moves every `rate` frames.
local SWEEP = {lowpass = {corner = 120, octaves = 7.2}, highpass = {corner = 3900, octaves = -7.6}, rate = 32}
-- A slice cut short fades over a few milliseconds, as a sampler's declick
-- does; `slack` absorbs the frame rounding between 16ths.
local SLICE = {fade = 0.003, slack = 16}
-- What the Sound sliders ask of the bass: octaves of cutoff either side of
-- the patch's own, around the slider's middle.
local SOUND = {cutoffOctaves = 2.5, middle = 0.5}
-- The Mix faders scale the style's own balance, by the family of a role;
-- Pump scales the sidechain depth, which never closes the gate completely.
local MAX_DUCK = 0.95
-- A channel's level meter falls by this much a second.
local METER = {fall = 3}
-- The loops a track will play are prepared ahead, so that no display frame
-- waits on one: the bars looked ahead, and the seconds of a render given to
-- the work.
local AHEAD = {bars = {2, 4, 8}, budget = 0.002}

--- The full mix for a style's overrides.
function Synth.mix(overrides)
	local mix = {}
	for key, value in pairs(DEFAULT_MIX) do mix[key] = value end
	for key, value in pairs(overrides or {}) do
		assert(DEFAULT_MIX[key] ~= nil, "unknown mix field " .. tostring(key))
		mix[key] = value
	end
	return mix
end

-- The one-pole coefficient for a filter `kind` at `opening` (0…1).
local function sweepCoef(kind, opening, sr)
	local sweep = SWEEP[kind]
	return 1 - exp(-TAU * sweep.corner * 2 ^ (opening * sweep.octaves) / sr)
end

local function strip(role)
	return {role = role, family = Model.family[role], drum = Model.family[role] == "drums",
		left = {}, right = {}, throwL = {}, throwR = {}, used = false,
		l = 0, r = 0, c = 1, high = false, filtered = false, peak = 0}
end

--- `settings` answers value(control) as Model does; `style` is the style
--- plugin's manifest, for its kit and mix.
function Synth.new(settings, sampleRate, style)
	local sr = sampleRate or 44100
	local self = setmetatable({
		settings = settings, sr = sr,
		frame = 0,           -- next frame to render
		nextBarFrame = 0,    -- where the next bar starts
		barNumber = 0,       -- timeline bar count across track changes
		composerBar = 0,     -- bar index within the current composer
		timeline = {},       -- recent {frame, bar} for the playhead
		events = {},         -- scheduled, sorted by frame
		voices = {},         -- sounding one-shots, slices and poly voices
		mono = {},           -- the voice of each mono channel, by role
		loops = {},          -- the slice voice each drum channel continues
		strips = {}, order = {},
		tempo = 120,         -- of the bar sounding, under the Pitch fader
		duck = 0,
		duckHits = {},       -- block-relative frames where a kick restarts the pump
		scratch = {scratchL = {}, scratchR = {}},
		bus = {dryL = {}, dryR = {}, duckL = {}, duckR = {}, sendL = {}, sendR = {},
			revInL = {}, revInR = {}, wetL = {}, wetR = {}, echoL = {}, echoR = {}, throwL = {}, throwR = {}},
	}, Synth)
	for _, role in ipairs(Model.roles) do
		self.strips[role.id] = strip(role.id)
		table.insert(self.order, self.strips[role.id])
	end
	self:applyStyle(style)
	self:initEffects()
	return self
end

-- The style's kit and mix; the kit is voiced for the current track's design.
function Synth:applyStyle(style)
	self.kit = Drums.design(style and style.kit)
	self.styleMix = Synth.mix(style and style.mix)
	self:mixLevels()
	self:applyDrums(self.design)
end

function Synth:applyDrums(design)
	self.design = design
	self.shots = Drums.shots(self.sr, self.kit, design)
end

-- The style's mix under the current fader positions. A level reaches a
-- channel at once.
function Synth:mixLevels()
	local settings, mix = self.settings, self.mixNow or {}
	for key, value in pairs(self.styleMix) do mix[key] = value end
	for _, role in ipairs(Model.roles) do
		local fader = Model.faders[role.family]
		if fader then mix[role.id] = mix[role.id] * settings:value(fader) end
	end
	mix.duckDepth = math.min(MAX_DUCK, mix.duckDepth * settings:value("pump"))
	self.mixNow = mix
	return mix
end

--- Plays `composer` from its first bar at the next bar line; the audio
--- already rendered keeps playing, so the change is seamless. A `style`
--- brings its kit and mix on that same bar line.
function Synth:setComposer(composer, style)
	self.composer = composer
	self.composerBar = 0
	if style then self.pendingStyle = style end
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

-- The Pitch fader, as a turntable's: a share of the tempo either way.
function Synth:pitch()
	return 1 + self.settings:value("pitch") / 100
end

-- Frames per 16th note of a bar at `tempo` BPM, under the Pitch fader.
function Synth:stepFrames(tempo)
	return self.sr * 60 / ((tempo or self.tempo) * self:pitch()) / 4
end

local function insertEvent(events, event)
	local i = #events
	while i > 0 and events[i].frame > event.frame do i = i - 1 end
	table.insert(events, i + 1, event)
end

function Synth:scheduleBar()
	local settings = self.settings
	local bar = self.composer:bar(self.composerBar, settings)
	local start = self.nextBarFrame
	local tempo = bar.tempo * self:pitch()
	local step = self.sr * 60 / tempo / 4
	local swing = bar.swing * settings:value("swing") * step
	-- Swing delays the off-16ths; rolls between 16ths swing with their 16th.
	-- A humanize nudge is a fraction of a step, never before the bar start.
	local function at(s, nudge)
		return math.max(start, start + floor((s + (nudge or 0)) * step + ((floor(s) % 2 == 1) and swing or 0) + 0.5))
	end
	bar.frame, bar.frames, bar.number, bar.playedTempo = start, floor(16 * step + 0.5), self.barNumber, tempo
	local events = self.events
	insertEvent(events, {frame = start, kind = "bar", bar = bar, tempo = tempo, style = self.pendingStyle})
	self.pendingStyle = nil
	for _, h in ipairs(bar.hits) do
		insertEvent(events, {frame = at(h.step, h.nudge), kind = "hit", role = h.role, voice = h.voice,
			gain = h.gain, throw = h.throw})
	end
	-- Slices sit on the straight grid: a loop carries its own feel.
	for _, s in ipairs(bar.slices) do
		insertEvent(events, {frame = start + floor(s.step * step + 0.5), kind = "slice", role = s.role, slice = s,
			length = floor((s.length or 1) * step + 0.5), bar = bar, tempo = tempo})
	end
	for _, n in ipairs(bar.notes) do
		insertEvent(events, {frame = at(n.step), kind = "note", role = n.role, note = n,
			length = math.max(1, floor(n.length * step - step * (n.gap or 0.1)))})
	end
	-- Absolute frames of the kicks and snares, for the pump and the flashes.
	bar.kicks, bar.snares = {}, {}
	for _, s in ipairs(bar.kickSteps) do table.insert(bar.kicks, at(s)) end
	for _, s in ipairs(bar.snareSteps) do table.insert(bar.snares, at(s)) end
	table.sort(bar.kicks)
	table.sort(bar.snares)
	for _, frame in ipairs(bar.kicks) do insertEvent(events, {frame = frame, kind = "kick"}) end
	self:prepare()
	table.insert(self.timeline, bar)
	if #self.timeline > 64 then table.remove(self.timeline, 1) end
	self.nextBarFrame = start + bar.frames
	self.barNumber = self.barNumber + 1
	self.composerBar = self.composerBar + 1
end

-- Asks for the loops of the bars to come, on the kits of their tracks.
function Synth:prepare()
	local settings = self.settings
	for _, ahead in ipairs(AHEAD.bars) do
		local bar = self.composer:bar(self.composerBar + ahead, settings)
		local seen = {}
		for _, slice in ipairs(bar.slices) do
			local key = slice.beat.id .. (slice.variant or "full")
			if not seen[key] then
				seen[key] = true
				Drums.prepare(self.sr, self.kit, bar.drums, slice.beat, {tempo = bar.trackTempo,
					swing = bar.swing * settings:value("swing"), humanize = settings:value("humanize"),
					variant = slice.variant, energy = slice.energy, complexity = slice.complexity})
			end
		end
	end
end

-- The bar sounding at an absolute frame, for the now-playing display.
function Synth:barAt(frame)
	for i = #self.timeline, 1, -1 do
		local bar = self.timeline[i]
		if frame >= bar.frame then return bar end
	end
	return self.timeline[1]
end

-- The loop a slice plays: its beat on the track's kit, at the track's own
-- tempo and feel.
function Synth:loopOf(slice, bar)
	local settings = self.settings
	return Drums.loop(self.sr, self.shots, slice.beat, {tempo = bar.trackTempo,
		swing = bar.swing * settings:value("swing"), humanize = settings:value("humanize"),
		variant = slice.variant, energy = slice.energy, complexity = slice.complexity})
end

function Synth:startEvent(e)
	local sr = self.sr
	if e.kind == "bar" then
		local bar = e.bar
		self.tempo = bar.tempo
		if e.style then self:applyStyle(e.style) end
		-- Each track plays its own kit, from its first bar.
		if bar.drums ~= self.design then self:applyDrums(bar.drums) end
		-- The ride each channel's block asks for through this bar.
		for _, s in ipairs(self.order) do
			local ride = bar.automation[s.role]
			s.ride = ride and {frame = e.frame, frames = bar.frames, level = ride.level, kind = ride.kind,
				filter = ride.filter} or nil
		end
	elseif e.kind == "kick" then
		-- The pump restarts on the kick's own frame within the block.
		table.insert(self.duckHits, e.frame - self.frame + 1)
	elseif e.kind == "hit" then
		local place = assert(Drums.place[e.voice], "unknown drum voice " .. tostring(e.voice))
		local data = self.shots[e.voice]
		table.insert(self.voices, {kind = "shot", strip = self.strips[e.role], data = data, pos = 1,
			gl = e.gain * (1 - place[1]) * 2, gr = e.gain * place[1] * 2, throw = e.throw and 1 or 0})
		if e.voice == "openHat" or e.voice == "hat" then
			-- A new hat chokes a ringing open hat, like one physical cymbal.
			for _, v in ipairs(self.voices) do
				if v.kind == "shot" and v.data == self.shots.openHat and v.pos > 1 then v.choke = true end
			end
		end
	elseif e.kind == "slice" then
		local slice = e.slice
		local loop = self:loopOf(slice, e.bar)
		-- Pitched to tempo like a sped-up record: a slice lasts one 16th.
		local rate = e.tempo / loop.tempo * (slice.rate or 1)
		local v = self.loops[e.role]
		local continues = v and v.loop == loop and v.next == slice.slice and v.left > -SLICE.slack
			and not slice.reverse and not v.reverse and (slice.rate or 1) == 1 and v.plain
		if continues then
			-- The next slice in order: the loop just keeps playing.
			v.left, v.gain, v.rate, v.fade = v.left + e.length, slice.gain, rate, 1
		else
			if v then v.left = math.min(v.left, 0) end
			local pos = slice.slice * loop.step
			if slice.reverse then pos = pos + loop.step * (slice.length or 1) - 1 end
			v = {kind = "slice", strip = self.strips[e.role], loop = loop, pos = pos % loop.frames,
				rate = slice.reverse and -rate or rate, reverse = slice.reverse, gain = slice.gain, left = e.length,
				fade = 1, plain = (slice.rate or 1) == 1}
			table.insert(self.voices, v)
			self.loops[e.role] = v
		end
		v.throw = slice.throw and 1 or 0
		v.next = (slice.slice + floor(slice.length or 1)) % loop.slices
	elseif e.kind == "note" then
		local note = e.note
		local patch = note.patch
		self.strips[e.role].send = patch.send
		local options = {sr = sr, hold = e.length, gain = note.gain, seed = e.frame, accent = note.accent,
			rate = note.rate, glide = note.glide, from = note.from, to = note.to,
			throw = note.throw and 1 or 0, phase = e.frame / sr * self.tempo / 60 * (patch.filter and patch.filter.rate or 0)}
		if patch.mono then
			local v = self.mono[e.role]
			if v and v.patch == patch then
				Instrument.retarget(v, note.notes[1], options)
			else
				-- A new track's patch takes the channel; the old voice rings out.
				if v then
					v.hold = math.min(v.hold, v.tick)
					table.insert(self.voices, v)
				end
				v = Instrument.voice(patch, {note.notes[1]}, options)
				v.kind, v.strip, v.bass = "voice", self.strips[e.role], e.role == "bass"
				self.mono[e.role] = v
			end
		else
			local v = Instrument.voice(patch, note.notes, options)
			v.kind, v.strip, v.bass = "voice", self.strips[e.role], e.role == "bass"
			table.insert(self.voices, v)
		end
	end
end

-- What the Sound sliders ask of a voice: the bass follows them, the rest
-- play as their patch says.
function Synth:voiceContext(bass)
	local ctx = self.scratch
	ctx.tempo = self.tempo * self:pitch()
	if bass then
		local settings = self.settings
		ctx.shift = (settings:value("cutoff") - SOUND.middle) * 2 * SOUND.cutoffOctaves
		ctx.wobble, ctx.drive = settings:value("wobble"), settings:value("drive")
	else
		ctx.shift, ctx.wobble, ctx.drive = 0, 1, 1
	end
	return ctx
end

-- Renders frames [first, last] of the channels (1-based within the block).
function Synth:renderVoices(first, last)
	local sr = self.sr
	local voices = self.voices
	local i = 1
	while i <= #voices do
		local v = voices[i]
		local s = v.strip
		local done = false
		s.used = true
		if v.kind == "shot" then
			local data, pos, gl, gr, throw = v.data, v.pos, v.gl, v.gr, v.throw
			local n = #data
			local fade = v.choke and 0.995 or 1
			local left, right, throwL, throwR = s.left, s.right, s.throwL, s.throwR
			for k = first, last do
				if pos > n then break end
				local x = data[pos]
				if v.choke then gl, gr = gl * fade, gr * fade end
				left[k] = left[k] + x * gl
				right[k] = right[k] + x * gr
				if throw > 0 then
					throwL[k] = throwL[k] + x * gl
					throwR[k] = throwR[k] + x * gr
				end
				pos = pos + 1
			end
			v.pos, v.gl, v.gr = pos, gl, gr
			done = pos > n or (v.choke and gl + gr < 1e-4)
		elseif v.kind == "slice" then
			-- Linear-interpolated resampling of the loop.
			local loop = v.loop
			local dataL, dataR, n = loop.left, loop.right, loop.frames
			local pos, rate, g, remaining, fade = v.pos, v.rate, v.gain, v.left, v.fade
			local fadeCoef = exp(-1 / (SLICE.fade * sr))
			local left, right, throwL, throwR, throw = s.left, s.right, s.throwL, s.throwR, v.throw
			for k = first, last do
				if remaining <= 0 then
					fade = fade * fadeCoef
					if fade < 1e-3 then break end
				end
				local at = floor(pos)
				local frac = pos - at
				local after = at + 2 <= n and at + 2 or 1
				local a, b = dataL[at + 1], dataL[after]
				local l = (a + (b - a) * frac) * g * fade
				local r = l
				if dataR ~= dataL then
					a, b = dataR[at + 1], dataR[after]
					r = (a + (b - a) * frac) * g * fade
				end
				left[k] = left[k] + l
				right[k] = right[k] + r
				if throw > 0 then
					throwL[k] = throwL[k] + l
					throwR[k] = throwR[k] + r
				end
				pos = pos + rate
				if pos >= n then pos = pos - n elseif pos < 0 then pos = pos + n end
				remaining = remaining - 1
			end
			v.pos, v.left, v.fade = pos, remaining, fade
			done = fade < 1e-3
			if done and self.loops[s.role] == v then self.loops[s.role] = nil end
		else
			done = Instrument.render(v, first, last, s, self:voiceContext(v.bass))
		end
		if done then table.remove(voices, i) else i = i + 1 end
	end
	for _, role in ipairs(Model.roles) do
		local v = self.mono[role.id]
		if v and Instrument.sounding(v) then
			v.strip.used = true
			Instrument.render(v, first, last, v.strip, self:voiceContext(v.bass))
		end
	end
end

-- Frames [first, last] of every channel through its strip into the buses:
-- the ride its block asks for (by absolute frame, so any block size renders
-- the same), its level, then the dry or the ducked bus, the sends and the
-- throw.
function Synth:mixChannels(first, last)
	local sr, mix, bus, frame = self.sr, self.mixNow, self.bus, self.frame
	local dryL, dryR, duckL, duckR = bus.dryL, bus.dryR, bus.duckL, bus.duckR
	local sendL, sendR, throwL, throwR = bus.sendL, bus.sendR, bus.throwL, bus.throwR
	local rate = SWEEP.rate
	local meterFall = exp(-(last - first + 1) / (sr / METER.fall))
	for _, s in ipairs(self.order) do
		s.peak = s.peak * meterFall
		-- A closed filter rings on after its last voice: the strip runs until
		-- it has.
		if s.used or s.filtered or math.abs(s.l) + math.abs(s.r) > 1e-12 then
			local left, right, tl, tr = s.left, s.right, s.throwL, s.throwR
			local level = mix[s.role]
			local send = s.drum and mix.drumSend or s.send or 0
			local outL, outR = s.drum and dryL or duckL, s.drum and dryR or duckR
			local throw = mix.throw
			local ride = s.ride
			local l1, r1, c, high, filtered = s.l, s.r, s.c, s.high, s.filtered
			local peak = 0
			if not ride and not filtered then
				-- An open channel at a steady level: nothing to ride. The pole
				-- follows the channel, so a sweep starts from where the sound is.
				for k = first, last do
					l1, r1 = left[k], right[k]
					local l, r = l1 * level, r1 * level
					outL[k] = outL[k] + l
					outR[k] = outR[k] + r
					sendL[k] = sendL[k] + l * send
					sendR[k] = sendR[k] + r * send
					throwL[k] = throwL[k] + tl[k] * level * throw
					throwR[k] = throwR[k] + tr[k] * level * throw
					local loud = l < 0 and -l or l
					if loud > peak then peak = loud end
					left[k], right[k], tl[k], tr[k] = 0, 0, 0, 0
				end
				c = 1
			else
				for k = first, last do
					local l, r = left[k], right[k]
					local gain = level
					local at = frame + k - 1
					if ride then
						local through = (at - ride.frame) / ride.frames
						if through > 1 then through = 1 end
						gain = gain * (ride.level.from + (ride.level.to - ride.level.from) * through)
						if at % rate == 0 then
							if ride.kind then
								local opening = ride.filter.from + (ride.filter.to - ride.filter.from) * through
								c, high, filtered = sweepCoef(ride.kind, opening, sr), ride.kind == "highpass", true
							else
								c, filtered = 1, false
							end
						end
					elseif at % rate == 0 then
						c, filtered = 1, false
					end
					l1 = l1 + c * (l - l1)
					r1 = r1 + c * (r - r1)
					if filtered then
						if high then l, r = l - l1, r - r1 else l, r = l1, r1 end
					end
					l, r = l * gain, r * gain
					outL[k] = outL[k] + l
					outR[k] = outR[k] + r
					sendL[k] = sendL[k] + l * send
					sendR[k] = sendR[k] + r * send
					throwL[k] = throwL[k] + tl[k] * gain * throw
					throwR[k] = throwR[k] + tr[k] * gain * throw
					local loud = l < 0 and -l or l
					if loud > peak then peak = loud end
					left[k], right[k], tl[k], tr[k] = 0, 0, 0, 0
				end
			end
			s.l, s.r, s.c, s.high, s.filtered = l1, r1, c, high, filtered
			if peak > s.peak then s.peak = peak end
			s.used = false
		end
	end
end

--- The level of each role's channel just played (0…1), for meters.
function Synth:level(role)
	return self.strips[role].peak
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
	local MIX = self.mixNow
	local bus = self.bus
	local settings = self.settings
	local space = settings:value("space")
	local volume = settings:value("volume") * MIX.master
	local duckRelease = exp(-1 / (MIX.duckRelease * sr))
	local delay = self.delay
	local dl, dr = delay.l, delay.r
	local bufL, bufR, n, wi, dlp = dl.buf, dr.buf, dl.n, dl.i, delay.lp
	local delayFrames = math.min(n - 1, floor(self:stepFrames() * MIX.delaySteps + 0.5))
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
	table.sort(hits)
	for k = 1, count do
		duck = duck * duckRelease
		while hits[nextHit] and hits[nextHit] <= k do duck, nextHit = 1, nextHit + 1 end
		local g = 1 - depth * duck
		local l = dryL[k] + duckL[k] * g + echoesL[k] + wetL[k]
		local r = dryR[k] + duckR[k] * g + echoesR[k] + wetR[k]
		out[2 * k - 1] = softClip(l * volume)
		out[2 * k] = softClip(r * volume)
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
	for _, s in ipairs(self.order) do
		local left, right, tl, tr = s.left, s.right, s.throwL, s.throwR
		for k = #left + 1, frames do left[k], right[k], tl[k], tr[k] = 0, 0, 0, 0 end
	end
	self:mixLevels()
	local blockStart = self.frame
	local blockEnd = blockStart + frames
	local cursor = 1
	while true do
		while self.nextBarFrame < blockEnd do self:scheduleBar() end
		local event = self.events[1]
		local stop = (event and event.frame < blockEnd) and (event.frame - blockStart + 1) or (frames + 1)
		if stop > cursor then
			self:renderVoices(cursor, stop - 1)
			self:mixChannels(cursor, stop - 1)
			cursor = stop
		end
		if not event or event.frame >= blockEnd then break end
		table.remove(self.events, 1)
		self:startEvent(event)
	end
	self:mixdown(out, frames)
	self.frame = blockEnd
	Drums.work(AHEAD.budget)
end

return Synth
