# Redesign: testable splits, template data sources, etlua

Target audience: AI agents running lua-objc scripts.
Goal: clear layered architecture, testable without a window, cell templates via etlua.

---

## Phase 1 — Editor panel owns its own split

**Motivation:** The outer `NSSplitViewController` (sidebar / content / detail)
is a window-level concern. The inner editor↔preview split is an editor-panel
concern. Mixing them couples Workspace to layout details it should not own —
exactly the Xcode mistake we want to avoid.

**Changes:**

1. **Remove `detail` from `ns.Window` in Workspace.lua.**
   The window becomes a two-pane layout: sidebar + editor-content.
   `detail` is dropped from `bridge_set_window_workspace`'s third-pane path
   when the caller passes `content` only (this path already exists; just stop
   passing `detail`).

2. **`EditorArea.lua` becomes the canonical editor component.**
   It owns an `ns.HSplit { proportions = {1,1} }` with editor on the left and
   preview on the right. This is already written but unused — activate it.

3. **Workspace passes `EditorArea { ... }` as `content`.**
   `EditorArea` receives `textView` and `previewArea` as props and composes the
   inner split. Workspace never touches split geometry again.

4. **`EditorArea` exposes a toggle: `editor:togglePreview()`.**
   Toolbar "Show Preview" button calls this; Workspace is not involved.

**Files:** `examples/IDEKit/EditorArea.lua`, `examples/IDEKit/Workspace.lua`,
`examples/IDEKit/PreviewArea.lua`.

**Test:** headless canvas eval still works; `--preview` CLI mode is unaffected
(it never uses `ns.Window`).

---

## Phase 2 — Embed etlua and wire cell templates

**Motivation:** `TableView` and `OutlineView` data sources currently accept row
dictionaries and render them with a hardcoded cell layout. AI agents need to
supply a template string that controls how each cell looks — without writing
native code.

**Changes:**

1. **Embed etlua verbatim.**
   Copy `etlua.lua` into `lua/vendor/etlua.lua`. No wrapper, no modification.
   Add it to the embedded-lua bundle (Makefile target that compiles `.lua` →
   byte array). Register as `"etlua"` so `require("etlua")` works from any
   Lua script.

2. **`ns.TableView { cellTemplate = "..." }`.**
   The native `LuaTableViewSource` reads an optional `cell_template` string
   from the constructor table. When present, for each row it calls a Lua helper:

   ```lua
   -- lua/template_cell.lua (new, ~15 lines)
   local etlua = require("etlua")
   return function(template, rowData)
       local src = etlua.render(template, rowData)
       local fn = load("local ns = require('AppKit'); return " .. src)
       return fn()
   end
   ```

   The returned view replaces the default `LuaTableCellView`. The helper is
   cached on first call; `etlua.compile` pre-compiles the template string once.

3. **Same for `ns.OutlineView { cellTemplate = "..." }`.**
   Same mechanism, same helper. The native data-source delegates both to the
   shared Lua helper — no C duplication.

4. **Fallback:** when `cellTemplate` is absent, existing hardcoded cell layout
   is used unchanged. No breaking change.

**Files:** `lua/vendor/etlua.lua` (new), `lua/template_cell.lua` (new),
`src/appkit/table_data_source.m`, `src/appkit/outline_data_source.m`,
`Makefile`.

**Test:** a new `examples/template_table.lua` that renders a three-column
table with a `cellTemplate` string — runnable headlessly via `--preview`.

---

## Phase 3 — PreviewArea encapsulation (B2 from old plan)

**Motivation:** `Workspace.lua` currently holds a `rebuildToolbar` closure that
PreviewArea leaked to it. After Phase 1, the editor panel owns PreviewArea, so
this becomes an internal detail.

**Changes:**

1. **`PreviewArea` exposes `setContent(view)` only.**
   The returned value from `PreviewArea.show` is an object with a single method.
   `rebuildToolbar` is internal.

2. **`Canvas.evalIntoCanvas` calls `previewArea:setContent(result)`.**
   The `rebuildToolbar` parameter is removed from `evalIntoCanvas`.

3. **`EditorArea` wires canvas → preview internally.**
   Workspace passes `onEval = function(result) previewArea:setContent(result) end`
   to EditorArea, or EditorArea owns both and wires them directly.

**Files:** `examples/IDEKit/PreviewArea.lua`, `examples/IDEKit/Canvas.lua`,
`examples/IDEKit/EditorArea.lua`, `examples/IDEKit/Workspace.lua`.

---

## Phase 4 — Crash fix and mechanical cleanup (from old A-track)

These are carried forward from the previous plan. Do them on this branch since
they are low-risk and unblock further refactor.

| Item | File | Notes |
|------|------|-------|
| A6: fix `gL` in `LuaTabViewDelegate` + `LuaImageViewerView` | `tabview.m`, `views.m` | P0 crash fix |
| A1: `LUA_OPT_CALLBACK_REF` macro | shared header | already partially done |
| A8: remove dead extraction in `bindings.m:289–292` | `bindings.m` | trivial |
| A7: replace `strcmp` style lookups with `lookupNameValue` | `tabview.m`, `presentation.m` | mechanical |
| B4: `onClick` → `action` in `Welcome.lua` | `Welcome.lua` | trivial |

---

## Phase 5 — Signal primitive (B3 from old plan)

**Motivation:** Workspace.lua's debounce counter and SearchView's imperative
update chain both want a lightweight reactive value. Pure Lua, no C changes.

**Changes:**

1. **`ns.signal(initialValue)` in `lua/AppKit.lua`.**

   ```lua
   function AppKit.signal(initial)
       local listeners = {}
       local s = { value = initial }
       function s:set(v)
           self.value = v
           for _, fn in ipairs(listeners) do fn(v) end
       end
       function s:onChange(fn) listeners[#listeners+1] = fn end
       return s
   end
   ```

2. **Opt-in migration.** `Workspace.lua`'s debounce timer, `SearchView.lua`'s
   query chain. Existing files are not touched until they migrate.

**Files:** `lua/embedded/AppKit.lua`, `examples/IDEKit/Workspace.lua` (opt-in),
`examples/IDEKit/SearchView.lua` (opt-in).

---

## Phase 6 — A2/A3/A4 native dedup (low urgency)

Carry forward from old plan when all Lua-side phases are stable.

- A2: shared column-setup helper (`table_utils.m`)
- A3: `make_or_reuse_cell` helper
- A4: `push_row_data_table` helper
- A5: merge `bridge_pick_folder`/`bridge_pick_file`
- A9: `DEFINE_LUA_STRUCT` macro for `structs.m`
- A10: break up `bridge_set_window_workspace`
- B1: inline event handlers in `NavigatorArea.lua`
- B5: `ForEach` separator leak

---

## Invariants to preserve across all phases

- `ns.VStack { padding=N, child1, child2 }` syntax: **no change**. The
  mixed-key table trick works perfectly and is the public API surface.
- `--preview` CLI mode: headless canvas eval must work at every commit.
- `make test` must pass at every phase boundary.
- No SwiftUI dependency is introduced. All layout is the existing custom flex
  engine.
