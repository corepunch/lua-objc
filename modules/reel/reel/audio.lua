-- An offline stereo mix for scores synthesised from a reel's own events.
--
-- Voices write into three bus pairs: dry, a sidechained ("ducked") bus that
-- dips under every kick, and a reverb send. `master` sums them through a
-- Freeverb-style room and a soft clipper, normalises, and returns two sample
-- arrays for ReelNative.writeWav. Noise comes from one deterministic LCG, so
-- a score renders the same every time.
local Audio = {}
Audio.__index = Audio

local floor, ceil, exp, cos, pi, abs, max, min = math.floor, math.ceil, math.exp, math.cos, math.pi, math.abs, math.max, math.min

local function truncate(x)
	if x >= 0 then return floor(x) end
	return ceil(x)
end

local function zeros(n)
	local list = {}
	for i = 1, n do list[i] = 0.0 end
	return list
end

-- Audio.new(duration, sampleRate)
function Audio.new(duration, sampleRate)
	local n = truncate(duration * sampleRate)
	local mix = setmetatable({ n = n, sr = sampleRate, duration = duration, seed = 12345 }, Audio)
	mix.dryL, mix.dryR, mix.sendL, mix.sendR, mix.duckL, mix.duckR = zeros(n), zeros(n), zeros(n), zeros(n), zeros(n), zeros(n)
	return mix
end

-- White noise in -1...1 from a 32-bit LCG (Numerical Recipes constants).
function Audio:noise()
	local seed = (self.seed * 1664525 + 1013904223) & 0xFFFFFFFF
	self.seed = seed
	return seed / 4294967295 * 2 - 1
end

-- range(t0, duration) -> first, last sample indices (0-based) to fill.
function Audio:range(t0, duration)
	local a = max(0, truncate(t0 * self.sr))
	local b = min(self.n, truncate((t0 + duration) * self.sr))
	return a, max(a, b) - 1
end

-- add(i, v, pan, send, duck): sample i (0-based); pan 0 left … 1 right.
function Audio:add(i, v, pan, send, duck)
	pan = pan or 0.5
	local l, r = v * (1 - pan) * 2, v * pan * 2
	local k = i + 1
	if duck then
		self.duckL[k] = self.duckL[k] + l
		self.duckR[k] = self.duckR[k] + r
	else
		self.dryL[k] = self.dryL[k] + l
		self.dryR[k] = self.dryR[k] + r
	end
	if send and send ~= 0 then
		self.sendL[k] = self.sendL[k] + l * send
		self.sendR[k] = self.sendR[k] + r * send
	end
end

-- A Freeverb-style room: eight damped combs into four allpasses. `spread`
-- detunes the right channel's delays for width.
local COMBS = { 1557, 1617, 1491, 1422, 1277, 1356, 1188, 1116 }
local ALLPASSES = { 556, 441, 341, 225 }
local ROOM = { input = 0.015, damp = 0.28, feedback = 0.85, allpassFeedback = 0.5 }

local function reverb(input, n, sr, spread)
	local scale = sr / 44100
	local combs, ci, store, alls, ai = {}, {}, {}, {}, {}
	for c, length in ipairs(COMBS) do combs[c] = zeros(truncate((length + spread) * scale)); ci[c] = 1; store[c] = 0.0 end
	for a, length in ipairs(ALLPASSES) do alls[a] = zeros(truncate((length + spread) * scale)); ai[a] = 1 end
	local out = {}
	local keep, damp, feedback, allFeedback, gain = 1 - ROOM.damp, ROOM.damp, ROOM.feedback, ROOM.allpassFeedback, ROOM.input
	local nc, na = #combs, #alls
	for i = 1, n do
		local x = input[i] * gain
		local y = 0.0
		for c = 1, nc do
			local buffer, index = combs[c], ci[c]
			local o = buffer[index]
			y = y + o
			local s = o * keep + store[c] * damp
			store[c] = s
			buffer[index] = x + s * feedback
			index = index + 1
			if index > #buffer then index = 1 end
			ci[c] = index
		end
		for a = 1, na do
			local buffer, index = alls[a], ai[a]
			local o = buffer[index]
			local v = -y + o
			buffer[index] = y + o * allFeedback
			index = index + 1
			if index > #buffer then index = 1 end
			ai[a] = index
			y = v
		end
		out[i] = y
	end
	return out
end

local function tanh(x)
	if x > 20 then return 1 end
	if x < -20 then return -1 end
	local e = exp(2 * x)
	return (e - 1) / (e + 1)
end

-- master{kicks, duckDepth, duckRelease, reverb, drive, peak, gain(t)} ->
-- left, right sample arrays. The ducked bus dips by `duckDepth` after each
-- kick; `gain(t)` shapes the master (fades, a breath before a drop).
function Audio:master(options)
	options = options or {}
	local n, sr = self.n, self.sr
	local kicks = {}
	for _, k in ipairs(options.kicks or {}) do table.insert(kicks, k) end
	table.sort(kicks)
	local depth, release = options.duckDepth or 0.6, options.duckRelease or 0.11
	local dryL, dryR, duckL, duckR = self.dryL, self.dryR, self.duckL, self.duckR
	local lastKick, k = -10.0, 1
	for i = 1, n do
		local t = (i - 1) / sr
		while k <= #kicks and kicks[k] <= t do lastKick = kicks[k]; k = k + 1 end
		local duck = 1 - depth * exp(-(t - lastKick) / release)
		dryL[i] = dryL[i] + duckL[i] * duck
		dryR[i] = dryR[i] + duckR[i] * duck
	end
	local rl = reverb(self.sendL, n, sr, 0)
	local rr = reverb(self.sendR, n, sr, 23)
	local wet, drive, gainAt = options.reverb or 0.8, options.drive or 1.25, options.gain
	local outL, outR, peak = {}, {}, 0.0
	for i = 1, n do
		local t = (i - 1) / sr
		local g = gainAt and gainAt(t) or 1
		local l = tanh(drive * (dryL[i] + rl[i] * wet)) * g
		local r = tanh(drive * (dryR[i] + rr[i] * wet)) * g
		outL[i], outR[i] = l, r
		peak = max(peak, abs(l), abs(r))
	end
	local gain = (options.peak or 0.89) / peak
	for i = 1, n do
		outL[i] = outL[i] * gain
		outR[i] = outR[i] * gain
	end
	return outL, outR
end

-- A raised-cosine fade to silence over [from, to].
function Audio.fadeOut(t, from, to)
	if t <= from then return 1 end
	return 0.5 + 0.5 * cos(pi * min(1, (t - from) / (to - from)))
end

function Audio.midiHz(note)
	return 440 * 2 ^ ((note - 69) / 12)
end

return Audio
