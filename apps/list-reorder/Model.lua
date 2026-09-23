local reorder = require("ui.reorder")

local Model = {}
Model.__index = Model

local initialTasks = {
	{ _id = "1", title = "Design new onboarding flow", done = false },
	{ _id = "2", title = "Review the latest pull request", done = true },
	{ _id = "3", title = "Update API documentation", done = false },
	{ _id = "4", title = "Fix layout bugs in settings", done = false },
	{ _id = "5", title = "Merge the current release branch", done = false },
	{ _id = "6", title = "Deploy to staging", done = true },
}

function Model.new(tasks)
	local rows = {}
	for index, task in ipairs(tasks or initialTasks) do
		rows[index] = {
			_id = task._id,
			title = task.title,
			done = task.done,
		}
	end
	return setmetatable({ tasks = rows }, Model)
end

function Model:applyReorder(difference)
	if getmetatable(difference) ~= reorder.Difference then
		return false
	end
	difference:apply(self.tasks)
	return true
end

return Model
