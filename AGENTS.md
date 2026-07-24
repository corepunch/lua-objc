# lua-objc

SwiftUI-like declarative UI from Lua scripts, backed by AppKit (NSView/NSWindow).
Edit `.lua` files — no recompilation needed.

**Goal: 100% SwiftUI coverage via Lua.** Every control should be a proper
AppKit-backed widget, never a hack (no `Text "----"` for separators or
`Text "[ ]"` for checkboxes). If something looks like a placeholder, the
missing widget must be built.

## Architecture

```
lua script  -->  UI.lua (sugar)  -->  bridge (C)  -->  AppKit objects
                                    (lua C API)      (NSWindow, NSView, etc.)
```

1. **`src/main.m`** — Host binary. Embeds Lua, registers the `bridge` module
   (C functions exposed to Lua), loads and runs a Lua script, then starts the
   Cocoa run loop.

2. **`lua/UI.lua`** — Lua module providing SwiftUI-like functions
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
| `_spinner()` / `_spinner_start` / `_spinner_stop` | `NSProgressIndicator` |
| `_show(window)` | orders window front (run loop in `main()`) |

### Layout

Layout is done recursively in C (`layout_recursive`). Containers tagged
via `objc_setAssociatedObject` (`"vstack"` / `"hstack"`) lay out their
children top-to-bottom or left-to-right with 12pt padding.

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

The array part of the table holds child views (added to a VStack inside the
window's content view). After building the view tree, calls `bridge._show(win)`
— the run loop starts in `main()` after the script returns.

```lua
Window {
    title = "My App",
    width = 600,
    height = 400,
    Text "Hello",           -- array part = children
    List { columns = ... }, -- added to window's VStack
}
```

### `VStack{...}` / `HStack{...}`

Layout containers. Children listed in the array part are stacked vertically or
horizontally with 12pt padding. Returns an NSView userdata that can be added as
a child of any other container.

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
| `columns` | `{{id, title}}` | *(required)* | Array of column specs |
| `width` | number | `400` | Scroll view width |
| `height` | number | `200` | Scroll view height |
| `data` | `{{key=val}}` | `{}` | Initial rows (array of string-keyed tables) |

```lua
List {
    width = 620,
    height = 350,
    columns = {
        { id = "name", title = "Name" },
        { id = "role", title = "Role" },
        { id = "dept", title = "Dept" },
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
    └── list.lua            # Window + List (NSTableView) demo
```
