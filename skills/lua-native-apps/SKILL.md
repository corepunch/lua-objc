---
name: lua-native-apps
description: Lua-first macOS/iOS app architecture for lua-objc. Use when building or refactoring native app shells, IDE-style welcome/workspace flows, plugin/editor surfaces, recent-files/folders persistence, headless smoke tests, or converting Lua view functions to etlua templates.
---

# Lua Native Apps

Build user-facing apps in Lua only. Keep AppKit/UIKit work behind the bridge
and keep the app shell thin enough that most behavior lives in reusable Lua
modules.

## Canonical Shape

- Use `App.new{...}` as the root lifecycle/controller object.
- Put startup routing in the app shell, not in ad hoc example scripts.
- Let `App:run()` decide:
  - folder argument present -> open the workspace
  - no folder -> show the welcome screen
- Keep recent files and recent folders separate.
- Keep `examples/<app>/main.lua` as a thin bootstrap only.

The current `lua-objc` pattern is:

```lua
local App = require("App")
local Recent = require("examples.IDEKit.state.Recent")
local Workspace = require("examples.IDEKit.Workspace")
local Welcome = require("examples.IDEKit.Welcome")

local app = App.new {
	recent = Recent.new { key = "ide" },
	openFolder = function(self, folder)
		return Workspace.open(folder, self)
	end,
	welcome = function(self)
		return Welcome {
			recentFolders = self.recent:folders(),
			recentFiles = self.recent:files(),
		}
	end,
}

return app:run()
```

## App architecture: Model → Controller → etlua views

Every app follows strict MVC separation with etlua as the sole view layer:

```
examples/<app>/
  init.lua        — entry point, requires and returns Controller class
  Model.lua       — pure data: queries, formatting, sample data
  Controller.lua  — creates views, wires Model → views, owns actions
  views/          — etlua templates, one per screen/section
```

**Views are etlua templates, never .lua files.** No `require("views/Component")` —
all views load via `xml.renderFile("views/Component.etlua", data)`.

### Why etlua-only

etlua templates are cross-platform (same XML renders NSTextField on AppKit,
UILabel on UIKit). The engine's `<% for %>` loops handle iteration — no need
for a `ForEach` XML tag or Lua callback functions in templates. Data
transformation (column splitting, metric grouping, decoration) lives in the
Controller; the template receives already-structured tables and emits view
trees declaratively.

### Data flow

The Controller pre-computes all display data into plain Lua tables. Templates
receive a single data table via `xml.renderFile()` and use etlua expressions
to inject values:

```lua
-- Controller
local function precomputeMetrics(stock)
	return {
		{ {"Open", stock.openStr}, {"High", stock.dailyHighStr} },
		{ {"Vol", stock.volumeStr}, {"P/E", "--"} },
	}
end

stock.metricColumns = precomputeMetrics(stock)
local view = xml.renderFile("views/StockDetail.etlua", { stock = stock })
```

```xml
<!-- StockDetail.etlua -->
<% for _, column in ipairs(stock.metricColumns) do %>
<VStack flexGrow="1" spacing="4">
    <% for _, row in ipairs(column) do %>
    <HStack fillWidth="true">
        <Label text="<%= row[1] %>" size="11" color="secondary" weight="semibold" />
        <Spacer />
        <Label text="<%= row[2] %>" size="12" weight="semibold" />
    </HStack>
    <% end %>
</VStack>
<% end %>
```

### Passing pre-built userdata to templates

When a Controller constructs native userdata (e.g., a `Curve` chart) that
can't be serialized into XML, pass it in the render data and use the `<Chart>`
tag to reference it:

```lua
-- Controller
self.chart = ns.Curve { data = chartData, width = 600, ... }
local view = xml.renderFile("views/StockDetail.etlua", { chart = self.chart })
```

```xml
<!-- StockDetail.etlua -->
<Chart />
```

The `<Chart>` tag (in `lua/ui/xml.lua` registry) returns the userdata from
the render data context keyed by `data` attribute (defaults to `"chart"`).

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
- Persist them through the app layer or a small state wrapper such as `examples.IDEKit.state.Recent`.
- When adding open actions, record the item kind at the same time the workspace opens.
- Keep path pickers in the app layer so the UI does not need to know how folders/files are chosen.

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
