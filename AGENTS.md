# lua-objc

SwiftUI-like declarative UI from Lua scripts, backed by AppKit (NSView/NSWindow).
Edit `.lua` files — no recompilation needed.

## Architecture

```
lua script  -->  UI.lua (sugar)  -->  bridge (C)  -->  AppKit objects
                                    (lua C API)      (NSWindow, NSView, etc.)
```

1. **`src/main.m`** — Host binary. Embeds Lua, registers the `bridge` module
   (C functions exposed to Lua), loads and runs a Lua script, then starts the
   Cocoa run loop.

2. **`lua/UI.lua`** — Lua module providing SwiftUI-like functions
   (`Window`, `VStack`, `HStack`, `Text`, `Image`, `Spacer`).
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
| `_text(str)` | `NSTextField` (non-editable label) |
| `_image(path)` | `NSImageView` |
| `_add(parent, child)` | calls `addSubview:` |
| `_layout(view, width)` | recursive frame-based layout in C |
| `_show(window)` | starts `[NSApp run]` |

### Layout

Layout is done recursively in C (`layout_recursive`). Containers tagged
via `objc_setAssociatedObject` (`"vstack"` / `"hstack"`) lay out their
children top-to-bottom or left-to-right with 12pt padding.

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

## Lua API (SwiftUI-like)

- `Window{...}` — table keys: `title`, `width`, `height`. Array part: children.
- `VStack{...}` / `HStack{...}` — layout containers. Array part: children.
- `Text "string"` — label (also accepts `Text{"string"}`).
- `Image "path"` — image view.
- `Spacer()` — empty 10×10 view.

Each function returns an ObjC userdata. Lua's parenthesis-free calling convention
makes the SwiftUI-like syntax possible: `fn "arg"` == `fn("arg")`, and
`fn { ... }` == `fn({...})`.

## Building

Requires:
- macOS (AppKit)
- Lua 5.4 (`brew install lua`)

```sh
make          # build ./lua-objc
make run      # run examples/hello.lua
make run ARGS="examples/hello.lua"
make clean
```

## File layout

```
lua-objc/
├── AGENTS.md
├── Makefile
├── src/
│   └── main.m          # host binary + bridge
├── lua/
│   └── UI.lua          # SwiftUI-like Lua module
└── examples/
    └── hello.lua       # example script
```
