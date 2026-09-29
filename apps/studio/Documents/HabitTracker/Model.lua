local Model = {}
Model.__index = Model

local STARTER_HABITS = {
	{ id = "move", title = "Move your body", detail = "30 minutes of movement", symbol = "figure.run", tint = "systemOrange", streak = 8, done = true },
	{ id = "read", title = "Read a little", detail = "10 pages, no distractions", symbol = "book.closed.fill", tint = "systemIndigo", streak = 12, done = true },
	{ id = "water", title = "Drink water", detail = "8 glasses through the day", symbol = "drop.fill", tint = "systemBlue", streak = 5 },
	{ id = "journal", title = "Write a few lines", detail = "A small reflection counts", symbol = "pencil.line", tint = "systemPurple", streak = 3 },
}

local function copyHabits(source)
	local result = {}
	for _, habit in ipairs(source) do
		local item = {}
		for key, value in pairs(habit) do item[key] = value end
		table.insert(result, item)
	end
	return result
end

function Model.new(storage)
	local saved
	if storage and storage.get and storage.decode then
		local source = storage.get("habit-state")
		if source then
			local ok, value = pcall(storage.decode, source)
			if ok and type(value) == "table" and type(value.habits) == "table" then saved = value end
		end
	end
	local reminders, weeklyGoal = true, 5
	if saved then
		if type(saved.reminders) == "boolean" then reminders = saved.reminders end
		if type(saved.weeklyGoal) == "number" then weeklyGoal = saved.weeklyGoal end
	end
	return setmetatable({ storage = storage, habits = copyHabits(saved and saved.habits or STARTER_HABITS),
		reminders = reminders, weeklyGoal = weeklyGoal }, Model)
end

function Model:save()
	if not (self.storage and self.storage.set and self.storage.encode) then return true end
	local source = self.storage.encode({ habits = self.habits, reminders = self.reminders, weeklyGoal = self.weeklyGoal })
	return self.storage.set("habit-state", source)
end

function Model:toggle(id)
	for _, habit in ipairs(self.habits) do
		if habit.id == id then habit.done = not habit.done; self:save(); return habit end
	end
end

function Model:setReminders(value)
	self.reminders = value == true
	self:save()
end

function Model:progress()
	local done = 0
	for _, habit in ipairs(self.habits) do if habit.done then done = done + 1 end end
	return { done = done, total = #self.habits,
		fraction = #self.habits > 0 and done / #self.habits or 0 }
end

function Model:presentation()
	local progress = self:progress()
	local rows = {}
	for _, habit in ipairs(self.habits) do
		local row = {}
		for key, value in pairs(habit) do row[key] = value end
		row.action = "toggle_" .. habit.id
		table.insert(rows, row)
	end
	return {
		habits = rows,
		progress = progress,
		greeting = progress.done == progress.total and "You showed up for yourself." or "A little progress goes a long way.",
		streak = 12,
		week = { { day = "M", value = 0.58 }, { day = "T", value = 0.82 }, { day = "W", value = 0.48 },
			{ day = "T", value = 1.0 }, { day = "F", value = 0.69 }, { day = "S", value = 0.36 }, { day = "S", value = 0.16 } },
		reminders = self.reminders,
		weeklyGoal = self.weeklyGoal,
	}
end

return Model
