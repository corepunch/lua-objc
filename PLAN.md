# PLAN: Offscreen Canvas Preview (Xcode-style)

## Goal

Render a Lua-defined view hierarchy into an **offscreen bitmap** and stream it
back to a host process — exactly as Xcode Previews does.  No visible NSWindow,
no GUI launching.  The result is a PNG (or a stream of PNGs for live/animated
previews) that a VS Code extension, a CI step, or a web UI can consume.

---

## How Xcode Previews Actually Works (reverse-engineered)

Apple does not document Preview internals. This is the best public picture:

### Shared infrastructure (macOS + iOS)
- Both use the **CoreSimulator runtime** headlessly — no `Simulator.app` GUI window.
- Xcode compiles changed source into a `.dylib` and injects it into a private
  `PreviewsHost` XPC service process that runs on top of the simulator runtime
  for the target platform.
- `PreviewsHost` renders the view **offscreen** into a bitmap buffer and
  streams frames back to Xcode's Canvas panel over a private XPC protocol.
  The protocol is completely undocumented.
- **Static preview**: one render, frame sent, done.
  **Live Preview**: process stays alive; Canvas forwards pointer events as
  synthetic input events (XPC → PreviewsHost → injected into the runtime).

### macOS canvas
- The rendered content is the **content view only** — no real `NSWindow`
  chrome.  The optional window frame visible in Canvas is a **decorative
  overlay image** composited around the bitmap in Xcode's UI, not part of the
  render.

### iOS / iPhone canvas
- Identical pipeline but runs on the **iOS simulator runtime**.
- The iPhone device bezel shown in Canvas is a **pre-baked bezel image**
  composited around the rendered content bitmap — not a real simulator screen.
- Touch/gesture forwarding in Live Preview: Canvas captures pointer events,
  transforms coordinates into the preview's space, and injects them as
  synthetic `UITouch`-equivalent events via XPC into `PreviewsHost`.

### What this means for lua-objc
- We don't have a UIKit/iOS runtime — no simulator needed.
- Our `ns.Window` intercept (→ `ns.VStack`) already matches Xcode's macOS
  approach: content only, no chrome.
- A "device frame" for any future mobile-style preview would be pure image
  compositing: draw a bezel PNG around the rendered bitmap.  No runtime
  changes required.

---

## Background / What We Already Have

| Thing | File | Notes |
|---|---|---|
| `bridge_eval(code, canvas=true)` | `src/canvas_eval.m` | Runs Lua in a fresh isolated `lua_State`; intercepts `ns.Window` → `ns.VStack`; returns an `NSView` |
| `IDEKit._evalIntoCanvas` | `lua/embedded/IDEKit.lua` | Clears a live canvas view and re-adds the result |
| `layout_recursive` | `src/main.m` | Full flex layout pass |
| `bridge._layout` | `src/main.m` | Lua-callable layout trigger |

The missing piece is: take the `NSView` tree that `bridge_eval` already
produces and render it to pixels **without showing a window**.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  preview-host  (new slim binary, or new --preview flag)      │
│                                                              │
│  stdin/args → Lua file path + size hint                      │
│                                                              │
│  1. canvas_state_create()  – isolated Lua state              │
│  2. bridge_eval(code, true) – get NSView tree                │
│  3. layout_recursive(view, width)                            │
│  4. offscreen_render(view, size) → NSBitmapImageRep          │
│  5. write PNG to stdout (or named pipe / temp file)          │
└──────────────────────────────────────────────────────────────┘
```

The host process **never calls `[NSApp run]`**.  It uses
`NSApplication.sharedApplication` (needed for AppKit to work) but exits
immediately after writing the PNG.

---

## Step-by-Step Plan

### Step 1 — Offscreen render function (`src/main.m`)

Add one C function:

```c
static NSData *offscreen_render(NSView *view, CGFloat width, CGFloat height);
```

Implementation:
1. Create an `NSBitmapImageRep` matching the desired pixel dimensions (use
   `[[NSScreen mainScreen] backingScaleFactor]` for HiDPI, fall back to 2.0).
2. Create an `NSGraphicsContext` from the bitmap rep.
3. `[NSGraphicsContext saveGraphicsState]` → set current → call
   `[view drawRect:view.bounds]` (after setting `view.frame` to the target
   rect) → restore.
4. Return `[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]`.

**Subtle point**: `drawRect:` only works for leaf views.  For our composite
stacks (plain `NSView` containers) we need `[view displayRectIgnoringOpacity:…
inContext:]`.  Use `-[NSView cacheDisplayInRect:toBitmapImageRep:]` — this is
the documented one-liner that recursively rasterises a view hierarchy into a
bitmap.

### Step 2 — Bridge exposure (`bridge._renderToPNG`)

```c
static int bridge_render_to_png(lua_State *L) {
    NSView *view   = check_view(L, 1);
    CGFloat width  = luaL_optnumber(L, 2, 400);
    CGFloat height = luaL_optnumber(L, 3, 300);
    view.frame = NSMakeRect(0, 0, width, height);
    layout_recursive(view, width);
    NSData *png = offscreen_render(view, width, height);
    if (!png) { lua_pushnil(L); return 1; }
    lua_pushlstring(L, png.bytes, png.length);
    return 1;
}
```

Register it as `bridge._renderToPNG` in `bridge_lib[]`.

### Step 3 — `--preview` CLI mode in `main()`

```
./lua-objc --preview [--width=N] [--height=N] [--out=path.png] file.lua
```

Flow inside `main()`:
1. Detect `--preview` flag.
2. Skip `[NSApp run]`.
3. Call `luaL_dofile` → the script returns a view (via the canvas intercept).
4. Call `offscreen_render(view, w, h)`.
5. Write PNG bytes to the output path (or stdout if `--out=-`).
6. Exit 0.

Because we call `[NSApplication sharedApplication]` but not `-run`, AppKit
initialises its drawing stack (CoreGraphics contexts work) but no event loop
spins.  This is the same trick Xcode Previews uses for its static-render fast
path.

### Step 4 — `IDEKit.renderCanvas` Lua helper

```lua
-- lua/embedded/IDEKit.lua  (embedded in IDEKit.dylib)
function IDEKit.renderCanvas(code, width, height)
    local result, err = bridge._eval(code, true)
    if err then return nil, err end
    local png = bridge._renderToPNG(result, width or 400, height or 300)
    return png, nil
end
```

This lets any Lua script (or a future HTTP server) call one function and get a
PNG back.

### Step 5 — IDE open-file watcher (`IDEKit` + `bridge._watchFile`)

The IDE needs to know when the file currently loaded in the editor changes on
disk.  Two parts:

**6a. Bridge primitive** (`src/main.m`):

```c
// bridge._watchFile(path, callback)
// Calls callback(path) when the file changes. Replaces any previous watcher
// on the same path. Pass nil callback to cancel.
static int bridge_watch_file(lua_State *L);
```

Internally uses the same `FSEventStream` mechanism as Step 5.  One stream per
watched path, stored in a global `NSMutableDictionary<NSString*, id>` (path →
stream wrapper).  Callback fires on the main queue.

**6b. `IDEKit.Editor` tracks `currentFile`** (`lua/embedded/IDEKit.lua`):

```lua
function IDEKit.Editor(props)
    -- ...existing setup...
    local currentFile = nil

    local function watchCurrentFile(path)
        if currentFile then
            bridge._watchFile(currentFile, nil)  -- cancel old watcher
        end
        currentFile = path
        if path then
            bridge._watchFile(path, function()
                local f = io.open(path, "r")
                if not f then return end
                local content = f:read("*a"); f:close()
                bridge._textViewSetText(editor, content)
                IDEKit._evalIntoCanvas(canvas, content)
            end)
        end
    end

    -- expose so the host script (ide.lua) can call it after openInEditor
    editor.watchFile = watchCurrentFile
    return editor
end
```

**6c. `ide.lua` calls `watchCurrentFile`** after loading a file:

```lua
local function openInEditor(filename)
    local path = examplesDir .. "/" .. filename
    local f = io.open(path, "r"); if not f then return end
    local content = f:read("*a"); f:close()
    bridge._textViewSetText(editor, content)
    ide._evalIntoCanvas(canvas, content)
    editor.watchFile(path)   -- start watching the new file
end
```

---

## Key Technical Notes

### Why `cacheDisplayInRect:toBitmapImageRep:` ?

It is the only AppKit API that correctly handles:
- Layer-backed views
- Subview clipping
- System-appearance (light/dark) on the bitmap rep

`lockFocus` / `unlockFocus` is deprecated and broken for layer-backed views
on macOS 14+.

### AppKit without a window

`NSView.drawRect` requires the view to have a valid `window` or it silently
no-ops on some macOS versions.  Work around: wrap the target view in a
temporary off-screen `NSWindow` with `NSWindowStyleMaskBorderless` and
`NSBackingStoreNonretained`, call `orderBack:nil` (makes it "exist" but
invisible), render, then close it.  This is documented in Apple's own
offscreen-rendering tech notes.

### Isolated Lua state

`canvas_state_create()` already exists and is correct — no changes needed.
`bridge_render_to_png` runs on the view that the isolated state produced, after
`lua_close(C)` was called.  Because `CFBridgingRetain` keeps the view alive
past `lua_close`, this is safe.

---

## File Changes Summary

| File | Change |
|---|---|
| `src/main.m` | Add `offscreen_render()`, `bridge_render_to_png()`, `--preview` branch in `main()`, `bridge_watch_file()`, register `_renderToPNG` + `_watchFile` |
| `lua/embedded/IDEKit.lua` | Add `IDEKit.renderCanvas()`, `editor.watchFile` tracking in `IDEKit.Editor` |
| `examples/ide.lua` | Call `editor.watchFile(path)` inside `openInEditor` |
| `examples/preview.lua` | Minimal example: `return ns.VStack { ... }` usable as `./lua-objc --preview examples/preview.lua` |

No new files needed in `src/` — consistent with the current single-translation-unit style.

---

## Out of Scope (for now)

- XPC transport / streaming frames (that is the phase-3 "true Xcode Preview" path)
- dylib injection — not applicable to a Lua runtime (re-eval is free)
- PNG → WebP or MJPEG for animated previews
