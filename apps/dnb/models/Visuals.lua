-- Visualizer state: smooths raw spectrum frames into falling bars with peak
-- holds, follows kicks, snares and beats from the synth timeline, directs
-- the scene plugins (one per section and phrase, or one the user pinned)
-- with a crossfade, and packs it all into the float layout documented at the
-- top of shaders/Kit.metal.
local Visuals = {}
Visuals.__index = Visuals

Visuals.bands = 40
Visuals.header = 20

-- The main view rect as fractions of the view from its top-left: where
-- scenes centre their subject. The whole view until a layout says otherwise.
Visuals.fullStage = {x = 0, y = 0, width = 1, height = 1}

local MOTION = {
	attack = 0.65,     -- share of a rise applied per frame
	fall = 1.5,        -- bar fall speed, heights per second
	peakHold = 0.45,   -- seconds a peak cap waits before falling
	peakFall = 0.7,
	kickDecay = 0.16,  -- seconds for a kick flash to fade to 1/e
	snareDecay = 0.12,
	presence = 2.5,    -- idle ↔ playing crossfade rate per second
	levelGain = 2.2,   -- RMS is small; scale it into 0…1
	floorDb = 78,      -- the analyser's 0…1 range, see AudioStream
	displayDb = 48,    -- bars span the top 48 dB, where a mix actually lives
	curve = 1.4,       -- expands loud differences so kicks and drops stand out
	crossfade = 1.6,   -- seconds from one scene to the next
	idleTravel = 0.15, -- scene travel speed at rest, and its gain from the level
	travelGain = 1.4,
}

-- Sections without scenes of their own borrow the drop's.
local SECTIONS = {"intro", "build", "drop", "breakdown", "outro"}
local BORROW = {outro = "drop", intro = "drop", build = "drop", breakdown = "drop"}
local PHRASE = 8 -- bars per scene inside a section

-- Scene numbers are 0-based plugin indices, the shader's switch.
local function pools(scenes)
	local result = {}
	for _, section in ipairs(SECTIONS) do result[section] = {} end
	for index, scene in ipairs(scenes) do
		for _, section in ipairs(scene.sections) do
			assert(result[section], "unknown section " .. tostring(section))
			table.insert(result[section], index - 1)
		end
	end
	for section, pool in pairs(result) do
		if #pool == 0 then result[section] = result[BORROW[section]] end
	end
	assert(#result.drop > 0, "some scene must play in drops")
	return result
end

-- Analyser level (0…1 over 78 dB) at full volume → bar height.
local function display(raw, lift)
	local db = (math.min(1, raw + lift) - 1) * MOTION.floorDb
	local x = 1 + db / MOTION.displayDb
	if x <= 0 then return 0 end
	return x ^ MOTION.curve
end
local INTENSITY = {intro = 0.35, build = 0.7, drop = 1, breakdown = 0.5}

-- `scenes` are the visualizer plugins' manifests, in shader order.
function Visuals.new(scenes, bands)
	local pool = pools(scenes)
	local idle = pool.intro[1]
	local self = setmetatable({n = bands or Visuals.bands, levels = {}, peaks = {}, holds = {},
		level = 0, kick = 0, snare = 0, presence = 0, hue = 0, intensity = 0.35, progress = 0, beat = 0,
		barPhase = 0, travel = 0, low = 0, high = 0, pools = pool, idle = idle, count = #scenes,
		scene = idle, nextScene = idle, fade = 0, sceneKey = nil, values = {}}, Visuals)
	for i = 1, self.n do self.levels[i], self.peaks[i], self.holds[i] = 0, 0, 0 end
	return self
end

--- Pins scene `index` (0-based), or returns to directing with nil. The
--- change crossfades like any other.
function Visuals:pin(index)
	assert(index == nil or (index >= 0 and index < self.count), "no scene " .. tostring(index))
	self.pinned, self.sceneKey = index, nil
	self:cut(index or self.idle)
end

-- Starts a crossfade to `scene`; one arriving mid-crossfade lands the
-- running one first.
function Visuals:cut(scene)
	if scene == self.nextScene then return end
	if self.fade > 0 then self.scene = self.nextScene end
	self.nextScene, self.fade = scene, 0
end

-- The scene a bar asks for: the section's pool, advanced once per phrase
-- and per section, never repeating the scene already showing.
function Visuals:sceneFor(bar)
	if self.pinned then return self.pinned, "pinned" end
	local pool = self.pools[bar.section] or self.pools.drop
	local start = (bar.number or 0) - bar.sectionBar
	local index = start // 4 + bar.sectionBar // PHRASE
	local scene = pool[index % #pool + 1]
	if scene == self.scene and #pool > 1 then scene = pool[(index + 1) % #pool + 1] end
	return scene, start * 64 + bar.sectionBar // PHRASE
end

function Visuals:follow(bar, playing, dt)
	if playing and bar then
		local scene, key = self:sceneFor(bar)
		if key ~= self.sceneKey then
			self.sceneKey = key
			if scene ~= self.scene then self:cut(scene) end
		end
	elseif not playing then
		local rest = self.pinned or self.idle
		if self.scene ~= rest and self.fade == 0 then self.nextScene, self.sceneKey = rest, nil end
	end
	if self.nextScene ~= self.scene then
		self.fade = self.fade + dt / MOTION.crossfade
		if self.fade >= 1 then self.scene, self.fade = self.nextScene, 0 end
	end
end

-- `frame` describes one display frame: raw band levels (or nil for silence),
-- rms, whether audio plays, the sounding bar, its played frame and sample
-- rate, and the output `gain` (volume). The picture shows the music, not the
-- volume knob, so levels are measured as if at full volume.
function Visuals:update(frame, dt)
	local raw = frame.bands
	local gain = math.max(frame.gain or 1, 0.01)
	local lift = -20 * math.log(gain, 10) / MOTION.floorDb
	local low, high = 0, 0
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
		if i <= self.n // 4 then low = low + level elseif i > self.n * 3 // 4 then high = high + level end
	end
	self.low = low / math.max(1, self.n // 4)
	self.high = high / math.max(1, self.n - self.n * 3 // 4)
	self.level = math.min(1, (frame.rms or 0) / gain * MOTION.levelGain)
	local toward = frame.playing and 1 or 0
	local step = MOTION.presence * dt
	self.presence = self.presence + math.max(-step, math.min(step, toward - self.presence))
	-- Distance travelled, not time: scenes fly faster when the music is
	-- loud without jumping when the level changes.
	self.travel = (self.travel + dt * (MOTION.idleTravel + MOTION.travelGain * self.level * self.presence)) % 4096

	local bar = frame.bar
	self.kick = self.kick * math.exp(-dt / MOTION.kickDecay)
	self.snare = self.snare * math.exp(-dt / MOTION.snareDecay)
	if bar then
		local rate = frame.sampleRate
		local function flash(frames, decay)
			local since
			for _, at in ipairs(frames or {}) do
				if at <= frame.played then since = (frame.played - at) / rate end
			end
			return (since and frame.playing) and math.exp(-since / decay) or 0
		end
		self.kick = math.max(self.kick, flash(bar.kicks, MOTION.kickDecay))
		self.snare = math.max(self.snare, flash(bar.snares, MOTION.snareDecay))
		local beatFrames = bar.frames / 4
		self.beat = ((frame.played - bar.frame) / beatFrames) % 1
		self.barPhase = math.max(0, math.min(1, (frame.played - bar.frame) / bar.frames))
		self.progress = (bar.sectionBar + self.barPhase) / bar.sectionLength
		self.intensity = INTENSITY[bar.section] or 1
		self.hue = (bar.tonic or 0) / 12
	end
	self:follow(bar, frame.playing, dt)
	return self:pack(frame.stage)
end

-- True once bars, peaks, pulses and scene changes have come to rest, so an
-- idle window can stop sending values.
function Visuals:settled()
	if self.kick > 1e-3 or self.snare > 1e-3 or (self.presence > 0 and self.presence < 1) then return false end
	if self.scene ~= self.nextScene then return false end
	for i = 1, self.n do
		if self.levels[i] > 1e-3 or self.peaks[i] > 1e-3 then return false end
	end
	return true
end

--- The scenes on the visualizer's layers, 0-based: the current scene, then
--- the one crossfading in while a cut runs.
function Visuals:layers()
	if self.nextScene ~= self.scene then return {self.scene, self.nextScene} end
	return {self.scene}
end

-- Each open view packs its own `stage`: the main window's sits above its
-- panels, the mini player's above its transport bar.
function Visuals:pack(stage)
	stage = stage or Visuals.fullStage
	local v = self.values
	v[1], v[2], v[3], v[4] = self.level, self.kick, self.hue, self.intensity
	v[5], v[6], v[7], v[8] = self.progress, self.beat, self.presence, self.n
	v[9], v[10], v[11], v[12] = self.scene, self.nextScene, self.fade, self.snare
	v[13], v[14], v[15], v[16] = self.low, self.high, self.travel, self.barPhase
	v[17], v[18], v[19], v[20] = stage.x, stage.y, stage.width, stage.height
	local h = Visuals.header
	for i = 1, self.n do
		v[h + i] = self.levels[i]
		v[h + self.n + i] = self.peaks[i]
	end
	return v
end

return Visuals
