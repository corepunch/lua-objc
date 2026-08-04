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

## Non-negotiable project rules

- **No backwards compatibility, ever.** When the right design is found, move
  to it completely. Delete old paths, old names, and old files — do not leave
  shims, aliases, or forwarding stubs behind. A clean break is always preferred
  over a compatibility layer. Callers update in the same commit.
- **No monolith scenes.** Components return view trees (`ns.VStack { ... }`).
  Only the app entry point (`init.lua` or the `App` object) creates an
  `ns.Window`. A component that creates a window is wrong.
- **Apps live in `examples/<appname>/`.** Every app has its own folder with
  `init.lua` as the entry point. Flat `examples/<appname>.lua` files are
  forbidden. There are no forwarding shims.
- **MVP folder layout inside each app:**
  ```
  examples/<app>/
    init.lua        ← requires and returns Controller class (framework instantiates)
    Model.lua       ← data, queries, mutations
    Controller.lua  ← wires model → views, owns actions
    views/          ← etlua templates and Lua component functions
  ```
  init.lua never self-starts. It returns the class; the framework calls
  `class.new():createWindow()`.
- **XML templates are cross-platform.** View XML files live in `views/` and
  use the tag vocabulary in `lua/ui/xml.lua` (`<Label>`, `<VStack>`, `<Button>`,
  etc.). The platform module (`ns`) is injected by the caller; the same XML
  file renders NSTextField on AppKit and UILabel on UIKit without conditionals.
  To extend the vocabulary, add one entry to `xml.registry`.
- **etlua is the only template engine.** It is vendored at
  `lua/vendor/etlua` (git submodule). Import with `require("etlua")`. Do not
  add Mustache, Handlebars, or any other template dependency.

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
- Keep `examples/<app>/init.lua` thin — entry point only. Put UI bricks in
  `views/`, state in `Model.lua`, and wiring in `Controller.lua`.
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

## Native bridge surfaces

AppKit and UIKit have no XML schemas. Their Lua metatables read and write
Objective-C properties through KVC. Put semantic aliases and framework-owned
state on the exported classes themselves:

- ordinary Cocoa property: no bridge declaration;
- semantic alias: accessor on an exported subclass such as `LuaTextField`;
- property shared by every view: accessor on the `NSView` base extension;
- non-property operation: explicit entry in `src/appkit/bindings.m`;
- module constructor/service: `src/appkit/constructors.m` or its owning native
  subsystem;
- native value structs: explicit userdata in the platform runtime.

Do not add getter/setter wrappers, generated bridge artifacts, or platform XML
metadata layers.

## Build and verification

```sh
make
make test
make run ARGS="examples/hello/init.lua"
./lua-objc --preview --out=/tmp/preview.png examples/hello/init.lua
```

### Inspect computed AppKit layout

Use the native layout dump whenever a macOS view is clipped, misplaced, or
unexpectedly sized. It launches the app headlessly, forces AppKit and the
lua-objc layout engine to finish layout, writes the hierarchy, and exits:

```sh
make
./lua-objc --dump-layout=/tmp/layout.xml examples/stocks/init.lua
rg -n 'cropped="true"|outsideParent="true"|contentClipped="true"' /tmp/layout.xml

# Repeat at the app's minimum supported content size.
./lua-objc --dump-layout=/tmp/layout-small.xml --width=760 --height=468 \
  examples/stocks/init.lua
```

The XML is generated automatically by Objective-C; application code must not
manually construct a diagnostic tree. Each native view records its class,
computed frame, intrinsic/fitting sizes, clipping state, and relevant text.
`NSTableView` nodes additionally record computed column widths and visible cell
text geometry with an explicit `cropped` flag. Inspect the dump before changing
layout values and again afterward so the diagnosis and fix are both evidenced.

For UI changes, completion requires actual visual QA:

1. Launch every affected example and inspect a screenshot.
2. Resize substantially smaller and larger.
3. Exercise supported loading, loaded, empty, selected, disabled, error, and
   long-text states.
4. Check native selection, focus, keyboard access, alignment, and truncation.
5. Check light and dark appearances.

Headless tests set `_G.__headless = true`. Add new example entry points to
`tests/examples.test.lua`.
