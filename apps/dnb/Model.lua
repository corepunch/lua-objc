-- Generator settings: the style and how its sound is shaped. The control
-- table is the single source of truth for the sliders the window renders
-- and the Synth's mix. A style (a plugin manifest) sets the controls'
-- starting values; its tracks, not the listener, decide what plays and how
-- fast.
local Model = {}
Model.__index = Model

-- A track plays on eight channels, as a tracker module does. Each track
-- names its own from these roles, so one tune's channels are not the
-- next's. `family` matches a role to its Mix fader.
Model.channels = 8
Model.roles = {
	{id = "drums", family = "drums", title = "Drums"},
	{id = "tops", family = "drums", title = "Tops"},
	{id = "bass", family = "bass", title = "Bass"},
	{id = "pad", family = "chords", title = "Pad"},
	{id = "keys", family = "chords", title = "Keys"},
	{id = "stab", family = "chords", title = "Stab"},
	{id = "arp", family = "melody", title = "Arp"},
	{id = "lead", family = "melody", title = "Lead"},
	{id = "counter", family = "melody", title = "Counter"},
	{id = "texture", family = "fx", title = "Texture"},
	{id = "fx", family = "fx", title = "FX"},
}
Model.family, Model.roleIndex, Model.faders = {}, {}, {}
for i, role in ipairs(Model.roles) do
	Model.family[role.id] = role.family
	Model.roleIndex[role.id] = i
end
-- Effects have no fader: they follow the style's level.
for _, family in ipairs({"drums", "bass", "chords", "melody"}) do Model.faders[family] = family end

-- `format` renders the value label beside each slider.
local function percent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
Model.controlGroups = {
	{title = "Groove", controls = {
		-- A turntable's pitch fader: every track has its own tempo, and this
		-- moves it, and the pitch of its drum loops, a few percent.
		{id = "pitch", label = "Pitch", min = -8, max = 8, default = 0, step = 0.5,
			format = function(v) return string.format("%+.1f%%", v) end},
		{id = "energy", label = "Energy", min = 0, max = 1, default = 0.65, format = percent},
		{id = "complexity", label = "Complexity", min = 0, max = 1, default = 0.5, format = percent},
		-- Swing scales the track's own; 100% is the groove as it was written.
		{id = "swing", label = "Swing", min = 0, max = 2, default = 1, format = percent},
		{id = "humanize", label = "Humanize", min = 0, max = 1, default = 0.35, format = percent},
	}},
	-- Filter, Wobble and Drive move the bass around its patch: the middle
	-- of Filter and 100% of the others are the patch as it was designed.
	{title = "Sound", controls = {
		{id = "cutoff", label = "Filter", min = 0, max = 1, default = 0.5, format = percent},
		{id = "wobble", label = "Wobble", min = 0, max = 2, default = 1, format = percent},
		{id = "drive", label = "Drive", min = 0, max = 2, default = 1, format = percent},
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
for _, role in ipairs(Model.roles) do known[role.id] = true end
for _, group in ipairs(Model.controlGroups) do
	for _, control in ipairs(group.controls) do controlsById[control.id] = control end
end

function Model.new(seed, style)
	local self = setmetatable({values = {}, ranges = {}, seed = seed or 1}, Model)
	local roles = {}
	for _, role in ipairs(Model.roles) do table.insert(roles, role.id) end
	self:setRoles(roles)
	for id, control in pairs(controlsById) do
		self.values[id] = control.default
		self.ranges[id] = {min = control.min, max = control.max}
	end
	if style then self:setStyle(style) end
	return self
end

-- Takes a style's control defaults.
function Model:setStyle(style)
	self.style = style
	for id, control in pairs(controlsById) do
		self:setValue(id, (style.defaults or {})[id] or control.default)
	end
	for id in pairs(style.defaults or {}) do assert(controlsById[id], "unknown control default: " .. id) end
end

function Model:range(id)
	local range = assert(self.ranges[id], "unknown control: " .. tostring(id))
	return range.min, range.max
end

-- The channels that sound, by role; every one does by default. Muting a
-- role silences its blocks without changing the arrangement.
function Model:setRoles(ids)
	self.playing = {}
	for _, id in ipairs(ids) do
		assert(known[id], "unknown role: " .. tostring(id))
		self.playing[id] = true
	end
end

function Model:plays(id)
	assert(known[id], "unknown role: " .. tostring(id))
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
