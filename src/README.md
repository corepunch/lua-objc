# Native source map

`main.m` is the AppKit translation-unit root; `uikit/bridge.m` is the UIKit
translation-unit root. Each owns its platform keys and module registration,
then includes focused implementation fragments. This preserves static-symbol
and ARC ownership while letting readers open only the subsystem they need.

| File | Responsibility | Useful search terms |
|---|---|---|
| `main.m` | imports, constants, includes, Lua module table, host entry point | `bridge_lib`, `lua_objc_main` |
| `appkit/table_data_source.m` | reusable table rows and cells | `LuaTableViewSource`, `LuaTableCellView` |
| `appkit/outline_data_source.m` | hierarchical outline rows and cells | `LuaOutlineViewSource`, `LuaOutlineCellView` |
| `appkit/action_button.m` | callback target, lookup tables, compound action button | `LuaButtonTarget`, `LuaActionButton` |
| `appkit/toolbar.m` | native toolbar item construction | `LuaToolbarDelegate` |
| `appkit/runtime.m` | userdata conversion, KVC, metatables, shared helpers | `push_objc`, `nsview_index` |
| `appkit/views.m` | windows, stacks, splits, images, basic view creation | `bridge_window`, `LuaImageViewerView` |
| `appkit/layout.m` | measurement, flex distribution, frame placement | `measure_view`, `layout_recursive` |
| `appkit/controls.m` | buttons, tables, loading, refresh, selection | `bridge_button`, `bridge_tableview` |
| `appkit/outline.m` | outline view and directory tree conversion | `bridge_outlineview`, `bridge_list_directory` |
| `appkit/editor.m` | show/KVC helpers, text editor, symbol controls | `bridge_text_view`, `bridge_symbol_toggle` |
| `appkit/platform.m` | PNG rendering, file watching, open panels | `offscreen_render`, `bridge_watch_file` |
| `appkit/canvas_eval.m` | isolated preview states and canvas mounting | `canvas_state_create`, `bridge_eval` |
| `appkit/syntax_highlight.m` | editor syntax storage | `SyntaxTextStorage` |
| `uikit/bridge.m` | UIKit keys, fragment includes, registration | `luaopen_UIKitNative`, `bridge_lib` |
| `uikit/layout.m` | UIKit stack measurement and placement | `layout_recursive` |
| `uikit/views.m` | UIKit windows, stacks, images, and layout entry points | `bridge_window`, `bridge_image` |
| `uikit/controls.m` | UIKit buttons and switches | `bridge_button`, `bridge_toggle` |
| `uikit/table_data_source.m` | reusable UITableView rows | `LuaTableViewSource` |
| `uikit/tables.m` | UITableView construction and mutation | `bridge_tableview` |
| `uikit/runtime.m` / `uikit/metatable.m` | userdata conversion and property access | `push_objc`, `nsview_index` |
| `uikit/platform.m` | window display and generic UIKit invocation | `bridge_show`, `bridge_perform` |
| `shared/lua_async.m` | state owners, timers, HTTP, and JSON for both platforms | `LuaStateOwner`, `bridge_http_get` |
| `shared/lua_error.m` | protected callback error reporting | `report_lua_error` |

The fragments are not independent libraries and must not be added as separate
linker inputs. The Makefile uses `find` over `src/appkit/` + `src/shared/` for
AppKit and `src/uikit/` + `src/shared/` for UIKit. Adding or changing a nested
fragment therefore rebuilds the appropriate runtime without maintaining file
lists.

To add a bridge function:

1. Put it in the fragment matching its native responsibility.
2. Add a forward declaration only when an earlier fragment needs it.
3. Register it in the platform root's `bridge_lib`.
4. Wrap it in the corresponding `lua/embedded/*.lua` when it is public API.
5. Add a headless assertion in `tests/bridge.test.lua` and visual QA when UI is
   affected.
