-- Visualizer state: smooths raw spectrum frames into falling bars with peak
-- holds, follows kicks and beats from the synth timeline, and packs it all
-- into the float layout documented at the top of shaders/Visualizer.metal.
local Visuals = {}
Visuals.__index = Visuals

Visuals.bands = 40

local MOTION = {
	attack = 0.65,     -- share of a rise applied per frame
	fall = 1.5,        -- bar fall speed, heights per second
	peakHold = 0.45,   -- seconds a peak cap waits before falling
	peakFall = 0.7,
	kickDecay = 0.16,  -- seconds for a kick flash to fade to 1/e
	presence = 2.5,    -- idle ↔ playing crossfade rate per second
	levelGain = 2.2,   -- RMS is small; scale it into 0…1
	floorDb = 78,      -- the analyser's 0…1 range, see AudioStream
	displayDb = 48,    -- bars span the top 48 dB, where a mix actually lives
	curve = 1.4,       -- expands loud differences so kicks and drops stand out
}

-- Analyser level (0…1 over 78 dB) at full volume → bar height.
local function display(raw, lift)
	local db = (math.min(1, raw + lift) - 1) * MOTION.floorDb
	local x = 1 + db / MOTION.displayDb
	if x <= 0 then return 0 end
	return x ^ MOTION.curve
end
local INTENSITY = {intro = 0.35, build = 0.7, drop = 1, breakdown = 0.5}

function Visuals.new(bands)
	local self = setmetatable({n = bands or Visuals.bands, levels = {}, peaks = {}, holds = {},
		level = 0, kick = 0, presence = 0, hue = 0, intensity = 0.35, progress = 0, beat = 0, values = {}}, Visuals)
	for i = 1, self.n do self.levels[i], self.peaks[i], self.holds[i] = 0, 0, 0 end
	return self
end

-- `frame` describes one display frame: raw band levels (or nil for silence),
-- rms, whether audio plays, the sounding bar, its played frame and sample
-- rate, and the output `gain` (volume). The picture shows the music, not the
-- volume knob, so levels are measured as if at full volume.
function Visuals:update(frame, dt)
	local raw = frame.bands
	local gain = math.max(frame.gain or 1, 0.01)
	local lift = -20 * math.log(gain, 10) / MOTION.floorDb
	for i = 1, self.n do
		local target = raw and raw[i] and raw[i] > 0 and display(raw[i], lift) or 0
		local level = self.levels[i]
		if target > level then
			level = level + (target - level) * MOTION.attack
		else
			level = math.max(target, level - MOTION.fall * dt)
		end
		self.levels[i] = level
		if level >= self.peaks[i] then
			self.peaks[i], self.holds[i] = level, MOTION.peakHold
		elseif self.holds[i] > 0 then
			self.holds[i] = self.holds[i] - dt
		else
			self.peaks[i] = math.max(level, self.peaks[i] - MOTION.peakFall * dt)
		end
	end
	self.level = math.min(1, (frame.rms or 0) / gain * MOTION.levelGain)
	local toward = frame.playing and 1 or 0
	local step = MOTION.presence * dt
	self.presence = self.presence + math.max(-step, math.min(step, toward - self.presence))

	local bar = frame.bar
	self.kick = self.kick * math.exp(-dt / MOTION.kickDecay)
	if bar then
		local rate = frame.sampleRate
		local since
		for _, at in ipairs(bar.kicks or {}) do
			if at <= frame.played then since = (frame.played - at) / rate end
		end
		if since and frame.playing then self.kick = math.max(self.kick, math.exp(-since / MOTION.kickDecay)) end
		local beatFrames = bar.frames / 4
		self.beat = ((frame.played - bar.frame) / beatFrames) % 1
		self.progress = (bar.sectionBar + math.min(1, (frame.played - bar.frame) / bar.frames)) / bar.sectionLength
		self.intensity = INTENSITY[bar.section] or 1
		self.hue = (bar.tonic or 0) / 12
	end
	return self:pack()
end

-- True once bars, peaks and pulses have come to rest, so an idle window can
-- stop sending values.
function Visuals:settled()
	if self.kick > 1e-3 or (self.presence > 0 and self.presence < 1) then return false end
	for i = 1, self.n do
		if self.levels[i] > 1e-3 or self.peaks[i] > 1e-3 then return false end
	end
	return true
end

function Visuals:pack()
	local v = self.values
	v[1], v[2], v[3], v[4] = self.level, self.kick, self.hue, self.intensity
	v[5], v[6], v[7], v[8] = self.progress, self.beat, self.presence, self.n
	for i = 1, self.n do
		v[8 + i] = self.levels[i]
		v[8 + self.n + i] = self.peaks[i]
	end
	return v
end

return Visuals
