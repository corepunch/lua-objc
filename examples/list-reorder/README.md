# Drag-to-Reorder List Example

This example demonstrates how to implement drag-to-reorder functionality in lua-objc using the reorder API.

## Overview

The example shows:

1. **Model Layer** (`Model.lua`) - Task collection with reorder support
2. **Controller Layer** (`Controller.lua`) - View setup and reorder callback handling
3. **UI Layer** - A reorderable VStack of tasks with a history panel

Users can drag tasks to reorder them, and the UI updates to show:
- The new task order
- A history of reorder operations (last 10)
- Task priority and completion status

## Architecture

### Files

- `init.lua` - Entry point, returns Controller
- `Model.lua` - Task model with methods:
  - `Model.tasks` - Array of task objects
  - `Model.find(id)` - Find task by ID
  - `Model.toggleDone(id)` - Toggle task completion
  - `Model.applyReorder(difference)` - Apply reorder Difference
  
- `Controller.lua` - Main controller with:
  - `Controller:createWindow()` - Build the view hierarchy
  - `Controller:handleReorder(difference)` - Callback for reorder events
  - `Controller:refreshUI()` - Update views after changes

## Data Model

Each task has:
```lua
{
  _id = "unique-id",
  title = "Task description",
  done = false,
  priority = "high|medium|low"
}
```

The `_id` field is used for tracking items across reorders.

## Reorder Flow

### Before Implementation

1. View renders tasks from `Model.tasks`
2. User drags a task to reorder
3. ...native implementation needed...

### After Native Implementation

1. View renders tasks from `Model.tasks` with `.reorderable="true"`
2. User drags a task to new position
3. Native layer detects drop and creates a `Difference` object
4. Reorder callback invoked with `Difference`
5. Lua code calls `difference:apply(Model.tasks)`
6. UI refreshes with new order
7. History panel updates

## Reorder Difference API

The `Difference` object passed to the callback provides:

```lua
function handleReorder(difference)
  -- difference has these methods:
  difference:move(from, to)           -- Record move
  difference:insert(index, item)      -- Record insert
  difference:remove(index)            -- Record remove
  difference:apply(items)             -- Apply to array
  difference:applyTo(items)           -- Non-mutating apply
  difference:isEmpty()                -- Check if any ops
  difference:toTable()                -- Serialize for logging
  
  -- Plus a .operations table:
  for _, op in ipairs(difference.operations) do
    print(op.op, op.from, op.to)  -- op.op = "move"|"insert"|"remove"
  end
end
```

## Using the Example

### 1. Run the example as-is (without native reorder)

```bash
# In a Lua REPL or app that loads examples
local Controller = require("examples.list-reorder.Controller")
local ctrl = Controller.new()
local window = ctrl:createWindow()
```

The window displays with:
- Left pane: Task list (not yet draggable)
- Right pane: Reorder history (empty until reorder callback is wired)

### 2. Add native reorder support

In the native code (AppKit.lua / UIKit.lua), when a drop completes:

```objc
// Pseudocode: In the drag-drop handler
void handleDrop(NSInteger fromIndex, NSInteger toIndex) {
  // Create a Difference object
  lua_getglobal(L, "reorder");
  lua_getfield(L, -1, "Difference");
  lua_getfield(L, -1, "new");
  lua_call(L, 0, 1);
  
  // Call :move(from, to)
  lua_getfield(L, -1, "move");
  lua_insert(L, -2);
  lua_pushinteger(L, fromIndex);
  lua_pushinteger(L, toIndex);
  lua_call(L, 3, 1);  // self + 2 args
  
  // Call the reorder callback with the Difference
  if (reorderCallback) {
    lua_pushvalue(L, -1);  // Difference
    reorderCallback(L);    // Custom Lua call
  }
}
```

### 3. Test the integration

After native support is added:

1. Run the example
2. Drag a task to reorder
3. Watch the list reorder and history update

## Extending the Example

### Add Undo/Redo

```lua
local undoStack = {}
local redoStack = {}

function Controller:handleReorder(difference)
  local copy = difference:applyTo(Model.tasks)
  undoStack[#undoStack + 1] = Model.tasks
  
  difference:apply(Model.tasks)
  redoStack = {}  -- Clear redo stack on new action
  
  self:refreshUI()
end

function Controller:undo()
  if #undoStack == 0 then return end
  redoStack[#redoStack + 1] = {}
  for i, v in ipairs(Model.tasks) do redoStack[#redoStack][i] = v end
  
  Model.tasks = table.remove(undoStack)
  self:refreshUI()
end
```

### Persist Reorder to Server

```lua
function Controller:handleReorder(difference)
  difference:apply(Model.tasks)
  self:refreshUI()
  
  -- Send to server asynchronously
  local serialized = difference:toTable()
  asyncPersistReorder(serialized, function(err)
    if err then
      print("Failed to persist reorder:", err)
    end
  end)
end
```

### Add Drop Validation

```lua
function Controller:handleReorder(difference)
  -- Validate the reorder
  local preview = difference:applyTo(Model.tasks)
  
  -- Custom validation logic
  if not self:isValidOrder(preview) then
    print("Invalid reorder, reverting")
    self:refreshUI()
    return
  end
  
  difference:apply(Model.tasks)
  self:refreshUI()
end

function Controller:isValidOrder(tasks)
  -- Examples: high-priority tasks must stay in top positions
  -- Or: no more than N items in a group
  return true
end
```

## Integration with View Diffing

The `reorder.lua` module works with the view diffing system in `lua/ui/viewdesc.lua`:

1. View descriptions track `reorderable` and `reorder_container` attributes
2. Diffs preserve reorder state across updates
3. Callbacks use Scope for proper lifecycle management

See `lua/ui/reorder.lua` for full API documentation.

## Files to Review

- `/lua/ui/reorder.lua` - Difference class and utilities
- `/lua/ui/viewdesc.lua` - View description with reorderable metadata
- `/lua/ui/xml.lua` - XML schema for reorderable attribute
- `/docs/vocabulary_reorder.md` - Complete API documentation

## Next Steps

1. **Implement Native Reorder**: Add drag-drop handling to AppKit.lua / UIKit.lua
2. **Wire Callback**: Connect native drop handler to Lua reorder callback
3. **Test Integration**: Verify move, insert, remove operations work
4. **Optimize Performance**: Use LazyVStack/LazyVGrid for large lists
5. **Add Animations**: Show drop target highlight during drag
6. **Cross-Platform**: Test macOS and iOS behavior
