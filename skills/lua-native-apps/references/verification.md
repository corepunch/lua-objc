# Verification & Testing

Before claiming a UI task is done, verify it with screenshots, tests, and layouts. Do not rely on test-only validation.

## Screenshot Verification

### Take Screenshots

Use the `--screenshot` flag to render the app and save an image:

```bash
./lua-objc --screenshot apps/myapp/init.lua > /tmp/screenshot.png
```

Verify:
- ✅ Layout looks correct (no overlaps, proper alignment)
- ✅ Text is readable (not truncated, proper contrast)
- ✅ All elements are visible (nothing hidden off-screen)
- ✅ Colors match design (semantic colors used correctly)
- ✅ Icons are visible and clear (SF Symbols render correctly)

### Light & Dark Mode Screenshots

Test in both light and dark mode:

```bash
# Light mode (default)
./lua-objc --screenshot apps/myapp/init.lua > /tmp/light.png

# Dark mode (on iOS/macOS with dark theme enabled)
# Set environment variable:
export FORCE_DARK_MODE=1
./lua-objc --screenshot apps/myapp/init.lua > /tmp/dark.png
```

Verify:
- ✅ Text is readable in both modes
- ✅ Icons have appropriate contrast
- ✅ Background colors adapt correctly
- ✅ No hard-coded colors (use semantic colors)

### Side-by-Side Comparison

Compare your screenshot with the design spec:

```bash
# Compare screenshot with design
open /tmp/screenshot.png  # Your implementation
open ~/Design/spec.png    # Reference design

# Look for misalignments, wrong colors, or layout issues
```

## Layout Verification

### Dump Layout Tree

Use `--dump-layout` to inspect the view hierarchy and dimensions:

```bash
./lua-objc --dump-layout=/tmp/layout.xml apps/myapp/init.lua
```

This outputs an XML file with every view's dimensions and properties:

```xml
<View class="UIView" x="0" y="100" width="360" height="568">
  <Label class="UILabel" x="10" y="110" width="340" height="20" text="Title" />
</View>
```

Verify:
- ✅ All views have `width` and `height` set (not zero)
- ✅ Views fit within their container bounds
- ✅ No overlapping views (unless intentional with ZStack)
- ✅ Text doesn't overflow its container

### Check Alignment with Layout Dump

For split views with aligned peers, verify top-edge alignment:

```bash
./lua-objc --dump-layout=/tmp/layout.xml apps/myapp/init.lua
grep -E 'search|header|Detail' /tmp/layout.xml | head -20
```

Calculate visual position:

```
For macOS (bottom-left origin):
visual_y_from_top = window_height - (element.y + element.height)

For iOS (top-left origin):
visual_y_from_top = element.y
```

Ensure aligned elements have the same `visual_y_from_top`.

## Dynamic Content Testing

### Test with Placeholder / Real Data

Render the same template with:
1. **Empty data** (no items): Verify "no results" state
2. **Small data** (5 items): Normal layout
3. **Large data** (100+ items): Verify scrolling, virtualization
4. **Long text**: Verify text wrapping and truncation
5. **Long lists**: Verify list virtualization performance

```lua
function testWithVariousData()
    local testCases = {
        { items = {}, label = "empty" },
        { items = makeItems(5), label = "small" },
        { items = makeItems(100), label = "large" },
        { items = makeItems(1000), label = "huge" },
    }
    
    for _, case in ipairs(testCases) do
        local view, refs = xml.renderFile("views/Main.etlua", case.items, ns)
        screenshot("main_" .. case.label)
    end
end
```

### Test Text Truncation & Wrapping

```xml
<!-- Single-line truncation -->
<Label lines="1" truncation="tail">Very long text that should be truncated...</Label>

<!-- Multi-line text with word wrap -->
<Label lines="3">Paragraph text that wraps across multiple lines up to three lines maximum.</Label>
```

Verify:
- ✅ Long text doesn't overflow container
- ✅ Truncation appears at correct position ("..." at end)
- ✅ Multi-line text wraps correctly
- ✅ Ellipsis is visible (not clipped)

## Headless Tests

Headless tests verify behavior without a UI, but don't catch layout or visual bugs.

### Model Tests

Test data operations independently:

```lua
function testModelQuery()
    local model = Model.new()
    model:addItem({ id = 1, name = "Item 1" })
    model:addItem({ id = 2, name = "Item 2" })
    
    assert(model:item(1).name == "Item 1")
    assert(#model:allItems() == 2)
end
```

### Controller Tests

Test actions and navigation:

```lua
function testControllerAction()
    local controller = createController()
    
    -- Verify initial state
    assert(controller.selectedItem == nil)
    
    -- Trigger action
    controller:selectItem(1)
    
    -- Verify state changed
    assert(controller.selectedItem == 1)
end
```

### Template Tests

Verify templates render without errors:

```lua
function testTemplateRendering()
    local template = [[
        <VStack>
          <% for _, item in ipairs(items) do %>
            <Label><%= item.name %></Label>
          <% end %>
        </VStack>
    ]]
    
    local view = xml.render(template, {
        items = { { name = "Item 1" } },
    }, ns)
    
    assert(view ~= nil)
end
```

### Run Headless Tests

```bash
# Set headless flag so tests don't try to open windows
_G.__headless = true

# Run test file
./lua-objc --test tests/myapp.test.lua
```

## Visual Regression Tests

Check that visual output doesn't regress after changes:

```bash
# Save golden screenshot after design review
./lua-objc --screenshot apps/myapp/init.lua > /tmp/golden.png

# After making code changes, compare
./lua-objc --screenshot apps/myapp/init.lua > /tmp/current.png

# Compare (OS-specific)
# macOS: open /tmp/golden.png /tmp/current.png
# Linux: diff -u <(convert /tmp/golden.png txt:-) <(convert /tmp/current.png txt:-)

# Programmatically (using ImageMagick):
# convert /tmp/golden.png /tmp/current.png -compose difference -composite -threshold 0 /tmp/diff.png
# If /tmp/diff.png is blank, images are identical
```

## Platform-Specific Verification

### macOS-Specific Checks

- ✅ Window size and position are sensible (not 0×0 or off-screen)
- ✅ Title bar shows app name
- ✅ Close/minimize/maximize buttons are functional
- ✅ Keyboard shortcuts work (Cmd+Q to quit, Cmd+W to close window)
- ✅ Toolbar items have proper icons and tooltips
- ✅ Menu bar integration works if applicable

```bash
./lua-objc --screenshot apps/myapp/init.lua > /tmp/macos.png
# Verify window chrome, title bar, toolbar
```

### iOS-Specific Checks

- ✅ Layout is safe area-aware (doesn't hide behind notch/home indicator)
- ✅ Portrait and landscape orientations work
- ✅ Navigation bar shows correctly
- ✅ Tab bar items are properly labeled
- ✅ Status bar is visible and readable

```bash
export FORCE_PORTRAIT=1
./lua-objc --screenshot apps/myapp/init.lua > /tmp/portrait.png

export FORCE_LANDSCAPE=1
./lua-objc --screenshot apps/myapp/init.lua > /tmp/landscape.png
```

## Performance Verification

### Benchmark List Performance

For lists with 1,000+ items:

```bash
./lua-objc --benchmark apps/myapp/init.lua
```

This measures:
- Render time (< 1 second for 1k items)
- Scroll smoothness (should be 60fps)
- Memory usage (should not balloon)

Verify:
- ✅ Renders without freezing
- ✅ Scrolling is smooth (no jank)
- ✅ Memory usage stays reasonable

### Profile with Instruments

For animation performance:

```bash
# Record Core Animation metrics
instruments -t "Core Animation" -o /tmp/perf_trace \
    ./lua-objc apps/myapp/init.lua

# View frame rate and rendering time
```

## Accessibility Verification

### Screen Reader Test

With VoiceOver enabled:

```bash
# macOS
System Preferences > Accessibility > Voiceover > On
# Then navigate app with VO + Left/Right arrows

# iOS
Settings > Accessibility > Voiceover > On
# Then navigate with two-finger swipe
```

Verify:
- ✅ All interactive elements can be reached
- ✅ Labels are clear and meaningful
- ✅ Navigation order is logical
- ✅ No silent elements that should have labels

### Dynamic Type Test

Test with maximum text size:

```bash
# iOS
Settings > Display > Text Size (drag to max)

# macOS
System Preferences > General > Increase contrast > On
# + use system text size settings

# Then open app and verify text is readable
```

### Reduce Motion Test

With Reduce Motion enabled:

```bash
# iOS
Settings > Accessibility > Motion > Reduce Motion > On

# macOS
System Preferences > Accessibility > Display > Reduce motion > On

# Verify animations either don't play or play instantly
```

## Final Verification Checklist

Before opening a PR or marking task done:

### Visual (Required)
- [ ] Screenshot shows correct layout
- [ ] Text is readable and not truncated
- [ ] Colors match design (light and dark mode)
- [ ] Icons render clearly
- [ ] Layout is aligned properly (use `--dump-layout` to verify)

### Data (Required)
- [ ] Works with empty data (no items)
- [ ] Works with small data (5-10 items)
- [ ] Works with large data (100+ items)
- [ ] Long text doesn't break layout
- [ ] Lists virtualize correctly

### Behavior (Required)
- [ ] Taps/clicks work on interactive elements
- [ ] Navigation flows work as expected
- [ ] Errors are handled gracefully
- [ ] State is preserved when needed

### Performance (Required for lists/animations)
- [ ] List with 1k+ items renders smoothly
- [ ] Animations don't stutter (60fps)
- [ ] Memory usage is reasonable

### Accessibility (Required)
- [ ] Screen reader can access all elements
- [ ] Text is readable at max size
- [ ] Animations respect Reduce Motion
- [ ] Keyboard navigation works (macOS)

### Testing (Required)
- [ ] Headless tests pass
- [ ] No console warnings or errors
- [ ] Layout dump shows no zero-sized views

## Example Verification Script

```bash
#!/bin/bash
# verify.sh - Run all verification steps

app="apps/myapp"
echo "Verifying $app..."

# Screenshots
echo "Taking screenshots..."
./lua-objc --screenshot $app/init.lua > /tmp/screenshot.png
echo "  ✓ Screenshot saved to /tmp/screenshot.png"

# Layout dump
echo "Dumping layout..."
./lua-objc --dump-layout=/tmp/layout.xml $app/init.lua
grep 'width="0"' /tmp/layout.xml && echo "  ✗ Found zero-width views!" || echo "  ✓ No zero-sized views"

# Tests
echo "Running tests..."
./lua-objc --test tests/$app.test.lua && echo "  ✓ Tests passed" || echo "  ✗ Tests failed"

echo ""
echo "Verification complete. Check /tmp/screenshot.png for visual review."
```

Run it before every PR:

```bash
./verify.sh
```
