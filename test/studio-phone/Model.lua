-- Lua Studio on a phone, as a prototype: the running project fills the
-- screen and Studio is a glass capsule over it that opens the
-- conversation as a sheet. The data here is a showcase: one project, its
-- habits, a conversation with one edit, and the project's real source for
-- the code page. Nothing talks to a provider.
local Model = {}
Model.__index = Model

local PROJECT = { id = "HabitTracker", title = "Habit Garden", icon = "leaf.fill", model = "openrouter/free" }

local PROJECTS = {
	{ id = "HabitTracker", title = "Habit Garden", icon = "leaf.fill", selected = true },
	{ id = "CoinQuest", title = "Coin Quest", icon = "gamecontroller.fill" },
	{ id = "StarterApp", title = "Starter App", icon = "app.dashed" },
}

local HABITS = {
	{ id = "move", title = "Move your body", detail = "30 minutes of movement", symbol = "figure.run", tint = "systemOrange", done = true },
	{ id = "read", title = "Read a little", detail = "10 pages, no distractions", symbol = "book.closed.fill", tint = "systemIndigo", done = true },
	{ id = "water", title = "Drink water", detail = "8 glasses through the day", symbol = "drop.fill", tint = "systemBlue" },
	{ id = "journal", title = "Write a few lines", detail = "A small reflection counts", symbol = "pencil.line", tint = "systemPurple" },
}

-- The conversation a fresh launch shows: the last turn already changed the
-- project, so the capsule has something to report.
local CONVERSATION = {
	{ role = "user", text = "Add a streak badge next to the title and celebrate when every habit is done." },
	{ role = "agent", text = "Added a flame badge with the current streak to the Today header, and the summary card now cheers once every habit is checked.",
		changes = {
			{ path = "views/Today.etlua", added = 9, removed = 2, lines = {
				'+ <Button title="12 day streak" systemImage="flame.fill" tint="systemOrange" style="bordered" controlSize="small" />' } },
			{ path = "Model.lua", added = 3, removed = 1, lines = {
				'+ greeting = progress.done == progress.total and "You showed up for yourself."' } },
		},
		conclusion = "Check a habit in the preview to see the card change.",
		previewState = "ready" },
}

-- The canned reply to anything typed: the prototype has no provider.
local REPLY = {
	role = "agent", text = "Done. The Today screen now sorts unfinished habits first so the next one is always at the top.",
	changes = { { path = "Model.lua", added = 6, removed = 0, lines = { "+ table.sort(rows, function(a, b) return (a.done and 1 or 0) < (b.done and 1 or 0) end)" } } },
	previewState = "ready",
}

local FILES = { "Controller.lua", "Model.lua", "views/Window.etlua", "views/Today.etlua", "views/Stats.etlua", "views/Settings.etlua" }

function Model.new(read)
	local habits = {}
	for _, habit in ipairs(HABITS) do
		local copy = {}
		for key, value in pairs(habit) do copy[key] = value end
		table.insert(habits, copy)
	end
	local messages = {}
	for _, message in ipairs(CONVERSATION) do table.insert(messages, message) end
	return setmetatable({ read = read, habits = habits, messages = messages, draft = "", selectedFile = "Controller.lua" }, Model)
end

function Model:toggle(id)
	for _, habit in ipairs(self.habits) do
		if habit.id == id then habit.done = not habit.done; return habit end
	end
end

function Model:progress()
	local done = 0
	for _, habit in ipairs(self.habits) do if habit.done then done = done + 1 end end
	return { done = done, total = #self.habits, fraction = #self.habits > 0 and done / #self.habits or 0 }
end

-- The running project's screen.
function Model:app()
	local progress = self:progress()
	local rows = {}
	for _, habit in ipairs(self.habits) do
		local row = {}
		for key, value in pairs(habit) do row[key] = value end
		row.action = "toggle_" .. habit.id
		table.insert(rows, row)
	end
	return {
		habits = rows, progress = progress, streak = 12,
		greeting = progress.done == progress.total and "You showed up for yourself." or "A little progress goes a long way.",
		week = { { day = "M", value = 0.58 }, { day = "T", value = 0.82 }, { day = "W", value = 0.48 },
			{ day = "T", value = 1.0 }, { day = "F", value = 0.69 }, { day = "S", value = 0.36 }, { day = "S", value = 0.16 } },
		reminders = true, weeklyGoal = 5,
	}
end

-- What the capsule says: the last agent turn, summarised, or an invitation.
function Model:status()
	local last = self.messages[#self.messages]
	if last and last.role == "agent" and last.changes then
		local files, added, removed = #last.changes, 0, 0
		for _, change in ipairs(last.changes) do added, removed = added + change.added, removed + (change.removed or 0) end
		local delta = "+" .. added .. (removed > 0 and (" −" .. removed) or "")
		return { title = "Preview updated", detail = files .. (files == 1 and " file" or " files") .. " changed, " .. delta .. ". Tap to review." }
	end
	return { title = "Ask to change anything", detail = PROJECT.title .. " · " .. PROJECT.model }
end

function Model:send(text)
	if type(text) ~= "string" or text:match("^%s*$") then return nil end
	table.insert(self.messages, { role = "user", text = text })
	table.insert(self.messages, REPLY)
	self.draft = ""
	return true
end

function Model:selectFile(name)
	for _, file in ipairs(FILES) do
		if file == name then self.selectedFile = name; return true end
	end
	return nil
end

function Model:code()
	local path = "apps/studio/Documents/HabitTracker/" .. self.selectedFile
	local ok, source = pcall(self.read, path)
	return { name = self.selectedFile, text = ok and source or ("-- " .. tostring(source)),
		language = self.selectedFile:match("%.(%w+)$") or "lua", files = FILES }
end

Model.project = PROJECT
Model.projects = PROJECTS
Model.files = FILES
return Model
