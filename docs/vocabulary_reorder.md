# Drag-to-Reorder API

This document describes the drag-to-reorder API for containers in lua-objc, including VStack, HStack, List, and other collection containers.

## Overview

Drag-to-reorder allows users to rearrange items within a container by dragging them to a new position. The framework provides:

1. **`.reorderable()` modifier** - Marks a container as supporting drag-to-reorder
2. **`.reorder_container()` modifier** - Attaches a callback to handle reorder operations
3. **`Difference` object** - Represents the reorder operations (move, insert, remove)
4. **`apply()` method** - Updates the model after reordering

## API Reference

### XML Attributes

#### `.reorderable` (boolean)

Marks a container as reorderable. When set to `true`, the container accepts drag-to-reorder gestures.

```xml
<VStack reorderable="true">
  <!-- child items -->
</VStack>
```

When reorderable is enabled:
- macOS: Users can drag items within the container
- iOS: Long-press gesture followed by drag
- Items show visual feedback during drag
- Empty space indicates drop position

#### `.reorder_container` (string)

Specifies the callback function to receive reorder events. The callback is called whenever items are reordered.

```xml
<VStack reorderable="true" reorder_container="myCallback">
  <!-- child items -->
</VStack>
```

The callback receives a `Difference` object as its only argument.

### Lua API

#### `reorder.Difference` class

Located in `lua/ui/reorder.lua`, this class represents a series of reorder operations.

##### Methods

**`Difference.new()` → Difference**

Creates a new empty Difference object.

```lua
local reorder = require("ui.reorder")
local diff = reorder.Difference.new()
```

**`diff:move(from_index, to_index) → self`**

Records a move operation: move item at `from_index` to position `to_index`.

```lua
diff:move(3, 1)  -- Move item at position 3 to position 1
```

All items between positions shift as needed. This is chainable.

**`diff:insert(index, item) → self`**

Records an insert operation: insert `item` at `index`.

```lua
diff:insert(2, newItem)
```

This is chainable for multiple operations.

**`diff:remove(index) → self`**

Records a remove operation: remove item at `index`.

```lua
diff:remove(5)
```

This is chainable.

**`diff:apply(items) → items`**

Applies all recorded operations to `items` in-place and returns the modified array.

```lua
local myTasks = { ... }
diff:apply(myTasks)
-- myTasks is now reordered
```

Operations are applied sequentially, with indices adjusted for previous operations.

**`diff:applyTo(items) → copy`**

Returns a new array with operations applied (non-mutating).

```lua
local originalTasks = { ... }
local reorderedTasks = diff:applyTo(originalTasks)
-- originalTasks is unchanged, reorderedTasks has the new order
```

**`diff:isEmpty() → boolean`**

Returns true if no operations have been recorded.

```lua
if not diff:isEmpty() then
  diff:apply(myModel.items)
end
```

**`diff:clear() → self`**

Clears all recorded operations. Returns self for chaining.

```lua
diff:clear():move(1, 2)
```

**`diff:toTable() → table`**

Serializes to a plain table (useful for debugging or network transport).

```lua
local serialized = diff:toTable()
-- { operations = { { op = "move", from = 3, to = 1 }, ... } }
```

#### Utility Functions

**`reorder.fromArrayDiff(oldItems, newItems, identifierKey) → Difference`**

Compares two arrays and generates a Difference representing the changes.

```lua
local reorder = require("ui.reorder")
local oldItems = { { _id = "1", name = "Alice" }, { _id = "2", name = "Bob" } }
local newItems = { { _id = "2", name = "Bob" }, { _id = "1", name = "Alice" } }

local diff = reorder.fromArrayDiff(oldItems, newItems, "_id")
-- Generates a Difference with a move operation
```

Parameters:
- `oldItems` - Array of items before reordering
- `newItems` - Array of items after reordering
- `identifierKey` - Field name to match items (default: `"_id"`)

Returns a Difference object representing all moves, inserts, and removes needed to transform oldItems into newItems.

## Usage Examples

### Example 1: Basic Reorderable VStack

XML template:

```xml
<Window title="Tasks" width="400" height="500">
  <VStack reorderable="true" reorder_container="handleReorder">
    <% for i, task in ipairs(tasks) do %>
      <VStack ref="task_<%= task._id %>" padding="12" fillWidth="true">
        <Label weight="bold" text="<%= task.title %>" />
      </VStack>
    <% end %>
  </VStack>
</Window>
```

Lua controller:

```lua
local Model = require("models.TaskModel")
local reorder = require("ui.reorder")

local function handleReorder(difference)
  -- difference is a reorder.Difference object
  
  -- Apply to model
  difference:apply(Model.tasks)
  
  -- Persist changes
  Model.save()
  
  -- Update UI
  updateTaskList()
end
```

### Example 2: Reorderable List with Comparison

```lua
local oldTasks = {}
for i, task in ipairs(Model.tasks) do
  oldTasks[i] = task
end

-- User reorders tasks...
-- Later, compute the difference:

local reorder = require("ui.reorder")
local diff = reorder.fromArrayDiff(oldTasks, Model.tasks, "_id")

if not diff:isEmpty() then
  -- Log reorder operations for analytics
  for _, op in ipairs(diff:toTable().operations) do
    print("Operation:", op.op, "from:", op.from, "to:", op.to)
  end
  
  -- Persist to server
  Model.persistReorder(diff)
end
```

### Example 3: Reorderable List (macOS)

```xml
<Window title="Employee Directory">
  <List reorderable="true" reorder_container="employeeReordered">
    <Column id="name" title="Name" width="150" />
    <Column id="dept" title="Department" width="100" />
  </List>
</Window>
```

```lua
function employeeReordered(difference)
  difference:apply(Model.employees)
  Model.updateSortOrder()
end
```

## Implementation Notes

### View Implementation (Native Layer)

When implementing reorderable support in the native layer:

1. **Drag Recognition**: Detect drag gesture on container items
   - macOS: Mouse drag
   - iOS: Long-press + drag

2. **Drop Zone Rendering**: Show visual indicator for drop position
   - A gap or highlight where the item will land

3. **Difference Generation**: After drop, determine:
   - Which item moved
   - From which index
   - To which index
   - Create a Difference object
   - Call the reorder callback with the Difference

4. **Scope Integration**: The callback should be wrapped with Scope tracking:
   ```objc
   // Pseudocode
   reorderCallback = scopeValue(luaFunction);  // via LuaReg/Scope
   ```

### Callback Behavior

When a reorder completes:

1. The native layer creates a `Difference` object
2. Passes it to the Lua callback as a userdata object
3. The Lua callback receives the Difference
4. The Lua code calls `:apply()` to update the model
5. The Lua code updates the UI as needed

### Index Management

When multiple moves occur:

1. Each operation adjusts indices for previous operations
2. Move operations are processed atomically
3. The Difference:apply() method handles all index adjustments automatically

Example:
```lua
diff:move(5, 1):move(2, 3)
-- First: move item at 5 to position 1, shifting items 1-4 down
-- Then: move item at 2 (original position) to position 3
-- apply() handles all shifts correctly
```

### Best Practices

1. **Track Original State**: Keep a snapshot of the original order before changes for rollback/undo
   ```lua
   local originalTasks = {}
   for i, task in ipairs(Model.tasks) do
     originalTasks[i] = task
   end
   ```

2. **Non-Mutating Comparison**: Use `applyTo()` to preview changes without modifying the model
   ```lua
   local preview = diff:applyTo(Model.tasks)
   -- preview has new order, Model.tasks unchanged
   ```

3. **Validation**: Validate that items have proper identifiers for diff computation
   ```lua
   if not item._id then
     error("Items must have _id field for reorder support")
   end
   ```

4. **Async Persistence**: If persisting to a server, handle it asynchronously
   ```lua
   diff:apply(Model.tasks)
   updateUI()
   asyncPersistReorder(diff)
   ```

## Supported Containers

- `VStack` - Vertical collection
- `HStack` - Horizontal collection  
- `List` - Table/list structure (macOS)
- `HSplit` - Split container with reorderable panes
- `LazyVStack` - (when implemented) Lazy-loaded vertical container
- `LazyVGrid` - (when implemented) Lazy-loaded grid

## Limitations & Future Work

Current implementation:
- Basic move/insert/remove operations
- No built-in undo/redo
- No multi-select drag

Future enhancements:
- Undo/redo support via Difference stacking
- Multi-item selection and reordering
- Drop-outside-container deletion
- Custom drop indicators
- Drop zone validation callbacks
