-- Sample fitness, storage and sleep data for the component gallery. The
-- numbers come from a fixed seed so every launch, screenshot and test sees
-- the same week; `advance` moves the week on by one day.
local Model = {}
Model.__index = Model

local DAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
-- Half a year of daily activity, a week per heatmap column.
local HISTORY = 26 * 7

-- A small linear congruential generator: deterministic across platforms.
-- Its low bits repeat every few draws, so a draw reads the high ones.
local function generator(seed)
	local state = seed
	return function(low, high)
		state = (state * 1103515245 + 12345) % 2147483648
		return low + (state // 65536) % (high - low + 1)
	end
end

function Model.new(seed)
	local self = setmetatable({ day = 1, random = generator(seed or 7) }, Model)
	self.rings = {
		{ id = "move", label = "Move", unit = "kcal", value = 420, goal = 500, color = "systemRed" },
		{ id = "exercise", label = "Exercise", unit = "min", value = 24, goal = 30, color = "systemGreen" },
		{ id = "stand", label = "Stand", unit = "hr", value = 9, goal = 12, color = "systemCyan" },
	}
	self.steps = {}
	for index = 1, #DAYS do
		table.insert(self.steps, { day = DAYS[index], value = self.random(3000, 12000) })
	end
	self.history = {}
	for index = 1, HISTORY do
		table.insert(self.history, { day = index, value = self.random(0, 3) == 0 and 0 or self.random(1, 12) })
	end
	self.storage = {
		total = 994,
		segments = {
			{ label = "Applications", value = 182, color = "systemBlue" },
			{ label = "Documents", value = 236, color = "systemPurple" },
			{ label = "Photos", value = 148, color = "systemOrange" },
			{ label = "System Data", value = 96, color = "systemGray" },
		},
	}
	-- Minutes after going to bed.
	self.sleep = {
		duration = 480,
		stages = {
			{ stage = "awake", start = 0, finish = 12 }, { stage = "core", start = 12, finish = 70 },
			{ stage = "deep", start = 70, finish = 118 }, { stage = "core", start = 118, finish = 170 },
			{ stage = "rem", start = 170, finish = 200 }, { stage = "core", start = 200, finish = 262 },
			{ stage = "deep", start = 262, finish = 290 }, { stage = "core", start = 290, finish = 340 },
			{ stage = "rem", start = 340, finish = 382 }, { stage = "awake", start = 382, finish = 390 },
			{ stage = "core", start = 390, finish = 440 }, { stage = "rem", start = 440, finish = 472 },
			{ stage = "awake", start = 472, finish = 480 },
		},
	}
	return self
end

-- Moves the data on by one day: rings refill, the step week scrolls, the
-- heatmap gains a day and loses the oldest, and documents grow.
function Model:advance()
	self.day = self.day + 1
	for _, ring in ipairs(self.rings) do
		ring.value = math.floor(ring.goal * self.random(40, 160) / 100)
	end
	table.remove(self.steps, 1)
	table.insert(self.steps, { day = DAYS[(self.day + #DAYS - 2) % #DAYS + 1], value = self.random(2000, 14000) })
	table.remove(self.history, 1)
	table.insert(self.history, { day = HISTORY + self.day - 1, value = self.random(0, 12) })
	local documents = self.storage.segments[2]
	documents.value = math.min(documents.value + self.random(4, 24), self.storage.total - 600)
end

function Model:used()
	local used = 0
	for _, segment in ipairs(self.storage.segments) do used = used + segment.value end
	return used
end

function Model:activeDays()
	local count = 0
	for _, entry in ipairs(self.history) do if entry.value > 0 then count = count + 1 end end
	return count
end

function Model:weekSteps()
	local total = 0
	for _, entry in ipairs(self.steps) do total = total + entry.value end
	return total
end

-- The plain values the gallery template renders.
function Model:snapshot()
	local rings = {}
	for _, ring in ipairs(self.rings) do
		table.insert(rings, { label = ring.label, value = ring.value, goal = ring.goal, color = ring.color,
			summary = string.format("%s %d of %d %s", ring.label, ring.value, ring.goal, ring.unit) })
	end
	local used = self:used()
	return {
		rings = rings,
		steps = self.steps,
		weekSteps = self:weekSteps(),
		history = self.history,
		activeDays = self:activeDays(),
		storage = self.storage,
		used = used,
		available = self.storage.total - used,
		sleep = self.sleep,
	}
end

return Model
