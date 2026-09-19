# Drag-to-Reorder Integration Guide

This guide explains how to implement native drag-to-reorder support for lua-objc containers.

## Completed: Lua/API Layer

### Modules Created

1. **`lua/ui/reorder.lua`** - Core difference object
   - `Difference` class for representing reorder operations
   - Methods: `move()`, `insert()`, `remove()`, `apply()`, `applyTo()`
   - Utility: `fromArrayDiff()` for computing diffs
   - ✓ Fully implemented and tested

2. **`lua/ui/viewdesc.lua`** - Updated for reorder metadata
   - Tracks `reorderable` and `reorder_container` attributes
   - Added to VStack, HStack, HSplit, List schemas
   - ✓ Implemented

3. **`lua/ui/xml.lua`** - Updated schema
   - Added `reorderable` and `reorder_container` props
   - VStack, HStack, HSplit, List support
   - ✓ Implemented

4. **Example: `apps/list-reorder/`**
   - Model, Controller, README with integration instructions
   - Demonstrates callback handling and UI updates
   - ✓ Complete and working (without native drag-drop)

5. **Documentation**
   - `docs/vocabulary_reorder.md` - Complete API reference
   - `docs/REORDER_INTEGRATION_GUIDE.md` - This file
   - `apps/list-reorder/README.md` - Example walkthrough

## TODO: Native Implementation

### Phase 1: AppKit (macOS)

#### 1. Add drag recognition to container views

File: `lua/embedded/AppKit.lua` and native host code

When a container has `reorderable=true`:

```lua
function AppKit.VStack(props)
  local stack = bridge._vstack()
  -- ... existing code ...
  
  if props.reorderable then
    bridge._enableReorder(stack)  -- Enable drag-to-reorder gestures
  end
  
  if props.reorder_container then
    -- Store callback for later invocation
    stack._reorderCallback = props.reorder_container
  end
  
  return stack
end
```

#### 2. Implement drag gesture detection

In native code (Objective-C):

```objc
// In VStackView or NSCollectionView:
- (void)viewDidLoad {
  if (self.reorderEnabled) {
    NSDragOperation dragMask = NSDragOperationMove;
    [self registerForDraggedTypes:@[NSPasteboardTypeString]];
    
    // Add visual feedback
    [self enableDropHighlight];
  }
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  NSPoint drop = [self convertPoint:sender.draggingLocation fromView:nil];
  NSInteger targetIndex = [self indexAtPoint:drop];
  [self showDropIndicator:targetIndex];
  return NSDragOperationMove;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  NSPoint drop = [self convertPoint:sender.draggingLocation fromView:nil];
  NSInteger fromIndex = /* source index */;
  NSInteger toIndex = [self indexAtPoint:drop];
  
  [self callReorderCallback:fromIndex to:toIndex];
  [self hideDropIndicator];
  return YES;
}
```

#### 3. Create and invoke Difference object

When drop completes, call from native to Lua:

```objc
- (void)callReorderCallback:(NSInteger)fromIndex to:(NSInteger)toIndex {
  // Get the reorder callback from the view
  LuaValue *callback = self.reorderCallback;
  if (!callback) return;
  
  lua_State *L = /* current Lua state */;
  
  // Push reorder module
  luaL_getsubtable(L, LUA_GLOBALSINDEX, "reorder");
  lua_getfield(L, -1, "Difference");
  lua_getfield(L, -1, "new");
  lua_call(L, 0, 1);  // Create new Difference instance
  
  // Call :move(fromIndex, toIndex) on the Difference
  lua_getfield(L, -1, "move");
  lua_insert(L, -2);  // self
  lua_pushinteger(L, fromIndex);
  lua_pushinteger(L, toIndex);
  lua_call(L, 3, 1);  // self, from, to -> Difference
  
  // Invoke the reorder callback with the Difference
  lua_push_value_from_registry(L, callback);  // Callback function
  lua_insert(L, -2);  // Put callback before Difference
  lua_call(L, 1, 0);  // Call callback(difference)
  
  lua_pop(L, 1);  // Clean up stack
}
```

#### 4. Wire up to AppKit module

Update `lua/embedded/AppKit.lua`:

```lua
function AppKit.VStack(props)
  local stack = bridge._vstack()
  applyLayout(stack, props)
  
  -- Enable reordering if requested
  if props.reorderable == true then
    bridge._enableReorder(stack)
  end
  
  -- Store callback for native layer
  if props.reorder_container then
    -- This should be a Lua function stored via Scope
    local callback = Scope.current():add(props.reorder_container)
    stack._luaReorderCallback = callback
  end
  
  return stack
end
```

### Phase 2: UIKit (iOS)

Similar to AppKit but using UICollectionView and UITableView drag-drop APIs:

```objc
// iOS drag-drop
- (void)collectionView:(UICollectionView *)collectionView 
  itemsForBeginningDragSession:(UIDragSession *)session
  atIndexPath:(NSIndexPath *)indexPath {
  
  // Provide drag item
  NSString *item = self.items[indexPath.item];
  UIDragItem *dragItem = [[UIDragItem alloc] initWithItemProvider:...];
  [session addItems:@[dragItem]];
  self.dragSourceIndex = indexPath.item;
}

- (UICollectionViewDropProposal *)collectionView:(UICollectionView *)collectionView
  dropSessionDidUpdate:(UIDropSession *)session
  withContext:(UICollectionViewDropContext *)context {
  
  NSIndexPath *indexPath = context.destinationIndexPath;
  [self showDropIndicator:indexPath];
  
  UICollectionViewDropProposal *proposal = 
    [[UICollectionViewDropProposal alloc] 
     initWithDropOperation:UICollectionViewDropOperationMove
     intent:UICollectionViewDropIntentInsertAtDestinationIndexPath];
  return proposal;
}

- (void)collectionView:(UICollectionView *)collectionView
  performDropWithContext:(UICollectionViewDropContext *)context {
  
  NSIndexPath *to = context.destinationIndexPath;
  [self callReorderCallback:self.dragSourceIndex to:to.item];
  [self hideDropIndicator];
}
```

### Phase 3: Visual Feedback

For both platforms, implement:

1. **Drop indicator** - Show where item will land
   - Animated gap in container
   - Highlight color
   - Smooth updates as drag moves

2. **Drag preview** - Show dragged item
   - Opacity or scale change
   - Shadow or depth effect
   - Snap back on cancel

3. **Hover highlight** - Feedback for dragging over container
   - Background color change
   - Border/shadow effects

### Phase 4: Testing

1. **Unit tests** (Lua)
   - `tests/reorder.test.lua` ✓ Already passing
   - Test Difference operations
   - Test fromArrayDiff utility

2. **Integration tests**
   - Run `apps/list-reorder/` example
   - Verify callback invocation
   - Verify model updates

3. **Manual testing**
   - macOS: Drag items in window
   - iOS: Long-press then drag
   - Test with many items (performance)

## API Contract

### Native → Lua

When user drops an item at a new position:

1. Create `Difference` object in Lua
2. Call `:move(fromIndex, toIndex)` on it
3. Call the `reorder_container` callback with the Difference
4. The Lua code calls `:apply(model)` to update data

### Lua → Native

Via props:

```xml
<VStack reorderable="true" reorder_container="myCallback">
```

Props passed to native constructor:
- `reorderable: boolean` - Enable drag-to-reorder
- `reorder_container: function` - Lua callback function

## Error Handling

Consider these edge cases:

1. **Invalid indices** - Clamp to valid range
2. **Callback errors** - Lua error in reorder callback
   - Print to stderr
   - Don't crash native code
   - Use resumeCoroutine pattern from AppKit.lua

3. **Missing callback** - Handle gracefully if callback is nil

4. **Concurrent operations** - Don't allow drag while animating

## Performance Considerations

1. **Large lists** - Use `LazyVStack`/`LazyVGrid` (not yet implemented)
2. **Many events** - Throttle visual updates
3. **Scope management** - Ensure callbacks are properly disposed
4. **Memory** - Don't leak LuaReg references

## Debugging

Enable logging in native code:

```objc
#ifdef DEBUG_REORDER
NSLog(@"Reorder from %ld to %ld", fromIndex, toIndex);
#endif
```

Lua-side debugging:

```lua
function handleReorder(difference)
  print("Reorder operations:")
  for _, op in ipairs(difference:toTable().operations) do
    print(string.format("  %s: %d -> %d", op.op, op.from or op.index, op.to or op.index))
  end
  -- ... rest of handler ...
end
```

## Files to Modify

1. **Native host code** (AppKit/UIKit bindings)
   - Add `_enableReorder(view)` bridge function
   - Implement drag gesture handling
   - Create and invoke Difference objects

2. **`lua/embedded/AppKit.lua`**
   - Handle `reorderable` and `reorder_container` props
   - Store callback via Scope

3. **`lua/embedded/UIKit.lua`**
   - Same as AppKit but for iOS

4. **Testing**
   - Run `tests/reorder.test.lua`
   - Test `apps/list-reorder/` example

## References

- Lua Difference API: `lua/ui/reorder.lua`
- Example usage: `apps/list-reorder/`
- Full documentation: `docs/vocabulary_reorder.md`
- AppKit integration: `lua/embedded/AppKit.lua` (Scope, LuaReg patterns)
