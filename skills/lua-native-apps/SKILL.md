---
name: lua-native-apps
description: Laravel-style MVC architecture for Lua macOS/iOS apps in lua-objc. Use when building or refactoring app models, controllers, native app shells, etlua views, or their headless regression tests.
---

# Lua Native Apps

Build user-facing apps in Lua only. Keep AppKit/UIKit work behind the bridge
and keep the app shell thin enough that most behavior lives in reusable Lua
modules.

## Laravel-style MVC with etlua views

Use Laravel's separation of models, controller actions, and Blade views as the
app architecture; etlua fills the Blade role. Keep the native app lifecycle:
controllers and native widgets persist across events, so controller actions
update existing refs or navigate to rendered templates. This convention does
not require an HTTP router, ORM, service container, or Laravel dependency.

```text
examples/<app>/
  init.lua        — requires and returns Controller class; never self-starts
  Model.lua       — domain data, queries, validation, state, mutations
  Controller.lua  — coordinates model operations, rendering, navigation, callbacks
  views/          — .etlua screens and reusable partials only
```

Add focused model or service modules only when there is a concrete second
responsibility. For example, Adventure Arena's `Catalog.lua` stores seed data,
`Model.lua` queries games and owns session state, and `ZIL.lua` adapts the game
runtime and file access. Do not create empty Laravel-style directories.

### Model and service boundaries

- Models own domain decisions: lookup, validation, command normalization,
  session transitions, transcript history, and failure semantics.
- Models never import AppKit/UIKit, accept the whole `ns` module, create views,
  retain widget refs, render templates, or navigate.
- Keep file, network, compiler, and engine integration in focused services.
  Inject the needed operation (such as a file reader or engine factory), not
  a platform module. Wire concrete dependencies at controller construction or
  the app composition boundary.
- Query the controller's model instance rather than reaching around it into
  module-level catalog tables. Use stable record IDs for actions; resolve and
  validate them through the model. Allow model/service injection for tests.
- Keep symbols, colors, typography, layout, and display formatting out of domain
  models. Preserve raw model data when preparing a view; do not decorate shared
  records with transient presentation fields.

### Thin controllers

Controller actions follow: resolve input → call the model → render/navigate or
update existing native refs. Keep callbacks short by delegating to named actions.
A controller may assemble a small view-data table and action map, but must not
implement business rules, file/compiler operations, widget trees, or rating/icon
rendering algorithms. Extract complex presentation transformations into a focused
presenter only when a template or small data projection is insufficient.

For example, `showGame(id)` asks `self.model:game(id)` for a record, handles a
missing record without disturbing navigation, and renders `Detail.etlua` with
`{ game = game, actions = ... }`. `submitCommand(text)` calls the session model,
then updates transcript/input refs. The model trims and executes the command.

### etlua is the sole view layer

**Views are etlua templates, never `.lua` files.** This includes tab shells,
detail and session screens, loading/empty/error states, and reusable components.
Render screens with `xml.renderFile(path, data, ns)` and compose templates with
`partial("Component.etlua", data)`. Only the controller's `createWindow()` or the
root App lifecycle creates a native window; components emit view trees only.

Views own presentation: native XML tags, layout, labels, scalar formatting,
conditionals, and loops over supplied data. Reuse display logic such as rating
stars in a shared etlua partial. Templates must not query models, perform IO,
mutate domain state, call Lua view constructors, or implement action bodies.
Callbacks arrive in `data.actions` or are attached to returned refs by the
controller. If a required native control lacks a template tag, extend
`xml.registry` rather than bypassing templates with a Lua view module.

The same XML vocabulary renders AppKit and UIKit controls; pass the platform to
the renderer rather than adding platform conditionals to views. etlua is the
only template engine, imported with `require("etlua")` when used directly.

During refactors, migrate callers and tests together and delete replaced Lua
views and obsolete APIs completely. Do not move view constructors into the
controller, retain forwarding stubs, or preserve a parallel static model API.

### Verify the boundaries

Test model queries and mutations with injected services and no UI dependencies.
Cover empty/missing records, rejected input, failed operations preserving prior
state, and independent model instances. Controller tests should use injected
models and exercise the actions actually bound by templates, including navigation
and unchanged unrelated state. Render etlua with special characters and long
text. Follow the repository's native layout and visual QA requirements as well.

## IDE App Layout

- Top-level files in `IDEKit/` are the core IDE components (workspace, editors, navigators, etc.).
- Use `IDEKit/plugins/` for concrete editor surfaces — only files that call `App.registerPlugin()`.
- Use `IDEKit/state/` for persistence and recent-item adapters.
- Keep the IDE's plugin registry inside `lua/App.lua` — the base App class owns
  plugin discovery, registration, and loading. `plugins/` contains only plugin
  definitions (no boilerplate).
- Follow Xcode's `-Kit` naming convention: `IDEKit` for the IDE framework,
  `DVTKit` for shared dev-tools widgets, `IDEFoundation` for non-UI model logic.

## IDE-Owned Plugins

The framework provides the Lua/AppKit boundary; the IDE owns the plugin
catalog and loading policy. Keep editor surfaces as Lua modules and let the IDE
select them by file extension, command, or capability:

```lua
local App = require("App")
local app = App.new { name = "ide" }
local surface = app:resolvePluginByFile(path, "editor")
-- App.new() auto-loads plugins from the plugin directory on construction.
```

Lua plugins can optionally load native controls through the standard Lua
dynamic-module ABI. The IDE registry's `loadNative(path, moduleName)` calls the dylib's
`luaopen_<moduleName>` entry point; the dylib should return a normal Lua module
whose functions create bridge-compatible native views. The dylib is an
extension provider, not the IDE plugin itself:

```lua
local App = require("App")
local controls = App.loadNativePlugin("build/ide-controls.dylib", "ide_controls")
local colorWell = controls.ColorWell()
```

This keeps application code Lua-only while allowing missing AppKit controls to
be added without moving IDE behavior into Objective-C. Native extensions share
the host Lua state and are therefore trusted in-process code, not a security
sandbox.

## Recent State

- Track `recent files` and `recent folders` independently.
- Keep app-specific persistence in the app model or a small state wrapper under
  the app's own folder.
- When adding open actions, record the item kind at the same time the workspace opens.
- Keep path pickers in the app layer so the UI does not need to know how folders/files are chosen.

## Cross-pane alignment

When a split-view layout has aligned peer content in both panes (e.g. a sidebar
search field and a detail header that share the same visual baseline), the
elements must sit at the same Y position across panes. Do not let independent
per-pane padding values drift apart.

To verify:

```sh
./lua-objc --dump-layout=/tmp/layout.xml examples/<app>/init.lua
rg 'search|header|Detail|SearchField' /tmp/layout.xml | head -20
```

In the dump, compare the y+height top edge of the two elements. AppKit uses
bottom-left origin: `y` is the distance from the split-view bottom, so the
visual distance from the window top is `windowHeight - (element.y + element.height)`.

Example from stocks: the search field sat at y=592 (56px from top), the detail
header at y=578 (70px from top) — a 14px drift caused by the detail pane's
`padding="18"` not accounting for the sidebar's glass-effect margin + search
container vertical padding.

Fix approach:
- Compute the target top-edge offset for the primary element (usually the
  sidebar anchor — search field, master list header, etc.).
- Set the detail pane's `paddingTop` to match it, pulling the padding constant
  from a shared `LAYOUT` table in the Controller rather than hardcoding in the
  template.
- Verify both dumps (default size + minimum size) show equal top-edge values.

## Headless Verification

- Set `_G.__headless = true` in tests.
- Load example files with `loadfile` and wrap them in `pcall`.
- Test controllers directly in-process (no subprocess spawning). Require the
  Controller module, instantiate it, call `createWindow()`, and assert
  workspace state, view dimensions, and model behavior.
- Do NOT spawn `./lua-objc <dir>` subprocesses in tests — they introduce
  run-loop timing races with `dispatch_after` key/main window activation.
- Test startup routing by stubbing `openFolder`, `openFile`, and `welcome`.
- Verify recent-store behavior with a temporary storage root so tests do not touch user data.
- Add a smoke test when a new app surface, entrypoint, or persistence path is introduced.
- Test both Lua plugin loading and native provider loading when an IDE plugin
  depends on a dylib; a successful dylib build alone does not verify the Lua
  module ABI.
