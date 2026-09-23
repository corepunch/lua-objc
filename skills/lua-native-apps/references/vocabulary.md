# XML Vocabulary & Modifiers

## Framework mapping

Use this table to translate a design idea into APIs this repository actually
provides. An unimplemented item is a framework gap, not permission to invent an
app-side substitute.

| Concept | lua-objc API or status |
|---|---|
| SwiftUI stacks and controls | XML tags in this reference, rendered by `lua/ui/xml.lua` |
| SwiftUI `List` / native table | `<List>` with `<Column>` children and data records |
| Expo Router / `NavigationStack` path values | Not yet available; see issue [#8](https://github.com/corepunch/lua-objc/issues/8) |
| Sheets with detents and drag indicator | Not yet available as a shared presentation API; see issue [#8](https://github.com/corepunch/lua-objc/issues/8) |
| Native List row reordering | `<List reorderable="true" reorderContainer="actionName">`; stacks and grids are not supported |
| System Liquid Glass | `<GlassEffect style="regular|clear">`; use `style="glass"` for a glass button |
| Native toolbar spacing/overflow | `<ToolbarSpacer />`, native toolbar overflow, and `ToolbarItem visibilityPriority`; on iOS set `TabView minimizeBehavior="onScroll"` for its tab bar |
| `WebView` / observable `WebPage` | Not yet available; see issue [#7](https://github.com/corepunch/lua-objc/issues/7) |
| Lazy containers and large-list virtualization | Do not use eager `VStack` for unbounded rows; see issue [#9](https://github.com/corepunch/lua-objc/issues/9) |
| Native animation, haptics, and motion preferences | Use only existing documented bridge operations; broader surface is tracked in issue [#10](https://github.com/corepunch/lua-objc/issues/10) |
| Private navigation palettes / private `LazyLayout` | Research only, opt-in proposal; never use in default app code. See issue [#11](https://github.com/corepunch/lua-objc/issues/11) |
| Swipe actions on non-List containers | Not yet available; see issue [#12](https://github.com/corepunch/lua-objc/issues/12) |
| State observation / invalidation | Controller actions update retained refs or render the affected template; see `ARCHITECTURE.md` and issue [#12](https://github.com/corepunch/lua-objc/issues/12) |

For tabs, read the current XML registry and [project reference](../../../docs/PROJECT_REFERENCE.md)
before assuming a tag or presentation behavior exists. For iOS builds and
streamed simulator reloads, follow [`docs/ios.md`](../../../docs/ios.md).

This document lists every supported XML tag and modifier attribute. If a tag is not listed here, it does not exist in the bridge — extend `xml.registry` in the appropriate platform module instead of inventing SwiftUI modifiers the bridge does not implement.

## Layout Containers

Layout containers arrange child views in a specific pattern. Every container accepts child elements.

### VStack
Vertical layout — arranges children from top to bottom.
- `spacing`: number (optional) — distance between children
- `alignment`: "leading" | "center" | "trailing" (optional)

```xml
<VStack spacing="8" alignment="center">
  <Label>Item 1</Label>
  <Label>Item 2</Label>
</VStack>
```

### HStack
Horizontal layout — arranges children left to right.
- `spacing`: number (optional) — distance between children
- `alignment`: "top" | "center" | "bottom" (optional)

```xml
<HStack spacing="12">
  <Label>Left</Label>
  <Label>Right</Label>
</HStack>
```

### ZStack
Overlay layout — arranges children in depth order (last on top).

```xml
<ZStack>
  <Image systemImage="background.fill" />
  <Label>Content</Label>
</ZStack>
```

### Form
Grouped form layout with labels and controls.
- `spacing`: number (optional)
- `alignment`: "leading" | "center" | "trailing" (optional)

```xml
<Form>
  <LabeledContent label="Name">
    <TextField />
  </LabeledContent>
</Form>
```

### ScrollView
Scrollable container.
- `horizontal`: "true" | "false" (optional)
- `vertical`: "true" | "false" (optional)
- `contentWidth`: number (optional)
- `contentHeight`: number (optional)

```xml
<ScrollView vertical="true">
  <VStack><!-- content --></VStack>
</ScrollView>
```

### Section / GroupBox
Grouped content with optional header.
- `header`: string (optional) — section title
  
```xml
<Section header="Account">
  <Label>Settings go here</Label>
</Section>
```

### LabeledContent
Label + content pair for forms.
- `label`: string — the label text
- `labelWeight`: "light" | "regular" | "semibold" | "bold" (optional)
- `spacing`: number (optional)

```xml
<LabeledContent label="Email">
  <TextField />
</LabeledContent>
```

### Grid / GridRow
Grid layout with rows.

```xml
<Grid>
  <GridRow>
    <Label>Cell 1</Label>
    <Label>Cell 2</Label>
  </GridRow>
</Grid>
```

### Spacer
Flexible spacing that expands to fill available space.

```xml
<VStack>
  <Label>Top</Label>
  <Spacer />
  <Label>Bottom</Label>
</VStack>
```

### Divider
Horizontal or vertical separator line.
- `orientation`: "horizontal" | "vertical" (optional)

## Text & Labels

### Label / Text
Display text.
- `text` or positional argument: string (required) — text content
- `size`: number (optional) — font size
- `weight`: "light" | "regular" | "semibold" | "bold" (optional)
- `italic`: "true" | "false" (optional)
- `color`: color name or system color (optional)
- `alignment`: "leading" | "center" | "trailing" (optional)
- `lines`: number (optional) — line limit (0 = unlimited)
- `truncation`: "middle" | "tail" (optional)
- `systemImage`: SF symbol name (optional) — display icon
- `iconSize`: number (optional)
- `iconWeight`: "light" | "regular" | "semibold" | "bold" (optional)
- `spacing`: number (optional) — space between icon and text

```xml
<Label size="14" weight="semibold" color="accent">
  Heading
</Label>
```

### Title
Large heading text.
- `text` or positional: string (optional)

```xml
<Title>Section Title</Title>
```

### TextEditor
Multi-line editable text.
- `value` / `text`: string (optional) — initial text
- `size`: number (optional)
- `weight`: "light" | "regular" | "semibold" | "bold" (optional)
- `editable`: "true" | "false" (optional)
- `selectable`: "true" | "false" (optional)
- `wrapMode`: "true" | "false" (optional)
- `drawsBackground`: "true" | "false" (optional)

### SearchField
Search/filter input.
- `value` / `text`: string (optional) — current search text
- `placeholder`: string (default: "Search")
- `accessibilityLabel`: string (optional) — for screen readers

```xml
<SearchField placeholder="Find..." />
```

## Controls & Input

### TextField
Single-line text input.
- `value` / `text`: string (optional) — initial text
- `placeholder`: string (optional) — hint text
- `size`: number (optional)
- `editable`: "true" | "false" (optional)
- `secure`: "true" | "false" (optional) — mask characters for passwords
- `bezeled`: "true" | "false" (optional)
- `bordered`: "true" | "false" (optional)
- `disabled`: "true" | "false" (optional)

```xml
<TextField placeholder="Enter name" />
```

### Button
Interactive button.
- `title` / `label`: string (required) — button text
- `subtitle`: string (optional) — secondary text
- `style`: "plain" | "bordered" | "filled" | "glass" | "tinted" (optional)
- `role`: "destructive" | "cancel" (optional)
- `systemImage`: SF symbol (optional)
- `detail`: string (optional)
- `truncation`: "middle" | "tail" (optional)
- `disabled`: "true" | "false" (optional)
- `action`: name of action from `data.actions` (optional)

```xml
<Button title="Save" style="filled" action="save" />
```

### Toggle
Boolean switch/checkbox.
- `label`: string (optional) — toggle label
- `value` / `checked`: "true" | "false" (optional)
- `disabled`: "true" | "false" (optional)

```xml
<Toggle label="Notifications" value="true" />
```

### Slider
Numeric input with visual slider.
- `value`: number (optional)
- `min`: number (optional)
- `max`: number (optional)
- `step`: number (optional)

### Stepper
Increment/decrement control.
- `value`: number (optional)
- `min`: number (optional)
- `max`: number (optional)
- `step`: number (optional)

### Picker / Option
Selection dropdown.
- `value`: string (optional) — selected option

```xml
<Picker value="option1">
  <Option>Option 1</Option>
  <Option>Option 2</Option>
</Picker>
```

### DatePicker
Date/time selection.
- `value`: ISO date string (optional)

### ColorPicker
Color selection.
- `value`: hex color (optional)

### Link
Hyperlink.
- `title` / `label`: string (optional) — link text
- `url`: string (required) — target URL

```xml
<Link label="Learn more" url="https://example.com" />
```

### Menu
Dropdown menu with items.
- `title`: string (optional)

```xml
<Menu title="Actions">
  <MenuItem>Edit</MenuItem>
  <MenuItem>Delete</MenuItem>
</Menu>
```

## Lists & Collections

### List
Native table/list backed by `NSTableView` on AppKit and `UITableView` on UIKit.
The XML form takes `<Column>` definitions and a named record array from template
data. `List` dequeues native cells; it is a table API, not a generic row-view
container.

```xml
<List ref="myList" data="items" header="false">
  <Column id="title" title="Title" />
</List>
```

`LazyVStack` and `LazyVGrid` are not current XML tags. Large-list performance
and lazy containers are tracked in [issue #9](https://github.com/corepunch/lua-objc/issues/9).

Use `LazyVStack` for large dynamic lists; use `VStack` + `ScrollView` for small static content.

### LazyVGrid
Virtualized grid layout.

## Images & Graphics

### Image
Display image from asset or system icon.
- `systemImage`: SF symbol name (optional)
- `named`: asset name (optional)
- `tint`: color name (optional)
- `resizable`: "true" | "false" (optional)
- `contentMode`: "fit" | "fill" (optional)
- `width`: number (optional)
- `height`: number (optional)

```xml
<Image systemImage="star.fill" tint="yellow" />
```

### SystemImage
Alias for Image with systemImage.

```xml
<SystemImage name="gear" size="18" weight="semibold" color="gray" />
```

### LinearGradient
Gradient fill.
- `colors`: space-separated color names (required)
- `startPoint`: "topLeading" | "top" | "topTrailing" | ... (optional)
- `endPoint`: similar (optional)

### MaterialView
Background material/blur effect.
- `material`: "thin" | "regular" | "thick" | "ultraThin" | "ultraThick" (optional)
- `style`: "regular" | "prominent" (optional)

## Data & State

### ForEach (etlua pattern, not an XML tag)
Repeat template for each item in a list. Use etlua syntax:

```xml
<VStack>
  <% for _, item in ipairs(items) do %>
    <Label><%= item.name %></Label>
  <% end %>
</VStack>
```

### Conditional (etlua pattern)
Show/hide content based on condition:

```xml
<% if user.isAdmin then %>
  <Label>Admin controls</Label>
<% end %>
```

## Navigation & Windows

### Window
Top-level native window (macOS) or root (iOS).
- `title`: string (optional)
- `id`: string (optional) — persistent window ID
- `width`: number (optional)
- `height`: number (optional)

```xml
<Window title="My App">
  <VStack><!-- content --></VStack>
</Window>
```

### NavigationStack
iOS navigation controller / macOS split view.
- `path`: Lua table (optional) — navigation path stack

```xml
<NavigationStack>
  <Label>Root view</Label>
</NavigationStack>
```

### TabView
Tabbed interface.

```xml
<TabView>
  <VStack systemImage="house">
    <Label>Home</Label>
  </VStack>
  <VStack systemImage="gear">
    <Label>Settings</Label>
  </VStack>
</TabView>
```

### Toolbar
Toolbar button container (macOS) / action bar (iOS).
- `placement`: "principal" | "navigation" | "status" (optional)

```xml
<Toolbar>
  <ToolbarItem title="Save" action="save" />
</Toolbar>
```

## Common Attributes

All elements support:

- `ref`: string (optional) — store view reference in `refs` table
  ```xml
  <TextField ref="nameField" />
  ```

- `id`: string (optional) — stable identifier for this element

- Accessibility attributes:
  - `accessibilityLabel`: string — label for screen readers
  - `accessibilityHint`: string — description for screen readers
  - `accessibilityRole`: "button" | "header" | ... — semantic role

## Not Yet Implemented

These are planned but not yet available:

- Drag-to-reorder for lazy stacks, grids, and custom containers — see issue #5
- Custom transitions/animations beyond built-in platform defaults
- Text selection styling (`SelectionShapeStyle`)
- Advanced gesture recognizers beyond tap/long-press
- WebView with observable state — see issue #7

When an XML tag or modifier is not available, extend the platform module rather than inventing cross-platform fiction:

```lua
-- In your platform extension module:
xml.registry["MyCustomView"] = function(ns, attrs, children)
    -- Create and return a native view
    local view = ns.createMyCustomView()
    -- ... setup ...
    return view
end
```

## Adding New Tags

To add a new tag to the registry:

1. Define it in the appropriate platform's `xml.lua` or a platform extension
2. Document it in this vocabulary reference
3. Test with both macOS and iOS (or document platform-specific behavior)
4. Add examples to `apps/<app>/views/` showing usage
