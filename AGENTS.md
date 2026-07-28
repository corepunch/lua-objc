# lua-objc agent guide

lua-objc exposes SwiftUI-like Lua APIs backed by real AppKit/UIKit controls.
Most application work belongs in `.lua`; native bridge work belongs in `src/`.

## Start here

Read only the material needed for the current task:

- [README.md](README.md) — commands and task-to-file map
- [ARCHITECTURE.md](ARCHITECTURE.md) — runtime layers, state lifetime, layout,
  plugins, and previews
- [src/README.md](src/README.md) — native bridge subsystem and symbol map
- [docs/PROJECT_REFERENCE.md](docs/PROJECT_REFERENCE.md) — detailed API and
  implementation reference; consult the relevant heading, not the whole file
- [docs/tableview_swiftui.md](docs/tableview_swiftui.md) — table behavior
- [docs/research/XCODE_UI_ARCHITECTURE.md](docs/research/XCODE_UI_ARCHITECTURE.md)
  — research notes; only relevant to Xcode/IDE parity work

Use `rg` before reading a large file. Typical entry points:

```sh
rg -n 'function_name|LuaClassName' src lua tests
rg -n '^### `Widget|WidgetName' docs/PROJECT_REFERENCE.md
```

## Non-negotiable product rules

- The goal is complete SwiftUI-style coverage through native AppKit/UIKit
  widgets. Never imitate a native control with text, emoji, hard-coded color,
  or decorative drawing.
- Use system controls, metrics, fonts, semantic colors, SF Symbols, keyboard
  behavior, and accessibility labels.
- The macOS target is macOS 26 and later. Never add legacy, deprecated, or
  compatibility UI implementations, appearance shims, or old-material
  fallbacks. Use current semantic AppKit containers directly. In particular,
  source lists must not insert an `NSVisualEffectMaterialSidebar` wrapper;
  the owning `NSSplitViewItem` sidebar supplies the system appearance.
- Never recreate an existing system control with another control or a custom
  view. Document tabs must use public `NSWindow` tabbing; never imitate them
  with `NSSegmentedControl`, custom drawing, or private Finder classes such as
  `NSTabBar` and `NSTabButton`. AppKit may use private implementation classes
  internally when the public API is invoked.
- Floating panels use an ordinary titled, full-size-content `NSPanel` and let
  AppKit own the frame shape, corners, clipping, and shadow. Do not expose
  per-panel `cornerRadius`, `shadowRadius`, `shadowOpacity`, `shadowOffset`, or
  `shadowInset` APIs in Lua or the native bridge. Do not add custom shadow
  layers or transparent shadow insets unless the user explicitly requests a
  non-native effect.
- Primary content consumes flexible space. Stacks add sibling spacing, not
  implicit outer margins.
- Let native containers own their geometry. In particular, do not fight
  `NSSplitView` with custom pane frames.
- Use edge-to-edge `plain`/`fullWidth` tables for primary data, `sourceList`
  only for navigation, and `inset` for grouped/settings content.
- A loading table shows its own centered native spinner with `showLoading()`
  and `hideLoading()`; do not simulate latency with sleeps.
- Put window-wide actions in `NSToolbar`; keep row/section actions local.
- New leaf controls fit the eager bridge. State-dependent structural changes
  require retained descriptions/reconciliation, not feature-specific subtree
  mutation hooks. See “Declarative components” in the detailed reference.

## Code conventions

- New public Lua APIs and properties use camelCase. Preserve documented legacy
  names such as `fetch_json` and `Toggle.is_on` until an intentional migration.
- Repeated sibling views use `ForEach`; reusable structure uses ordinary Lua
  component functions. `Group` emits multiple siblings.
- Use tabs for leading indentation in `.m` and `.lua`.
- Visual/layout numeric values must be named constants in the platform root:
  `src/main.m` for AppKit and `src/uikit/bridge.m` for UIKit.
- Group related layout constants into a local table (e.g. `local SEARCH = {
  width = 520, rowHeight = 28 }`) rather than separate `local SCREAMING_SNAKE`
  variables. Prefer flat camelCase keys.
- Comments explain design reasons, edge cases, and existing prior art.
- Keep `examples/<app>/main.lua` thin. Put UI bricks in `components/`, state in
  `state/`, and editor surfaces in `plugins/`.
- Native `.m` sources expose existing Cocoa classes to Lua. New classes are
  implemented in Lua whenever possible. Only reach for `.m` when the
  feature cannot be built in pure Lua (e.g. Canvas requires offscreen
  rendering via `CGImage`).
- Preserve one runtime image per platform. AppKit and UIKit fragments are
  intentionally included by their platform roots to share static bridge state;
  platform-neutral services belong in `src/shared/`.

## Testing

**Every implementation or bugfix must include fast headless regression tests.**
Tests are ordinary Lua scripts discovered by `make test` (any `tests/*.test.lua`)
and run in under a second — no windows, no pauses. They should verify:

- Construction, properties, layout contracts, data mutation.
- Column widths, flex behavior, split proportions.
- Edge cases: empty, zero-size, overflow, missing data.
- Round-trip: create → mutate → verify no change in unrelated state.

Use `t.assertSize` / `t.assertEqual` / `t.expect` from `TestKit` (see
`lua/TestKit.lua`). Bridge helpers available in test context:

- `bridge._viewSize(view)` → `(width, height)`
- `bridge._tableColumnWidths(view)` → `{{id, width, minWidth}}`
- `bridge._setContentSize(view, w, h)` + `bridge._layout(view, w)` to simulate
  container sizing without a window

Tests are the project's primary safety net. When in doubt, add more assertions
rather than fewer. The test suite should grow continually.

## Bridge code generation

Most AppKit and UIKit bridge boilerplate is **generated** from XML config files.
Never edit the generated files directly — edit the XML and regenerate.

### Files

| File | Purpose |
|---|---|
| `tools/bridge.xml` | AppKit bridge surface (properties, constructors, callback setters, manual entries) |
| `tools/uikit_bridge.xml` | UIKit bridge surface (same structure, UIKit classes and key style) |
| `tools/gen_bridge.py` | Generator — reads XML, emits three files per platform |

### Generated files (do not edit)

| Generated file | Used by | Contains |
|---|---|---|
| `src/appkit/generated/bridge_funcs.m` | `src/main.m` | `bridge_xxx()` C functions |
| `src/appkit/generated/bridge_props.m` | `src/appkit/runtime.m` | `INDEX_xxx` / `NEWINDEX_xxx` macro calls |
| `src/appkit/generated/bridge_lib.inc` | `src/main.m` | `luaL_Reg` table entries |
| `src/uikit/generated/bridge_funcs.m` | `src/uikit/bridge.m` | same, UIKit |
| `src/uikit/generated/bridge_props.m` | `src/uikit/metatable.m` | same, UIKit |
| `src/uikit/generated/bridge_lib.inc` | `src/uikit/bridge.m` | same, UIKit |

### Regenerate after any XML change

```sh
python3 tools/gen_bridge.py                                              # AppKit
python3 tools/gen_bridge.py --xml tools/uikit_bridge.xml --out src/uikit/generated  # UIKit
make
```

### Adding a new bridge function

**Simple constructor** (alloc a view, set properties, return it):

```xml
<!-- tools/bridge.xml or uikit_bridge.xml -->
<constructor name="my_widget" lua_name="_myWidget" returns="nsview">
  <arg index="1" name="title"    type="string"   required="true"/>
  <arg index="2" name="callback" type="function?" required="false"/>
  <alloc class="NSMyClass" frame="NSZeroRect"/>
  <set_prop property="title" from_arg="title"/>
  <call_method method="sizeToFit"/>
  <assoc key="kFlexibleKey" value="@YES"/>
  <callback arg="callback" key="kCallbackKey"
            target="[LuaButtonTarget shared]" action="onAction:"/>
</constructor>
```

**Callback setter** (stores a Lua function ref on an existing view):

```xml
<callback_setter name="widget_on_change" lua_name="_widgetOnChange">
  <guard type="MySourceClass" key="kMySourceKey" msg="not a my_widget"/>
  <store key="kMyChangeKey" on="obj"/>
  <!-- optional side effects when setting or clearing: -->
  <!-- <side_effect_set>ObjC statements here</side_effect_set> -->
  <!-- <side_effect_clear>ObjC statements here</side_effect_clear> -->
</callback_setter>
```

**Manual entry** (complex logic that stays hand-written, but is registered via generated table):

```xml
<manual_entry name="my_complex_func" lua_name="_myComplexFunc" src="views.m"/>
```
Then implement `static int bridge_my_complex_func(lua_State *L)` in the named `.m` file.

**New layout property** (appears on all views as `view.myProp`):

```xml
<!-- in <properties metatable="nsview"> -->
<prop name="myProp" key="kMyPropKey" type="number" default="0"/>
```
Also add `kMyPropKey` to the enum in `src/main.m`.

### Key styles

The two XML files use different key styles, handled automatically:

- `bridge.xml` (`key_style="enum"`) — AppKit uses a single `char kKeys[kKeyCount]` array; props macro args are bare enum names (`kFooKey`).
- `uikit_bridge.xml` (`key_style="direct"`) — UIKit uses individual `static char kFooKey` vars; all references are `&kFooKey`.

### Callback target styles

- `callback_style="property"` (AppKit) — sets `.target` / `.action` on NSControl subclasses.
- `callback_style="addTarget"` (UIKit) — calls `addTarget:action:forControlEvents:`. Set the `event=` attribute on `<callback>` to specify the control event (default: `UIControlEventTouchUpInside`).

## Build and verification

```sh
make
make test
make run ARGS="examples/hello.lua"
./lua-objc --preview --out=/tmp/preview.png examples/hello.lua
```

For UI changes, completion requires actual visual QA:

1. Launch every affected example and inspect a screenshot.
2. Resize substantially smaller and larger.
3. Exercise supported loading, loaded, empty, selected, disabled, error, and
   long-text states.
4. Check native selection, focus, keyboard access, alignment, and truncation.
5. Check light and dark appearances.

Headless tests set `_G.__headless = true`. Add new example entry points to
`tests/examples.test.lua`.
