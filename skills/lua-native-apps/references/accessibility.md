# Accessibility Guidelines

Making your app accessible is not optional — it's a requirement for shipping. This guide covers VoiceOver (screen readers), Dynamic Type (text scaling), Reduce Motion, and keyboard navigation.

## Screen Readers (VoiceOver / TalkBack)

### Provide Accessibility Labels

Every interactive element must have a label:

```xml
<Button title="Save" accessibilityLabel="Save document" action="save" />
<TextField placeholder="Email" accessibilityLabel="Email address" />
<Image systemImage="star.fill" accessibilityLabel="Rating" />
```

The label is what users of assistive technology hear. It should be clear and concise.

### Use accessibilityHint for Clarification

For actions with unclear consequences, provide context:

```xml
<Button 
    title="Delete" 
    accessibilityLabel="Delete" 
    accessibilityHint="This cannot be undone"
    action="delete" />
```

### Semantic HTML/XML Roles

Use semantic tags that convey meaning:

✅ **Good: Semantic tag**
```xml
<Button title="Submit">  <!-- Screen reader knows this is a button -->
```

❌ **Bad: Generic container**
```xml
<Label text="Submit" />  <!-- Screen reader sees text, not actionable button -->
```

### Label Images and Icons

Every visual element needs a text equivalent:

```xml
<Image systemImage="heart.fill" accessibilityLabel="Favorite" />
<Image named="logo.png" accessibilityLabel="Company logo" />

<!-- Icons without text need labels -->
<Button systemImage="plus" title="" accessibilityLabel="Add new" />
```

### Hidden Decorative Elements

Mark purely decorative images so they're skipped by screen readers:

```xml
<Image systemImage="star.fill" tint="gray" accessibilityLabel="" />
<!-- Empty label = skipped by VoiceOver -->

<!-- Or use a hidden attribute if available -->
<Divider accessibilityLabel="" />  <!-- Decorative divider -->
```

### Test with Screen Reader

On device:
- **iOS:** Settings > Accessibility > VoiceOver > On
- **macOS:** System Preferences > Accessibility > Voiceover > Enable

Navigate your app using only the screen reader. Can you:
- ✅ Find all buttons and interactive elements?
- ✅ Understand what each button does?
- ✅ Navigate in logical order (top to bottom)?
- ✅ Read all content?

## Dynamic Type (Text Scaling)

Users can increase text size in Settings. Your app must adapt.

### Use System Font Sizes

Never hardcode pixel sizes; use system font scales:

❌ **Bad: Fixed pixel size**
```xml
<Label text="Heading" size="24" />  <!-- Doesn't scale -->
```

✅ **Good: Use relative sizes**
```xml
<Label text="Heading" weight="bold" size="18" />
<!-- Or use size="large" -->
```

### Scale-aware Testing

Test at different text sizes:
- **iOS:** Settings > Display > Text Size (drag slider to max)
- **macOS:** System Preferences > General > Increase contrast

Verify:
- ✅ Text is readable at max size
- ✅ Layout doesn't break (no cut-off text)
- ✅ No hardcoded line counts that hide text

```lua
-- Test with a large font size
function testDynamicType()
    local controller = createController()
    -- Render with large text
    local view, refs = xml.renderFile("views/Main.etlua", {
        fontSize = "extraLarge",  -- User's system size
    }, ns)
    -- Verify layout fits on screen without truncation
    assert(refs.title.frame.width < screenWidth)
end
```

## Reduce Motion

Some users experience motion sickness or distractions from animations.

### Respect User's Motion Preference

```lua
function Controller:shouldAnimate()
    -- Check if user has enabled "Reduce Motion"
    return not bridge._reduceMotionEnabled()
end

function Controller:transitionToDetail(id)
    local detail = createDetailView(id)
    
    if self:shouldAnimate() then
        detail:animate("opacity", { from = 0, to = 1, duration = 0.3 })
    else
        detail.opacity = 1  -- Instant transition
    end
    
    table.insert(self.navStack, detail)
end
```

Check Reduce Motion in:
- **iOS:** Settings > Accessibility > Motion > Reduce Motion
- **macOS:** System Preferences > Accessibility > Display > Reduce motion

Test your app with Reduce Motion enabled. All animations should either:
- ✅ Play instantly (appear without easing)
- ✅ Not play at all
- ❌ Not stutter or stall the UI

## Keyboard Navigation

Keyboard-only users must be able to navigate your entire app.

### Tab Order

By default, interactive elements are in visual order (top-to-bottom, left-to-right). Verify with Tab key.

**macOS:** Tab moves between interactive elements  
**iOS:** Does not apply (touch-only)

### Return Key

Return (Enter) should activate the focused button:

```xml
<TextField placeholder="Search" />
<Button title="Search" action="search" />
<!-- Pressing Return in TextField should trigger Search button -->
```

Set as the default action:

```lua
searchField.returnKeyType = "search"  -- Show "Search" instead of "Return"
-- Pressing Return in field triggers the default button action
```

### Escape Key

Escape should close dialogs and sheets (macOS convention):

```lua
function Controller:showDialog()
    local dialog, refs = xml.renderFile("views/Dialog.etlua", {
        actions = {
            close = function() dialog:close() end,
        },
    }, ns)
    
    dialog:setEscapeKeyAction(function() dialog:close() end)
end
```

### Focus Management

When presenting a new screen, move focus to the primary interactive element:

```lua
function Controller:showLogin()
    local login, refs = xml.renderFile("views/Login.etlua", {}, ns)
    
    -- Move focus to email field
    refs.emailField:focus()  -- Keyboard starts here
    
    self.mainWindow = ns.Window(login)
end
```

### Testing Keyboard Navigation

- **macOS:** Disable "Move focus with Tab" in System Preferences if not defaulting to keyboard nav, then manually test Tab/Shift+Tab
- Test that you can:
  - ✅ Tab to every interactive element
  - ✅ Tab back with Shift+Tab
  - ✅ Activate buttons with Space or Return
  - ✅ Close dialogs with Escape

## Color & Contrast

### Don't Rely on Color Alone

Don't use color as the only way to convey information:

❌ **Bad: Red = error, green = success**
```xml
<Label text="Saved" color="green" />  <!-- Color-blind users see only text -->
```

✅ **Good: Use text + color**
```xml
<VStack>
  <SystemImage name="checkmark.circle.fill" color="green" />
  <Label text="Saved" />
</VStack>
```

### Sufficient Contrast

Text should have a contrast ratio of at least 4.5:1 (WCAG AA standard).

- ✅ Dark text on light background: OK
- ✅ Light text on dark background: OK
- ❌ Gray text on white: Usually fails contrast
- ❌ Light gray on white: Always fails

Use system colors which have built-in contrast:

```xml
<Label text="Text" color="accent" />     <!-- High contrast -->
<Label text="Text" color="lightGray" />  <!-- Low contrast; avoid -->
```

## Headings & Structure

Use semantic heading elements to structure content:

```xml
<Title>Main Heading</Title>        <!-- H1 -->
<Label weight="semibold">Subheading</Label>  <!-- H2 equivalent -->
<Label>Body text</Label>           <!-- Paragraph -->
```

Screen readers use headings to navigate. Headings should be nested logically (don't skip levels).

## Form Accessibility

Forms must be fully accessible:

```xml
<Form>
  <LabeledContent label="Email">
    <TextField 
        placeholder="user@example.com"
        accessibilityLabel="Email address"
        ref="emailField" />
  </LabeledContent>
  
  <LabeledContent label="Password">
    <TextField 
        placeholder="••••••••"
        secure="true"
        accessibilityLabel="Password"
        ref="passwordField" />
  </LabeledContent>
  
  <LabeledContent label="Stay signed in">
    <Toggle accessibilityLabel="Stay signed in" />
  </LabeledContent>
  
  <Button 
      title="Sign In"
      accessibilityLabel="Sign in with email and password"
      action="signin" />
</Form>
```

## Error Messages

Errors must be clear and actionable:

❌ **Bad: Vague error**
```xml
<Label text="Error" color="red" />
```

✅ **Good: Clear error with action**
```xml
<Label text="Email address not found" color="red" accessibilityHint="Check your email address and try again" />
<Button title="Retry" action="retry" />
```

## Summary Checklist

- [ ] Every button has `accessibilityLabel`
- [ ] Every image has `accessibilityLabel`
- [ ] Form labels are associated with fields
- [ ] Text is readable at maximum font size
- [ ] Animations disabled when Reduce Motion is enabled
- [ ] Keyboard navigation is complete (Tab, Shift+Tab, Escape, Return)
- [ ] Color contrast is sufficient (4.5:1 ratio)
- [ ] Content structure is semantic (headings, forms, lists)
- [ ] Tested with screen reader enabled
- [ ] Tested with Reduce Motion enabled
- [ ] Tested with maximum text size
- [ ] Tested with keyboard only

## Resources

- [Apple Accessibility Fundamentals](https://developer.apple.com/accessibility/) — macOS/iOS best practices
- [WCAG 2.1 Accessibility Guidelines](https://www.w3.org/WAI/WCAG21/quickref/) — Web standard (applies to native too)
- [WAI-ARIA Authoring Practices](https://www.w3.org/WAI/ARIA/apg/) — Labeling and semantic patterns

Remember: Accessibility is not a feature; it's a baseline requirement.
