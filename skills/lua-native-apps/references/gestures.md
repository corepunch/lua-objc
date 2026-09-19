# Gestures & Haptics

Native gesture recognizers and haptic feedback running on UIKit/AppKit, not Lua-driven animations or simulation.

## Gesture Recognition

Gestures are attached to views via XML attributes or Lua callbacks. The native layer detects the gesture and calls your Lua handler with state information.

### Tap Gesture

Recognize taps on a view.

```xml
<Button title="Save" onTap="handleSave" />
<VStack onTap="handleAreaTap">
  <Label>Tap anywhere here</Label>
</VStack>
```

Lua callback:

```lua
function handleSave(recognizer)
  -- recognizer.location — {x, y} in view coordinates
  -- recognizer.state — "recognized" (tap just completed)
  print("Tapped at:", recognizer.location.x, recognizer.location.y)
end

function handleAreaTap(recognizer)
  -- Handle tap on container
end
```

### Long-Press Gesture

Recognize long press (default 0.5 seconds).

```xml
<VStack onLongPress="handleLongPress" longPressDuration="0.5">
  <Label>Press and hold</Label>
</VStack>
```

```lua
function handleLongPress(recognizer)
  -- recognizer.state — "began", "changed", "ended", "cancelled"
  -- recognizer.location — current tap position
  if recognizer.state == "began" then
    print("Long press started")
  elseif recognizer.state == "ended" then
    print("Long press completed at:", recognizer.location)
  end
end
```

### Drag Gesture

Recognize dragging (pan).

```xml
<View onDrag="handleDrag" ref="draggableView" />
```

```lua
function handleDrag(recognizer)
  -- recognizer.state — "began", "changed", "ended"
  -- recognizer.translation — {x, y} total displacement
  -- recognizer.velocity — {x, y} points per second
  
  if recognizer.state == "began" then
    print("Drag started")
  elseif recognizer.state == "changed" then
    -- View follows finger: update position with translation
    myView:animate("position", {
      from = myView.position,
      to = myView.position + recognizer.translation,
      duration = 0,  -- Immediate (no animation)
    })
  elseif recognizer.state == "ended" then
    -- Apply spring-back with velocity
    local velocity = recognizer.velocity
    myView:animate("position", {
      from = myView.position,
      to = originalPosition,
      timing = "spring",
      damping = 0.7,
      velocity = velocity,  -- Carry finger velocity into spring
    })
  end
end
```

### Swipe Gesture

Recognize swipes in a direction.

```xml
<VStack onSwipe="handleSwipe" swipeDirection="right">
  <Label>Swipe right to dismiss</Label>
</VStack>
```

```lua
function handleSwipe(recognizer)
  -- recognizer.direction — "left" | "right" | "up" | "down"
  -- recognizer.location — where swipe started
  
  if recognizer.direction == "right" then
    print("Swiped right")
    animateDismissal()
  end
end
```

Supported directions: "up", "down", "left", "right"

### Rotation Gesture

Recognize two-finger rotation.

```xml
<Image systemImage="star.fill" onRotation="handleRotation" />
```

```lua
function handleRotation(recognizer)
  -- recognizer.rotation — radians rotated
  -- recognizer.state — "began", "changed", "ended"
  
  if recognizer.state == "changed" then
    myView:animate("rotation", {
      from = 0,
      to = recognizer.rotation,
      duration = 0,  -- Follow finger
    })
  elseif recognizer.state == "ended" then
    -- Spring back to 0
    myView:animate("rotation", {
      from = recognizer.rotation,
      to = 0,
      timing = "spring",
    })
  end
end
```

### Pinch Gesture

Recognize two-finger pinch (zoom).

```xml
<Image systemImage="photo" onPinch="handlePinch" />
```

```lua
function handlePinch(recognizer)
  -- recognizer.scale — scaling factor (1.0 = no scale, 2.0 = doubled)
  -- recognizer.velocity — scale velocity (points per second)
  -- recognizer.state — "began", "changed", "ended"
  
  if recognizer.state == "changed" then
    myImage:animate("scale", {
      from = 1,
      to = recognizer.scale,
      duration = 0,  -- Follow finger
    })
  elseif recognizer.state == "ended" then
    -- Snap to nearest valid scale
    local targetScale = recognizer.scale > 1.5 and 2.0 or 1.0
    myImage:animate("scale", {
      from = recognizer.scale,
      to = targetScale,
      timing = "spring",
    })
  end
end
```

## Haptic Feedback

Haptic feedback runs on the hardware haptic engine (Taptic Engine on iPhone, trackpad on Mac). It's instantaneous and doesn't block the Lua thread.

### Haptics Module

```lua
local haptics = require("ui.haptics")
```

### Impact Haptics

Different intensities of impact feedback.

```lua
-- Light impact (selection)
haptics.impact("light")

-- Medium impact (user action)
haptics.impact("medium")

-- Heavy impact (warning)
haptics.impact("heavy")
```

Common uses:
- "light" — selection feedback, toggling, tapping
- "medium" — form submission, action confirmation
- "heavy" — error, warning, destructive action

### Selection Haptics

Feedback when user selects between options (picker, slider).

```lua
-- As user drags slider
function handleSliderDrag(recognizer)
  local newValue = calculateValue(recognizer.location)
  if newValue ~= currentValue then
    currentValue = newValue
    haptics.selection()  -- Tick-tick as you drag past values
  end
end
```

### Notification Haptics

Feedback for completion or error states.

```lua
-- Success completion
haptics.notification("success")

-- Warning (something wrong but recoverable)
haptics.notification("warning")

-- Error (operation failed)
haptics.notification("error")
```

### Custom Pattern

For complex feedback, chain haptics:

```lua
local haptics = require("ui.haptics")

function playLoadingPattern()
  haptics.impact("light")
  os.sleep(0.1)
  haptics.impact("light")
  os.sleep(0.1)
  haptics.impact("medium")
end
```

### Respect Reduce Motion

Users can disable haptics along with animations.

```lua
local function triggerFeedback()
  if not bridge._reduceMotionEnabled() then
    haptics.impact("light")
  end
end
```

## Event Flow: Gesture → Animation → Haptics

A complete gesture interaction:

```lua
function handleDeleteSwipe(recognizer)
  if recognizer.state == "began" then
    -- Provide immediate feedback
    haptics.impact("light")
    
  elseif recognizer.state == "changed" then
    -- Follow gesture with animation
    swipeContainer:animate("position.x", {
      from = 0,
      to = recognizer.translation.x,
      duration = 0,
    })
    
  elseif recognizer.state == "ended" then
    -- Determine if swipe was decisive
    if math.abs(recognizer.translation.x) > 100 then
      -- Swipe far enough: delete
      haptics.notification("success")
      
      -- Animate out
      swipeContainer:animate("opacity", {
        from = 1,
        to = 0,
        duration = 0.2,
      })
      
      -- Update model after animation
      model:delete(itemId)
    else
      -- Snap back
      haptics.impact("medium")
      
      swipeContainer:animate("position.x", {
        from = recognizer.translation.x,
        to = 0,
        timing = "spring",
      })
    end
  end
end
```

## Touch Handling

### Cancel Touch

Prevent a gesture recognizer from triggering:

```xml
<VStack onTap="handleTap" cancelsTouchesInView="true">
  <!-- Child taps are blocked; parent gets the event -->
</VStack>
```

### Simultaneous Gestures

Allow multiple gesture recognizers to fire:

```xml
<View onTap="handleTap" onLongPress="handleLongPress" simultaneousGestures="true">
  <!-- Both tap and long-press can fire -->
</View>
```

### Priority

Set which gestures have priority:

```xml
<VStack onTap="handleTap" onLongPress="handleLongPress">
  <!-- Long-press has higher priority; tap fails if long-press succeeds -->
</VStack>
```

## Performance Rules

1. **Gesture handlers run on main thread** — keep them fast
   - Do calculations in the model, not in the gesture handler
   - Avoid heavy file I/O or network calls

2. **Animations are GPU-accelerated** — safe to run during gestures
   - Opacity, scale, rotation, position
   - Avoid layout changes (`frame.width`, `cornerRadius`)

3. **No Lua loops in gestures** — use native animations
   ```lua
   -- ❌ Bad: Blocks gesture recognizer
   while gesture.isActive do
       view.x = view.x + 10
       os.sleep(0.016)
   end
   
   -- ✅ Good: GPU-driven
   view:animate("position.x", { ... })
   ```

## Testing Gestures

```lua
function testSwipeGesture()
    local controller = createController()
    local swipeHandled = false
    
    controller:handleSwipe(function()
        swipeHandled = true
    end)
    
    -- Simulate swipe (headless: just call the handler)
    controller:simulateSwipe("right")
    
    assert(swipeHandled, "Swipe should call handler")
end

function testHapticFeedback()
    -- Haptics are OS-level; test that they're requested, not that they fire
    local haptics = require("ui.haptics")
    
    -- In tests, this should not crash
    haptics.impact("light")
    haptics.notification("success")
    
    print("Haptics called successfully")
end
```

## Common Patterns

### Swipe to Delete

```lua
function handleRowSwipe(recognizer)
    if recognizer.direction == "left" and recognizer.translation.x < -100 then
        haptics.notification("success")
        row:animate("opacity", { from = 1, to = 0, duration = 0.2 })
        model:delete(rowId)
    end
end
```

### Pinch to Zoom

```lua
function handleImagePinch(recognizer)
    if recognizer.state == "changed" then
        image:animate("scale", { from = 1, to = recognizer.scale, duration = 0 })
    elseif recognizer.state == "ended" then
        local target = recognizer.scale > 1.5 and 2 or 1
        image:animate("scale", { from = recognizer.scale, to = target, timing = "spring" })
    end
end
```

### Drag to Reorder

Already covered in [drag-to-reorder.md](../vocabulary.md#drag-to-reorder).

### Long-Press Context Menu

```lua
function handleLongPress(recognizer)
    if recognizer.state == "began" then
        showContextMenu(recognizer.location)
        haptics.impact("heavy")
    end
end
```

## Accessibility

Gesture feedback must be accessible:

1. **Haptics are not screen-reader alternatives** — provide visual + audio feedback too
2. **Label gesture buttons** — "Double-tap to delete" label
3. **Respect Reduce Motion** — disable decorative haptics and animations

```xml
<Button 
    title="Delete"
    onDoublePress="delete"
    accessibilityLabel="Delete item (double-tap to confirm)" />
```

## Summary

| Feature | Thread | GPU | Blocking |
|---------|--------|-----|----------|
| Tap/Swipe/Drag | Main | No | No |
| Animation (position) | Main | Yes | No |
| Animation (layout) | Main | No | Yes |
| Haptics | Main | N/A | No |

Keep gesture handlers fast, use GPU animations, and respect user motion preferences.
