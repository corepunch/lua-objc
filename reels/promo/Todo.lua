-- The Todo app's states the film moves between on the phone, with the
-- order of its rows taken from the app's own model: the edits (v0…v3) and
-- the states reached by using it (a task checked, the Open filter). Each
-- state's screenshot is captures/todo-iphone-<name>.png.
local Model = require("demo.todo.Model")

local Todo = {}

-- Visible rows, top to bottom, as the app lays them out: every task in
-- order before the "Group completed tasks" edit, open then completed after.
local function rows(model, grouped)
	local view = model:presentation()
	local ids = {}
	if not grouped then
		for _, task in ipairs(view.tasks) do table.insert(ids, task.id) end
		return ids
	end
	for _, task in ipairs(view.open) do table.insert(ids, task.id) end
	for _, task in ipairs(view.completed) do table.insert(ids, task.id) end
	return ids
end

function Todo.states()
	-- The task checked on the preview stays checked from then on.
	local checked = Model.new()
	checked:toggle(2)
	local open = Model.new()
	open:toggle(2)
	open:setFilter(2)
	return {
		v0 = rows(Model.new(), false),
		v1 = rows(Model.new(), true),
		v2 = rows(Model.new(), true),
		checked = rows(checked, true),
		filtered = rows(checked, true),
		open = rows(open, true),
	}
end

return Todo
