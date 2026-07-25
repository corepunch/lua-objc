# lua-objc Architecture

## Overview

lua-objc is a macOS application that runs Lua scripts and renders native AppKit UIs from them. It consists of three layers:

```
examples/*.lua          Lua scripts (user-facing UI descriptions)
lua/AppKit.lua          High-level SwiftUI-like Lua API
lua/IDEKit.lua          IDE workspace components (Xcode-aligned)
src/main.m              ObjC/C bridge + layout engine
src/canvas_eval.m       Isolated Lua state for canvas preview eval
```

---

## Layer 1 — Bridge (`src/main.m` + `canvas_eval.m`)

The bridge is a single Objective-C/C translation unit that registers a `bridge` Lua module.

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

### Canvas eval (`canvas_eval.m`)

Each canvas preview evaluation runs in a **fresh, isolated `lua_State`** (created by `canvas_state_create()`). This means:

- User code globals do not persist between evals.
- Module cache (`package.loaded`) is reset each run.
- Registry refs from previous evals cannot fire.

Inside the isolated state, `ns.Window` and `ns.Preview` are monkey-patched to return an `ns.VStack` instead of creating a real `NSWindow`. This is the same approach Xcode uses for its macOS preview: render the content view only, no window chrome.

The resulting `NSView` is marshalled back to the main Lua state via `CFBridgingRetain`, which keeps the view alive past `lua_close(C)`.

---

## Async state lifetime (`LuaStateOwner` + `lua_getextraspace`)

Async bridge functions (`_httpGet`, `_timerAfter`, `_textViewOnChange`) schedule ObjC work that completes *after* the calling Lua code returns — sometimes after the `lua_State` that started it would normally be closed. The lifetime rule is:

> A state must die exactly once, on the main thread, when its creator and all in-flight async ops are done with it.

That is a reference count. We spell it with an ObjC object (`LuaStateOwner`) instead of a hand-rolled `_Atomic int` because ARC removes the three classic failure modes:

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

## Layer 2 — AppKit.lua

Provides a SwiftUI-like declarative API over the bridge.

### Key functions

| Lua API | Bridge call | Notes |
|---|---|---|
| `ns.Window { ... }` | `bridge._window(...)` | Creates NSWindow, adds content VStack, triggers layout |
| `ns.VStack { ... }` | `bridge._vstack()` | Vertical flex container |
| `ns.HStack { ... }` | `bridge._hstack()` | Horizontal flex container |
| `ns.HSplit { ... }` | `bridge._hsplit()` | NSSplitView, left-right panes |
| `ns.VSplit { ... }` | `bridge._vsplit()` | NSSplitView, top-bottom panes |
| `ns.Separator()` | `bridge._separator()` | 1px NSBox rule |
| `ns.Text { ... }` | `bridge._create("NSTextField")` | Label with KVC property setting |
| `ns.List { ... }` | `bridge._tableview(...)` | NSTableView in NSScrollView |
| `ns.Spacer()` | `bridge._spacer()` | flexGrow=1 filler |

### Layout props

All container and leaf views accept layout props applied via `applyLayout()`:

```
padding, paddingHorizontal, paddingVertical
spacing, alignment
fixedWidth, fixedHeight
minWidth, minHeight, maxWidth, maxHeight
flexGrow, flexShrink, flexBasis
fillWidth, fillHeight
```

---

## Layer 3 — IDEKit.lua

Xcode-aligned IDE workspace components. Each component maps to a named Xcode private class.

### Component map

| IDEKit component | Xcode equivalent | Description |
|---|---|---|
| `IDEKit.ControlBar` | `DVTControlBar` | 28px header strip with title + leading/trailing slots, terminated by a 1px separator |
| `IDEKit.NavigatorArea` | `NSView_ControlledBy_IDENavigatorArea` | Left sidebar: ControlBar + content |
| `IDEKit.EditorArea` | `DVTSplitView_ControlledBy_IDEEditorArea` | Centre pane: ControlBar + editor content |
| `IDEKit.PreviewArea` | macOS preview canvas panel | Right pane: ControlBar + inline canvas |
| `IDEKit.WorkspaceLayout` | Workspace root `NSSplitView` | `ns.HSplit` of navigator + editor + preview |
| `IDEKit.Canvas` | `IDEEditorContextClipView` content area | `ns.VStack` that receives eval results |
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

This table wrapper avoids triggering KVC on `NSScrollView` when storing Lua-side methods.

---

## IDE layout (`examples/ide.lua`)

```
ns.Window
└── ns.VStack
    └── IDEKit.WorkspaceLayout  (ns.HSplit)
        ├── IDEKit.NavigatorArea  fixedWidth=160
        │   ├── IDEKit.ControlBar  "FILES"
        │   └── ns.List  (file tree)
        ├── IDEKit.EditorArea  flexGrow=1
        │   ├── IDEKit.ControlBar  "EDITOR"
        │   └── NSTextView (editor._view)
        └── IDEKit.PreviewArea  flexGrow=1
            ├── IDEKit.ControlBar  "CANVAS"
            └── IDEKit.Canvas (inline preview)
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

- **Single translation unit**: all C/ObjC code lives in `src/main.m` (with `canvas_eval.m` `#include`d). No separate `.h` files.
- **No subclassing for layout**: layout metadata is attached via associated objects, keeping native view classes unmodified.
- **Isolated canvas evals**: each preview run gets a clean Lua state; no global pollution between runs.
- **ARC-owned state lifetime**: `lua_State` teardown is tied to `LuaStateOwner` refcount; async callbacks resolve the owner via `lua_getextraspace` (inherited by coroutines), never by raw pointer lookup.
- **No AutoLayout**: the custom flex engine replaces AppKit's AutoLayout entirely for bridge-created views.
