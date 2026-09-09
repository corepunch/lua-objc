# Native source map

`main.m` is the AppKit translation-unit root; `uikit/bridge.m` is the UIKit
translation-unit root. Each owns its platform keys and module registration,
then includes focused implementation fragments. This shares static symbols
within each platform while letting readers open only the subsystem they need.
Object lifetime comes from retains, registry references, and explicit state
ownership, not from the directory or translation unit containing a class.
See [object and state ownership](../ARCHITECTURE.md#object-and-state-ownership).

| File | Responsibility | Useful search terms |
|---|---|---|
| `main.m` | imports, constants, includes, Lua module table, host entry point | `bridge_lib`, `lua_objc_main` |
| `appkit/table_data_source.m` | reusable table rows and cells | `LuaTableViewSource`, `LuaTableCellView` |
| `appkit/outline_data_source.m` | hierarchical outline rows and cells | `LuaOutlineViewSource`, `LuaOutlineCellView` |
| `appkit/action_button.m` | callback target, lookup tables, compound action button | `LuaButtonTarget`, `LuaActionButton` |
| `appkit/toolbar.m` | native toolbar item construction | `LuaToolbarDelegate` |
| `appkit/runtime.m` | userdata conversion, KVC, metatables, shared helpers | `push_objc`, `nsview_index` |
| `appkit/presentation.m` | generic adaptive panels, focus, and menu items | `LuaPanel`, `bridge_present_panel` |
| `appkit/text_field.m` / `uikit/text_field.m` | native editing events and semantic command routing | `LuaTextFieldDelegate` |
| `appkit/navigation.m` / `uikit/navigation.m` | native page history and navigation stacks | `LuaPageController`, `LuaNavigationController` |
| `appkit/views.m` | windows, stacks, splits, images, basic view creation | `bridge_window`, `LuaImageViewerView` |
| `appkit/layout.m` | measurement, flex distribution, frame placement | `measure_view`, `layout_recursive` |
| `appkit/controls.m` | buttons, tables, loading, refresh, selection | `bridge_button`, `bridge_tableview` |
| `appkit/outline.m` | outline view and directory tree conversion | `bridge_outlineview`, `bridge_list_directory` |
| `appkit/editor.m` | show/KVC helpers, text editor, symbol controls | `bridge_text_view`, `bridge_symbol_toggle` |
| `appkit/platform.m` | PNG rendering, file watching, open panels | `offscreen_render`, `bridge_watch_file` |
| `appkit/syntax_highlight.m` | editor syntax storage | `SyntaxTextStorage` |
| `uikit/bridge.m` | UIKit keys, fragment includes, registration | `luaopen_UIKitNative`, `bridge_lib` |
| `uikit/constructors.m` | UIKit native stack and leaf-control constructors | `bridge_UIKitControls_*` |
| `uikit/layout.m` | UIKit stack measurement and placement | `layout_recursive` |
| `uikit/views.m` | UIKit windows, stacks, images, and layout entry points | `bridge_window`, `bridge_image` |
| `uikit/hosting.m` | scene installer and `LuaHostingController` | `bridge_install_scene` |
| `uikit/controls.m` | UIKit buttons and switches | `bridge_button`, `bridge_toggle` |
| `uikit/table_data_source.m` | reusable UITableView rows | `LuaTableViewSource` |
| `uikit/tables.m` | UITableView construction and mutation | `bridge_tableview` |
| `uikit/runtime.m` / `uikit/metatable.m` | userdata conversion and property access | `push_objc`, `nsview_index` |
| `uikit/platform.m` | window display and native values | `bridge_show`, `bridge_font` |
| `shared/lua_bridge_support.m` | userdata retain/release, Foundation conversion, shared boundary helpers | `ObjCRef`, `push_objc`, `gc_objc`, `lua_to_objc_value` |
| `shared/lua_async.m` | state owners, timers, HTTP, and JSON for both platforms | `LuaStateOwner`, `bridge_http_get` |
| `shared/lua_error.m` | protected callback error reporting | `report_lua_error` |

The fragments are not independent libraries and must not be added as separate
linker inputs. The Makefile uses `find` over `src/appkit/` + `src/shared/` for
AppKit and `src/uikit/` + `src/shared/` for UIKit. Adding or changing a nested
fragment therefore rebuilds the appropriate runtime without maintaining file
lists.

Dependency discovery does not include a new file into the compiler input.
Add the corresponding `#include` in the owning root (or owning fragment), in
declaration order. `appkit/bindings.m` is included in multiple macro-controlled
passes; keep that ordering intact. If adding headers, also add their rebuild
dependencies: the current fragment discovery covers `.m` files only.

## Folder and dependency boundaries

Keep `.m` files with the subsystem they implement. Further nesting under
`appkit/`, `uikit/`, or `shared/` is allowed; update relative includes when
moving a file. Do not group unrelated controls, hosting, and services merely
because they share a language.

Use one shared header per native folder when its implementations need shared
declarations. Keep private helpers and state in `.m` files. The iOS host uses
`ios/LuaObjCHost/LuaObjCHost.h` for all its independently compiled `.m` files;
the platform bridge fragments already share declarations through inclusion.
Do not add per-class headers or empty headers to those fragment folders.

- AppKit fragments can use AppKit and shared helpers; UIKit fragments can use
  UIKit and shared helpers. Neither platform includes the other platform.
- Shared helpers express platform-neutral behavior. The userdata converter
  takes platform classes/metatable names from root-defined macros; it does
  not select or construct platform widgets.
- Hosts own process lifecycle and integration. The packager owns development
  transport. These may have independently compiled `.m` files outside the
  bridge folders; they are different products/responsibilities.
- Application models, actions, and composition stay in Lua. Native bridge
  code must not depend on an example app or its model.

A runtime image is a linked library or executable; a translation unit is one
compiler input after preprocessing. They are different boundaries. The AppKit
image already links `appkit-runtime.o` with `appkit-module.o`. The current
bridge fragments share a translation unit because they rely on static keys,
helpers, declarations, and state. Compiling those fragments independently
requires an intentional internal interface and one definition of each shared
symbol; moving folders alone does not provide that interface.

## iOS host build

The iPhone Simulator host compiles `ios/LuaObjCHost/*.m` + `src/uikit_module.m`
+ `liblua.a` only — never glob `src/uikit/*.m` as extra Compile Sources.
Application Lua and assets are not in the `.app`; they stream from the
packager. See [`docs/ios.md`](../docs/ios.md).

## Adding native behavior

To add a bridge function:

1. Put it in the fragment matching its native responsibility.
2. Add a forward declaration only when an earlier fragment needs it.
3. Register module operations in the platform root's `bridge_lib`; AppKit
   instance methods belong in `appkit/bindings.m`. Ordinary properties use
   KVC, with semantic aliases on exported classes and shared view properties
   on the base extension.
4. Wrap it in the corresponding `lua/embedded/*.lua` when it is public API.
5. Add headless regression coverage in `tests/*.test.lua` and visual QA when
   UI is affected. Any callback addition must name its originating state and
   the path that releases its registry reference. Follow the lifetime gaps
   and target contracts in `ARCHITECTURE.md`; native retention alone does not
   make a Lua callback safe.
