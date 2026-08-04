# lua-objc detailed project reference

This is opt-in reference material, not a start page. Use the repository
`README.md` and `src/README.md` to locate the relevant heading or symbol before
reading a section.

SwiftUI-like declarative UI from Lua scripts, backed by AppKit (NSView/NSWindow).
Edit `.lua` files — no recompilation needed.

**Goal: 100% SwiftUI coverage via Lua.** Every control should be a proper
AppKit-backed widget, never a hack (no `Text "----"` for separators or
`Text "[ ]"` for checkboxes). If something looks like a placeholder, the
missing widget must be built.

## Apple UI design quality bar

Working is necessary but not sufficient. Every example and widget must look and
behave like a polished macOS app. Use native AppKit controls, system metrics,
semantic colors, system fonts, and SF Symbols; do not imitate system UI with
text, emoji, hard-coded colors, or custom drawing when a native control exists.
These rules summarize Apple's current Human Interface Guidelines:

- [Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles):
  keep the interface focused, establish a clear hierarchy, use concise wording,
  and refine visual details instead of treating them as optional polish.
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/):
  use the large display for useful content, maintain comfortable information
  density, support precise pointer and keyboard interaction, and let people
  resize and configure windows.
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout):
  put the most important content near the top and leading edge, align related
  elements, use consistent spacing, respect the content area, and adapt
  gracefully throughout the supported window-size range.

### Placement and hierarchy

- The primary content must dominate the window and consume the remaining
  flexible space. Never leave a large empty region unless it communicates an
  intentional empty state.
- Stacks add spacing between siblings, not implicit outer margins. Add explicit
  padding only around content that needs separation. Primary scrollable content
  such as a table normally reaches the content-area edges.
- Put persistent, window-wide actions in the toolbar. Put actions that operate
  on one row or local section next to that content or in its context menu.
  Avoid duplicating the same action in the toolbar and body.
- Keep passive status near the content it describes. Keep alerts, validation,
  and progress feedback close to the initiating action. Don't place critical
  controls only at the bottom of a macOS window, because that edge can be off
  screen.
- Preserve reading order: top to bottom, then leading to trailing. Use visual
  weight, alignment, and grouping to communicate importance before adding
  decoration.

### Native components

- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars):
  use `NSToolbar` and `NSToolbarItem`. Use a recognizable
  [SF Symbol](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
  plus a concise label and accessibility description. Let the native toolbar
  render the item; don't replace an icon item with a custom text button.
- [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables):
  use succinct row text, descriptive noun or short noun-phrase headings,
  visible selection feedback, resizable columns, sorting when valuable, and
  alternating row backgrounds for wide multicolumn data. Cells must use native
  reusable cell views and align their content consistently.
  **Table styles:** `plain` / `fullWidth` (default) produce edge-to-edge tables
  for primary data content — they fill the container without padding and the
  standard column header provides the vertical baseline. `sourceList` is for
  navigation sidebars: hide the column header, add a section label above the
  table as a separate `Text`, and set `style = "sourceList"` for the vibrant
  blur-background appearance. `inset` adds rounded corners and automatic padding
  for grouped/settings-style lists that sit inside a larger form. Never use
  `inset` or `sourceList` for the main content table of a window. Never use
  `plain` / `fullWidth` inside a settings panel when `inset` is available.
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons):
  use native roles and bezel styles. Make the most likely safe action primary;
  never make a destructive action primary. Use precise verb labels.
- [Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators):
  show progress only while work is occurring, prefer determinate progress when
  duration is known, keep indeterminate indicators moving, and generally avoid
  labeling a spinner. Refresh automatically when appropriate while still
  allowing an explicit refresh action when useful.
  **Table loading state:** When a list or table is fetching data, show a
  centered indeterminate `NSProgressIndicator` (spinner) in the scroll view's
  content area — this is the HIG-recommended pattern. Use `showLoading()`
  before data fetches begin and `hideLoading()` after the last row arrives.
  Never insert artificial `ui.sleep()` delays to simulate animation; let
  network latency provide the natural progressive-loading rhythm. Each table
  must activate the content-area spinner independently of the toolbar progress
  indicator, because the toolbar item is easy to miss while the empty content
  area communicates "nothing here yet."
- Use menus, separators, split views, sidebars, search fields, toggles, and
  other real AppKit widgets for their intended roles. A visual approximation is
  a missing framework feature, not an acceptable sample implementation.
- Let native container controls own the geometry they are designed to manage.
  In particular, `NSSplitView` owns split-pane frames, divider dragging, and
  proportional resizing. Do not reapply pane frames from the custom stack
  layout engine, seed dividers from hard-coded pixel widths, or subclass/override
  native split behavior without a demonstrated platform limitation. Lua layout
  may arrange content inside a pane after Cocoa resizes it, but it must not
  compete with Cocoa for ownership of the pane itself.

### Typography, color, and accessibility

- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography):
  prefer system fonts and standard control font variants. Use size and weight
  sparingly to establish hierarchy; don't hard-code a custom font merely for
  decoration.
- [Color](https://developer.apple.com/design/human-interface-guidelines/color):
  use semantic dynamic system colors, preserve their meanings, and verify light,
  dark, and increased-contrast appearances. Never rely on color alone to convey
  state.
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility):
  provide meaningful accessibility labels, keyboard navigation, sufficient
  contrast, and comfortable targets. On macOS, aim for the 28×28 pt default
  control size (20×20 pt minimum) and 13 pt default text (10 pt minimum).
  Verify the accessibility tree with Accessibility Inspector for new controls.

### Required visual QA

Before declaring UI work complete:

1. Launch every affected example and inspect an actual screenshot.
2. Resize each window substantially smaller and larger; content must reflow or
   clip intentionally, never drift, overlap, or create accidental voids.
3. Exercise loading, loaded, empty, selected, disabled, error, and long-text
   states that the component supports.
4. Check toolbar icons and labels, table alignment and truncation, native
   selection appearance, focus behavior, and keyboard access.
5. Check both light and dark appearance and avoid hard-coded geometry that
   breaks with longer text or localization.

## Architecture

```
lua script  -->  require("AppKit")  -->  AppKit.dylib  -->  AppKit objects
                                        native API +     (NSWindow, NSView, etc.)
                                        embedded Lua
```

For iOS targets, `require("UIKit")` loads `UIKit.dylib` inside the iOS runtime.
Both modules expose the same SwiftUI-like API but use framework-appropriate
native controls and element names.

1. **`src/host.c`** — Tiny executable loader. Loads `AppKit.dylib` and invokes
   its `lua_objc_main` host entry point.

2. **`build/AppKit.dylib`** — Self-contained macOS Lua module and runtime.
   `src/main.m` includes focused bridge fragments from `src/appkit/`; together
   they own the ObjC bridge, layout engine, canvas services, and embedded
   `lua/embedded/AppKit.lua` declarative layer.
3. **`build/UIKit.dylib`** — iOS Simulator Lua module. Owns the UIKit bridge
   split under `src/uikit/`, shares async state/HTTP/JSON services from
   `src/shared/`, and embeds `lua/embedded/UIKit.lua`.
4. **`build/IDEKit.dylib`** — IDE component module with embedded
   `lua/embedded/IDEKit.lua`.
5. **`examples/*.lua`** — UI scripts written by the user. No compilation step.

The embedded AppKit layer provides SwiftUI-like functions
(`Window`, `VStack`, `HStack`, `Text`, `Image`, `Spacer`, `List`).
It translates to private `AppKitNative._*` calls that create real ObjC objects.
The UIKit counterpart has the same API shape with UIKit-appropriate names
(`Label` for `UILabel`, `ImageView` for `UIImageView`, etc.).

### Declarative components: the escape hatch beyond the eager native tree

The current API is declarative in syntax but eager in execution. `Text`,
`VStack`, and the other constructors immediately create native objects, and a
container immediately attaches the already-created child `NSView`s. This is a
useful small architecture, but it is not the part of SwiftUI that makes view
structure reactive.

In Swift, `struct Foo: View` does not inherit from a `View` class: a struct
cannot inherit. It conforms to the `View` protocol and supplies a `body`.
SwiftUI retains the description produced by `body`, reevaluates it when its
dependencies change, and reconciles the new description with the mounted native
view hierarchy. `some View` hides the concrete nested result type, while
`@ViewBuilder` translates conditionals and other supported control flow into
that result.

The corresponding first-class composition mechanism in Lua should be an
ordinary function. It permits normal `if`, `for`, early returns, local values,
and decomposition without inventing an inheritance system:

```lua
local function PresenterWindow(props)
	local request = props.request
	local session = request and PresentationSession(request)

	if session then
		return PresenterWindowView { session = session }
	end

	return InvalidPresenterCleanup()
end

local function PeopleList(props)
	local children = {}
	for _, person in ipairs(props.people) do
		children[#children + 1] = PersonRow { person = person }
	end
	return VStack(children)
end

Window {
	PresenterWindow { request = request },
	PeopleList { people = people },
}
```

A Lua table constructor is evaluated at runtime, so a tree written with table
syntax is not inherently compile-time static. It can already contain expression
conditions such as `loading and Spinner() or Content()`. Lua cannot, however,
place statement-form `if` or `for` blocks directly inside a table constructor.
Component functions are the simple, idiomatic answer. React follows the same
model: a function uses JavaScript control flow and returns an element
description; JSX itself is only syntax for that description.

The eager renderer already provides `ForEach` and `Group` for data-driven
initial composition:

```lua
ns.VStack {
	ns.ForEach(people, function(person)
		return PersonRow { person = person }
	end),
}
```

`ns.ForEach` eagerly invokes its content function once per array item.
`ns.Group` returns flattenable siblings when one item needs to produce several
views. This removes repeated view declarations during initial construction, but
it does not provide identity, diffing, or reactive reevaluation. A future `If`
must receive lazy callbacks or Lua will eagerly build both branches.

#### Know when the eager model has reached its limit

For initial construction, reusable component functions returning native
userdata are sufficient. Prefer them over adding a nominal `View` base class or
metatable solely for organization: Lua does not need Swift's static protocol
machinery.

The crucial limitation is that such a function currently runs once. If its
input or state changes later, the framework does not reevaluate the function.
Callbacks must mutate native controls manually, and state-dependent structural
changes require ad hoc removal and rebuilding. A `View { body = ... }` wrapper
that merely invokes `body` once does not solve this limitation; it is only a
more elaborate spelling of a function.

When implementing SwiftUI behavior, treat any of the following as evidence that
the eager native-tree architecture may have hit the wall this section predicts:

- view structure must change when state, bindings, or environment values change;
- the same component must preserve local state while its body is reevaluated;
- conditional branches or collections must insert, remove, move, or reuse
  native controls without bespoke imperative code for that one feature;
- modifiers, animation transactions, lifecycle, environment, preferences, or
  navigation need to propagate through a logical component hierarchy;
- implementing the feature would require every application callback to know and
  manually synchronize the underlying AppKit subtree.

At that point, do not keep extending the design with feature-specific mutation
hooks merely to avoid an architectural change. Reconsider the representation:
component functions should return lightweight, unevaluated descriptions rather
than mounted `NSView`s, and a renderer should own evaluation and reconciliation.
The intended progression is:

1. Use ordinary Lua functions for reusable components and unrestricted initial
   `if`/`for` construction.
2. Evolve eager `ForEach`/`Group` into lazy keyed descriptions, and add lazy
   `If`, when inline tree composition needs reactive identity.
3. Separate logical view descriptions from mounted native AppKit objects.
4. Add observable state/bindings and dependency invalidation so the appropriate
   component function is reevaluated.
5. Add stable identity and keyed reconciliation so native widgets and component
   state survive updates where their logical identity is unchanged.
6. Layer environment, lifecycle, preferences, navigation, transactions, and
   animation on that retained logical graph.

This is not a mandate to build a virtual tree for every small missing control.
A new leaf widget with stable structure should still use the existing direct
AppKit bridge. It is a decision rule for preserving the project's 100% SwiftUI
coverage goal: when SwiftUI semantics require reevaluating structure, the
framework must evolve toward function components plus a retained description
and reconciliation engine instead of declaring the behavior impossible under
the current eager tree.

## Bridge (C ↔ ObjC)

Each ObjC object is wrapped in a Lua full userdata with a metatable (`nsview` or
`nswindow`). The `__gc` metamethod calls `CFRelease` to balance the
`CFBridgingRetain` done at creation time — ARC-compatible memory management.

### Key bridge functions

| Function | Creates / acts on |
|---|---|
| `_window(title, w, h)` | `NSWindow` |
| `_vstack()` | `NSView` (vertical layout) |
| `_hstack()` | `NSView` (horizontal layout) |
| `_text(str, size, weight)` | `NSTextField` (non-editable label, optional font) |
| `_image(path)` | `NSImageView` |
| `_button(title, callback)` | `NSButton` (push button, stores callback in registry) |
| `_toggle(label, is_on, callback)` | `NSButton` (checkbox, stores callback in registry) |
| `_actionButton(title, subtitle, symbol, style, detail, callback)` | `LuaActionButton` (compound button) |
| `_systemImage(symbol, description, size, weight, color)` | `NSImageView` with SF Symbol |
| `_symbolToggle(symbol, tooltip, state, callback?)` | `NSButton` (toggle) with SF Symbol, fires callback with sender |
| `_textView()` | `NSScrollView` wrapping `NSTextView` + `SyntaxTextStorage` |
| `_textViewGetText(textView)` | Reads `NSTextView.string` |
| `_textViewSetText(textView, str)` | Sets `NSTextView.string` |
| `_textViewOnChange(textView, callback)` | Registers `NSTextDidChangeNotification` observer |
| `_textViewSetLanguage(textView, lang)` | Sets syntax highlighting language |
| `_textViewSetWrapMode(textView, wrap)` | Toggles word wrap; default is OFF (horizontally scrollable) |
| `_separator()` | `NSBox` (separator line) |
| `_add(parent, child)` | calls `addSubview:` |
| `_layout(view, width)` | recursive frame-based layout in C |
| `_tableview(columns, w, h)` | `NSScrollView` wrapping `NSTableView` + `LuaTableViewSource` |
| `_timer_after(delay, callback)` | one-shot `NSTimer` |
| `_toolbar_item(window, id)` | Finds an `NSToolbarItem` for generic property access |
| `_show(window)` | orders window front (run loop in `main()`) |

### Layout

Layout is done recursively in C (`layout_recursive`). Containers tagged via
`objc_setAssociatedObject` (`"vstack"` / `"hstack"`) lay out their children
top-to-bottom or left-to-right with 8pt sibling spacing and no implicit outer
padding. `HStack` uses intrinsic vertical height and flexible horizontal width;
primary flexible content such as `List` consumes the remaining proposal.

Non-container views (Text, Image, List) are treated as leaf nodes — their frame
is used as-is, and recursion stops there. The `respondsToSelector:` guard on
`sizeToFit` avoids crashes on views like `NSScrollView` that don't support it.

## Lua API — Views

Each function returns an ObjC userdata. Lua's parenthesis-free calling convention
makes the SwiftUI-like syntax possible: `fn "arg"` == `fn("arg")`, and
`fn { ... }` == `fn({...})`.

Scripts start with `local ns = require("AppKit")` (macOS) or
`local ui = require("UIKit")` (iOS). All widget functions are namespaced under
the module name.

### `Window{...}`

Creates an `NSWindow`. Table keys:

| Key | Type | Default | Description |
|---|---|---|---|
| `title` | string | `"Window"` | Window title |
| `width` | number | `480` | Content width in points |
| `height` | number | `360` | Content height in points |
| `transparentTitlebar` | bool | `false` | Full-size content, transparent title bar |
| `hideTitle` | bool | `=transparentTitlebar` | Hide title text in transparent mode |
| `sidebar` | view | none | Semantic `NSSplitViewItem` sidebar; requires `content` |
| `content` | view | none | Main view paired with `sidebar` in `NSSplitViewController` |
| `detail` | view | none | Optional detail pane added as a third native split item |
| `contentAccessory` | view | none | macOS 26 top accessory spanning only the content split |
| `sidebarWidth` | number | `240` | Preferred native sidebar width |
| `tabbingMode` | `"automatic"` `"preferred"` `"disallowed"` | AppKit default | Native `NSWindow` tab behavior |
| `tabbingIdentifier` | string | AppKit default | Groups compatible native window tabs |
| `toolbar` | `{{id, label, icon?, tooltip?, action?}}` | none | Native NSToolbar items; `id = "toggleSidebar"` uses AppKit's standard sidebar command |
| `toolbarLabels` | bool | `false` | Show labels below toolbar icons |
| `toolbarContentDividerAfter` | string | none | Continue a vertical content split divider through the toolbar after this item ID |

The array part of the table holds child views (added to a VStack inside the
window's content view). After building the view tree, calls `bridge._show(win)`
— the run loop starts in `main()` after the script returns.

When `sidebar` and `content` are present, `Window` instead installs a native
`NSSplitViewController`. AppKit gives the semantic sidebar its current system
appearance—including floating glass on macOS 26—and a `contentAccessory`
occupies only the content column. Supplying `detail` adds a third sibling split
item, allowing a tracking toolbar separator to create a native titlebar section
boundary between content and detail. In this form, `transparentTitlebar`
defaults to `true`. A toolbar item with `id = "toggleSidebar"` uses AppKit's
standard first-responder action. The workspace pairs it with a native tracking
separator so the button follows the semantic sidebar divider.

#### Sidebar recipe

Use a semantic window sidebar for navigation, and put the source-list table
inside a small native stack when the sidebar needs a search field or heading.
The window owns the sidebar width and split geometry; the table only owns its
rows and selection.

```lua
local search = ns.TextField {
    placeholder = "Search",
    accessibilityLabel = "Search items",
    onChange = function(query) filterRows(query) end,
}
local sourceList = ns.List {
    flexGrow = 1,
    style = "sourceList",
    header = false,
    columns = {{ id = "name", title = "Name" }},
}
local sidebar = ns.VStack {
    spacing = 12,
    padding = 12,
    search,
    ns.Text { "Navigation", weight = "bold" },
    sourceList,
}
local window = ns.Window {
    sidebar = sidebar,
    content = mainContent,
    sidebarWidth = 240,
    toolbar = {{ id = "toggleSidebar" }},
}
```

This is the pattern used by `examples/mail` and `examples/stocks`. Keep
`style = "sourceList"` limited to navigation; primary data belongs in a
`plain` or `fullWidth` table in the content column.

```lua
ns.Window {
    title = "My App",
    width = 600,
    height = 400,
    toolbar = {
        { id = "new",  label = "New" },
        { id = "save", label = "Save", action = function() print("saved") end },
    },
    ns.Text "Hello",
    ns.List { columns = ... },
}
```

`ns.Window{...}` returns its native window userdata. Use
`ns.ToolbarItem(window, id)` when an item needs dynamic native properties, or
`ns.ToolbarProgress(window, id)` to replace an action's symbol with a real
indeterminate `NSProgressIndicator` while work is active:

```lua
local progress = ns.ToolbarProgress(window, "refresh")
progress:start("Refreshing data")
-- asynchronous work
progress:stop("Refresh data — last updated just now")
```

Use `ns.addTabbedWindow(window, tabbedWindow, order?)` to put two complete
document windows in a native AppKit tab group. `order` is `"above"` (the
default) or `"below"`. `ns.windowTabCount(window)` reports the number of windows
in the group, and `ns.selectWindowTab(window)` selects an existing document
window in its group. Window tabs own complete content trees; use an inner
`NSSplitView` when one document contains an editor and preview. The public
`NSWindow` API owns all tab presentation; applications must not instantiate
Finder's private `NSTabBar` or `NSTabButton` implementation classes.

Toolbar state such as `enabled`, `view`, `label`, and `toolTip` uses the native
object's KVC-compliant properties directly. Semantic aliases live as accessors
on exported Objective-C subclasses.

### `VStack{...}` / `HStack{...}`

Layout containers. Children listed in the array part are stacked vertically or
horizontally with 8pt sibling spacing and no implicit outer padding. Set
`padding = number` explicitly when a group needs margins. Returns an NSView
userdata that can be added as a child of any other container.

```lua
ns.VStack {
    ns.Text "Line 1",
    ns.Text "Line 2",
    ns.HStack {
        ns.Text "Left",
        ns.Spacer(),
        ns.Text "Right",
    }
}
```

### `ForEach(data, content)` / `Group{...}`

Use `ForEach` whenever sibling views share the same structure and differ only
by data. The content function receives `(item, index, count)` and returns a
native view or a `Group` of sibling views. Containers flatten the result without
inserting an extra placeholder `NSView`.

```lua
local actions = {
	{ title = "New", icon = "plus" },
	{ title = "Open", icon = "folder" },
}

ns.VStack {
	ns.ForEach(actions, function(item)
		return ns.Button {
			title = item.title,
			systemImage = item.icon,
		}
	end),
}
```

`ForEach` is currently eager: it constructs native views once and does not
diff, reuse, or reevaluate them when the source table changes.

### `HSplit{...}`

Horizontal split view (NSSplitView with thin vertical divider). Children
are divided equally across the available width. Useful for sidebar + content
layouts.

```lua
ns.HSplit {
    ns.VStack { ns.Text "Sidebar" },
    ns.VStack { ns.Text "Content" },
}
```

### `Text "string"` / `Text{"string"}`

Creates a non-editable, bezel-less `NSTextField` label. Both forms work,
with an optional `size` and `weight` key for custom fonts:

```lua
ns.Text "Hello"                          -- default font
ns.Text { "Hello", size = 16 }           -- 16pt system font
ns.Text { "Hello", size = 18, weight = "bold" }  -- 18pt bold
```

### `Title "string"`

Shorthand for `Text{string, size = 22, weight = "bold"}`. Useful for
window headers.

### `Image "path"`

Creates an `NSImageView`. The image is scaled proportionally, max width 400px.
Paths can be absolute (`/Library/Desktop Pictures/Beach.jpg`) or relative to
the working directory.

### `Button{...}`

Creates an `NSButton` (rounded push button). The optional `action` key stores a
Lua callback in the registry, fired via `LuaButtonTarget` + target-action.
**Callbacks receive the sender NSView as the first argument** — Lua functions
silently ignore extra arguments, so `function() ... end` and
`function(btn) ... end` both work.

```lua
ns.Button { title = "Create New Script" }
ns.Button {
    title = "Create New Script",
    action = function() print("clicked") end
}
```

### `Toggle{...}`

Creates an `NSButton` checkbox. Keys: `label` (string), `is_on` (bool),
`action` (function, optional). **Callbacks receive the sender NSButton** —
read `btn.state == 1` to get the current toggle state.

```lua
ns.Toggle { label = "Show on launch", is_on = true }
ns.Toggle {
    label = "Show on launch",
    is_on = true,
    action = function(btn) print("toggled", btn.state) end
}
```

The native KVC `state` property returns `1` (on) or `0` (off); assign
`toggle.state = 1` to turn it on.

### `SymbolToggle(symbol, tooltip, is_on, action?)`

Creates an `NSButton` toggle with an SF Symbol instead of a text label. Uses
`NSButtonTypeOnOff` with `NSBezelStyleRounded` — the symbol appears filled
when toggled on. **Callbacks receive the sender** for reading `btn.state`.

```lua
local wrapToggle = bridge._symbolToggle(
    "arrow.left.and.line.vertical.and.arrow.right",
    "Toggle Word Wrap",
    false,
    function(btn)
        local wrapped = btn.state == 1
        bridge._textViewSetWrapMode(editor._view, wrapped)
    end
)
```

This is a low-level bridge function (`bridge._symbolToggle`), not wrapped by
the embedded AppKit declarative layer. It's intended for ControlBar header
toggles and similar compact toolbar-like buttons.

### `Separator()`

Creates an `NSBox` with `NSBoxSeparator` style — a thin horizontal line.
Use between sections instead of faking it with `Text "---"`.

### `Spacer()`

Empty 10×10 view used to push siblings apart in HStack/VStack.

### `PathView{...}`

Creates a `LuaPathView` — a custom `NSView` subclass backed by an `NSBezierPath`
that renders in `drawRect:`. The coordinate system is flipped (y-axis goes
top-to-bottom) to match standard UI coordinate space. Path operations are
persistent; call `clear()` to start a new path.

```lua
local p = ns.PathView { width = 200, height = 150 }
p:moveTo(10, 10)
p:lineTo(100, 80)
p:lineTo(180, 30)
p:setStrokeColor(0.2, 0.6, 1.0, 1.0)  -- r, g, b, a
p:setLineWidth(2)
```

| Method | Arguments | Description |
|---|---|---|
| `:moveTo(x, y)` | number, number | Begin a new subpath at point |
| `:lineTo(x, y)` | number, number | Draw a straight line to point |
| `:curveTo(cp1x, cp1y, cp2x, cp2y, x, y)` | 6 numbers | Cubic Bezier curve to end point with two control points |
| `:closePath()` | none | Close the current subpath (line from current point to start) |
| `:clear()` | none | Remove all points from the path |
| `:setStrokeColor(r, g, b[, a])` | 3–4 numbers | Set stroke color (0.0–1.0, alpha defaults to 1.0) |
| `:setFillColor(r, g, b[, a])` | 3–4 numbers | Set fill color (0.0–1.0, alpha defaults to 1.0) |
| `:setLineWidth(w)` | number | Set line width in points |

### `Curve{...}`

Convenience constructor that builds a `PathView` and draws a line chart from a
flat array of y-values. Values are auto-scaled to the view bounds. Supports
optional area fill below the line.

```lua
ns.Curve {
    data          = {10, 12, 8, 14, 11, 16, 9},  -- y-values, left to right
    width         = 400,
    height        = 200,
    strokeColor   = {0.2, 0.8, 0.4},              -- r, g, b (alpha = 1)
    lineWidth     = 2,
    fillArea      = true,
    fillColor     = {0.2, 0.8, 0.4, 0.15},        -- optional explicit fill
    chartPadding  = 8,                             -- inset on all sides
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `data` | `{number}` | required | Flat array of y-values to plot |
| `width` | number | `100` | View width in points |
| `height` | number | `100` | View height in points |
| `strokeColor` | `{r,g,b[,a]}` | accent | Line color as RGBA table |
| `lineWidth` | number | `2` | Stroke width in points |
| `fillArea` | bool | `false` | Fill region below the line |
| `fillColor` | `{r,g,b[,a]}` | auto | Fill color; defaults to stroke with alpha 0.15 |
| `chartPadding` | number | `0` | Inner margin on all sides |

### `ide.SearchView` — Open Quickly palette (Cmd+P)

`IDEKit.SearchView` is the Xcode-style search palette. The complete feature is
implemented in `lua/embedded/IDEKit.lua`: recursive file collection, substring
filtering, keyboard selection, datasource replacement, collapsed/expanded
state, and result activation all remain in Lua.

AppKit exposes only reusable primitives:

- `ns.TextField` with `onChange` and normalized `onCommand` callbacks.
- `ns.OutlineView` with `replaceRows`, `selectRow`, `onRowSelect`, and
  `onRowActivate`.
- `ns.Panel`, `ns.present`, `ns.dismiss`, `ns.focus`, and `ns.resizeWindow`.
- `ns.MenuItem` for registering an ordinary menu command and shortcut.

There is intentionally no Quick Open-specific native bridge or Objective-C
datasource. `SearchView` refreshes the native `NSOutlineView` datasource in one
`replaceRows(results)` operation whenever the query changes.

```lua
local ns = require("AppKit")
local ide = require("IDEKit")

local searchView = ide.SearchView {
    rootDir = "examples",
    maxDepth = 5,
    onSelect = function(path)
        openPath(path)
    end,
}

ns.MenuItem {
    menu = "Find",
    title = "Open Quickly...",
    keyEquivalent = "p",
    modifiers = { "command" },
    action = function()
        searchView:show(window)
    end,
}
```

The palette starts as a focused input bar. It expands downward only while the
query has matches and uses AppKit's adaptive popover material. Escape dismisses
it, Up/Down changes the selected result, and Return or double-click activates
the result.

## Lua API — List (NSTableView)

The `List` widget is the most architecturally significant part of lua-objc. It
wraps NSTableView with a native ObjC data source, providing incremental row
insertion without full-table reloads.

### Design rationale

We evaluated five approaches for bridging NSTableView to Lua:

| # | Approach | Reload on add? | Extensibility | Verdict |
|---|----------|:---:|---|---|
| 1 | Push full array, `reloadData` | Yes | Low | Violates the "no full reload" requirement |
| 2 | `NSArrayController` + Cocoa Bindings | No (automatic) | Medium | Obscure KVO setup, hard to debug |
| 3 | Lua callback for every `numberOfRows`/`viewForColumn` | No | High | Heavy cross-language traffic per cell |
| 4 | Lua metatable proxy intercepting writes | No | Medium | Fragile, leaks ObjC/Lua duality |
| 5 | **Native ObjC source + key-based cells** | **No** | **High** | **Clean, idiomatic, fast** |

We chose **#5** because:

- **Data lives in ObjC** (`NSMutableArray<NSDictionary *>`) — fast random access
  for `tableView:viewForTableColumn:row:`. No Lua round-trips during scrolling.
- **`insertRowsAtIndexes:withAnimation:`** — rows slide in one at a time instead
  of flashing the whole table. ObjC gives us this for free; we just need to wrap it.
- **Column `id` → row dictionary key** — minimal but extensible. Each column's
  `id` maps directly to a key in the row's `NSDictionary`. Cells default to
  native `NSTextField`s; a column may instead provide a `cell(row)` callback
  that returns any native view.
- **Methods via `nsview` metatable `__index`** — instead of returning a Lua
  wrapper table (which can't be added as a subview), we attach the data source
  to the scroll view via `objc_setAssociatedObject`. The `nsview` metatable's
  `__index` function checks for this association and returns C functions for
  `addRow`, `removeRow`, `clearRows`, `rowCount`. This means the userdata
  returned by `List{...}` is both a valid NSView (addable to any container) and
  a method-bearing object.

```
List { ... }  returns  NSScrollView userdata
                              │
              objc_setAssociatedObject(scrollView, &kTableSourceKey, dataSource)
                              │
              tv:addRow{} → nsview.__index → bridge_tableview_add()
                              │
                     [dataSource addRow:]
                     [tableView insertRowsAtIndexes:withAnimation:]
```

### `List{...}`

Creates an `NSScrollView` wrapping a view-based `NSTableView` with alternating
row colors, a header, and a vertical scroller. Table keys:

| Key | Type | Default | Description |
|---|---|---|---|
| `columns` | `{{id, title, width?, minWidth?, alignment?}}` | *(required)* | Array of column specs |
| `width` | number | `400` | Scroll view width |
| `height` | number | `200` | Scroll view height |
| `header` | bool | `true` | Show the native table header |
| `bordered` | bool | `false` | Draw a bezel around the scroll view |
| `style` | `"plain"` `"fullWidth"` `"inset"` `"sourceList"` | automatic | `NSTableView.Style` (SwiftUI: `.tableStyle()`) |
| `alternatingRows` | bool | `true` | Alternating row background colors (SwiftUI: `.alternatingRowBackgrounds()`) |
| `gridLines` | `"none"` `"horizontal"` `"vertical"` `"both"` | `"none"` | Grid line style |
| `data` | `{{key=val}}` | `{}` | Initial rows (array of string-keyed tables) |
| `rowHeight` | number | native default | Height of each native table row |
| `refresh` | `function(list)` | `nil` | See SwiftUI-like async refresh below |

```lua
List {
    width = 620,
    height = 350,
    columns = {
        { id = "name", title = "Name", width = 240 },
        { id = "role", title = "Role", width = 180 },
        { id = "dept", title = "Department", alignment = "trailing" },
    },
    data = {
        { name = "Alice Chen",   role = "Engineer",  dept = "Core" },
        { name = "Bob Martinez", role = "Designer",  dept = "UX" },
        { name = "Carol Park",   role = "Manager",   dept = "Eng" },
    }
}
```

Each column `id` must match a key in the row data tables. Cells render the
string value of `row[id]`, unless the column has a `cell` callback. A callback
receives the row table and returns a native view; this supports compact
two-line rows, inline charts, and other compound native content. Numbers are
converted to strings automatically.
Column alignment can be `"leading"` (default), `"center"`, or `"trailing"`;
the header and reusable native cells use the same alignment.

**Column sizing:**

- **`width`** — explicit column width in points. The column keeps this size.
- **No `width`** — the column becomes a stretch column that fills the remaining
  viewport space. Multiple stretch columns split the space equally.
- **`minWidth`** — minimum width in points (default `40`). When the viewport is
  too narrow for all fixed columns at their `minWidth`, a horizontal scroller
  appears.

```lua
columns = {
    { id = "from",    title = "From",    width = 120 },
    { id = "subject", title = "Subject" },               -- stretches
    { id = "date",    title = "Date",    width = 60, minWidth = 40 },
}
```

### List methods

These are available on the userdata returned by `List{...}`, exposed via the
nsview metatable `__index`:

```lua
tv:addRow{ key = "value", ... }       -- inserts with slide-down animation
tv:removeRow(2)                        -- removes row at 0-based index
tv:clearRows()                         -- removes all rows (reloadData)
tv:replaceRows(rows)                   -- atomically replaces the datasource
tv:selectRow(0)                        -- selects and reveals a 0-based row
tv:activateRow(0)                      -- invokes native row activation
tv:onRowSelect(callback)               -- selection callback
tv:onRowActivate(callback)             -- double-click activation callback
n = tv:rowCount                        -- returns number of rows (read-only property)
tv:showLoading()                       -- shows centered spinner in content area
tv:hideLoading()                       -- removes the spinner
tv:refresh()                           -- auto-managed loading + refresh callback
tv:refresh(onDone)                     -- with optional completion callback
```

`tv:refresh()` wraps the `refresh` callback set on `List{...}`. When called:
1. Shows a centered `NSProgressIndicator` (content-area spinner)
2. Clears all existing rows via `reloadData`
3. Invokes the `refresh` callback in a coroutine — the callback yields for
   each async operation (e.g. `fetch_json`) and auto-resumes when data arrives
4. Hides the spinner when the coroutine completes

This is modeled on SwiftUI's `.refreshable { ... }` — the developer provides
only the data-loading logic; the framework manages the loading indicator.

```lua
local list = ns.List {
    columns = { ... },
    refresh = function(l)
        for _, sym in ipairs(symbols) do
            l:addRow{ symbol = sym, price = fetch_price(sym) }
        end
    end,
}

-- Trigger refresh from toolbar:
{ id = "refresh", label = "Refresh", action = function() list:refresh() end },

-- Or call imperatively:
list:refresh()
```

If an optional `on_done` callback is passed to `list:refresh(on_done)`, the
callback fires after `hideLoading()` — useful for coordinating with
`ns.ToolbarProgress` or other UI updates.

Methods can be called **before** `ns.Window{...}` shows the app (e.g. in initial
setup) or **during** runtime (e.g. from a timer/event handler — see below).

### Complete example

```lua
ns.Window {
    title = "Employee Directory",
    width = 640,
    height = 420,
    ns.VStack {
        ns.Text "Employees",
        ns.List {
            width = 620,
            height = 350,
            columns = {
                { id = "name", title = "Name" },
                { id = "role", title = "Role" },
                { id = "dept", title = "Dept" },
            },
            data = {
                { name = "Alice Chen",    role = "Engineer",   dept = "Core" },
                { name = "Bob Martinez",  role = "Designer",   dept = "UX" },
                { name = "Carol Park",    role = "Manager",    dept = "Eng" },
                { name = "Dave Johnson",  role = "Engineer",   dept = "Core" },
                { name = "Eve Williams",  role = "Analyst",    dept = "Data" },
                { name = "Frank Brown",   role = "Intern",     dept = "Eng" },
            }
        }
    }
}
```

### Extending: custom cell renderers

Custom renderers return native views, not a canvas or a second table
implementation. Keep their height bounded with `rowHeight`, and let the
returned stack or control own its internal layout.

### Dynamic updates at runtime

Since `Window{...}` calls `[NSApp run]` which blocks, dynamic data updates need
an event source. A simple approach is an `NSTimer` exposed as a bridge function:

```c
static int bridge_timer(lua_State *L) {
    double interval = luaL_checknumber(L, 1);  // seconds
    luaL_checktype(L, 2, LUA_TFUNCTION);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);

    [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer *t) {
        lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
        lua_pcall(L, 0, 0, 0);
    }];

    return 0;
}
```

Then users can write:

```lua
local tv = ns.List { columns = {...} }

ns.Timer(2.0, function()
    tv:addRow{ name = "New User", role = "Engineer", dept = "Core" }
end)

ns.Window { title = "Live Data", width = 600, height = 400, tv }
```

## Conventions

**CamelCase naming.** New method names and property keys use camelCase to match
SwiftUI conventions: `addRow`, `clearRows`, `fixedWidth`, `flexGrow`,
`transparentTitlebar`. A few shipped compatibility names remain snake_case,
including `fetch_json` and `Toggle.is_on`; do not silently rename them while
touching unrelated code.

**Data-driven repeated views.** Never duplicate sibling view declarations whose
structure is the same and whose content or styling varies only by values. Put
those values in an array and render them with `ns.ForEach`; extract the repeated
view into a component function when it improves clarity. Use `ns.Group` when
one data item must emit multiple siblings, such as a row plus a conditional
divider. Direct duplication is acceptable only when the views have genuinely
different structure or behavior that a shared component would obscure.

**Tab indentation.** All source files (`.m`, `.lua`) use tabs for leading
indentation, not spaces. Set your editor to display tabs at 4 columns wide.

```sh
# To convert spaces to tabs in any file:
perl -i -pe '1 while s/^(\t*)    /$1\t/' file
```

**No magic numbers.** Every numeric literal that controls visual appearance or
layout must be a named `#define` constant in the constants section at the top of
`src/main.m`. This includes spacing, font sizes, dimensions, corner radii,
alpha values, point sizes, and default widths/heights. Group new constants with
the existing category and follow the `k` prefix naming convention. When tuning a
value, change the constant — never hard-code a number in layout code. Loop
bounds, array indices, arithmetic factors (e.g. division by 2 for centering),
and system API constants (e.g. `kFSEventStreamEventIdSinceNow`) are exempt.

```c
// existing constant categories:
//  Table / Outline cells   kTableCellImageWidth    kTableColumnMinWidth
//  ActionButton             kActionBtnSymbolSize   kActionBtnCornerRadius
//  Spacer & Separator       kSpacerSize            kSeparatorSize
//  Image                    kDefaultImageMaxWidth  kImageViewerMinZoomScale
//  System Image / SF        kDefaultSymbolPointSize
//  Code Editor              kEditorFontSize        kEditorDefaultWidth
//  Symbol Toggle            kSymbolToggleSize      kSymbolTogglePointSize
//  Loading Spinner          kLoadingSpinnerSize
//  Layout Engine            kLayoutDefaultWidth    kMinLeafWidth  kFlexEpsilon
//  Preview / Render         kRenderDefaultWidth    kRenderDefaultHeight
//  Misc                     kFallbackBackingScale  kFSWatcherLatency
```

**Code documentation.** Always explain the *why* behind non-trivial decisions —
design rationale, edge cases being handled, why a particular approach was chosen
over alternatives. Comments should tell a future maintainer what problem was
solved, not restate what the code does. Skip comments for self-explanatory
mechanics (e.g. calling a well-known AppKit method, standard Lua idioms).

When adding new code, also document what infrastructure already exists:
capabilities the framework already provides, patterns already in use, and
prior art within the codebase that shows how similar problems were solved.
This avoids reinvention and keeps the codebase consistent.

## Building

Requires:
- macOS (AppKit)
- Lua 5.4 (`brew install lua`)

```sh
make          # build ./lua-objc
make run      # run examples/hello.lua
make run ARGS="examples/hello.lua"
make run ARGS="examples/list.lua"
make clean
```

## Testing

Tests are `.lua` files that exercise the framework headlessly — no window
showing, no run loop. `ns.Window{visible = false}` creates a window without
ordering it front.

```sh
make test      # runs all tests/*.test.lua
```

The `lua/TestKit.lua` module provides assertions:

```lua
local ns = require("AppKit")
local t = require("TestKit")

local win = ns.Window {
    title = "Test",
    width = 400,
    height = 300,
    visible = false,
}

t.assertEqual(win.title, "Test", "window title")
t.expect(ns.fetch ~= nil, "fetch exists")
t.assertEqual(list.rowCount, 0, "new list is empty")
t.assertThrows(function() ns.List{columns = {}} end, "missing columns")
```

Tests run in a single `lua_State` and `os.exit(0)` on success, `os.exit(1)`
on failure. Add `.test.lua` files under `tests/` and they're automatically
picked up by `make test`.

**Smoke-testing examples.** Set `_G.__headless = true` before loading any
example to suppress `bridge._show(win)`. This lets you verify every example
parses and constructs its view hierarchy without popping windows. The
`tests/examples.test.lua` smoke test uses this pattern — add new examples
to its list when you create them.

### Debugging view frames with `DebugTree`

`lua/DebugTree.lua` dumps the full view hierarchy of a window or any
view as XML, including each view's frame, absolute position, and parent
dimensions.  Overlaps and unexpected widths are immediately visible.

```lua
local dt = require("DebugTree")
dt.write(window.contentView, "/tmp/layout.xml")
```

Every `<View>` element records `x`, `y`, `w`, `h` (local frame),
`parentW`, `parentH` (superview frame), and `absX`, `absY` (cumulative
origin from the root).  Leaf views self-close; containers nest children
as `<subN>` elements sorted by subview index.

## ObjC tricks that make Lua binding shorter (vs C++ or C)

ObjC's dynamic runtime eliminates a lot of binding boilerplate compared to
statically-typed languages. These are the tricks we use — and the ones we
should add next.

### Already in use

| Trick | How it helps |
|---|---|
| **`objc_setAssociatedObject`** | Attach Lua callback refs, layout tags, data sources directly to ObjC objects — no wrapper structs or side tables. We use it for `kAxisKey` (layout), `kTableSourceKey` (table view), `kCallbackKey` (button actions). |
| **`CFBridgingRetain` / `CFRelease`** | Seamless ARC ↔ C pointer ownership. One call to retain when crossing into Lua, one to release on `__gc`. No `retain`/`release` bookkeeping. |
| **`isKindOfClass:`** | Type-safe downcasting. `check_objc` returns `id`; bridge functions check `[obj isKindOfClass:[NSWindow class]]` before casting. Prevents crashes on wrong types. |
| **Blocks (`^ { ... }`)** | ObjC closures capture variables by value. `NSTimer` and `NSNotificationCenter` accept blocks — no C function pointers or `void *` contexts. We use this for timer callbacks and window-close handlers. |
| **`id` dynamic typing** | `id` accepts any ObjC object without static type info. Bridge functions receive `id` and decide at runtime which class to cast to. |
| **Static lookup tables + block prop parsers** | Replace chained `if/strcmp`/`isEqualToString:` with data arrays. `NameValueEntry` maps compile-time string constants to enum values via a 4-line lookup loop. `TablePropParser` arrays make option-table parsing declarative — each Lua key → block entry. Adding a property is one line; the parsing loop never changes. See `GridLinesMap` / `TableStyleMap` / `AlignmentMap` + the `propParsers[]` array in `bridge_tableview` / `bridge_outlineview`. |

### Dynamic runtime tools

| Trick | How it helps | Effort |
|---|---|---|
| **KVC (`setValue:forKey:`)** | Used for Cocoa properties and inherited bridge properties. Exported subclasses own semantic aliases and custom accessors. | In use |
| **`performSelector:`** | Rejected for the public bridge: specialized operations use explicit native method bindings. | — |
| **`class_copyMethodList`** | Enumerate all methods on NSView/NSWindow at runtime, auto-register them as Lua-callable bridge functions. One-time setup, then new AppKit methods work for free. | Medium |
| **Generic Lua↔NSDictionary** | A recursive converter: Lua table → `NSDictionary`/`NSArray`, ObjC collection → Lua table. Eliminates `lua_table_to_dict` and enables passing complex data anywhere. | Medium |
| **KVO** | `observeValueForKeyPath:ofObject:change:context:` → Lua callback. Enables reactive UI: change a property in ObjC, Lua gets notified automatically. | Medium |
| **`NSInvocation`** | Rejected for ordinary public calls in favor of explicit native method bindings. | — |
| **`NSProxy` + `forwardingTargetForSelector:`** | Create a Lua-backed proxy object that responds to any selector by calling a Lua function. The Lua side defines the interface; ObjC forwards everything. | High |

### C++ things that don't apply here

| C++ concept | Why it doesn't help |
|---|---|
| RTTI (`dynamic_cast`) | ObjC has `isKindOfClass:` — simpler, no type_info needed |
| Templates | No equivalent in ObjC; use `id` + runtime checks instead |
| Function pointers | ObjC uses blocks or `performSelector:` — type-safe, no raw pointers |
| `std::bind` / lambdas | ObjC blocks are the equivalent, with automatic memory management |
| RAII | ARC handles memory; use `CFBridgingRetain`/`CFRelease` at the boundary |

### Gotchas to avoid

| Gotcha | Why it happens | Fix |
|---|---|---|
| **Resolving ownership from a coroutine** | `L` in a coroutine bridge call differs from the root state's pointer, so pointer-keyed owner maps miss. | Use `owner_for_state(L)`, which reads the inherited owner pointer from `lua_getextraspace`; do not restore the deleted `"bridge_main"` registry workaround. |
| **`lua_tostring` mutating numbers on the stack** | Calling `lua_tostring` on a number changes the stack slot to a string, breaking `lua_next` iteration. | Use `lua_pushvalue` before conversion, or check `lua_type` first. |
| **`sizeToFit` on non-NSControl views** | `NSScrollView`, `NSSplitView` don't implement it — crash. | Guard with `respondsToSelector:@selector(sizeToFit)`. |
| **ARC and `lua_State*` lifetime** | ARC won't release the `lua_State*` for you — it's a C pointer. The ObjC object holding it can be dealloc'd while the state is still alive. | Never store `lua_State*` as an ObjC property without a corresponding `__weak` or manual cleanup in `dealloc`. |
| **Blocks capturing `lua_State*` in async work** | A raw pointer can outlive its state, especially for isolated canvas evaluations. | Capture `LuaStateOwner` strongly, check cancellation, and resume through its live state. Never capture a bare state pointer as the lifetime mechanism. |

## File layout

```
lua-objc/
├── AGENTS.md
├── Makefile
├── src/
│   ├── host.c              # tiny AppKit.dylib loader executable
│   ├── main.m              # constants, fragment includes, registration + host
│   ├── appkit/             # focused bridge fragments in the same translation unit
│   ├── uikit/              # focused UIKit bridge fragments
│   ├── shared/             # shared Lua state, async, HTTP, JSON, error helpers
│   └── uikit_module.m      # self-contained UIKit Lua module
├── lua/
│   ├── embedded/
│   │   ├── AppKit.lua      # embedded declarative macOS layer
│   │   ├── UIKit.lua       # embedded declarative iOS layer
│   │   └── IDEKit.lua      # embedded IDE component layer
│   └── TestKit.lua         # Assertion helpers for testing
└── tests/
│   └── bridge.test.lua      # Framework tests
└── examples/
    ├── hello.lua           # Window + Text + Image demo
    ├── list.lua            # Window + List (NSTableView) demo
    ├── live.lua            # Stock ticker with coroutines + spinner
    ├── weather.lua         # Real network fetch (wttr.in)
    ├── welcome.lua         # Xcode-style welcome window
    └── mail.lua            # Sidebar + toolbar + split view
```

## XML view templates

`lua/ui/xml.lua` provides a cross-platform XML-to-view renderer. It sits between
the app controller layer and the `ns.*` APIs. The same XML file produces
`NSTextField` on AppKit and `UILabel` on UIKit with no conditionals in the
template, because the platform module (`ns`) is injected by the caller.

Templates use the `.etlua` extension to reflect that they contain etlua
(Lua embedded in XML) rather than plain XML.

### How it works

1. **etlua pass** — the XML source is treated as an etlua template.
   `<%= expr %>` substitutes a value; `<% stmt %>` runs Lua code (conditionals,
   loops). The data table passed to `render` is the template's environment.
2. **XML parse** — a pure-Lua SAX-style parser turns the rendered string into a
   node tree. No external XML dependency.
3. **Tag dispatch** — each element tag is looked up in the registry and called as
   `handler(ns, attrs, children) → view`. Unknown tags raise an error at render
   time, not at template load time.

### Tag vocabulary

| XML tag | AppKit result | UIKit result |
|---------|---------------|--------------|
| `<Label text="…">` / `<Text>` | `ns.Text` (NSTextField) | `ns.Text` (UILabel) |
| `<Title text="…">` | `ns.Title` | `ns.Title` |
| `<TextField>` | `ns.TextField` | `ns.TextField` |
| `<Button title="…">` | `ns.Button` | `ns.Button` |
| `<VStack>` / `<HStack>` | flex containers | flex containers |
| `<HSplit>` | `ns.HSplit` (NSSplitView) | — |
| `<Spacer>` / `<Divider>` | layout helpers | layout helpers |
| `<Image src="…">` | `ns.Image` | `ns.Image` |
| `<Image symbol="…">` / `<SystemImage>` | `ns.SystemImage` | `ns.SystemImage` |
| `<Toggle>` / `<Switch>` | `ns.Toggle` | `ns.Toggle` |
| `<List>` + `<Column>` children | `ns.List` (NSTableView) | — |
| `<Window>` | window config table | window config table |
| `<Toolbar>` + `<ToolbarItem>` | toolbar items | toolbar items |

All layout attributes (`flexGrow`, `padding`, `fixedWidth`, etc.) are accepted on
every tag and forwarded to `applyLayout`.

**`<List>` attributes:**

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `style` | `"plain"` `"sourceList"` `"inset"` | automatic | `NSTableView` style |
| `header` | bool | `true` | Show the column header |
| `alternatingRows` | bool | `true` | Alternating row colors |
| `bordered` | bool | `false` | Bezel around the scroll view |
| `gridLines` | string | — | `"horizontal"` `"vertical"` `"both"` |

**`<Column>` attributes:** `id` (required, matches row dict key), `title`, `width`, `minWidth`, `alignment`.

**`ref=` attribute (all tags):** Storing `ref="name"` on any element causes `xml.renderFile`
to return that view as `refs["name"]`. Controllers use refs to attach callbacks after
rendering without building views in Lua code:

```xml
<List ref="messageList" style="plain" header="false">
    <Column id="from" title="From" />
</List>
```

```lua
local layout, refs = xml.renderFile("views/Window.etlua")
refs.messageList:replaceRows(rows)
refs.messageList:onRowSelect(function(_, _, row) ... end)
```

### Window config from XML (NIB-style)

The `<Window>` tag captures window configuration declaratively, similar to
Xcode NIB/Storyboard files. `xml.renderFile` detects a `<Window>` root and
returns `(config, refs)` instead of `(view, refs)`:

```xml
<Window title="Mail" width="940" height="520" minWidth="640" minHeight="400">
    <Toolbar>
        <ToolbarItem id="compose" label="Compose"
                     icon="square.and.pencil" tooltip="New Message" />
    </Toolbar>
    <HSplit>
        <List ref="mailboxList" ... />
    </HSplit>
</Window>
```

**Window attributes:** `title`, `width`, `height`, `minWidth`, `minHeight`,
`maxWidth`, `maxHeight`, `appearance`, `tabbingMode`, `tabbingIdentifier`,
`toolbarLabels`, `visible`, `sidebarWidth`, `toolbarContentDividerAfter`.

**ToolbarItem attributes:** `id`, `label`, `icon`, `tooltip`, `action`.

Toolbar `action` strings are resolved to Controller methods via an ACTIONS table:

```lua
local ACTIONS = {
    compose = function(self) self:compose() end,
    refresh = function(self) self:refresh() end,
}
for _, item in ipairs(cfg.toolbar or {}) do
    if item.action and ACTIONS[item.action] then
        local fn = ACTIONS[item.action]
        item.action = function() fn(self) end
    end
end
```

### Template inheritance (Blade/Twig style)

Child templates can extend a parent layout, defining blocks that the parent
renders via `yield()`. This is similar to PHP's Blade/Twig template inheritance.

**Parent template** (`views/AppWindow.etlua`):

```xml
<Window title="<%= title %>" width="<%= width or 640 %>" height="<%= height or 420 %>">
    <% if toolbar then %>
    <Toolbar>
        <% for _, item in ipairs(toolbar) do %>
        <ToolbarItem id="<%= item.id %>"
                     <% if item.label then %>label="<%= item.label %>"<% end %>
                     <% if item.icon then %>icon="<%= item.icon %>"<% end %>
                     <% if item.tooltip then %>tooltip="<%= item.tooltip %>"<% end %>
                     />
        <% end %>
    </Toolbar>
    <% end %>
    <%- yield("content") %>
</Window>
```

**Child template** (`examples/hello/views/Window.etlua`):

```lua
<% extends("views/AppWindow.etlua", { title = "Hello", width = 480, height = 420 }) %>
<% block("content", [[
    <VStack flexGrow="1" padding="24" spacing="12" alignment="leading">
        <Label text="Hello from Lua" size="24" weight="bold" />
        <Label text="A SwiftUI-like API backed by native AppKit controls." size="14" />
    </VStack>
]]) %>
```

**API:**
- `extends(path, data)` — load parent template with data context
- `block(name, content)` — define a named content section (content is a Lua string)
- `yield(name)` — emit block content in parent template (returns empty string if undefined)

Relative paths are resolved from the child template's directory.

### Partials

Include reusable sub-templates with `partial()`. This is similar to PHP's
`@include` or Rails' `render partial`:

```lua
<%= partial("views/partials/SimpleList.etlua", {
    ref = "employeeList",
    columns = {
        { id = "name", title = "Name" },
        { id = "role", title = "Role" },
    },
}) %>
```

Partials receive their own data context and resolve paths relative to their
own file location.

**Example partial** (`views/partials/SimpleList.etlua`):

```xml
<List ref="<%= ref or 'list' %>" flexGrow="1"
      <% if style then %>style="<%= style %>"<% end %>
      header="false" alternatingRows="false">
    <% for _, col in ipairs(columns) do %>
    <Column id="<%= col.id %>"
            <% if col.title then %>title="<%= col.title %>"<% end %>
            <% if col.width then %>width="<%= col.width %>"<% end %>
            <% if col.alignment then %>alignment="<%= col.alignment %>"<% end %>
            />
    <% end %>
</List>
```

### View description format

For efficient diffing and patching, `lua/ui/viewdesc.lua` compiles templates
to plain-table descriptions instead of live native views. This enables
React-style updates where only changed views are recreated:

```lua
local viewdesc = require("ui.viewdesc")

-- Generate description from template
local desc = viewdesc.fromFile("views/Window.etlua", data)

-- Later, with new data
local newDesc = viewdesc.fromFile("views/Window.etlua", newData)

-- Diff (returns list of patches)
local patches = viewdesc.diff(desc, newDesc)

-- Apply to live views (stub — implementation depends on native bridge)
viewdesc.apply(liveView, patches)
```

**Description format:**

```lua
{
    tag = "VStack",           -- component name
    props = { padding = 24 }, -- layout props
    children = { ... },       -- child descriptions
    key = "unique-id",        -- for stable identity during diffing
}
```

### Extending the registry

```lua
local xml = require("ui.xml")
xml.registry["Avatar"] = function(ns, attrs, children)
    -- attrs.src, attrs.size available
    return ns.Image { attrs.src, fixedWidth = tonumber(attrs.size) or 32 }
end
```

### API

```lua
local xml = require("ui.xml")

-- Render from a string (data optional, ns defaults to require("AppKit"))
local view = xml.render(xmlString, data, ns)

-- Render from a file path (relative to cwd)
local view = xml.renderFile("examples/mail/views/Window.etlua", rowData, ns)

-- When XML root is <Window>, returns (config, refs) instead of (view, refs)
local cfg, refs = xml.renderFile("examples/mail/views/Window.etlua")

-- Decode data XML into Lua tables via schema
local data = xml.decode(xmlString, schema)

-- Decode from file path
local data = xml.decodeFile("examples/mail/share/messages.xml", schema)
```

The returned value is a single view userdata. When the XML root has multiple
sibling elements, they are wrapped in a `ns.VStack`.

### Schema-based XML data decoding

`xml.decode` and `xml.decodeFile` parse XML into Lua tables based on a schema,
so app models can describe structure/types once instead of re-implementing
attribute parsing, entity decoding, arrays, and CDATA handling.

Supported schema primitives:

- `root = "a/b"` — select the document root path before decoding fields.
- `fields = { ... }` — object mapping.
- `array = true` + `path = "x/y"` — collect many child elements.
- `attr = "name"` — read an attribute value.
- `text = true` — read element text content.
- `type = "string" | "number" | "integer" | "boolean"` — type coercion.
- `default = value` — fallback when value is missing or coercion fails.

String field shorthands:

- `"@id"` is equivalent to `{ attr = "id" }`.
- `"#text"` is equivalent to `{ text = true }`.
- `"body/title"` is equivalent to `{ path = "body/title", text = true }`.

Example (mail data):

```lua
local xml = require("ui.xml")

local schema = {
  root = "mail",
  fields = {
    mailboxes = {
      path = "mailboxes/mailbox",
      array = true,
      fields = {
        id = "@id",
        name = "@name",
        count = { attr = "count", type = "number", default = 0 },
      },
    },
    messages = {
      path = "messages/message",
      array = true,
      fields = {
        id = { attr = "id", type = "number" },
        unread = { attr = "unread", type = "boolean", default = false },
        body = { path = "body", text = true, default = "" },
      },
    },
  },
}

local data = xml.decodeFile("examples/mail/share/messages.xml", schema)
```

This API decodes XML entities in attributes/text and preserves multiline CDATA
content when extracting text fields.

## MVP app structure

Every standalone example app follows the same three-layer structure:

```
examples/<appname>/
  init.lua        — entry point only: WindowController.new():createWindow()
  Model.lua       — data, queries, mutations; no ns.* calls
  Controller.lua  — defines WindowController class; one ns.Window call
  views/          — *.etlua templates; all view construction happens here
```

### Rules

- `init.lua` constructs one `WindowController` instance and calls
  `createWindow()`. It must not contain UI logic.
- `Model.lua` must not call any `ns.*` APIs. It is testable headlessly without
  AppKit.
- `Controller.lua` defines a `WindowController` class (metatable + `__index`).
  It is the only file that calls `ns.Window { ... }`. All other view
  construction is delegated to XML templates via `xml.renderFile`.
- Controllers must not call `ns.VStack`, `ns.HStack`, `ns.List`, or any other
  view constructor. Use `xml.renderFile` and wire behaviour through `refs`.
- XML templates in `views/` express the complete view hierarchy. `ref="name"`
  on any element surfaces that view to the controller for callback wiring.

### Example: mail app

```lua
-- examples/mail/init.lua
local WindowController = require("examples.mail.Controller")
return WindowController.new():createWindow()
```

```lua
-- examples/mail/Controller.lua  (abridged)
local WindowController = {}
WindowController.__index = WindowController

function WindowController.new()
    return setmetatable({ selectedMailbox = Model.mailboxes[1] }, WindowController)
end

function WindowController:createWindow()
    local cfg, refs = xml.renderFile("views/Window.etlua")
    self.messageList = refs.messageList
    self.detailPane  = refs.detailPane
    self.messageList:replaceRows(Model.byMailbox(self.selectedMailbox.id))
    self.messageList:onRowSelect(function(_, _, row)
        self:showDetail(Model.find(row._id))
    end)
    return ns.Window(cfg)
end
end
```

```xml
<!-- examples/mail/views/Window.etlua -->
<HSplit>
    <List ref="mailboxList" fixedWidth="180" style="sourceList" header="false">
        <Column id="name" title="Mailbox" />
    </List>
    <List ref="messageList" fixedWidth="280" style="plain" header="false">
        <Column id="from" title="From" />
    </List>
    <VStack ref="detailPane" flexGrow="1" />
</HSplit>
```

```xml
<!-- examples/mail/views/MessageDetail.etlua -->
<VStack flexGrow="1" padding="24" spacing="16" alignment="leading">
    <Label text="<%= subject %>" size="18" weight="semibold" />
    <HStack spacing="8">
        <Label text="<%= from %>" size="13" weight="medium" />
        <Label text="<%= date %>"  size="12" color="secondary" />
    </HStack>
    <Divider />
    <Label text="<%= body %>" size="13" flexGrow="1" />
</VStack>
```
