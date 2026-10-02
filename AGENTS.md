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
- [docs/animation.md](docs/animation.md) — animation, transitions, retained
  template reconciliation and steady live updates
- [docs/reels.md](docs/reels.md) — making 3-D promo reels with Reel and
  SceneKit: captures, component motion, camera, traps, performance
- [docs/data-driven.md](docs/data-driven.md) — manifests, schemas, `$field`
  and `@name` bindings, commands, two-way binding, the model graph
- [docs/components.md](docs/components.md) — components: new XML tags
  written as etlua templates, the bundled set, resolution
- [docs/scenekit.md](docs/scenekit.md) — `<SceneView>` 3-D scenes: scene
  records, reconciliation by id, per-frame poses, game architecture
- [docs/ios.md](docs/ios.md) — iPhone Simulator host, streamed Lua/assets,
  in-process reload (the host does not quit)
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
  The project is work in progress: this covers persisted data too. Saved
  games, settings, documents and caches carry no format versions, migrations,
  upgrade paths, or handling for data written by an older build or an older
  story. When a format or a story changes, old data may simply stop loading
  or replay differently; do not write code to detect, repair or preserve it.
- **Views are etlua only, without exception.** Screens and reusable
  components are `.etlua` templates composed with `partial()`. Controllers
  must never construct view trees, create layout containers, or assemble UI in
  controller code. Controllers prepare plain data, render templates, retain
  template refs, and bind actions only. If a view needs a new visual branch,
  add or update an `.etlua` template; do not add a controller-side view
  builder, helper, or fallback path.
  Application controllers must not call `ns` view constructors such as
  `ns.VStack`, `ns.Text`, `ns.List`, or `ns.Button`. The XML renderer is the
  sole application-layer caller that maps template tags to platform view
  constructors. A new tag an app needs is an etlua template in its
  `components/` folder (see [docs/components.md](docs/components.md)); the
  Lua module beside it computes template data and never touches `ns`. The
  app entry point/controller may create `ns.Window` only.
  Only the app entry point (`init.lua` or the `App` object) creates an
  `ns.Window`. A component that creates a window is wrong.
- **Product apps live in `apps/<appname>/`, demos in `demo/<name>/`, and test
  apps in `test/<name>/`.** Each has its own folder with `init.lua` as the
  entry point. Flat app files are
  forbidden. There are no forwarding shims.
- **Improve the framework, never patch around it in apps.** If a UI API is missing
  or behaves unlike its SwiftUI counterpart, fix the shared framework and add
  regression coverage. Do not hide layout or control defects with app-specific hacks.
- **Laravel/PHP-style composition.** Break growing controllers and models into
  focused controllers, domain models, and injected services in `controllers/`,
  `models/`, and `services/`. Each must be independently testable; the root
  controller coordinates them. See [ARCHITECTURE.md](ARCHITECTURE.md#app-layer).
- **Data-driven by default.** Views bind to model fields by name (`$field`),
  take constants from XML resources (`@name`), and declare their fields in an
  XML schema; the framework's generic controller sits between them. Write a
  controller class only to coordinate (sheets, confirmation, batch flows).
  Constants belong in `resources.xml` or a `<Resources>` element, not in Lua
  tables at the top of a template. See
  [docs/data-driven.md](docs/data-driven.md).
- **Laravel-style MVC.** Models own domain queries, validation, and mutations;
  controllers coordinate model calls, navigation, and callbacks; etlua views
  own presentation. Models never depend on `ns` or native widgets. Inject
  focused services for IO/runtime integration; keep controller actions thin.
- **MVC folder layout inside each app:**
  ```
  apps/<app>/, demo/<name>/, or test/<name>/
    init.lua       ← requires and returns Controller class (framework instantiates)
    Model.lua      ← data, queries, mutations
    Controller.lua ← wires model → views, owns actions
    views/         ← etlua templates only, including reusable partials
    components/    ← optional etlua components: new tags used by the views
    schemas/       ← optional XML schemas: the fields views bind to
    app.xml        ← optional manifest: models, sections and pages
    resources.xml  ← optional XML constants, referenced as `@name`
  ```
  init.lua never self-starts. It returns the class; the framework calls
  `class.new():createWindow()`. A manifest app (`app.xml`) has no
  `Controller.lua`: `init.lua` returns the manifest path and the framework
  builds the window, sidebar, menu and a generic controller per page.
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
- **Alignment is exact, never approximate.** In any block of stacked rows
  (a legend, a card's rows, a list of topics, section titles down a page):
  - every leading symbol, dot, spinner and disclosure triangle is centered
    on one vertical line. SF Symbols differ in width, so give the symbol a
    fixed column (`width` on `<SystemImage>`, `indicatorWidth` on
    `<DisclosureGroup>`) taken from one named constant; never rely on
    symbols happening to be the same size;
  - every label starts at one leading edge: the same column and the same
    gap in every row, including rows of a different kind in the same card
    (a warning, a legend row, a summary row);
  - within a row, a symbol, its label, its value and its trailing buttons
    share one center line. Do not top-align siblings of different heights;
    put those that belong on one line in an `alignment="center"` stack;
  - trailing values end at one edge: reserve a fixed column for optional
    trailing buttons so a row without the button does not shift its value.

  Do not use a label's own `systemImage` for rows stacked with other symbol
  rows; its symbol cannot join the column. Verify with `--dump-layout`
  (compare `window` x of symbols and labels) and keep a headless test, as
  `tests/diskmap_alignment.test.lua` does.
- Primary content consumes flexible space. Stacks add sibling spacing, not
  implicit outer margins.
- SwiftUI parity includes implicit sizing: omit dimensions and expansion
  attributes wherever the reference omits them. Fix shared layout defaults
  instead of adding repeated sizing instructions to application templates.
- When XML API design is ambiguous, refer to WPF property and content
  conventions, retaining camelCase names and SwiftUI-style native behavior.
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

- Append to Lua sequences with `table.insert(items, value)`, never
  `items[#items + 1] = value`. Preserve single-value semantics when the value
  is a call that can return multiple results: `table.insert(items, (fn()))`.
- New public Lua APIs and properties use camelCase. Preserve documented legacy
  names such as `fetch_json` and `Toggle.is_on` until an intentional migration.
- Repeated template siblings use etlua loops; reusable view structure uses
  etlua partials. Framework-level Lua composition uses `ForEach` and `Group`.
- Use tabs for leading indentation in `.m` and `.lua`.
- Project-owned native folders use at most one shared `.h` for their `.m`
  implementations, not one header per class. Keep implementation-only details
  in `.m`; included bridge fragments need no header unless sharing declarations
  across compilation units. Vendored and generated headers are excluded.
- Visual/layout numeric values must be named constants in the platform root:
  `src/main.m` for AppKit and `src/uikit/bridge.m` for UIKit.
- Group related layout constants into a local table (e.g. `local SEARCH = {
  width = 520, rowHeight = 28 }`) rather than separate `local SCREAMING_SNAKE`
  variables. Prefer flat camelCase keys.
- Comments explain design reasons, edge cases, and existing prior art.
- Keep each app's `init.lua` thin — entry point only. Put UI bricks in
  `views/`, state in `Model.lua`, and wiring in `Controller.lua`.
- Native `.m` sources expose existing Cocoa classes to Lua. New classes are
  implemented in Lua whenever possible; a new visual element composed from
  existing tags is an etlua component (`lua/components/` when the framework
  bundles it). Only reach for `.m` when the
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
make run ARGS="demo/hello/init.lua"
./lua-objc --preview --out=/tmp/preview.png demo/hello/init.lua
./lua-objc --screenshot=/tmp/screenshot.png apps/stocks/init.lua
```

### Run an app in iPhone Simulator

The streaming UIKit host runs an app entry point from the Mac packager. Use
`PROJECT` (not `ARGS`) to select the app:

```sh
make ios-run PROJECT=demo/hello
make ios-run PROJECT=apps/adventure-arena
```

The command builds `build/ios/LuaRuntime.app` if needed, starts the packager on
port 8081, boots the configured simulator, installs the host, and launches it.
Lua, templates, and assets are served from the working tree. Keep the packager
running while the app is open for file loading and hot reload.

#### Simulator troubleshooting

- Confirm the selected Xcode and SDK with `xcode-select -p` and
  `xcrun --sdk iphonesimulator --show-sdk-version`.
- List installed simulator runtimes and devices with
  `xcrun simctl list devices available`. If Xcode Settings shows an installed
  runtime but this command reports `CoreSimulatorService connection became
  invalid` or `Connection refused`, retry `simctl` with elevated sandbox
  permissions. A restricted shell may not be allowed to connect to the host's
  CoreSimulator XPC service. That error does not mean the runtime is absent.
- `make ios-run` also expects
  `$DEVELOPER_DIR/Applications/Simulator.app`. If that GUI app path is missing
  but `simctl` can list devices, boot and launch by explicit device UDID instead
  of treating the simulator runtime as unavailable:

  ```sh
  xcrun simctl list devices available
  SIMULATOR_UDID="paste-the-selected-device-udid-here"
  xcrun simctl boot "$SIMULATOR_UDID" || true
  xcrun simctl bootstatus "$SIMULATOR_UDID" -b
  make ios-host ios-packager
  ```

  Start the packager in a separate terminal, using the same app entry point:

  ```sh
  build/lua-objc-packager --root "$PWD" --port 8081 \
    --entry apps/adventure-arena
  ```

  The packager ignores `SIGPIPE` and drops hot-reload clients whose socket
  has closed. Then install and launch the host explicitly:

  ```sh
  xcrun simctl install "$SIMULATOR_UDID" build/ios/LuaRuntime.app
  SIMCTL_CHILD_LUA_OBJC_APP=apps/adventure-arena \
  SIMCTL_CHILD_LUA_OBJC_PACKAGER=http://127.0.0.1:8081 \
    xcrun simctl launch --terminate-running-process \
      "$SIMULATOR_UDID" org.luaobjc.host
  xcrun simctl io "$SIMULATOR_UDID" screenshot /tmp/ios-simulator.png
  ```

- If the screen says it is waiting for the packager, confirm the packager
  process is still alive and serving port 8081, then relaunch the host after
  the packager is ready.
- If an iOS build fails to link symbols for `WKWebView` or
  `WKFindConfiguration`, make sure the relevant `FRAMEWORKS` list links `WebKit`.

### Run a bundled app in iPad Simulator

Use the standalone app bundle when you want the app and its Lua files bundled
together, without the Mac packager:

```sh
make ipad-run APP=adventure-arena
```

This builds for `iphonesimulator`, bundles `apps/adventure-arena/` and the Lua
framework, then installs and launches on an available iPad simulator. Choose a
specific simulator by name or UDID with `IPAD_DEVICE`:

```sh
make ipad-run APP=adventure-arena IPAD_DEVICE="iPad Pro 13-inch (M5)"
```

If `open -a Simulator` fails but `simctl` can access CoreSimulator, build and
launch the app with an explicit simulator UDID:

```sh
make ipad-simulator APP=adventure-arena
SIMULATOR_UDID="paste-the-selected-device-udid-here"
xcrun simctl boot "$SIMULATOR_UDID" || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
xcrun simctl install "$SIMULATOR_UDID" \
  build/ipad/iphonesimulator-arm64/adventure-arena.app
xcrun simctl launch --terminate-running-process \
  "$SIMULATOR_UDID" org.luaobjc.adventure-arena
```

Simulator builds do not need a signing profile.

### Capture and compare iOS Simulator screenshots

`simctl io screenshot` captures the active display of a booted simulator
directly. **Simulator.app does not need to be open or visible on the Mac.**
Launch the candidate app on a known device, then capture its screen:

```sh
SIMULATOR_UDID="paste-the-selected-device-udid-here"
xcrun simctl io "$SIMULATOR_UDID" screenshot /tmp/candidate.png
sips -g pixelWidth -g pixelHeight /tmp/candidate.png
```

This is how the Adventure Arena simulator image was captured: `simctl launch`
started the app on the booted iPhone 17, then
`xcrun simctl io "$SIMULATOR_UDID" screenshot /tmp/adventure-arena-simulator.png`
saved the simulator display as a PNG. The Simulator window itself was not
visible. If a restricted shell reports a CoreSimulator connection error, run
the `simctl` command with elevated sandbox permissions and retry.

For a visual comparison with a SwiftUI reference, capture both apps on the
same simulator device and iOS runtime, with matching appearance, orientation,
content, and interaction state. Put one app in the foreground and capture it,
then launch the other app on that same simulator and capture the reference.
Compare PNGs at their native pixel size; do not compare an iPhone capture with
an iPad capture or a Simulator screenshot with a macOS window screenshot.

### Deploy a bundled app to a physical iPad or iPhone

First pair and trust the device with the Mac, unlock it, and inspect available
devices:

```sh
make list-devices
```

Deploy an app to an iPad:

```sh
make ipad-deploy APP=adventure-arena
```

The target builds for `iphoneos`, finds exactly one available physical iPad,
signs the app with a matching installed Apple Development certificate and
provisioning profile, then installs and launches it. If multiple iPads are
available, select one by name or identifier:

```sh
make ipad-deploy APP=adventure-arena IPAD_DEVICE="iPad device name or identifier"
```

If automatic signing selection cannot find a matching profile, install a
development profile that includes the target device and app identifier, or
pass its path and, if needed, the Apple Developer team ID:

```sh
make ipad-deploy APP=adventure-arena \
  IPAD_DEVICE="iPad device name or identifier" \
  PROFILE="/path/to/development.mobileprovision" TEAM="TEAMID1234"
```

Deploy to a physical iPhone with the matching target:

```sh
make iphone-deploy APP=adventure-arena
```

It expects exactly one available physical iPhone; use `make list-devices` if
selection or pairing fails. `make ipad` only builds the device app bundle;
`make ipad-deploy` performs signing, installation, and launch.

### Inspect computed AppKit layout

Use the native layout dump whenever a macOS view is clipped, misplaced, or
unexpectedly sized. It launches the app headlessly, forces AppKit and the
lua-objc layout engine to finish layout, writes the hierarchy, and exits:

```sh
make
./lua-objc --dump-layout=/tmp/layout.xml apps/stocks/init.lua
rg -n 'cropped="true"|outsideParent="true"|contentClipped="true"' /tmp/layout.xml

# Repeat at the app's minimum supported content size.
./lua-objc --dump-layout=/tmp/layout-small.xml --width=760 --height=468 \
  apps/stocks/init.lua
```

The XML is generated automatically by Objective-C; application code must not
manually construct a diagnostic tree. Each native view records its class,
`frame` and `window` rectangles (`"x y width height"`; `window` is in
top-left window points), `intrinsic` and `fitting` sizes (`"width height"`),
clipping state, and relevant text. Treemaps list their cells as
`TreemapCell` records.
`NSTableView` nodes additionally record computed column widths and visible cell
text geometry with an explicit `cropped` flag. Inspect the dump before changing
layout values and again afterward so the diagnosis and fix are both evidenced.

### Screenshot verification

Use `--screenshot=<path>` to launch the app, let it settle, capture the window
content, and quit automatically:

```sh
make
./lua-objc --screenshot=/tmp/before.png apps/stocks/init.lua
# make your change
make
./lua-objc --screenshot=/tmp/after.png apps/stocks/init.lua
```

Or with the Makefile shortcut:

```sh
make screenshot ARGS="apps/stocks/init.lua" OUT=/tmp/screenshot.png
```

The flag runs the full app event loop, waits 1.5 s for layout and rendering to
finish, captures the `contentView` of the first window as PNG, and exits with
code 0 on success or 1 on failure. Unlike `--preview`, this exercises the real
window geometry, split-view proportions, toolbar, and all live state. Use it to:

- Verify a UI change before and after without keeping the app open.
- Confirm a specific example renders without visual regressions.
- Capture both light and dark appearances:
  ```sh
  ./lua-objc --screenshot=/tmp/light.png --appearance=light apps/stocks/init.lua
  ./lua-objc --screenshot=/tmp/dark.png  --appearance=dark  apps/stocks/init.lua
  ```
- Capture at a custom content size:
  ```sh
  ./lua-objc --screenshot=/tmp/small.png --width=760 --height=468 apps/stocks/init.lua
  ```

### Window captures for tools

`--capture=<prefix>` writes `<prefix>.png` and `<prefix>.layout.xml` from one
settled moment of the window: the content view at backing scale without the
window shadow, and its layout dump, whose `<Layout scale="2">` gives the
image's pixels per point. A dump rect times `scale` is a pixel rect.

`--capture-plan=<plan.lua>` captures several states in one launch. The plan
returns `function(capture, app)`; `app` is the instance the framework created,
so the plan navigates with the app's own methods, then calls
`capture.appearance("dark")` and `capture.shot(prefix)`. See
`lua/ui/capture.lua` and `reels/diskmap/capture.lua`:

```sh
./lua-objc --capture=/tmp/map --width=1280 --height=800 apps/diskmap/init.lua --showcase --page=map
./lua-objc --capture-plan=reels/diskmap/capture.lua --width=1280 --height=800 \
  apps/diskmap/init.lua --showcase
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
