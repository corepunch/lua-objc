-- The drum machine: a kit of one-shots designed per style and voiced anew
-- for every track, and the loops a track's drum channel plays. A beat is
-- authored as steps (library/Beats.lua) and rendered once into a loop, the
-- way a tracker module carries its drum loop as one sample: a slice of it
-- holds everything that rang into that 16th, and the channel plays the loop
-- by slice, in order or jumping to any point of it (the sample-offset
-- effect). No IO: the Synth and the headless tests share this code.
local Drums = {}

local sin, exp, floor = math.sin, math.exp, math.floor
local TAU = 2 * math.pi

-- The programmed kit. A kick is a sine swept down from base + sweep to
-- base. A snare is a tuned body (`drop` bends it down from above, for
-- a fat thwack) and wires: noise from dark (`bright` 0) to fizzy
-- (`bright` 1), with a looser `rattle` tail, a rimshot `snap`, a `clap`
-- layered on, a short `room` and `drive`. A clap is quick bursts of
-- noise band-passed around `tone` and a tail; hats are 808-style metal
-- with a share of `noise`. These are drum & bass values; a style's `kit`
-- overrides any field and keeps the rest.
local DEFAULT_KIT = {
	kick = {base = 46, sweep = 115, sweepTime = 0.026, decay = 0.2, drive = 1.6, click = 0.35, length = 0.42},
	snare = {tone = 188, overtone = 332, bodyDecay = 0.055, noiseDecay = 0.1, noise = 0.42,
		drop = 0, bright = 1, rattle = 0, snap = 0, clap = 0, room = 0, drive = 0},
	clap = {bursts = 3, spacing = 0.011, decay = 0.16, level = 0.9, tone = 0.35},
	hat = {scale = 1.6, decay = 0.016, openDecay = 0.12, noise = 0.12},
}

--- The snare characters a producer picks between, over a style's own
--- snare: factors multiply its fields, settings replace them. A flavour may
--- list the ones that suit it as `snares`.
Drums.snares = {"tight", "fat", "rimshot", "roomy", "crunchy", "layered", "vintage"}
local SNARES = {
	tight = {factors = {tone = 1.12, overtone = 1.1, bodyDecay = 0.7, noiseDecay = 0.6}, set = {snap = 0.5}},
	fat = {factors = {tone = 0.82, overtone = 0.85, bodyDecay = 1.6, noiseDecay = 1.3, noise = 1.1},
		set = {drop = 0.45, bright = 0.6}},
	rimshot = {factors = {tone = 1.25, overtone = 1.3, noise = 0.7, noiseDecay = 0.8}, set = {snap = 1}},
	roomy = {factors = {noiseDecay = 1.2}, set = {room = 0.55, bright = 0.8}},
	crunchy = {factors = {noise = 1.2, bodyDecay = 1.1}, set = {drive = 0.7}},
	layered = {factors = {noiseDecay = 1.1, noise = 0.85}, set = {clap = 0.6, snap = 0.2}},
	vintage = {factors = {bodyDecay = 1.25, noiseDecay = 1.1}, set = {bright = 0.25, rattle = 0.8, room = 0.2}},
}

--- Dimensions of a track's kit, each −1…1 around the style's design.
Drums.dimensions = {"snareTune", "kickTune", "kickLength", "kickDrive", "kickClick",
	"hatTone", "hatLength", "hatNoise", "clapSpread", "clapLength", "clapTone"}

-- How far a track's kit design moves the style's drums: semitones, or
-- octaves of a time or level.
local VARIANT = {snareTune = 3, kickTune = 2, kickSweep = 0.35, kickLength = 0.45, kickDrive = 0.5,
	kickClick = 1, hatTone = 0.2, hatLength = 0.6, hatNoise = 1.3, clapSpread = 0.4, clapLength = 0.5,
	clapTone = 0.5}

-- A record's break: a short room, a little tape drive and a dull top give
-- it its age. `fade` declicks a slice cut short, as a sampler does.
local BREAK = {room = {0.019, 0.027}, roomFeedback = 0.32, roomMix = 0.3, tone = 0.55, drive = 1.3}
-- A small room for a snare: two feedback combs at wall-bounce delays.
local SNARE_ROOM = {delays = {0.0113, 0.0171}, feedback = 0.55, tail = 0.45}
-- TR-808 style metal: six detuned square waves.
local METAL = {205.3, 304.4, 369.6, 522.7, 540.0, 800.0}
-- How a loop is played by hand: the most a hit drifts from the grid (in
-- 16ths) and loses of its level at full Humanize; the kick and the
-- backbeat stay tight, as a drummer's would. A ringing open hat is choked
-- by the next hat over `choke` seconds, like one physical cymbal.
local FEEL = {drift = 0.14, level = 0.3, anchor = 0.25, choke = 0.012}

-- Work that is prepared ahead pauses every so many hits and frames, so
-- that no display frame waits on a whole loop.
local WORK = {hits = 2, frames = 2048}

--- Stereo placement per voice: {pan (0 left, 1 right), effect send}.
Drums.place = {
	kick = {0.5, 0}, snare = {0.5, 0.35}, ghost = {0.46, 0.25}, hat = {0.62, 0.05},
	openHat = {0.62, 0.15}, ride = {0.36, 0.2}, crash = {0.44, 0.3},
	rim = {0.3, 0.3}, conga = {0.7, 0.25}, shaker = {0.76, 0.2}, clap = {0.52, 0.4},
	tomHigh = {0.66, 0.25}, tomMid = {0.5, 0.25}, tomLow = {0.34, 0.25},
	cowbell = {0.68, 0.2}, clave = {0.28, 0.25}, tambourine = {0.72, 0.2}, snap = {0.42, 0.35},
	breakKick = {0.5, 0}, breakSnare = {0.5, 0}, breakRide = {0.5, 0}, breakHat = {0.5, 0},
}

-- Voices of a loop's variants: `tops` plays these and nothing else.
local TOPS = {hat = true, openHat = true, ride = true, shaker = true, rim = true, conga = true,
	cowbell = true, clave = true, tambourine = true, breakRide = true, breakHat = true}
local HATS = {hat = true, openHat = true, breakHat = true}

local function softClip(x)
	if x > 3 then return 1 elseif x < -3 then return -1 end
	local x2 = x * x
	return x * (27 + x2) / (27 + 9 * x2)
end
Drums.softClip = softClip

-- Deterministic white noise so rendered drums, and therefore tests, are
-- identical on every run.
local function noiseSource(seed)
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) & 0x7FFFFFFF
		return state / 0x3FFFFFFF - 1
	end
end
Drums.noise = noiseSource

--- The full kit design for a style's overrides.
function Drums.design(overrides)
	local kit = {}
	for group, fields in pairs(DEFAULT_KIT) do
		local merged = {}
		for key, value in pairs(fields) do merged[key] = value end
		for key, value in pairs(overrides and overrides[group] or {}) do
			assert(fields[key] ~= nil, "unknown kit field " .. group .. "." .. tostring(key))
			merged[key] = value
		end
		kit[group] = merged
	end
	for group in pairs(overrides or {}) do assert(DEFAULT_KIT[group], "unknown kit group " .. tostring(group)) end
	return kit
end

--- A style's kit voiced for one track's `design` (StyleKit.drumDesign): its
--- snare character over the style's snare, then retuned and reshaped
--- within the VARIANT ranges.
function Drums.variant(kit, design)
	if not design then return kit end
	local result = {}
	local function copy(group)
		local fields = {}
		for key, value in pairs(kit[group]) do fields[key] = value end
		result[group] = fields
		return fields
	end
	local function semitones(x, range) return 2 ^ (x * range / 12) end
	local function octaves(x, range) return 2 ^ (x * range) end
	local snare = copy("snare")
	local character = assert(SNARES[design.snare], "unknown snare character " .. tostring(design.snare))
	for key, factor in pairs(character.factors) do snare[key] = snare[key] * factor end
	for key, value in pairs(character.set) do snare[key] = value end
	local tune = semitones(design.snareTune, VARIANT.snareTune)
	snare.tone, snare.overtone = snare.tone * tune, snare.overtone * tune
	local kick = copy("kick")
	kick.base = kick.base * semitones(design.kickTune, VARIANT.kickTune)
	kick.sweep = kick.sweep * octaves(design.kickDrive, VARIANT.kickSweep)
	kick.decay = kick.decay * octaves(design.kickLength, VARIANT.kickLength)
	kick.length = kick.length * octaves(math.max(0, design.kickLength), VARIANT.kickLength)
	kick.drive = kick.drive * octaves(design.kickDrive, VARIANT.kickDrive)
	kick.click = kick.click * octaves(design.kickClick, VARIANT.kickClick)
	local hat = copy("hat")
	hat.scale = hat.scale * octaves(design.hatTone, VARIANT.hatTone)
	hat.decay = hat.decay * octaves(design.hatLength, VARIANT.hatLength)
	hat.openDecay = hat.openDecay * octaves(design.hatLength, VARIANT.hatLength)
	hat.noise = hat.noise * octaves(design.hatNoise, VARIANT.hatNoise)
	local clap = copy("clap")
	clap.spacing = clap.spacing * octaves(design.clapSpread, VARIANT.clapSpread)
	clap.bursts = design.clapSpread > 0.3 and 4 or clap.bursts
	clap.decay = clap.decay * octaves(design.clapLength, VARIANT.clapLength)
	clap.tone = clap.tone * octaves(design.clapTone, VARIANT.clapTone)
	return result
end

-- `pause`, when given, is called every so many frames, so that a kit can
-- be rendered a little at a time (see Drums.prepare).
local function shotRenderer(sr, shots, pause)
	return function(name, seconds, fn)
		local data, n = {}, floor(seconds * sr)
		local state = {}
		for i = 1, n do
			if pause and i % WORK.frames == 1 then pause() end
			data[i] = fn((i - 1) / sr, state)
		end
		-- Declick the tail.
		local fade = math.min(n, floor(0.004 * sr))
		for i = 0, fade - 1 do data[n - i] = data[n - i] * i / fade end
		shots[name] = data
	end
end

local function metalSource(noise)
	return function(t, s, scale, hiss)
		local v = 0
		for _, f in ipairs(METAL) do v = v + ((t * f * scale) % 1 < 0.5 and 1 or -1) end
		-- Two differences act as a steep high-pass on the metallic cluster.
		local d1 = v - (s.a or 0); s.a = v
		local d2 = d1 - (s.b or 0); s.b = d1
		return d2 / 12 + noise() * (hiss or 0.12)
	end
end

-- Clap bursts: noise band-passed around `tone` (the difference of two
-- one-pole low-passes), in quick bursts and then a tail.
local function clapSource(noise, clap)
	local tailStart = (clap.bursts - 1) * clap.spacing
	return function(t, s)
		local n = noise()
		s.ca = (s.ca or 0) + clap.tone * (n - (s.ca or 0))
		s.cb = (s.cb or 0) + clap.tone * 0.17 * (s.ca - (s.cb or 0))
		local burst = 0
		for i = 0, clap.bursts - 1 do
			local since = t - i * clap.spacing
			if since >= 0 then burst = math.max(burst, exp(-since / 0.005)) end
		end
		local tail = t >= tailStart and exp(-(t - tailStart) / clap.decay) * 0.8 or 0
		return (s.ca - s.cb) * math.max(burst, tail) * 2.4
	end, tailStart + clap.decay * 4
end

-- The voices a style designs: kick, snare (and its ghost), clap and hats.
local function renderKit(sr, kit, pause)
	local noise = noiseSource(11)
	local shots = {}
	local shot = shotRenderer(sr, shots, pause)
	local metal = metalSource(noise)
	local kick, snare, clap, hat = kit.kick, kit.snare, kit.clap, kit.hat
	shot("kick", kick.length, function(t, s)
		s.phase = (s.phase or 0) + TAU * (kick.base + kick.sweep * exp(-t / kick.sweepTime)) / sr
		local click = t < 0.003 and noise() * kick.click * (1 - t / 0.003) or 0
		return softClip(kick.drive * sin(s.phase) * exp(-t / kick.decay)) * 0.95 + click
	end)
	local layer = clapSource(noise, clap)
	local combs = {}
	for i, delay in ipairs(SNARE_ROOM.delays) do combs[i] = {line = {}, size = floor(delay * sr), at = 0} end
	local driveNorm = snare.drive > 0 and 1 / softClip(1 + 3 * snare.drive) or 1
	shot("snare", 0.32 + snare.room * SNARE_ROOM.tail, function(t, s)
		s.phase = (s.phase or 0) + TAU * snare.tone * (1 + snare.drop * exp(-t / 0.012)) / sr
		local body = sin(s.phase) * exp(-t / snare.bodyDecay) * 0.55
			+ sin(s.phase * snare.overtone / snare.tone) * exp(-t / 0.035) * 0.25
		-- Wires: a first difference is bright fizz, a band around 3 kHz
		-- the darker hiss of an older kit.
		local n = noise()
		local hp = n - (s.prev or 0)
		s.prev = n
		s.lp = (s.lp or 0) + 0.45 * (n - (s.lp or 0))
		s.lp2 = (s.lp2 or 0) + 0.08 * (s.lp - (s.lp2 or 0))
		local wires = hp * snare.bright + (s.lp - s.lp2) * 1.6 * (1 - snare.bright)
		local envelope = exp(-t / snare.noiseDecay) + snare.rattle * 0.35 * exp(-t / (snare.noiseDecay * 3))
		local v = body + wires * envelope * snare.noise
		if snare.snap > 0 and t < 0.004 then
			v = v + (hp * 0.6 + sin(TAU * 1750 * t)) * snare.snap * (1 - t / 0.004)
		end
		if snare.clap > 0 then v = v + layer(t, s) * clap.level * snare.clap * 0.6 end
		if snare.drive > 0 then v = softClip(v * (1 + 3 * snare.drive)) * driveNorm * 0.5 end
		if snare.room > 0 then
			local wet = 0
			for _, c in ipairs(combs) do
				local slot = c.at % c.size + 1
				local out = c.line[slot] or 0
				c.line[slot] = v + out * SNARE_ROOM.feedback
				c.at = c.at + 1
				wet = wet + out
			end
			v = v + wet * snare.room * 0.5
		end
		return v
	end)
	local clapShot, clapLength = clapSource(noise, clap)
	shot("clap", clapLength, function(t, s) return clapShot(t, s) * clap.level end)
	shot("hat", 0.07, function(t, s) return metal(t, s, hat.scale, hat.noise) * exp(-t / hat.decay) end)
	shot("openHat", math.max(0.4, hat.openDecay * 3.5), function(t, s)
		return metal(t, s, hat.scale, hat.noise) * exp(-t / hat.openDecay) * 0.8
	end)
	-- A ghost note is the snare played softly: a separate name lets a loop
	-- leave ghosts out.
	shots.ghost = shots.snare
	return shots
end

-- Voices every style shares: cymbals, hand percussion, toms and the
-- break's own kit.
local function renderShared(sr)
	local noise = noiseSource(7)
	local shots = {}
	local shot = shotRenderer(sr, shots)
	local metal = metalSource(noise)
	-- A washy ride: high-passed noise over a quiet metal cluster, with the
	-- stick's tick at the front. No sustained sine, so it never rings.
	shot("ride", 0.9, function(t, s)
		local n = noise()
		local hp = n - (s.prev or 0)
		s.prev = n
		local wash = (hp * 0.32 + metal(t, s, 3.4, 0.2) * 0.22) * exp(-t / 0.28)
		local tick = t < 0.006 and hp * 0.5 * (1 - t / 0.006) or 0
		return wash + tick
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
	-- The 808 cowbell: two square waves a fifth-and-a-bit apart, band-limited
	-- by a one-pole and let ring briefly.
	shot("cowbell", 0.3, function(t, s)
		local v = ((t * 540) % 1 < 0.5 and 1 or -1) + ((t * 800) % 1 < 0.5 and 1 or -1)
		s.lp = (s.lp or 0) + 0.35 * (v - (s.lp or 0))
		return s.lp * (0.7 * exp(-t / 0.015) + 0.3 * exp(-t / 0.09)) * 0.4
	end)
	shot("clave", 0.08, function(t)
		return sin(TAU * 2450 * t) * exp(-t / 0.012) * 0.7
	end)
	-- A tambourine: jingles are metal far up, shaken in rather than struck.
	shot("tambourine", 0.18, function(t, s)
		return metal(t, s, 4.6, 0.3) * math.min(1, t / 0.004) * exp(-t / 0.045) * 0.6
	end)
	-- A finger snap: a click and a short band of noise a moment later.
	shot("snap", 0.14, function(t, s)
		local n = noise()
		s.ca = (s.ca or 0) + 0.5 * (n - (s.ca or 0))
		s.cb = (s.cb or 0) + 0.12 * (s.ca - (s.cb or 0))
		local late = t - 0.008
		return (s.ca - s.cb) * (exp(-t / 0.002) * 0.6 + (late >= 0 and exp(-late / 0.03) or 0)) * 1.6
	end)
	-- The break's kit: a 1960s funk kit, tuned and roomy — a round kick with
	-- a felt beater, a snare with a ringing head and loose wires, a ride
	-- with its bell and a tight hi-hat.
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
	shot("breakHat", 0.12, function(t, s)
		return metal(t, s, 2.1, 0.25) * exp(-t / 0.028) * 0.7
	end)
	return shots
end

-- Kits by sample rate and design: switching back to a style or skipping
-- back a track reuses its rendered kit. Every track brings a new design, so
-- only the most recent few stay; a playing Synth holds its own.
local CACHE = {kits = 8, loops = 10}
local kits, kitOrder = {}, {}
local shared = {}
local loops, loopOrder = {}, {}

local function kitKey(sr, kit)
	local parts = {sr}
	for _, group in ipairs({"kick", "snare", "clap", "hat"}) do
		local fields = kit[group]
		local keys = {}
		for key in pairs(fields) do table.insert(keys, key) end
		table.sort(keys)
		for _, key in ipairs(keys) do table.insert(parts, group .. "." .. key .. "=" .. tostring(fields[key])) end
	end
	return table.concat(parts, ";")
end

local function remember(cache, order, limit, key, value)
	cache[key] = value
	table.insert(order, key)
	if #order > limit then cache[table.remove(order, 1)] = nil end
	return value
end

--- The one-shots of a style's `kit` voiced for a track's `design`, over the
--- shots every kit shares. `shots.key` names the kit, for caches. `pause`
--- is called between the shots of a kit that has to be rendered.
function Drums.shots(sr, kit, design, pause)
	local voiced = Drums.variant(kit, design)
	local key = kitKey(sr, voiced)
	local shots = kits[key]
	if not shots then
		shared[sr] = shared[sr] or renderShared(sr)
		local own, common = renderKit(sr, voiced, pause), shared[sr]
		shots = setmetatable({key = key}, {__index = function(_, name) return own[name] or common[name] end})
		remember(kits, kitOrder, CACHE.kits, key, shots)
	end
	return shots
end

--- Which of a beat's hits a loop plays. `variant` is "full", "light" (the
--- groove without its extra layers: an intro or outro) or "tops" (hats and
--- percussion alone); `energy` and `complexity` let in the layers a beat
--- marks with `when`.
function Drums.plays(hit, variant, energy, complexity)
	if variant == "tops" then
		if not TOPS[hit.voice] then return false end
	elseif variant == "light" then
		return hit.when == nil and hit.light ~= false
	end
	if hit.when == "energy" then return energy == true end
	if hit.when == "complexity" then return complexity == true end
	return true
end

-- A reproducible 0…1 for hit `index` of a beat.
local function drift(seed, index, salt)
	local h = (seed * 0x9E3779B1 + index * 0x85EBCA6B + salt * 0xC2B2AE35) & 0x7FFFFFFF
	h = ((h ~ (h >> 15)) * 0x2C1B3C6D) & 0x7FFFFFFF
	h = ((h ~ (h >> 12)) * 0x297A2D39) & 0x7FFFFFFF
	return ((h ~ (h >> 15)) & 0xFFFFFF) / 0x1000000
end

local function beatSeed(id)
	local sum = 7
	for i = 1, #id do sum = (sum * 31 + id:byte(i)) & 0x7FFFFFFF end
	return sum
end

-- Where a hit lands in a loop of `n` frames, and at what level.
local function placement(beat, index, hit, step, options)
	local anchor = hit.voice == "kick" or hit.voice == "breakKick"
		or ((hit.voice == "snare" or hit.voice == "clap" or hit.voice == "breakSnare") and hit.step % 4 == 0)
	local loose = (options.humanize or 0) * (anchor and FEEL.anchor or 1)
	local seed = beatSeed(beat.id)
	local nudge = (drift(seed, index, 1) - 0.5) * FEEL.drift * loose
	local swing = (floor(hit.step) % 2 == 1) and (options.swing or 0) or 0
	local at = math.max(0, floor((hit.step + nudge + swing) * step + 0.5))
	return at, hit.gain * (1 - FEEL.level * loose * drift(seed, index, 2))
end

local function render(sr, shots, beat, options, pause)
	-- A record's break is rendered at the record's tempo and resampled to
	-- the track's, pitched up as a sped-up record is.
	local step = sr * 60 / (beat.bpm or options.tempo) / 4
	local n = floor(beat.slices * step + 0.5)
	local record = beat.kit == "break"
	local left, right = {}, nil
	for i = 1, n do left[i] = 0 end
	if not record then
		right = {}
		for i = 1, n do right[i] = 0 end
	end
	local placed = {}
	for index, hit in ipairs(beat.hits) do
		if Drums.plays(hit, options.variant, options.energy, options.complexity) then
			local at, gain = placement(beat, index, hit, step, options)
			table.insert(placed, {hit = hit, at = at, gain = gain})
		end
	end
	table.sort(placed, function(a, b) return a.at < b.at end)
	local chokeFall = exp(-1 / (FEEL.choke * sr))
	for i, p in ipairs(placed) do
		if pause and i % WORK.hits == 0 then pause() end
		local hit = p.hit
		local shot = assert(shots[hit.voice], "unknown drum voice " .. tostring(hit.voice))
		local place = Drums.place[hit.voice]
		local pan = hit.pan or place[1]
		local gl, gr = p.gain * (1 - pan) * 2, p.gain * pan * 2
		if record then gl = p.gain end
		-- An open hat rings until the next hat closes it; tails wrap round
		-- the loop, as a looped record's do.
		local choke
		if hit.voice == "openHat" then
			for offset = 1, #placed - 1 do
				local other = placed[(i + offset - 1) % #placed + 1]
				if HATS[other.hit.voice] then
					choke = (other.at - p.at) % n
					break
				end
			end
		end
		local fade = 1
		for k = 1, #shot do
			if choke and k > choke then
				fade = fade * chokeFall
				if fade < 1e-4 then break end
			end
			local j = (p.at + k - 1) % n + 1
			local s = shot[k] * fade
			left[j] = left[j] + s * gl
			if right then right[j] = right[j] + s * gr end
		end
	end
	if record then
		local combs = {}
		for _, seconds in ipairs(BREAK.room) do
			local c = {buf = {}, n = floor(seconds * sr), i = 1}
			for i = 1, c.n do c.buf[i] = 0 end
			table.insert(combs, c)
		end
		local lp = 0
		-- Twice round, so the room and the tone wrap into the loop's start:
		-- the first pass only fills the room, the second writes each frame
		-- after reading it dry.
		for pass = 1, 2 do
			for i = 1, n do
				if pause and i % WORK.frames == 0 then pause() end
				local x = left[i]
				local room = 0
				for _, c in ipairs(combs) do
					local y = c.buf[c.i]
					c.buf[c.i] = x + y * BREAK.roomFeedback
					c.i = c.i % c.n + 1
					room = room + y
				end
				lp = lp + BREAK.tone * (x + room * BREAK.roomMix - lp)
				if pass == 2 then left[i] = softClip(lp * BREAK.drive) / BREAK.drive end
			end
		end
	end
	return {left = left, right = right or left, frames = n, step = step, slices = beat.slices,
		tempo = beat.bpm or options.tempo, send = beat.send or 0.1, beat = beat}
end

local function loopKey(sr, shotsKey, beat, options)
	return table.concat({sr, shotsKey, beat.id, beat.bpm and "" or options.tempo,
		string.format("%.3f", options.swing or 0), string.format("%.2f", options.humanize or 0),
		options.variant or "full", tostring(options.energy == true), tostring(options.complexity == true)}, "|")
end

local function optionsOf(options)
	return {tempo = options.tempo, swing = options.swing, humanize = options.humanize,
		variant = options.variant or "full", energy = options.energy, complexity = options.complexity}
end

-- Loops being prepared, oldest first: {key, run}, `run` a coroutine that
-- ends with the loop in the cache.
local jobs = {}

local function finish(key)
	for i, job in ipairs(jobs) do
		if job.key == key then
			while coroutine.status(job.run) ~= "dead" do assert(coroutine.resume(job.run)) end
			table.remove(jobs, i)
			return
		end
	end
end

--- The loop of `beat` (a parsed beat from the library) played on `shots`.
--- `options`: `tempo` (the track's, which a programmed beat is rendered at),
--- `swing` (the delay of off-16ths, in 16ths), `humanize` (0…1), `variant`,
--- `energy` and `complexity` (see Drums.plays). The loop is
--- {left, right, frames, step (frames per slice), slices, tempo, send}; a
--- record's break is mono, so both sides are one table. A loop that is
--- being prepared is finished at once.
function Drums.loop(sr, shots, beat, options)
	local key = loopKey(sr, shots.key, beat, options)
	if not loops[key] then finish(key) end
	local loop = loops[key]
	if not loop then
		loop = remember(loops, loopOrder, CACHE.loops, key, render(sr, shots, beat, optionsOf(options)))
	end
	return loop
end

--- Prepares, a little at a time, the loop a track will need: the kit of
--- `design` on the style's `kit`, then `beat` played on it. Drums.work does
--- the work; Drums.loop finds the loop ready, or finishes it.
function Drums.prepare(sr, kit, design, beat, options)
	local key = loopKey(sr, kitKey(sr, Drums.variant(kit, design)), beat, options)
	if loops[key] then return end
	for _, job in ipairs(jobs) do
		if job.key == key then return end
	end
	local wanted = optionsOf(options)
	table.insert(jobs, {key = key, run = coroutine.create(function()
		local shots = Drums.shots(sr, kit, design, coroutine.yield)
		local loop = render(sr, shots, beat, wanted, coroutine.yield)
		remember(loops, loopOrder, CACHE.loops, key, loop)
	end)})
end

--- Works on what is being prepared for up to `seconds`. Returns whether
--- anything is left to do.
function Drums.work(seconds)
	local deadline = os.clock() + seconds
	while jobs[1] do
		local job = jobs[1]
		assert(coroutine.resume(job.run))
		if coroutine.status(job.run) == "dead" then table.remove(jobs, 1) end
		if os.clock() >= deadline then break end
	end
	return jobs[1] ~= nil
end

return Drums
