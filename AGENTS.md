# lua-objc agent guide

lua-objc exposes SwiftUI-like Lua APIs backed by real AppKit/UIKit controls.
It is a lightweight framework: Apple's frameworks do the work and an idle
app burns no CPU (see "A lightweight framework"). Most application work
belongs in `.lua`; native bridge work belongs in `src/`.

## Start here

Read only the material needed for the current task:

- [README.md](README.md) — commands and task-to-file map
- [ARCHITECTURE.md](ARCHITECTURE.md) — runtime layers, state lifetime, layout,
  plugins, and previews
- [docs/agents/application-architecture.md](docs/agents/application-architecture.md) — how an app is
  built: what goes where, with examples; folder structure; sidebar and
  tab-bar shapes
- [docs/agents/layout.md](docs/agents/layout.md) — page width (fill or
  readable), chart sizing, chart colors, how to verify a layout
- [src/README.md](src/README.md) — native bridge subsystem and symbol map
- [docs/PROJECT_REFERENCE.md](docs/PROJECT_REFERENCE.md) — detailed API and
  implementation reference; consult the relevant heading, not the whole file
- [docs/tableview_swiftui.md](docs/tableview_swiftui.md) — table behavior
- [docs/retained-templates.md](docs/retained-templates.md) — motion, retained
  template reconciliation and steady live updates
- [docs/reels.md](docs/reels.md) — making 3-D promo reels with Reel and
  SceneKit: captures, component motion, camera, traps, performance
- [docs/data-driven.md](docs/data-driven.md) — manifests, pages as requests over
  models, `@name` resources, the model graph
- [docs/components.md](docs/components.md) — components: new XML tags
  written as etlua templates, the bundled set, resolution
- [docs/scenekit.md](docs/scenekit.md) — `<SceneView>` 3-D scenes: scene
  records, reconciliation by id, per-frame poses, game architecture
- [docs/ios.md](docs/ios.md) — iPhone Simulator host, streamed Lua/assets,
  in-process reload (the host does not quit)
- [docs/research/XCODE_UI_ARCHITECTURE.md](docs/research/XCODE_UI_ARCHITECTURE.md)
  — research notes; only relevant to Xcode/IDE parity work
- [.agents/skills/lua-objc-hig/SKILL.md](.agents/skills/lua-objc-hig/SKILL.md) — Apple HIG adapted for lua-objc declarative UIs (use for design and review of screens)

Use `rg` before reading a large file. Typical entry points:

```sh
rg -n 'function_name|LuaClassName' src lua tests
rg -n '^### `Widget|WidgetName' docs/PROJECT_REFERENCE.md
```

## App Store Connect and Apple Developer tasks

Use [App Store Connect CLI (`asc`)](https://github.com/rorkai/App-Store-Connect-CLI)
for every task its commands support. This includes app/version management,
metadata and localizations, screenshots and previews, build uploads and
processing, TestFlight and testers, submission readiness, review and releases,
certificates and provisioning profiles, bundle IDs and capabilities, pricing
and availability, in-app purchases and subscriptions, analytics and reports,
notarization, and Xcode Cloud management.

Discover the current command with `asc search "<task>" --output json` and
`asc <command> --help`; use `asc capabilities --output json` to check coverage.
Prefer `asc` over browser/computer-use interactions and custom API scripts
for supported operations. Use `asc api` for supported API requests without a
dedicated command; use another tool when `asc` cannot perform the operation.
Use JSON output for scripts and verify the result of remote changes.

On this Mac, use the existing `corepunch` authentication profile stored in
macOS Keychain. Check it with `asc --profile corepunch auth status --validate`.
CI credentials belong in GitHub Actions secrets. Never commit or log private
keys, credential values, or authentication tokens.

Build artifacts with the repository's Makefiles and each app's declared
platform. Use `asc`'s management and distribution commands for those artifacts.

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
- **Pages are requests.** A page is a route and a view: the framework asks the
  route for `data(state)` and renders the etlua view with it; an action in the view
  is a method of the route, followed by the same request again. No bindings, no
  notifications, no controller that copies model values into views. Pages that
  differ by an argument are one route reading `self.params` from their `<Page>`
  (`route="workflow" workflow="music"`), never a class per page. Constants live
  in `resources.xml` or a `<Resources>` element (`@name`), not in Lua tables at the
  top of a template. Write a controller class only to coordinate (sheets,
  confirmation, batch flows). See [docs/data-driven.md](docs/data-driven.md).
- **Models are Lapis models.** A model is one table of the app's store:
  `local Files, File = Model:extend("files", {...})`, class methods for queries
  (`Files:find`, `Files:select`), row methods for rows, `constraints` for
  validation (`lua/data/model.lua`). The store is plain Lua data an app binds
  (`Store.lua`); models read the bound store and never take it as an argument.
  Few models, one per kind of row; a table computed from other tables is a
  model too (`source`), as a database view is. Only models read the store:
  a helper is pure and computes over the rows and values it is given, IO is
  a service, shared action code a flow (`Flow:extend`, `self:flow(name)`).
  A store is bound where code enters a window: the page controller for a
  page's actions, the root controller for its own methods and menu commands,
  `Model.bound` for a service's callbacks. Nothing else calls `Model.bind`.
- **Laravel-style MVC.** Models own domain queries, validation, and mutations;
  controllers coordinate model calls, navigation, and callbacks; etlua views
  own presentation. Models never depend on `ns` or native widgets. Inject
  focused services for IO/runtime integration; keep controller actions thin.
- **MVC folder layout inside each app:**
  ```
  apps/<app>/, demo/<name>/, or test/<name>/
    init.lua       ← requires and returns Controller class (framework instantiates)
    Model.lua      ← a small app's data, queries, mutations
    Controller.lua ← wires model → views, owns actions
    Store.lua      ← the store's seed: the tables the models read
    models/        ← Lapis models (Model:extend), stored or computed; every file is one
    routes.lua     ← the app's pages by route name; may gather pages/*.lua
    pages/         ← route files, one per page or small group; no AppKit
    flows/         ← action code several pages share (Flow:extend)
    helpers/       ← pure computation and formatting over rows given as arguments:
                     no store, no model, no service, no file
    services/      ← injected IO and runtime integration
    controllers/   ← coordination only (sheets, navigation, commands); with the
                     root controller and services, the only code that touches `ns`
    views/         ← etlua templates only, sorted like a web frontend:
      layouts/       app shell (window, sidebar, content frame)
      pages/         one template per screen
      sections/      large blocks a page composes (hero, decision, details)
      components/    small reusable partials (header, button row, tile)
      sheets/        modal dialogs and popovers
      (a folder per other kind, e.g. topics/; no loose files in views/)
      view names are paths under views/ ("pages/Overview"); partials resolve
      relative to the including template: partial("../components/X.etlua")
    components/    ← optional etlua components: new tags used by the views
    app.xml        ← optional manifest: sections and pages, each naming its route
    resources.xml  ← optional XML constants, referenced as `@name`
  ```
  A small app is init.lua, Model.lua, Controller.lua and views/; it grows into
  the folders above. init.lua never self-starts. It returns the class; the
  framework calls `class.new():createWindow()`. A manifest app (`app.xml`) has
  no `Controller.lua`: `init.lua` returns
  `require("data.app").launcher("<app>/app.xml")` and the framework builds the
  window, sidebar, menu and a generic controller per page from `routes.lua`.
- **XML templates are cross-platform.** View XML files live in `views/` and
  use the tag vocabulary in `lua/ui/xml.lua` (`<Label>`, `<VStack>`, `<Button>`,
  etc.). The platform module (`ns`) is injected by the caller; the same XML
  file renders NSTextField on AppKit and UILabel on UIKit without conditionals.
  To extend the vocabulary, add one entry to `xml.registry`.
- **etlua is the only template engine.** It is vendored at
  `lua/vendor/etlua` (git submodule). Import with `require("etlua")`. Do not
  add Mustache, Handlebars, or any other template dependency.

## A lightweight framework

lua-objc is a thin layer: etlua templates and plain Lua over Apple's own
frameworks. It is not a second UI toolkit. Everything below follows from
that, and outranks any feature request that conflicts with it.

- **Apple's frameworks do the work; we do not invent our own.** Scrolling,
  animation, transitions, text, selection, focus, drag and drop, tables and
  window behavior come from AppKit, UIKit and Core Animation as they ship.
  The bridge exposes what exists; it does not reimplement it. If Apple has
  no API for an effect, the answer is to go without the effect, not to
  build an engine for it.
- **Scrolling is the system's.** `NSScrollView` and `UIScrollView` scroll.
  No custom scroll animation, no Lua or timer-driven offsets, no code that
  runs per scroll frame.
- **No animation is better than a wasteful one.** The project once had its
  own motion engine (`src/shared/motion.m`, removed in 7a909a21): it
  snapshotted and diffed whole layout subtrees and started about 35 Core
  Animation animations on every scan tick, on every page, and it fought
  scrolling. Nothing like it comes back. A view may animate itself with a
  system facility (a tour page slides with `CATransition`); nothing animates the view tree, and frequent updates
  (scan progress, streaming text, per-tick refreshes) are never animated.
- **An idle app uses 0% CPU.** Nothing redraws, lays out, polls or ticks
  unless something asked for it: a user action, a completed async result,
  or a controller setting a value. No display links, repeating timers or
  refresh loops behind a page the user is only looking at. A timer or
  display link exists only while the thing it drives is visibly running
  (a game scene, a playing reel) and stops with it.
- **No bindings, no observation, no notifications between models and
  views.** A value reaches the screen in exactly two ways: etlua writes it
  when the template renders (`<%= %>`, `<% for %>`), or a controller sets
  it on a retained view ref when that is truly necessary (a progress bar's
  value during a scan). There is no `attr="{field}"` or `$field` syntax, no
  observable model, no change subscription, no automatic refresh. A table
  `<Column>` takes no child views: its cell is a native kind chosen by key
  attributes that name row fields (`subtitleKey`, `levelKey`, ...).
- **Less machinery beats more.** Before adding a subsystem, a cache, a
  diffing pass, a registry or an abstraction layer, look for the version
  that is a loop in a template or one call on a native view. Delete
  machinery that a simpler design makes unnecessary.
- **Ask "are you sure?" first.** When the user asks for a feature that could
  slow the application down or add a large amount of machinery, stop and ask
  "are you sure?" before building it, naming the cost.

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

