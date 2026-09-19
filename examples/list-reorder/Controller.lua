--[[
  Controller for the reorderable list example.

  Demonstrates drag-to-reorder functionality with:
  - A reorderable VStack of tasks
  - Reorder callback that updates the model
  - History display showing reorder operations
  - Before/after task order comparison
]]

local ns = require("AppKit")
local reorder = require("ui.reorder")
local Model = require("examples.list-reorder.Model")

-- Track reorder history for display (operations in order)
local reorderHistory = {}

-- Snapshot of task order before current reorder (for computing diffs)
local prevTaskSnapshot = nil

-- Helper to make a task display view
local function makeTaskView(task, index)
  local priorityColors = {
    high = "#FF3B30",
    medium = "#FF9500",
    low = "#34C759",
  }
  local color = priorityColors[task.priority] or "#999999"

  return ns.VStack {
    padding = 12,
    spacing = 6,
    fillWidth = true,
    children = {
      ns.Text {
        text = string.format("%d. %s", index, task.title),
        fontSize = 14,
        fontWeight = task.done and "regular" or "semibold",
      },
      ns.HStack {
        spacing = 8,
        children = {
          ns.Text {
            text = "Priority: " .. task.priority:upper(),
            fontSize = 11,
            color = color,
          },
          ns.Text {
            text = task.done and "✓ Done" or "○ Pending",
            fontSize = 11,
            color = task.done and "#34C759" or "#999999",
          },
        },
      },
    },
  }
end

local Controller = {}
Controller.__index = Controller

function Controller.new()
  return setmetatable({
    taskListPane = nil,
    historyPane = nil,
    window = nil,
  }, Controller)
end

-- Handle reorder callback from the reorderable container
function Controller:handleReorder(difference)
  -- difference is a reorder.Difference object with move/insert/remove operations
  if not difference then return end

  -- Log operations for history display
  for _, op in ipairs(difference.operations or {}) do
    if op.op == "move" then
      local movedTask = Model.tasks[op.from] or { _id = "?" }
      reorderHistory[#reorderHistory + 1] = {
        task = movedTask,
        from_index = op.from,
        to_index = op.to,
      }
    elseif op.op == "insert" then
      reorderHistory[#reorderHistory + 1] = {
        op_type = "insert",
        index = op.index,
      }
    elseif op.op == "remove" then
      reorderHistory[#reorderHistory + 1] = {
        op_type = "remove",
        index = op.index,
      }
    end
  end

  -- Apply reorder to model and refresh UI
  difference:apply(Model.tasks)
  self:refreshUI()
end

-- Refresh task list display
function Controller:refreshTaskList()
  if not self.taskListPane then return end
  self.taskListPane:clearContainer()

  local stack = ns.VStack {
    spacing = 1,
    flexGrow = 1,
  }

  for i, task in ipairs(Model.tasks) do
    stack:add(makeTaskView(task, i))
  end

  self.taskListPane:add(stack)
  self.taskListPane:layout()
end

-- Refresh history display
function Controller:refreshHistory()
  if not self.historyPane then return end
  self.historyPane:clearContainer()

  local stack = ns.VStack {
    spacing = 8,
    padding = 12,
  }

  -- Title
  stack:add(ns.Text {
    text = "Reorder History",
    fontSize = 14,
    fontWeight = "bold",
  })

  if #reorderHistory == 0 then
    stack:add(ns.Text {
      text = "No reorders yet.\nDrag tasks to reorder.",
      fontSize = 12,
      color = "#999999",
    })
  else
    -- Show last operations (limit to 10)
    local start = math.max(1, #reorderHistory - 9)
    for i = start, #reorderHistory do
      local entry = reorderHistory[i]
      local label = ""
      if entry.task then
        label = string.format("#%d: Move '%s' from %d to %d",
          i, entry.task.title, entry.from_index, entry.to_index)
      else
        label = string.format("#%d: Operation", i)
      end
      stack:add(ns.Text {
        text = label,
        fontSize = 11,
        color = "#555555",
      })
    end
  end

  self.historyPane:add(stack)
  self.historyPane:layout()
end

function Controller:refreshUI()
  self:refreshTaskList()
  self:refreshHistory()
end

function Controller:createWindow()
  local cfg = {
    title = "Reorderable Task List",
    width = 900,
    height = 500,
    minWidth = 700,
    minHeight = 400,
  }

  -- Create main layout: tasks on left, history on right
  local mainStack = ns.HStack {
    spacing = 1,
    padding = 0,
    children = {},
  }

  -- Tasks pane (left side, resizable)
  self.taskListPane = ns.VStack {
    flexGrow = 1,
    spacing = 0,
    padding = 0,
  }

  -- History pane (right side, fixed width)
  self.historyPane = ns.VStack {
    fixedWidth = 300,
    flexGrow = 0,
    padding = 12,
    spacing = 8,
  }

  mainStack:add(self.taskListPane)
  mainStack:add(self.historyPane)

  cfg.content = mainStack
  self.window = ns.Window(cfg)

  -- Initial population
  self:refreshUI()

  -- NOTE: Wire up the reorder callback when the native layer is ready:
  -- self.taskListPane:reorder_container(function(diff)
  --   self:handleReorder(diff)
  -- end)

  return self.window
end

return Controller
