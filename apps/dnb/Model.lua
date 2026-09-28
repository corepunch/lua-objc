-- Generator settings: the style, which lanes sound and how the sound is
-- shaped. The control table is the single source of truth for the sliders
-- the window renders and the Synth's mix. A style (a plugin manifest)
-- narrows the tempo range and sets the controls' starting values; its
-- arrangement, not the listener, decides what plays.
local Model = {}
Model.__index = Model

-- The lanes of an arrangement, in the timeline's order, by family: the
-- instruments, then the structural moves (fills, risers, half-time…) that
-- are blocks on the timeline too. Families match the Mix faders.
Model.partGroups = {
	{family = "drums", parts = {"kick", "snare", "ghosts", "hats", "ride", "percussion", "amen"}},
	{family = "bass", parts = {"sub", "reese"}},
	{family = "chords", parts = {"pads", "keys", "stabs"}},
	{family = "melody", parts = {"arp", "lead"}},
	{family = "structure", parts = {"fills", "risers", "halftime", "throws", "chops"}},
}
Model.parts, Model.family = {}, {}
for _, group in ipairs(Model.partGroups) do
	for _, id in ipairs(group.parts) do
		table.insert(Model.parts, id)
		Model.family[id] = group.family
	end
end

-- `format` renders the value label beside each slider.
local function percent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
Model.controlGroups = {
	{title = "Groove", controls = {
		{id = "tempo", label = "Tempo", min = 160, max = 180, default = 174, step = 1,
			format = function(v) return string.format("%d BPM", v) end},
		{id = "energy", label = "Energy", min = 0, max = 1, default = 0.65, format = percent},
		{id = "complexity", label = "Complexity", min = 0, max = 1, default = 0.5, format = percent},
		{id = "swing", label = "Swing", min = 0, max = 0.5, default = 0.12, format = percent},
		{id = "humanize", label = "Humanize", min = 0, max = 1, default = 0.35, format = percent},
	}},
	{title = "Sound", controls = {
		{id = "cutoff", label = "Filter", min = 0, max = 1, default = 0.5, format = percent},
		{id = "wobble", label = "Wobble", min = 0, max = 1, default = 0.3, format = percent},
		{id = "drive", label = "Drive", min = 0, max = 1, default = 0.35, format = percent},
		{id = "space", label = "Space", min = 0, max = 1, default = 0.35, format = percent},
		{id = "pump", label = "Pump", min = 0, max = 2, default = 1, format = percent},
	}},
	-- Channel faders over the style's own balance: 100% is the mix as the
	-- style designed it.
	{title = "Mix", controls = {
		{id = "drums", label = "Drums", min = 0, max = 1.5, default = 1, format = percent},
		{id = "bass", label = "Bass", min = 0, max = 1.5, default = 1, format = percent},
		{id = "chords", label = "Chords", min = 0, max = 1.5, default = 1, format = percent},
		{id = "melody", label = "Melody", min = 0, max = 1.5, default = 1, format = percent},
		{id = "volume", label = "Volume", min = 0, max = 1, default = 0.8, format = percent},
	}},
}

local known, controlsById = {}, {}
for _, id in ipairs(Model.parts) do known[id] = true end
for _, group in ipairs(Model.controlGroups) do
	for _, control in ipairs(group.controls) do controlsById[control.id] = control end
end

function Model.new(seed, style)
	local self = setmetatable({values = {}, ranges = {}, seed = seed or 1}, Model)
	self:setParts(Model.parts)
	for id, control in pairs(controlsById) do
		self.values[id] = control.default
		self.ranges[id] = {min = control.min, max = control.max}
	end
	if style then self:setStyle(style) end
	return self
end

-- Takes a style's tempo range and control defaults.
function Model:setStyle(style)
	self.style = style
	local tempo = style.tempo
	assert(tempo.min < tempo.max and tempo.default >= tempo.min and tempo.default <= tempo.max, "bad tempo range")
	self.ranges.tempo = {min = tempo.min, max = tempo.max}
	for id, control in pairs(controlsById) do
		local value = id == "tempo" and tempo.default or (style.defaults or {})[id] or control.default
		self:setValue(id, value)
	end
	for id in pairs(style.defaults or {}) do assert(controlsById[id], "unknown control default: " .. id) end
end

function Model:range(id)
	local range = assert(self.ranges[id], "unknown control: " .. tostring(id))
	return range.min, range.max
end

-- The lanes that sound; every lane does by default. Muting a lane silences
-- its blocks without changing the arrangement.
function Model:setParts(ids)
	self.playing = {}
	for _, id in ipairs(ids) do
		assert(known[id], "unknown part: " .. tostring(id))
		self.playing[id] = true
	end
end

function Model:plays(id)
	assert(known[id], "unknown part: " .. tostring(id))
	return self.playing[id] == true
end

function Model:value(id)
	assert(controlsById[id], "unknown control: " .. tostring(id))
	return self.values[id]
end

-- Clamps to the control's range and snaps stepped controls; returns the
-- stored value so callers can display exactly what will play.
function Model:setValue(id, value)
	local control = assert(controlsById[id], "unknown control: " .. tostring(id))
	local min, max = self:range(id)
	value = tonumber(value) or control.default
	value = math.max(min, math.min(max, value))
	if control.step then
		value = min + math.floor((value - min) / control.step + 0.5) * control.step
		value = math.tointeger(value) or value
	end
	self.values[id] = value
	return value
end

function Model:formatted(id)
	return controlsById[id].format(self:value(id))
end

-- A new seed gives a new set: every track, key, groove and melody in it.
function Model:reseed(seed)
	self.seed = seed
end

return Model
