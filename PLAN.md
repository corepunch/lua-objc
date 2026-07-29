# Native AppKit surface

## Decision

AppKit properties come from Objective-C, not bridge metadata.

- `__index` reads with `valueForKey:`.
- `__newindex` writes with `setValue:forKey:`.
- Exported subclasses add semantic Lua names such as `text`.
- The `NSView` base extension owns framework layout properties.
- `Size`, `Point`, and `Rect` remain explicit value userdata.
- Specialized operations that are not properties remain native methods.

The AppKit/UIKit XML schemas and their generated bridge files are removed.
Each platform now owns ordinary native constructors, bindings, and KVC
accessors.

## Public naming

- `NSSize` → `ns.Size`
- `NSPoint` → `ns.Point`
- `NSRect` → `ns.Rect`
- No `NSSize`/`NSPoint`/`NSRect` compatibility exports
- Getter/setter pairs become assignments where they represent state

Examples:

```lua
label.text = "Hello"
field.editable = true
window.size = ns.Size(800, 600)
editor.wrapMode = true
```

## Native ownership

- `LuaTextField` exposes `text`, `placeholder`, and `lineLimit`.
- `LuaTextScrollView` exposes `text`, `language`, and `wrapMode`.
- `LuaNativeTextView` exposes `text`.
- `LuaWindow` is the exported window class.
- AppKit-native names such as `editable`, `hidden`, `toolTip`, and `rowHeight`
  require no declaration because KVC discovers them directly.

## Verification

- Headless tests cover property read/write round trips and unrelated-state
  preservation.
- Schema tests ensure both platform XML files are absent and native classes own
  semantic/layout properties.
- Build and test with `make test`.

---

# Cleanup plan: reduce boilerplate, close SwiftUI gap

Outcome of the audit in July 2026. Two tracks run independently.

---

## Track A — src/appkit binding layer

### A1. Shared callback-ref macro

**Problem:** The 5-line "extract optional Lua callback" block appears 9+ times
across `constructors.m`, `editor.m`, `tabview.m`, `controls.m`, `views.m`.

**Fix:** Add a `LUA_OPT_CALLBACK_REF(L, idx, ref_var)` macro in a shared
header (e.g., `lua_bridge_utils.h`). Replace every occurrence.

Files touched: `constructors.m`, `editor.m`, `tabview.m`, `controls.m`,
`views.m`, `outline.m`.

---

### A2. Shared column-setup and column-width helpers

**Problem:**
- `bridge_tableview` (`controls.m`) and `bridge_outlineview` (`outline.m`)
  share ~65 lines of column-construction code, copy-pasted.
- `LuaTableViewSource.updateTableFrame` and
  `LuaOutlineViewSource.updateTableFrame` share ~70 lines of flex
  column-width distribution, copy-pasted.

**Fix:**
- Extract `build_table_columns(lua_State *L, NSTableView *tv, int tableIdx)`
  as a static C helper in a new `table_utils.m` (or inline in `controls.m`
  and `#include`d by `outline.m`).
- Extract `distribute_column_widths(NSTableView *tv, NSScrollView *sv)` as a
  shared C function that both data-source classes call.

Files touched: `controls.m`, `outline.m`, `table_data_source.m`,
`outline_data_source.m`.

---

### A3. Shared cell-construction helper

**Problem:** `tableView:viewForTableColumn:row:` and
`outlineView:viewForTableColumn:item:` duplicate ~50 lines of
`LuaTableCellView` construction and reuse.

**Fix:** Static C function
`make_or_reuse_cell(NSTableView *tv, NSTableColumn *col, NSString *prefix)`
returning a configured `LuaTableCellView *`.

Files touched: `table_data_source.m`, `outline_data_source.m`.

---

### A4. Shared row-data push helper

**Problem:** The loop that builds a Lua table from a row `NSDictionary` is
copied in three places: `tableViewSelectionDidChange:`,
`activateSelectedRow:`, `outlineViewSelectionDidChange:`.

**Fix:** Static `push_row_data_table(lua_State *L, NSDictionary *rowData)`
used by all three.

Files touched: `table_data_source.m`, `outline_data_source.m`.

---

### A5. Merge bridge_pick_folder / bridge_pick_file

**Problem:** Two 17-line functions differing only in two `BOOL` values.

**Fix:** Single `bridge_pick_panel(lua_State *L, BOOL isFolder)` helper;
the two exported functions become 2-line wrappers.

Files touched: `platform.m`.

---

### A6. Fix gL usage in LuaTabViewDelegate and LuaImageViewerView

**Problem:** `LuaTabViewDelegate.dealloc` (`tabview.m:17-19`) and
`LuaImageViewerView.performDragOperation:` (`views.m:574`) use the global
`gL` instead of a stored `LuaStateOwner`. This is a latent crash if the
canvas Lua state is torn down while either object is still alive.

**Fix:** Add a `LuaStateOwner *_owner` ivar to `LuaTabViewDelegate` and
store/release via it, matching the pattern in `LuaTextFieldDelegate` and
`LuaMenuActionTarget`. Same fix for `LuaImageViewerView`.

Files touched: `tabview.m`, `views.m`.

---

### A7. Standardise style/enum lookups

**Problem:**
- `tabview.m:bridge_tabview` uses raw `strcmp` for the `style` argument.
- `presentation.m:panel_material` uses bare `if` branches.
- Both are inconsistent with `lookupNameValue` used everywhere else.

**Fix:** Replace both with `NameValueEntry` arrays + `lookupNameValue`.

Files touched: `tabview.m`, `presentation.m`.

---

### A8. Dead extraction in bridge_NSWindow_resize

**Problem:** `bindings.m:289-292` extracts `width`, `height`, `anchor`,
marks them `(void)`, then calls an impl that re-reads the stack.

**Fix:** Remove the dead extraction lines; the impl already handles them.

Files touched: `bindings.m`.

---

### A9. structs.m code-gen macro

**Problem:** `structs.m` repeats the same 6-function pattern (check, push,
index, newindex, bridge, register) for each of the 3 structs — ~67 lines
per struct, 200 lines total.

**Fix:** Define a `DEFINE_LUA_STRUCT(TypeName, ...)` macro bundle (parallel
to `LUA_NUMBER_ACCESSORS`) that generates all 6 functions from the struct
name and a field descriptor. Reduces the file to ~40 lines of declarations.

Files touched: `structs.m`.

---

### A10. Break up bridge_set_window_workspace

**Problem:** `views.m:bridge_set_window_workspace` is 135 lines performing
7 distinct tasks: hosting controller setup, sidebar item creation, split
position clamping, toolbar tracking separator, safe-area constraints, detail
pane wiring, initial layout.

**Fix:** Extract 3-4 named static C helpers. No behaviour change, just
readability. Defer if other A-track items are higher priority.

Files touched: `views.m`.

---

## Track B — examples/IDEKit SwiftUI parity

The binding layer already supports `onSelect`, `onChange`, etc. inside
constructor tables for most views. The examples don't consistently use this.

### B1. Move post-construction wiring inside constructor tables

**Problem:** `NavigatorArea.lua` calls `:setChangeHandler(fn)` and wires
`onRowSelect` imperatively after construction. `Editor.lua` calls
`:setChangeHandler(fn)` on the returned object.

**Target:** All event handlers declared inside the constructor table:

```lua
-- Before
local view, fileTree = NavigatorArea.create(props)
fileTree:onRowSelect(function(row) ... end)

-- After
local view = NavigatorArea.create {
    onSelect = function(row) ... end,
}
```

This matches `ns.TableView { onSelect = fn }` already used in other files.

Files touched: `examples/IDEKit/NavigatorArea.lua`,
`examples/IDEKit/Editor.lua`, any callers in `Workspace.lua`.

---

### B2. Encapsulate PreviewArea internals

**Problem:** `PreviewArea.lua` returns `(area, rebuildToolbar)`. The caller
(`Workspace.lua`) threads `rebuildToolbar` to `evalIntoCanvas` because there
is no way for the preview area to observe canvas output directly.

**Fix:** `PreviewArea` exposes a single `setContent(view)` method. The
`rebuildToolbar` closure becomes internal; the caller never holds it.
`Workspace.lua` calls `previewArea.setContent(result)` instead.

Files touched: `examples/IDEKit/PreviewArea.lua`, `Workspace.lua`.

---

### B3. Introduce a minimal observable/signal primitive

**Problem:** The largest structural gap vs SwiftUI is the absence of reactive
state. `Workspace.lua` debounces with a version counter + manual timer.
`SearchView.lua` chains 5 imperative calls on every query change.

**Fix:** Add `ns.signal(initialValue)` returning `{ value, onChange(fn) }`
in the Lua standard library (pure Lua, no native bridge needed). Example:

```lua
local query = ns.signal("")
query.onChange(function(v) results.rows = search(v) end)
-- binding an input:
ns.TextField { value = query }   -- ns.TextField reads query.value on change
```

This does not require changes to the C layer. Start with a pure-Lua
implementation; later the native text field can call `query:set(newValue)`
directly.

Files touched: `lua/AppKit.lua` (or new `lua/signal.lua`), any consumers
that opt in. Existing files are unaffected until they migrate.

---

### B4. Standardise the action key to `action`

**Problem:** `Welcome.lua` uses `onClick` on action items;
the rest of the codebase uses `action` (e.g., `ns.Button { action = fn }`).

**Fix:** Replace `onClick = ...` with `action = ...` in `Welcome.lua` and
update the `actionButton` helper to read `item.action`.

Files touched: `examples/IDEKit/Welcome.lua`.

---

### B5. Remove index/count leak from ForEach callbacks

**Problem:** `Recent.lua`'s `ForEach` callback receives `(item, index, count)`
so it can skip the trailing divider — a layout concern leaking into data
mapping.

**Fix:** Either (a) wrap rows in `ns.Group { row, ns.Divider() }` and let the
layout engine suppress the last divider via a `:separatedBy(ns.Divider())`
modifier (requires a small addition to the `ns.ForEach` implementation), or
(b) use `ns.List` if that widget handles inter-item separators natively.

Files touched: `examples/IDEKit/Recent.lua`, potentially `lua/AppKit.lua`.

---

## Priority order

| Priority | Item | Effort | Risk |
|---|---|---|---|
| P0 | A6 (gL crash bugs) | Small | Bug fix — do first |
| P1 | A1 (callback macro) | Small | Mechanical, low risk |
| P1 | A8 (dead extraction) | Trivial | Trivial |
| P1 | A7 (enum lookup consistency) | Small | Mechanical |
| P1 | B4 (onClick → action) | Trivial | Trivial |
| P2 | A2 (column-setup dedup) | Medium | Moderate — test table + outline |
| P2 | A3 + A4 (cell + row helpers) | Medium | Moderate |
| P2 | A5 (pick panel merge) | Small | Low |
| P2 | B1 (inline event handlers) | Small | Requires Workspace.lua edits |
| P2 | B2 (PreviewArea encapsulation) | Medium | Moderate |
| P3 | A9 (structs macro) | Medium | No behavior change |
| P3 | A10 (split workspace fn) | Small | No behavior change |
| P3 | B3 (signal primitive) | Medium | New API — additive only |
| P4 | B5 (ForEach separator) | Medium | Requires ns.ForEach change |
