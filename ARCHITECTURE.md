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
build/IDEKit.dylib          luaopen_IDEKit
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
require("IDEKit")  -- luaopen_IDEKit in IDEKit.dylib
require("UIKit")   -- luaopen_UIKit in UIKit.dylib, inside an iOS host
```

The build converts each `lua/embedded/*.lua` source into a byte-array header.
`luaopen_*` evaluates that embedded chunk and returns its complete public API
table. There is no loose `AppKit.lua`, `IDEKit.lua`, or `UIKit.lua` module that
can silently bypass native loading.

`AppKitNative` and `UIKitNative` are private implementation modules. The
legacy `bridge` name remains temporarily available for existing application
code, but public framework layers do not depend on it.

`make all` builds AppKit and IDEKit everywhere and also builds UIKit when an
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

## Layer 3 — IDEKit.dylib

Xcode-aligned IDE workspace components. The dylib embeds
`lua/embedded/IDEKit.lua`; each component maps to a named Xcode private class.

### Component map

| IDEKit component | Xcode equivalent | Description |
|---|---|---|
| `IDEKit.ControlBar` | `DVTControlBar` | 28px header strip with title + leading/trailing slots, terminated by a 1px separator |
| `IDEKit.NavigatorArea` | `NSView_ControlledBy_IDENavigatorArea` | Persistent semantic sidebar with one source-list file tree |
| `IDEKit.EditorArea` | `DVTSplitView_ControlledBy_IDEEditorArea` | Document pane: inner `NSSplitView` of source editor + preview |
| `IDEKit.PreviewArea` | macOS preview canvas panel | Document-local ControlBar + inline canvas |
| Native workspace | `NSSplitViewController` | Semantic sidebar item + content item with safe-area integration |
| `IDEKit.Canvas` | `IDEEditorContextClipView` content area | `ns.VStack` that receives eval results |
| Native document tabs | `NSWindow` tab group | Public `addTabbedWindow:ordered:`; AppKit owns the tab bar and tab buttons |
| `IDEKit.Editor` | `SourceEditorScrollView` | `NSTextView` in a scroll view; debounces eval on change |

### Canvas preview architecture

Matches Xcode's macOS preview model exactly:

```
Xcode macOS preview          lua-objc equivalent
─────────────────────────    ──────────────────────────────────
SwiftUI.AppKitApplication    main lua_State
NSPreviewTargetWindow        IDEKit.Canvas (ns.VStack host)
NSHostingView → content      bridge._eval(code, true) → NSView
no window chrome             ns.Window intercepted → ns.VStack
```

`IDEKit._evalIntoCanvas(canvas, code)` runs each eval in an isolated `lua_State` via `bridge._eval(code, true)`, clears the canvas, then inserts the returned view. Live updates are debounced 300ms via `bridge._timerAfter`.

### Editor wrapper

`IDEKit.Editor` returns a plain Lua **table** (not a raw userdata) with:

- `._view` — the underlying `NSScrollView` userdata, passed directly to bridge functions
- `.watchFile(path)` — installs/replaces an `FSEventStream` watcher; reloads and re-evals on disk change

The actual editor implementation now lives in `lua/Plugins/TextEditor.lua` and
is registered through `lua/PluginKit.lua`. `IDEKit.Editor` is a compatibility
wrapper that keeps the existing IDE canvas behavior while the editor-specific
logic stays isolated in a plugin module.

### Plugin layer

The first plugin layer is intentionally small:

- `PluginKit.register(spec)` stores a plugin manifest and factory.
- `PluginKit.use(id, props)` constructs a plugin instance.
- `PluginKit.resolveByFile(path, kind)` and `PluginKit.resolveByCommand(name, kind)` perform lazy selection from activation rules.
- `Plugins.TextEditor` is the first registered plugin and owns the native
  `NSTextView`, change callback, file watching, and text accessors.

This gives us a practical boundary for editor-specific features. A future slide
editor, image editor, or chat agent panel can ship as its own plugin module
without pulling its internals into the shared AppKit layer. That keeps the
surface area smaller for both humans and the agent, which is the main reason to
introduce the registry before the plugin count grows.

The IDE example now lives under `examples/IDEKit/` with `init.lua` as the real
entrypoint and `examples/ide.lua` kept as a compatibility shim. That gives the
workspace room to grow into a small plugin playground without cluttering the
top-level examples directory.

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

The IDE example is now organized like a small application bundle:

```text
examples/IDEKit/
├── init.lua       # module entrypoint (requires("examples.IDEKit"))
├── app.lua        # app lifecycle + routing
├── workspace.lua  # editor workspace window (IDEWorkspace)
├── welcome.lua    # startup / recent-project screen
├── Canvas.lua     # preview canvas
├── Editor.lua     # editor wrapper
├── EditorArea.lua
├── NavigatorArea.lua
├── PreviewArea.lua
├── ControlBar.lua
├── SearchView.lua
├── FindInFiles.lua
├── Recent.lua
├── plugins/       # editor surfaces (self-registering)
└── state/         # persistence and recents
```

That structure keeps app boot, scene selection, and UI composition separate
without introducing a second runtime or any non-Lua app scaffolding.

The next split is already in place in the filesystem:

```text
examples/IDEKit/
├── plugins/       # editor surfaces (files that call App.registerPlugin)
└── state/         # persistence and recents
```

Those subdirectories keep the app shell readable as the number of surfaces
grows, while preserving the same single-Lua-source workflow.

This table wrapper avoids triggering KVC on `NSScrollView` when storing Lua-side methods.

---

## IDE layout (`examples/IDEKit`)

```
ns.Window
└── NSSplitViewController
    ├── NSSplitViewItem.sidebar
    │   └── IDEKit.NavigatorArea
    │       └── ns.OutlineView  (source-list file tree)
    ├── NSSplitViewItem.contentList
    │   └── NSTextView  (source editor)
    └── NSSplitViewItem.content
        └── IDEKit.Canvas  (inline preview)
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
