# Motion & Animations

Animations in lua-objc run on native Core Animation (iOS) or CABasicAnimation (macOS), not on the JavaScript or Lua thread. This means smooth 60fps motion without main-thread blocking.

## Core Principle: Prefer System Animations

❌ **Bad: Lua-side animation (blocks the thread)**
```lua
for i = 1, 30 do
    view.opacity = i / 30
    view:display()
    os.delay(16)  -- ~60fps, but blocks Lua
end
```

✅ **Good: Native Core Animation (runs off-thread)**
```lua
view:animate("opacity", {
    from = 0,
    to = 1,
    duration = 0.5,
})
```

## Implicit Animations (Automatic)

When you change a property, the native platform may automatically animate it (depending on view type and context):

```lua
-- Property assignment often triggers implicit animation
button.backgroundColor = color.blue  -- Platform animates color change
textField.opacity = 0.5              -- Platform fades the text
```

For consistent behavior, use explicit animation.

## Explicit Animations

Animate specific properties with timing:

### Basic Animation

```lua
view:animate("property", {
    from = <start>,
    to = <end>,
    duration = <seconds>,
})
```

### Common Animations

```lua
-- Fade in
view:animate("opacity", { from = 0, to = 1, duration = 0.3 })

-- Slide from right
view:animate("position", {
    from = { x = 500, y = 0 },
    to = { x = 0, y = 0 },
    duration = 0.4,
})

-- Scale up
view:animate("scale", { from = 0.5, to = 1, duration = 0.3 })

-- Rotate
view:animate("rotation", { from = 0, to = math.pi * 2, duration = 1 })

-- Shake (multiple animations)
view:animate("position.x", {
    from = view.position.x - 10,
    to = view.position.x + 10,
    duration = 0.05,
})
```

### Timing Functions

Specify easing curves:

```lua
view:animate("opacity", {
    from = 0,
    to = 1,
    duration = 0.3,
    timingFunction = "easeInOut",  -- easeIn, easeOut, easeInOut, linear
})
```

### Chained Animations

Run animations in sequence:

```lua
-- Fade in, then slide down
view:animate("opacity", { from = 0, to = 1, duration = 0.2 })
    :onComplete(function()
        view:animate("position.y", {
            from = view.position.y,
            to = view.position.y + 50,
            duration = 0.3,
        })
    end)
```

### Parallel Animations (Spring)

Spring animations feel natural and don't need explicit duration:

```lua
-- Bounce in
view:animate("scale", {
    from = 0,
    to = 1,
    timing = "spring",  -- Spring animation
    damping = 0.6,      -- Oscillation: 0 (bouncy) to 1 (no bounce)
    stiffness = 200,    -- Responsiveness: higher = snappier
})
```

## Platform-Specific Animations

### iOS: Sheet Presentation

When presenting a sheet, the platform animates it; you only control timing:

```lua
local sheet = ns.Window({
    content = myView,
    mode = "sheet",
    animated = true,  -- Animates in
    duration = 0.3,
})
```

### macOS: Window Animations

```lua
window:animate("alpha", { from = 0, to = 1, duration = 0.5 })
-- Or system animations:
window:orderFront(nil)  -- Platform animates to front
window:close()          -- Platform animates close
```

## Transition Animations (View Hierarchy Changes)

When replacing views, animate the transition:

```lua
local oldView = container[1]
local newView = myNewView

-- Fade out old, fade in new
oldView:animate("opacity", {
    from = 1,
    to = 0,
    duration = 0.2,
}):onComplete(function()
    container[1] = newView  -- Swap after fade
    newView:animate("opacity", { from = 0, to = 1, duration = 0.2 })
end)
```

## List Item Animations

When inserting/removing list rows, animate them:

```lua
function Controller:addItem(item)
    self.model:add(item)
    
    -- Render new row
    local row, refs = xml.renderFile("views/ItemRow.etlua", {
        item = item,
    }, ns)
    
    -- Animate in
    row.opacity = 0
    table.insert(self.itemList, row)
    row:animate("opacity", { from = 0, to = 1, duration = 0.3 })
end

function Controller:removeItem(id)
    local row = self.itemRefs[id]
    
    -- Animate out, then remove
    row:animate("opacity", { from = 1, to = 0, duration = 0.2 })
        :onComplete(function()
            self.itemList:removeRow(row)
            self.itemRefs[id] = nil
        end)
end
```

## Loading & Placeholder Animations

Animate placeholders while data loads:

```lua
function Controller:showLoadingPlaceholder()
    local placeholder, refs = xml.renderFile("views/Placeholder.etlua", {}, ns)
    
    -- Pulse loading state
    refs.loadingView:animate("opacity", {
        from = 0.3,
        to = 0.8,
        duration = 1,
    }):onComplete(function()
        if refs.loadingView then  -- Still loading
            refs.loadingView:animate("opacity", {
                from = 0.8,
                to = 0.3,
                duration = 1,
            })
        end
    end)
    
    return placeholder
end
```

## Scroll View Animations

### Scroll to Position

```lua
list:scrollToRow(targetRow, {
    animated = true,
    position = "middle",
    duration = 0.3,
})
```

### Parallax (Scroll-linked Animation)

When an item scrolls into view, animate it:

```lua
-- In a list item render:
function Controller:onListScroll(scrollY)
    -- Adjust item opacity based on scroll position
    for _, itemRef in ipairs(self.visibleItems) do
        local itemY = itemRef.frame.y
        local progress = math.max(0, math.min(1, (scrollY - itemY) / 100))
        itemRef.opacity = progress  -- Fades in as scrolled up
    end
end
```

## Gesture-Driven Animations

Animate in response to user gestures:

```lua
function Controller:onPan(gesture)
    local translation = gesture:translation()
    
    if gesture.state == "began" then
        -- Start animation
        view:startInteractiveAnimation("position", {
            from = view.position,
            to = view.position + translation,
        })
    elseif gesture.state == "changed" then
        -- Update to follow gesture
        view.position = view.position + translation
    elseif gesture.state == "ended" then
        -- Finish with spring-back
        view:animate("position", {
            from = view.position,
            to = originalPosition,
            timing = "spring",
            damping = 0.7,
        })
    end
end
```

## Performance Rules for Animation

1. **Animate on the GPU**, not the CPU:
   - ✅ Opacity, scale, rotation
   - ❌ frame.width, frame.height (layout recalc)
   - ❌ cornerRadius (reshapes geometry)

2. **Keep animation count < 5 at once** — more causes jank

3. **Use shorter durations** (< 500ms) for frequent animations

4. **Disable animations during high-load operations**:
   ```lua
   CATransaction.setDisableActions(true)
   -- Many fast updates here
   CATransaction.setDisableActions(false)
   ```

5. **Profile with Xcode Instruments**:
   ```bash
   # Run with Core Animation tool
   ./lua-objc apps/myapp/init.lua
   # In Instruments: Core Animation > Render Performance
   ```

## Testing Animations

Animations are hard to test visually, but you can test that they're triggered:

```lua
local animated = false
view:animate("opacity", {
    from = 0,
    to = 1,
    duration = 0.1,
}):onComplete(function()
    animated = true
end)

-- Wait for animation to complete
os.sleep(0.2)
assert(animated, "Animation callback should have fired")
```

Or disable animations in tests:

```lua
-- At test start:
_G.__DISABLE_ANIMATIONS = true

-- In your controller:
function Controller:animate(...)
    if _G.__DISABLE_ANIMATIONS then
        -- Apply end state immediately for testing
        view[property] = targetValue
    else
        view:animate(...)  -- Normal animation
    end
end
```

## When Not to Animate

- ❌ Every property change (noisy, tiring)
- ❌ Animations > 1 second (too slow, wastes battery)
- ❌ List scrolling (platform handles it natively)
- ❌ Animations disabled by user (Settings > Accessibility > Reduce Motion)

Respect user preferences:

```lua
function Controller:shouldAnimate()
    return not bridge._reduceMotionEnabled()
end

function Controller:fadeIn(view)
    if self:shouldAnimate() then
        view:animate("opacity", { from = 0, to = 1, duration = 0.2 })
    else
        view.opacity = 1  -- Instant for accessibility
    end
end
```

## Summary

| Task | Method | Notes |
|------|--------|-------|
| Fade in/out | `view:animate("opacity", ...)` | Smooth, GPU-friendly |
| Slide | `view:animate("position", ...)` | Use for navigation transitions |
| Spring bounce | `timing = "spring", damping = 0.6` | Natural feel for interactions |
| Chained animations | `:onComplete(function() ... end)` | Sequential effects |
| Disable for a11y | `bridge._reduceMotionEnabled()` | Respect user preferences |
| Debug jank | Instruments Core Animation | Profile real frame time |
