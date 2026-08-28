# lua-objc Architecture

## Overview

lua-objc runs Lua scripts against native framework modules. Public UI
frameworks are Mach-O dylibs loaded by Lua; their declarative conveniences are
authored in Lua and embedded into the corresponding library at build time.

```
examples/*.lua              User-facing UI descriptions
src/host.c                  Tiny executable loader
src/main.m                  AppKit translation-unit root and registration
src/appkit/*.m              Focused bridge fragments included by main.m
src/uikit/*.m               UIKit bridge root and focused fragments
src/shared/*.m              Shared Lua state, async, HTTP, JSON, error helpers
build/AppKit.dylib          AppKit runtime + luaopen_AppKit
build/UIKit.dylib           UIKit runtime + luaopen_UIKit (iOS SDK)
lua/embedded/*.lua          Declarative layers embedded in those dylibs
src/appkit/canvas_eval.m    Isolated AppKit canvas evaluation
```

---

## Native module loading

`src/host.c` loads `build/AppKit.dylib` and calls its `lua_objc_main` entry
point. The framework owns the Lua state, AppKit bridge, layout metadata keys,
callback targets, and run loop. Keeping these in one image avoids splitting
native object identity or associated-object keys across the executable and a
plugin.

The runtime appends `build/?.dylib` to `package.cpath`. Consequently:

```lua
require("AppKit")  -- luaopen_AppKit in AppKit.dylib
require("UIKit")   -- luaopen_UIKit in UIKit.dylib, inside an iOS host
```

The build converts each `lua/embedded/*.lua` source into a byte-array header.
`luaopen_*` evaluates that embedded chunk and returns its complete public API
table. There is no loose `AppKit.lua`, `IDEKit.lua`, or `UIKit.lua` module that
can silently bypass native loading.

`AppKitNative` and `UIKitNative` are private implementation modules. The
legacy `bridge` name remains temporarily available for existing application
code, but public framework layers do not depend on it.

`make all` builds AppKit everywhere and also builds UIKit when an
iPhone Simulator SDK is available. `make uikit` requests that target
explicitly and fails with a focused message when Xcode platform support is
missing.

---

## Layer 1 — Native runtimes and shared services

### AppKit runtime (`src/main.m` and `src/appkit/*.m`)

The AppKit bridge is a single Objective-C/C translation unit inside
`AppKit.dylib`. `src/main.m` owns shared constants and registration and includes
the focused fragments under `src/appkit/`. This preserves static shared state
without forcing readers to load an unrelated 4,000-line file. See
`src/README.md` for the subsystem map.

### UIKit runtime (`src/uikit_module.m` and `src/uikit/*.m`)

`src/uikit_module.m` embeds the public Lua layer and includes
`src/uikit/bridge.m`, the UIKit translation-unit root. That root owns UIKit
keys and module registration and includes focused fragments for layout, views,
controls, tables, metatables, and platform helpers.

Both runtime roots include `src/shared/lua_error.m` and
`src/shared/lua_async.m`, plus the state-agnostic boundary helpers in
`src/shared/lua_bridge_support.m`. The support layer owns native userdata and
converts scalar and collection values between Lua and Foundation without
owning a Lua state. The shared async layer supplies timers, HTTP, JSON,
coroutine-safe owner lookup, and cancellation. AppKit-created states use
closing owners; UIKit is loaded into a host-owned state and installs a
non-closing registry owner that detaches safely during `lua_close`.

### View construction

Every UI primitive is a C function that allocates a native AppKit object and returns it as an `ObjCRef` userdata to Lua:

| Bridge function | AppKit class | Lua API |
|---|---|---|
| `bridge_vstack` | `NSView` (axis=vstack) | `ns.VStack` |
| `bridge_hstack` | `NSView` (axis=hstack) | `ns.HStack` |
| `bridge_hsplit` | `NSSplitView` (vertical=YES) | `ns.HSplit` |
| `bridge_vsplit` | `NSSplitView` (vertical=NO) | `ns.VSplit` |
| `bridge_separator` | `NSBox` (boxType=separator) | `ns.Separator` |
| `bridge_text_view` | `NSScrollView` + `NSTextView` | `bridge._textView()` |
| `bridge_tableview` | `NSScrollView` + `NSTableView` | `ns.List` |
| `bridge_window` | `NSWindow` | `ns.Window` |

Layout metadata (flexGrow, padding, fixedWidth, etc.) is stored as associated objects on the native view using `objc_setAssociatedObject`. This keeps all layout state alongside the view without subclassing.

### Layout engine

A custom flex-like layout engine is implemented entirely in C (`layout_recursive`, `measure_view`, `distribute_main_axis`). It runs synchronously when `bridge._layout(view)` is called.

**Pass 1 — Measure** (`measure_view`): each view reports its natural size given a constraint. Leaf views use `intrinsicContentSize` / `fittingSize`. Stack views sum their children.

**Pass 2 — Distribute** (`distribute_main_axis`): free space is distributed among children proportional to their `flexGrow` weight, clamped by `minWidth`/`maxWidth`.

**Pass 3 — Place**: each child is given a frame and `layout_recursive` descends into it.

`NSSplitView` divider thickness is accounted for in both hsplit and vsplit layout passes.

### Canvas eval (`src/appkit/canvas_eval.m`)

Each canvas preview evaluation runs in a **fresh, isolated `lua_State`** (created by `canvas_state_create()`). This means:

- User code globals do not persist between evals.
- Module cache (`package.loaded`) is reset each run.
- Registry refs from previous evals cannot fire.

Inside the isolated state, `ns.Window` and `ns.Preview` are monkey-patched to return an `ns.VStack` instead of creating a real `NSWindow`. This is the same approach Xcode uses for its macOS preview: render the content view only, no window chrome.

The resulting `NSView` is marshalled back to the main Lua state via `CFBridgingRetain`, which keeps the view alive past `lua_close(C)`.

---

## Async state lifetime (`LuaStateOwner` + `lua_getextraspace`)

Async bridge functions (`_httpGet`, `_timerAfter`, `_textViewOnChange`) schedule
ObjC work that completes after the calling Lua code returns. Runtime-created
states follow this lifetime rule:

> A state must die exactly once, on the main thread, when its creator and all in-flight async ops are done with it.

Host-owned UIKit states use the same owner for callback lookup and cancellation,
but the host remains responsible for `lua_close`. The registry holds a
non-closing owner that detaches before state teardown.

The owner is an ObjC object (`LuaStateOwner`) rather than a hand-rolled
`_Atomic int` because ARC removes the three classic failure modes:

| Manual refcount failure | Why ARC is immune |
|---|---|
| Missed decrement on a callback error/early-return path → leak | capture = retain, release = block disposal, both automatic |
| Block never runs (invalidated timer, cancelled task) → unbalanced count | blocks don't retain raw C pointers, so a manual increment is never balanced; ARC's retain is tied to the block, not its execution |
| Double decrement → use-after-free | `-dealloc` runs exactly once, at the last release |

`-dealloc` is the single choke point where `lua_close` lives.

### Why extraspace instead of a registry or dictionary

Bridge functions resolve the owner via `owner_for_state(L)`, which reads an unretained pointer from `lua_getextraspace(L)`. Two properties make this correct:

1. **Coroutine inheritance.** Lua 5.4 copies the main thread's extraspace into every new coroutine at `lua_newthread`. `fetch`/`timer` are always called *from coroutines*, and a coroutine's `L` is not the root state — this was the "stuck spinner" bug: a pointer-keyed dictionary lookup on `L` missed because only the root state was registered. Extraspace inherits, so resolution works from any thread.
2. **No ABA window.** The extraspace read happens inside the calling state during an active C call, when the state is provably alive. A freed-and-reused pointer can never be looked up, because we never look anything up by pointer after the call returns — blocks capture the owner object itself.

`bridge_main` (registry-based root-state resolution) and the `gLuaOwners` dictionary were both deleted once extraspace replaced them.

### Why main-thread close matters

`NSURLSession` runs and *releases* completion blocks on background queues. If that background release is the last one, `-dealloc` runs there — and `lua_close` runs `__gc` handlers that `CFRelease` `NSView`s, which AppKit requires on the main thread. `-dealloc` therefore marshals the close to the main queue when needed.

### Design rejected: eager close + invalidation token

Close the canvas state immediately at eval end; callbacks capture a retained `alive` flag and drop themselves when flipped. Simpler ownership, but a canvas mid-fetch at eval end has its coroutines killed with the state — `live.lua` in the IDE canvas would render the table shell and never populate a row. Keep-alive is what makes live data in canvas previews work.

### Behavior by context

| Context | Owner | Async outcome |
|---|---|---|
| Main app state (`gL`) | created in `main()`, released by ARC at exit | works (standalone `live.lua`, `weather.lua`) |
| IDE canvas eval | created in `bridge_eval`, released at return | works — canvas state outlives eval until fetches complete |
| `--preview` CLI | none (extraspace zeroed) | callbacks drop cleanly; no crash, coroutines never resume |

---

## Layer 2 — AppKit.dylib

Provides a SwiftUI-like declarative API over the native bridge. Its editable
source is `lua/embedded/AppKit.lua`; that file is build input rather than a
runtime-searchable Lua module.

### Key functions

| Lua API | Bridge call | Notes |
|---|---|---|
| `ns.Window { ... }` | `bridge._window(...)` | Creates NSWindow, adds content VStack, triggers layout |
| `ns.VStack { ... }` | `bridge._vstack()` | Vertical flex container |
| `ns.HStack { ... }` | `bridge._hstack()` | Horizontal flex container |
| `ns.HSplit { ... }` | `bridge._hsplit()` | NSSplitView, left-right panes |
| `ns.VSplit { ... }` | `bridge._vsplit()` | NSSplitView, top-bottom panes |
| `ns.Separator()` | `bridge._separator()` | 1px NSBox rule |
| `ns.Text { ... }` | `bridge._textField()` | LuaTextField constructor with inherited KVC accessors |
| `ns.List { ... }` | `bridge._tableview(...)` | NSTableView in NSScrollView |
| `ns.Spacer()` | `bridge._spacer()` | flexGrow=1 filler |

### Layout props

All container and leaf views inherit bridge-owned layout accessors from the
`NSView` base extension. Ordinary Cocoa properties use the same KVC metatable:

```
padding, paddingHorizontal, paddingVertical
spacing, alignment
fixedWidth, fixedHeight
minWidth, minHeight, maxWidth, maxHeight
flexGrow, flexShrink, flexBasis
fillWidth, fillHeight
```

---

## IDE example (`examples/ide`)

The IDE is an intentionally small Lua application, not a separate framework.
It uses one native semantic sidebar for folder contents and one native editor
content pane. Folder selection, file watching, and saving stay in its
`Controller.lua`; file access and language detection stay in `Model.lua`.

### App layer

`lua/App.lua` is the root app controller. It does not mimic Swift inheritance;
it provides the same lifecycle role with a Lua object and callbacks:

- `App.args()` reads command-line arguments exposed by `src/main.m` as the
  global `arg` table.
- `App.new(spec)` creates a controller that can decide between a welcome scene
  and a workspace scene.
- `App:run()` opens the folder passed on the command line when present, and
  falls back to the welcome screen when no folder was provided.
- `App.recentStore(key)` persists recent folders/files under the user's app
  support directory.

The IDE now uses that layer to behave like VS Code on startup: open a folder
immediately when one was provided, or show a welcome screen with recent items
and an open-folder picker otherwise.

**Scene separation rule.** Components return view trees. Only `init.lua` (or
the `App` object's `welcome` callback) calls `ns.Window`. `Welcome.lua` returns
a plain `ns.HStack` view; `App.lua` wraps it in `ns.Window`. No component
module should ever create a window directly.

**MVP example layout.** Every standalone example lives under
`examples/<appname>/` with this layout:

```text
init.lua        ← requires and returns Controller class (framework instantiates)
Model.lua       ← data, queries, mutations (no ns.* calls)
Controller.lua  ← defines Controller class; wires model → views, owns actions
views/          ← *.etlua templates; no ns.* calls inside templates
```

`init.lua` never self-starts. It returns the class; the framework calls
`class.new():createWindow()`. No module-level function controllers, no loose
table hierarchies. Flat `examples/<appname>.lua` shims are forbidden.

The IDE example is organized as:

```text
examples/ide/
├── init.lua          # entry point
├── Model.lua         # file access and language detection
├── Controller.lua    # folder sidebar, editor, file watching, and saving
└── views/            # window configuration templates
```

That structure keeps app boot, scene selection, and UI composition separate
without introducing a second runtime or any non-Lua app scaffolding.

**PreviewArea API.** `PreviewArea` exposes `setContent(result, toolbarItems)`.
The `rebuildToolbar` closure is internal; callers never hold it.

This table wrapper avoids triggering KVC on `NSScrollView` when storing Lua-side methods.

---

### XML view templates (`lua/ui/xml.lua`)

A cross-platform XML renderer sits between the app layer and the `ns.*` APIs.
Templates live in `examples/<app>/views/*.etlua`. The renderer:

- Applies etlua (`lua/vendor/etlua`, git submodule) to the XML source first,
  substituting `<%= expr %>` and `<% stmt %>` blocks.
- Parses the resulting XML with a pure-Lua SAX-style parser.
- Maps each tag to an `ns.*` call via a registry table. The platform module
  (`ns`) is injected by the caller — `<Label>` becomes `ns.Text` on AppKit
  and `ns.Label` (→ UILabel) on UIKit. No conditionals in the template.
- Custom tags: `xml.registry["MyTag"] = function(ns, attrs, children) ... end`
- API: `xml.render(src, data, ns)` and `xml.renderFile(path, data, ns)`

#### ref= attribute and named view handles

Any element may carry `ref="name"`. `xml.render` and `xml.renderFile` return
two values: the root view and a `refs` table `{ [name] = view }`. Controllers
use refs to attach callbacks and call methods on specific views without
scanning the tree manually:

```lua
local layout, refs = xml.renderFile("views/Window.etlua")
refs.messageList:onRowSelect(function(_, _, row) ... end)
refs.detailPane:clearContainer()
```

`ref` is consumed by the renderer and never forwarded to the native layer.

#### Window config from XML (NIB-style)

The `<Window>` tag captures window configuration declaratively, similar to
Xcode NIB/Storyboard files:

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

`xml.renderFile` detects a `<Window>` root and returns `(config, refs)` instead
of `(view, refs)`. The config table includes title, dimensions, toolbar items,
and other window properties. Controllers pass it to `ns.Window(cfg)`. Toolbar
action strings (e.g., `action="compose"`) resolve to Controller methods via an
ACTIONS table:

```lua
local ACTIONS = {
    compose = function(self) self:compose() end,
}
for _, item in ipairs(cfg.toolbar or {}) do
    if item.action and ACTIONS[item.action] then
        local fn = ACTIONS[item.action]
        item.action = function() fn(self) end
    end
end
```

#### Template inheritance (Blade/Twig style)

Child templates can extend a parent layout, defining blocks that the parent
renders via `yield()`:

```lua
-- Child: examples/hello/views/Window.etlua
<% extends("views/AppWindow.etlua", { title = "Hello", width = 480 }) %>
<% block("content", [[
    <VStack padding="24">
        <Label text="Hello from Lua" size="24" />
    </VStack>
]]) %>

-- Parent: views/AppWindow.etlua
<Window title="<%= title %>" width="<%= width %>">
    <%= yield("content") %>
</Window>
```

The framework resolves relative paths from the child template's directory.

#### Partials

Include reusable sub-templates with `partial()`:

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

#### View description format (`lua/ui/viewdesc.lua`)

For future diffing and patching, `viewdesc` compiles templates to plain-table
descriptions instead of live native views:

```lua
local viewdesc = require("ui.viewdesc")
local desc = viewdesc.fromFile("views/Window.etlua", data)
local newDesc = viewdesc.fromFile("views/Window.etlua", newData)
local patches = viewdesc.diff(desc, newDesc)
viewdesc.apply(liveView, patches)
```

This enables efficient updates: only changed views are recreated, similar to
React's virtual DOM diffing.

#### XML-first rule

All views in an example app are expressed as XML templates. Controllers must
not call `ns.VStack`, `ns.HStack`, `ns.List`, or any other view constructor
directly. The only `ns.*` calls allowed in a controller are `ns.Window` (one,
at the top level), property mutations on existing views, and layout helpers
(`view:layout()`, `view:clearContainer()`, etc.).

---

## IDE layout (`examples/ide`)

```
ns.Window
└── NSSplitViewController
    ├── NSSplitViewItem.sidebar  → OutlineView (source-list folder tree)
    └── NSSplitViewItem.content  → TextEditor (editable file content)
```

---

## --preview CLI mode

```
./lua-objc --preview [--width=N] [--height=N] [--out=path.png] file.lua
```

1. `canvas_state_create()` — fresh isolated Lua state
2. Script is wrapped: `ns.Window → ns.VStack`
3. Returned `NSView` is framed and laid out
4. `offscreen_render()` wraps the view in a borderless offscreen `NSWindow`, calls `cacheDisplayInRect:toBitmapImageRep:`, writes PNG
5. No `[NSApp run]` — process exits after write

This matches Xcode's static preview fast path: AppKit drawing stack initialises (via `[NSApplication sharedApplication]`) but no event loop spins.

---

## File watcher

`bridge._watchFile(path, callback)` uses `FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer`. One stream per path, stored in `gFileWatchers` (global `NSMutableDictionary`). Callbacks fire on the main queue. Passing `nil` as callback cancels the watcher.

---

## Key design constraints

- **One AppKit runtime image**: all AppKit bridge and host state lives in
  `AppKit.dylib`; `lua-objc` itself is only a loader.
- **Embedded public modules**: framework Lua helpers remain editable source,
  but ship inside native `luaopen_*` modules rather than loose runtime files.
- **No subclassing for layout**: layout metadata is attached via associated objects, keeping native view classes unmodified.
- **Isolated canvas evals**: each preview run gets a clean Lua state; no global pollution between runs.
- **ARC-owned state lifetime**: `lua_State` teardown is tied to `LuaStateOwner` refcount; async callbacks resolve the owner via `lua_getextraspace` (inherited by coroutines), never by raw pointer lookup.
- **No AutoLayout**: the custom flex engine replaces AppKit's AutoLayout entirely for bridge-created views.
