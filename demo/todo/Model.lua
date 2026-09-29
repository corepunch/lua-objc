-- Today's tasks: sample data, the queries the views read and the one
-- mutation the app has (checking a task off). No persistence.
local Model = {}
Model.__index = Model

Model.PROJECTS = {
	{id = "launch", name = "Launch", color = "systemBlue", symbol = "paperplane.fill"},
	{id = "home", name = "Home", color = "systemOrange", symbol = "house.fill"},
	{id = "studio", name = "Studio", color = "systemPurple", symbol = "paintbrush.pointed.fill"},
	{id = "personal", name = "Personal", color = "systemGreen", symbol = "leaf.fill"},
}

Model.TASKS = {
	{id = 1, title = "Ship the onboarding redesign", project = "launch", due = "10:00", done = true},
	{id = 2, title = "Review App Store screenshots", project = "launch", due = "11:30", flagged = true},
	{id = 3, title = "Morning run, 5 km", project = "personal", due = "7:00", done = true},
	{id = 4, title = "Sketch icon variations", project = "studio", due = "13:00"},
	{id = 5, title = "Water the fig tree", project = "home", done = true},
	{id = 6, title = "Book the venue for the launch party", project = "launch", due = "14:00"},
	{id = 7, title = "Export the brand colour palette", project = "studio", done = true},
	{id = 8, title = "Pick up the dry cleaning", project = "home", due = "17:30"},
	{id = 9, title = "Call Mum", project = "personal", due = "19:00", flagged = true},
}

-- The filters above the list, in order.
Model.FILTERS = {"All", "Open", "Flagged"}

-- `tasks` replaces the sample tasks (tests use small lists).
function Model.new(tasks)
	local self = setmetatable({tasks = {}, projects = {}, filter = 1}, Model)
	for _, project in ipairs(Model.PROJECTS) do self.projects[project.id] = project end
	for _, task in ipairs(tasks or Model.TASKS) do
		local copy = {}
		for key, value in pairs(task) do copy[key] = value end
		table.insert(self.tasks, copy)
	end
	return self
end

-- `index` is the 1-based position in FILTERS.
function Model:setFilter(index)
	if Model.FILTERS[index] then self.filter = index end
end

local SHOWN = {
	All = function() return true end,
	Open = function(task) return not task.done end,
	Flagged = function(task) return task.flagged == true end,
}

function Model:find(id)
	for _, task in ipairs(self.tasks) do if task.id == id then return task end end
end

function Model:toggle(id)
	local task = self:find(id)
	if task then task.done = not task.done end
	return task
end

-- One task as the views draw it.
function Model:row(task)
	local project = self.projects[task.project]
	return {
		id = task.id, title = task.title, done = task.done == true, flagged = task.flagged == true,
		due = task.due, project = project.name, color = project.color, symbol = project.symbol,
	}
end

function Model:progress()
	local done = 0
	for _, task in ipairs(self.tasks) do if task.done then done = done + 1 end end
	local total = #self.tasks
	return {done = done, total = total, share = total > 0 and done / total or 0}
end

-- The sidebar: smart lists, then one list per project, with open-task
-- counts as badges. Section rows are source-list group headers.
function Model:lists()
	local open, flagged, total = {}, 0, 0
	for _, task in ipairs(self.tasks) do
		if not task.done then
			open[task.project] = (open[task.project] or 0) + 1
			total = total + 1
			if task.flagged then flagged = flagged + 1 end
		end
	end
	local lists = {
		{id = "today", name = "Today", icon = "calendar", color = "systemBlue", badge = tostring(total)},
		{id = "scheduled", name = "Scheduled", icon = "calendar.badge.clock", color = "systemRed", badge = "12"},
		{id = "flagged", name = "Flagged", icon = "flag.fill", color = "systemOrange", badge = tostring(flagged)},
		{section = true, title = "My Lists"},
	}
	for _, project in ipairs(Model.PROJECTS) do
		table.insert(lists, {id = project.id, name = project.name, icon = project.symbol, color = project.color,
			badge = tostring(open[project.id] or 0)})
	end
	return lists
end

-- Everything the content template reads: the tasks the filter shows, in
-- order and split into open and completed, the filters (the picker's value
-- is 0-based) and the progress over the whole day.
function Model:presentation()
	local all, open, completed = {}, {}, {}
	local shown = SHOWN[Model.FILTERS[self.filter]]
	for _, task in ipairs(self.tasks) do
		if shown(task) then
			local row = self:row(task)
			table.insert(all, row)
			table.insert(task.done and completed or open, row)
		end
	end
	return {
		title = "Today",
		date = "Tuesday, 29 September",
		tasks = all,
		open = open,
		completed = completed,
		filters = Model.FILTERS,
		filter = self.filter - 1,
		progress = self:progress(),
		lists = self:lists(),
	}
end

return Model
