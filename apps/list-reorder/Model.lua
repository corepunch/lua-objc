--[[
  Model for the reorderable list example.

  Represents a collection of tasks that can be reordered via drag-and-drop.
  Each task has an _id, title, and done status.
]]

local Model = {}

-- Initial task list
Model.tasks = {
  { _id = "1", title = "Design new onboarding flow", done = false, priority = "high" },
  { _id = "2", title = "Review PR #42", done = true, priority = "medium" },
  { _id = "3", title = "Update API documentation", done = false, priority = "low" },
  { _id = "4", title = "Fix layout bugs in settings", done = false, priority = "high" },
  { _id = "5", title = "Merge develop into main", done = false, priority = "medium" },
  { _id = "6", title = "Deploy to staging", done = true, priority = "high" },
}

-- Find a task by ID
function Model.find(id)
  for _, task in ipairs(Model.tasks) do
    if task._id == id then return task end
  end
end

-- Toggle a task's done status
function Model.toggleDone(id)
  local task = Model.find(id)
  if task then
    task.done = not task.done
  end
end

-- Get the current order as an array of IDs (for comparison with new state)
function Model.getOrder()
  local order = {}
  for i, task in ipairs(Model.tasks) do
    order[i] = task._id
  end
  return order
end

-- Apply a reorder difference to the tasks array
function Model.applyReorder(difference)
  if not difference then return end
  local reorder = require("ui.reorder")
  if getmetatable(difference) == reorder.Difference then
    difference:apply(Model.tasks)
  end
end

return Model
