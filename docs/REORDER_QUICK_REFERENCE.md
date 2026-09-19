# Drag-to-Reorder Quick Reference

## XML Usage

```xml
<!-- Enable drag-to-reorder -->
<VStack reorderable="true" reorder_container="handleReorder">
  <% for i, item in ipairs(items) do %>
    <Label text="<%= item.name %>" />
  <% end %>
</VStack>

<!-- Or with List -->
<List reorderable="true" reorder_container="handleReorder">
  <Column id="name" title="Name" />
</List>
```

## Lua Callback Handler

```lua
function handleReorder(difference)
  -- difference is a reorder.Difference object
  
  -- Apply to your model
  difference:apply(Model.items)
  
  -- Refresh UI
  refreshView()
end
```

## Difference API

```lua
local reorder = require("ui.reorder")

-- Create
local diff = reorder.Difference.new()

-- Record operations
diff:move(from_index, to_index)
diff:insert(index, item)
diff:remove(index)

-- Apply to array (modifies in-place)
diff:apply(my_array)

-- Or create a copy without modifying
local new_array = diff:applyTo(my_array)

-- Check if empty
if diff:isEmpty() then end

-- Clear operations
diff:clear()

-- Serialize
local data = diff:toTable()

-- Chain operations
diff
  :move(5, 1)
  :insert(2, new_item)
  :remove(7)
  :apply(items)
```

## Common Patterns

### Basic Reorder Handler

```lua
function handleReorder(difference)
  difference:apply(Model.items)
  updateUI()
end
```

### With Validation

```lua
function handleReorder(difference)
  -- Preview without modifying model
  local preview = difference:applyTo(Model.items)
  
  -- Validate
  if isValidOrder(preview) then
    difference:apply(Model.items)
    updateUI()
  else
    showError("Invalid reorder")
    updateUI()  -- Refresh to original
  end
end
```

### With Persistence

```lua
function handleReorder(difference)
  difference:apply(Model.items)
  updateUI()
  
  -- Send to server
  asyncPersist(difference:toTable(), function(err)
    if err then
      showError("Failed to save reorder")
    end
  end)
end
```

### Computing Diffs

```lua
-- When you have old and new arrays
local old = Model.items
local new = loadedFromServer()

local diff = reorder.fromArrayDiff(old, new, "_id")
-- "_id" is the field used to match items

-- Get what changed
for _, op in ipairs(diff.operations) do
  print(op.op, ":", op.from, "to", op.to)
  -- Prints: "move : 3 to 1", etc.
end
```

## Supported Containers

- `<VStack>`
- `<HStack>`
- `<HSplit>`
- `<List>`
- `<LazyVStack>` (use VStack placeholder)
- `<LazyVGrid>` (use VStack placeholder)

## Difference Operations

### move(from, to)

Move item from index `from` to index `to`. Other items shift as needed.

```lua
diff:move(5, 1)  -- Move 5th item to 1st position
-- Items: [1,2,3,4,5] -> [5,1,2,3,4]
```

### insert(index, item)

Insert `item` at `index`.

```lua
diff:insert(3, newItem)
-- Existing item 3+ shift forward
```

### remove(index)

Remove item at `index`.

```lua
diff:remove(2)
-- Items after 2 shift backward
```

## Utility Functions

### fromArrayDiff(old, new, idKey)

Compute difference between two arrays.

```lua
local diff = reorder.fromArrayDiff(
  old_items,
  new_items,
  "_id"  -- Field to match items by
)
```

Returns a Difference with all move/insert/remove operations needed.

## Methods

| Method | Returns | Effect |
|--------|---------|--------|
| `new()` | Difference | Create new instance |
| `:move(from, to)` | self | Record move, chainable |
| `:insert(idx, item)` | self | Record insert, chainable |
| `:remove(idx)` | self | Record remove, chainable |
| `:apply(items)` | items | Apply operations to array |
| `:applyTo(items)` | copy | Apply to copy (non-mutating) |
| `:isEmpty()` | bool | True if no operations |
| `:clear()` | self | Clear operations, chainable |
| `:toTable()` | table | Serialize operations |

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `.operations` | table | Array of operations (read-only) |

Each operation has:
```lua
{
  op = "move|insert|remove",
  from = index,      -- for move
  to = index,        -- for move
  index = index,     -- for insert/remove
  item = object,     -- for insert
}
```

## Examples

### Reorderable Task List

```lua
-- Model
local Model = {
  tasks = {
    { _id = "1", title = "Task 1" },
    { _id = "2", title = "Task 2" },
    { _id = "3", title = "Task 3" },
  }
}

-- View
local xml = require("ui.xml")
local view = xml.render([[
  <VStack reorderable="true" reorder_container="handleReorder">
    <% for _, task in ipairs(tasks) do %>
      <Label text="<%= task.title %>" />
    <% end %>
  </VStack>
]], { tasks = Model.tasks })

-- Callback
function handleReorder(difference)
  difference:apply(Model.tasks)
  updateUI()
end
```

### History Tracking

```lua
local history = {}

function handleReorder(difference)
  -- Record operation
  history[#history + 1] = difference:toTable()
  
  -- Apply
  difference:apply(Model.items)
  updateUI()
end

-- Later, inspect history
for i, entry in ipairs(history) do
  print("Operation", i, ":", entry.operations[1].op)
end
```

### Sorted Lists

```lua
function handleReorder(difference)
  -- Apply reorder
  difference:apply(Model.items)
  
  -- Re-sort if needed
  table.sort(Model.items, function(a, b)
    return a.priority > b.priority
  end)
  
  updateUI()
end
```

## Troubleshooting

### Callback Not Firing

- Verify `reorder_container="functionName"` is set
- Function must be defined in global scope or accessible via Scope
- Check that native layer properly invokes callback

### Invalid Index Errors

- Ensure item indices are 1-based (Lua convention)
- Check array bounds in move/insert/remove
- Use `:isEmpty()` to check before applying

### Model Not Updating

- Must call `difference:apply(Model.items)` 
- Check that you're applying to correct array
- Ensure UI refresh is called after apply

### Memory Leaks

- Callbacks use Scope for lifecycle
- Ensure callbacks don't capture large closures
- Call dispose when window closes

## See Also

- Full API: `docs/vocabulary_reorder.md`
- Integration Guide: `docs/REORDER_INTEGRATION_GUIDE.md`
- Example: `examples/list-reorder/`
- Tests: `tests/reorder.test.lua`
