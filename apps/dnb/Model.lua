-- Generator settings: which parts play and how the sound is shaped. The part
-- and control tables are the single source of truth for the checkboxes and
-- sliders the window renders, the Composer's gating and the Synth's mix.
local Model = {}
Model.__index = Model

Model.partGroups = {
	{title = "Drums", parts = {
		{id = "kick", label = "Kick"},
		{id = "snare", label = "Snare"},
		{id = "ghosts", label = "Ghosts"},
		{id = "hats", label = "Hi-hats"},
		{id = "ride", label = "Ride"},
		{id = "percussion", label = "Perc"},
	}},
	{title = "Music", parts = {
		{id = "sub", label = "Sub"},
		{id = "reese", label = "Reese"},
		{id = "pads", label = "Pads"},
		{id = "stabs", label = "Stabs"},
	}},
	{title = "Structure", parts = {
		{id = "arrangement", label = "Arrange"},
		{id = "fills", label = "Fills"},
	}},
}

-- `format` renders the value label beside each slider.
local function percent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
Model.controlGroups = {
	{title = "Groove", controls = {
		{id = "tempo", label = "Tempo", min = 160, max = 180, default = 174, step = 1,
			format = function(v) return string.format("%d BPM", v) end},
		{id = "energy", label = "Energy", min = 0, max = 1, default = 0.65, format = percent},
		{id = "swing", label = "Swing", min = 0, max = 0.5, default = 0.12, format = percent},
	}},
	{title = "Sound", controls = {
		{id = "cutoff", label = "Filter", min = 0, max = 1, default = 0.5, format = percent},
		{id = "wobble", label = "Wobble", min = 0, max = 1, default = 0.3, format = percent},
		{id = "drive", label = "Drive", min = 0, max = 1, default = 0.35, format = percent},
		{id = "space", label = "Space", min = 0, max = 1, default = 0.35, format = percent},
		{id = "volume", label = "Volume", min = 0, max = 1, default = 0.8, format = percent},
	}},
}

local partsById, controlsById = {}, {}
for _, group in ipairs(Model.partGroups) do
	for _, part in ipairs(group.parts) do partsById[part.id] = part end
end
for _, group in ipairs(Model.controlGroups) do
	for _, control in ipairs(group.controls) do controlsById[control.id] = control end
end

function Model.new(seed)
	local self = setmetatable({parts = {}, values = {}, seed = seed or 1}, Model)
	for id in pairs(partsById) do self.parts[id] = true end
	for id, control in pairs(controlsById) do self.values[id] = control.default end
	return self
end

function Model:enabled(id)
	assert(partsById[id], "unknown part: " .. tostring(id))
	return self.parts[id]
end

function Model:setEnabled(id, on)
	assert(partsById[id], "unknown part: " .. tostring(id))
	self.parts[id] = on and true or false
end

function Model:value(id)
	assert(controlsById[id], "unknown control: " .. tostring(id))
	return self.values[id]
end

-- Clamps to the control's range and snaps stepped controls; returns the
-- stored value so callers can display exactly what will play.
function Model:setValue(id, value)
	local control = assert(controlsById[id], "unknown control: " .. tostring(id))
	value = tonumber(value) or control.default
	value = math.max(control.min, math.min(control.max, value))
	if control.step then
		value = control.min + math.floor((value - control.min) / control.step + 0.5) * control.step
		value = math.tointeger(value) or value
	end
	self.values[id] = value
	return value
end

function Model:formatted(id)
	return controlsById[id].format(self:value(id))
end

-- A new seed gives a new track: key, progressions, grooves and bass lines.
function Model:reseed(seed)
	self.seed = seed
end

return Model
