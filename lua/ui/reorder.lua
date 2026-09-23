--[[
  ui/reorder.lua — Drag-to-reorder difference object and utilities.

  Provides a structured way to express reorder operations (move, insert, remove)
  and apply them to a collection of items. Used with List onReorder callbacks.

  Usage:
    local reorder = require("ui.reorder")
    local diff = reorder.Difference.new()
    diff:move(3, 1)  -- Move item at index 3 to index 1
    diff:apply(myItems)  -- Update array in-place
--]]

local M = {}

-- ── Difference object ─────────────────────────────────────────────────────
--
-- Represents a series of reorder operations (move, insert, remove).
-- Operations are accumulated and then applied atomically to a collection.

local Difference = {}
Difference.__index = Difference

function Difference.new()
  return setmetatable({
    operations = {},
  }, Difference)
end

-- Record a move operation: from_index -> to_index
-- Moves element at from_index to position to_index, shifting others as needed.
function Difference:move(from_index, to_index)
  table.insert(self.operations, {
    op = "move",
    from = from_index,
    to = to_index,
  })
  return self
end

-- Record an insert operation: insert at index, item reference
-- Typically used when a new item is added during reorder.
function Difference:insert(index, item)
  table.insert(self.operations, {
    op = "insert",
    index = index,
    item = item,
  })
  return self
end

-- Record a remove operation: remove item at index
-- Typically used when an item is deleted during reorder.
function Difference:remove(index)
  table.insert(self.operations, {
    op = "remove",
    index = index,
  })
  return self
end

-- Apply all recorded operations to a collection (array-like table).
-- Modifies the collection in-place and returns it.
-- Handles array shifts correctly for multiple operations.
function Difference:apply(items)
  if not items then
    error("reorder.Difference:apply() requires a collection")
  end

  -- Operations address the array produced by the preceding operation.
  for _, op in ipairs(self.operations) do
    if op.op == "move" then
      -- Move operation: remove from 'from' and insert at 'to'
      local from_idx = op.from
      local to_idx = op.to

      -- Ensure valid indices
      if from_idx >= 1 and from_idx <= #items and to_idx >= 1 and to_idx <= #items then
        local item = table.remove(items, from_idx)
        if item then
          table.insert(items, to_idx, item)
        end
      end

    elseif op.op == "insert" then
      -- Insert operation: add item at index
      local idx = op.index
      if idx >= 1 and idx <= (#items + 1) and op.item ~= nil then
        table.insert(items, idx, op.item)
      end

    elseif op.op == "remove" then
      -- Remove operation: delete item at index
      local idx = op.index
      if idx >= 1 and idx <= #items then
        table.remove(items, idx)
      end
    end
  end

  return items
end

-- Returns a copy of items with operations applied (non-mutating).
function Difference:applyTo(items)
  if not items then return {} end
  local copy = {}
  for i, v in ipairs(items) do
    copy[i] = v
  end
  return self:apply(copy)
end

-- Check if this difference represents any operations at all
function Difference:isEmpty()
  return #self.operations == 0
end

-- Reset operations
function Difference:clear()
  self.operations = {}
  return self
end

-- Serialize to a plain table (for debugging, transport, etc.)
function Difference:toTable()
  return {
    operations = self.operations,
  }
end

M.Difference = Difference

-- ── Utilities ────────────────────────────────────────────────────────────

-- Create an ordered edit script keyed by stable, unique identifiers. A move
-- changes several positions at once, so comparing each item's old and new
-- index independently produces an edit script that cannot be applied.
function M.fromArrayDiff(oldItems, newItems, identifierKey)
  identifierKey = identifierKey or "_id"
  local diff = Difference.new()
  if not oldItems or not newItems then return diff end

  local function identifiers(items, label)
    local ids, seen = {}, {}
    for index, item in ipairs(items) do
      local id = type(item) == "table" and item[identifierKey]
      if id == nil or seen[id] then
        error(label .. " requires unique " .. identifierKey .. " values at index " .. index)
      end
      ids[index], seen[id] = id, true
    end
    return ids, seen
  end

  local working, _ = identifiers(oldItems, "oldItems")
  local desired, desiredSet = identifiers(newItems, "newItems")
  for index = #working, 1, -1 do
    if not desiredSet[working[index]] then
      diff:remove(index)
      table.remove(working, index)
    end
  end
  for index, id in ipairs(desired) do
    if working[index] ~= id then
      local found
      for candidate = index + 1, #working do
        if working[candidate] == id then found = candidate; break end
      end
      if found then
        diff:move(found, index)
        table.insert(working, index, table.remove(working, found))
      else
        diff:insert(index, newItems[index])
        table.insert(working, index, id)
      end
    end
  end
  return diff
end

return M
