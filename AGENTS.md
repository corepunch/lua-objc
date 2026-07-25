# lua-objc

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
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons):
  use native roles and bezel styles. Make the most likely safe action primary;
  never make a destructive action primary. Use precise verb labels.
- [Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators):
  show progress only while work is occurring, prefer determinate progress when
  duration is known, keep indeterminate indicators moving, and generally avoid
  labeling a spinner. Refresh automatically when appropriate while still
  allowing an explicit refresh action when useful.
- Use menus, separators, split views, sidebars, search fields, toggles, and
  other real AppKit widgets for their intended roles. A visual approximation is
  a missing framework feature, not an acceptable sample implementation.

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
lua script  -->  luaui.lua (sugar)  -->  bridge (C)  -->  AppKit objects
                                    (lua C API)      (NSWindow, NSView, etc.)
```

1. **`src/main.m`** — Host binary. Embeds Lua, registers the `bridge` module
   (C functions exposed to Lua), loads and runs a Lua script, then starts the
   Cocoa run loop.

2. **`lua/luaui.lua`** — Lua module providing SwiftUI-like functions
   (`Window`, `VStack`, `HStack`, `Text`, `Image`, `Spacer`, `List`).
   Translates to `bridge._*` calls that create real ObjC objects.

3. **`examples/*.lua`** — UI scripts written by the user. No compilation step.

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

## Scoping: `_ENV` trick

The host binary creates a custom Lua environment for each user script. The env's
`__index` metamethod first looks up names in the `UI` module, then falls back to
`_G`. This means users write bare names — no `require "UI"` or `UI.` prefix:

```lua
Window {
    title = "My App",
    width = 480,
    height = 360,
    VStack {
        Text "Hello, World!",
        Image "/path/to/image.jpg",
    }
}
```

This technique comes from [leafo's DSL guide](https://leafo.net/guides/dsl-in-lua.html).

## Lua API — Views

Each function returns an ObjC userdata. Lua's parenthesis-free calling convention
makes the SwiftUI-like syntax possible: `fn "arg"` == `fn("arg")`, and
`fn { ... }` == `fn({...})`.

### `Window{...}`

Creates an `NSWindow`. Table keys:

| Key | Type | Default | Description |
|---|---|---|---|
| `title` | string | `"Window"` | Window title |
| `width` | number | `480` | Content width in points |
| `height` | number | `360` | Content height in points |
| `transparent_titlebar` | bool | `false` | Full-size content, transparent title bar |
| `hide_title` | bool | `=transparent_titlebar` | Hide title text in transparent mode |
| `toolbar` | `{{id, label, icon?, tooltip?, action?}}` | none | Native NSToolbar items |
| `toolbar_labels` | bool | `false` | Show labels below toolbar icons |

The array part of the table holds child views (added to a VStack inside the
window's content view). After building the view tree, calls `bridge._show(win)`
— the run loop starts in `main()` after the script returns.

```lua
Window {
    title = "My App",
    width = 600,
    height = 400,
    toolbar = {
        { id = "new",  label = "New" },
        { id = "save", label = "Save", action = function() print("saved") end },
    },
    Text "Hello",
    List { columns = ... },
}
```

`Window{...}` returns its native window userdata. Use
`ToolbarItem(window, id)` when an item needs dynamic native properties, or
`ToolbarProgress(window, id)` to replace an action's symbol with a real
indeterminate `NSProgressIndicator` while work is active:

```lua
local progress = ToolbarProgress(window, "refresh")
progress:start("Refreshing data")
-- asynchronous work
progress:stop("Refresh data — last updated just now")
```

This API stays small by relying on the generic KVC bridge for properties like
`enabled`, `view`, `image`, and `toolTip`; don't add a dedicated C bridge
function for each toolbar state.

### `VStack{...}` / `HStack{...}`

Layout containers. Children listed in the array part are stacked vertically or
horizontally with 8pt sibling spacing and no implicit outer padding. Set
`padding = number` explicitly when a group needs margins. Returns an NSView
userdata that can be added as a child of any other container.

```lua
VStack {
    Text "Line 1",
    Text "Line 2",
    HStack {
        Text "Left",
        Spacer(),
        Text "Right",
    }
}
```

### `HSplit{...}`

Horizontal split view (NSSplitView with thin vertical divider). Children
are divided equally across the available width. Useful for sidebar + content
layouts.

```lua
HSplit {
    VStack { Text "Sidebar" },
    VStack { Text "Content" },
}
```

### `Text "string"` / `Text{"string"}`

Creates a non-editable, bezel-less `NSTextField` label. Both forms work,
with an optional `size` and `weight` key for custom fonts:

```lua
Text "Hello"                          -- default font
Text { "Hello", size = 16 }           -- 16pt system font
Text { "Hello", size = 18, weight = "bold" }  -- 18pt bold
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

```lua
Button { title = "Create New Script" }
Button {
    title = "Create New Script",
    action = function() print("clicked") end
}
```

### `Toggle{...}`

Creates an `NSButton` checkbox. Keys: `label` (string), `is_on` (bool),
`action` (function, optional).

```lua
Toggle { label = "Show on launch", is_on = true }
Toggle {
    label = "Show on launch",
    is_on = true,
    action = function() print("toggled") end
}
```

The toggle state can be read/written via `toggle:get_state()` and
`toggle:set_state(bool)` (exposed through the nsview metatable `__index`).

### `Separator()`

Creates an `NSBox` with `NSBoxSeparator` style — a thin horizontal line.
Use between sections instead of faking it with `Text "---"`.

### `Spacer()`

Empty 10×10 view used to push siblings apart in HStack/VStack.

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
  `id` maps directly to a key in the row's `NSDictionary`. For now, cells are
  `NSTextField`s showing the string value. A future `cell` callback per column
  (stored in the Lua registry) would enable custom renderers without changing
  the data model.
- **Methods via `nsview` metatable `__index`** — instead of returning a Lua
  wrapper table (which can't be added as a subview), we attach the data source
  to the scroll view via `objc_setAssociatedObject`. The `nsview` metatable's
  `__index` function checks for this association and returns C functions for
  `add_row`, `remove_row`, `clear_rows`, `row_count`. This means the userdata
  returned by `List{...}` is both a valid NSView (addable to any container) and
  a method-bearing object.

```
List { ... }  returns  NSScrollView userdata
                              │
              objc_setAssociatedObject(scrollView, &kTableSourceKey, dataSource)
                              │
              tv:add_row{} → nsview.__index → bridge_tableview_add()
                              │
                     [dataSource addRow:]
                     [tableView insertRowsAtIndexes:withAnimation:]
```

### `List{...}`

Creates an `NSScrollView` wrapping a view-based `NSTableView` with alternating
row colors, a header, and a vertical scroller. Table keys:

| Key | Type | Default | Description |
|---|---|---|---|
| `columns` | `{{id, title, width?, alignment?}}` | *(required)* | Array of column specs |
| `width` | number | `400` | Scroll view width |
| `height` | number | `200` | Scroll view height |
| `header` | bool | `true` | Show the native table header |
| `bordered` | bool | `false` | Draw a bezel around the scroll view |
| `data` | `{{key=val}}` | `{}` | Initial rows (array of string-keyed tables) |

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
string value of `row[id]`. Numbers are converted to strings automatically.
Column alignment can be `"leading"` (default), `"center"`, or `"trailing"`;
the header and reusable native cells use the same alignment.

### List methods

These are available on the userdata returned by `List{...}`, exposed via the
nsview metatable `__index`:

```lua
tv:add_row{ key = "value", ... }    -- inserts with slide-down animation
tv:remove_row(2)                     -- removes row at 0-based index
tv:clear_rows()                      -- removes all rows (reloadData)
n = tv:row_count                     -- returns number of rows (read-only property)
```

Methods can be called **before** `Window{...}` shows the app (e.g. in initial
setup) or **during** runtime (e.g. from a timer/event handler — see below).

### Complete example

```lua
Window {
    title = "Employee Directory",
    width = 640,
    height = 420,
    VStack {
        Text "Employees",
        List {
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

The current implementation maps column `id` → `row[id]` → `NSTextField`.
To support custom per-column cell renderers:

1. Add a `cell` key to each column spec — a Lua function stored in the registry.
2. In `LuaTableViewSource.tableView:viewForTableColumn:row:`, if a column has a
   registered cell callback, call it with the row dictionary to get a view.
3. The callback returns userdata (any NSView) which becomes the cell.

The bridge function prototype:

```c
// In bridge_tableview, after creating columns:
if (lua_getfield(L, -1, "cell") == LUA_TFUNCTION) {
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);  // store callback
    // attach ref to the NSTableColumn via associated object
}
```

This would let users write:

```lua
List {
    columns = {
        { id = "name", title = "Name" },
        { id = "avatar", title = "",
          cell = function(row) return Image(row.avatar_path) end },
    }
}
```

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
local tv = List { columns = {...} }

Timer(2.0, function()
    tv:add_row{ name = "New User", role = "Engineer", dept = "Core" }
end)

Window { title = "Live Data", width = 600, height = 400, tv }
```

## Conventions

**Tab indentation.** All source files (`.m`, `.lua`) use tabs for leading
indentation, not spaces. Set your editor to display tabs at 4 columns wide.

```sh
# To convert spaces to tabs in any file:
perl -i -pe '1 while s/^(\t*)    /$1\t/' file
```

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

### Not yet using — would reduce boilerplate further

| Trick | How it helps | Effort |
|---|---|---|
| **KVC (`setValue:forKey:`)** | Replace `bridge._set_text`, `bridge._set_frame`, etc. with one generic `bridge._set(view, "stringValue", "hello")`. KVC auto-boxes scalars and handles type conversion. | Low |
| **`performSelector:`** | `bridge._call(view, "sizeToFit")` — call any method by name without a typed bridge function. Guard with `respondsToSelector:`. | Low |
| **`class_copyMethodList`** | Enumerate all methods on NSView/NSWindow at runtime, auto-register them as Lua-callable bridge functions. One-time setup, then new AppKit methods work for free. | Medium |
| **Generic Lua↔NSDictionary** | A recursive converter: Lua table → `NSDictionary`/`NSArray`, ObjC collection → Lua table. Eliminates `lua_table_to_dict` and enables passing complex data anywhere. | Medium |
| **KVO** | `observeValueForKeyPath:ofObject:change:context:` → Lua callback. Enables reactive UI: change a property in ObjC, Lua gets notified automatically. | Medium |
| **`NSInvocation`** | Full dynamic method invocation with arbitrary signatures. More complex but enables calling any method without writing a typed wrapper. | High |
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
| **Calling `lua_pcall` from a coroutine's C function** | `L` in a coroutine's bridge function is the coroutine's `lua_State *`, not the main state. `lua_pcall` on it corrupts the stack. | Store main `L` as lightuserdata in registry (`"bridge_main"`), retrieve it before `lua_pcall` from timer callbacks. |
| **`lua_tostring` mutating numbers on the stack** | Calling `lua_tostring` on a number changes the stack slot to a string, breaking `lua_next` iteration. | Use `lua_pushvalue` before conversion, or check `lua_type` first. |
| **`sizeToFit` on non-NSControl views** | `NSScrollView`, `NSSplitView` don't implement it — crash. | Guard with `respondsToSelector:@selector(sizeToFit)`. |
| **ARC and `lua_State*` lifetime** | ARC won't release the `lua_State*` for you — it's a C pointer. The ObjC object holding it can be dealloc'd while the state is still alive. | Never store `lua_State*` as an ObjC property without a corresponding `__weak` or manual cleanup in `dealloc`. |
| **Blocks capturing `lua_State*` in timers** | The block captures the pointer by value. If the Lua state is closed before the timer fires → crash. | Ensure the Lua state outlives all timers (it does — state closes in `main()` after `[NSApp run]` returns). |

## File layout

```
lua-objc/
├── AGENTS.md
├── Makefile
├── src/
│   └── main.m              # host binary + bridge + LuaTableViewSource
├── lua/
│   └── UI.lua              # SwiftUI-like Lua module
└── examples/
    ├── hello.lua           # Window + Text + Image demo
    ├── list.lua            # Window + List (NSTableView) demo
    ├── live.lua            # Stock ticker with coroutines + spinner
    ├── weather.lua         # Real network fetch (wttr.in)
    ├── welcome.lua         # Xcode-style welcome window
    └── mail.lua            # Sidebar + toolbar + split view
```
