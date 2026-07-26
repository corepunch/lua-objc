---
name: lua-native-apps
description: Lua-first macOS/iOS app architecture for lua-objc. Use when building or refactoring native app shells, IDE-style welcome/workspace flows, plugin/editor surfaces, recent-files/folders persistence, or headless smoke tests for Lua-only apps.
---

# Lua Native Apps

Build user-facing apps in Lua only. Keep AppKit/UIKit work behind the bridge and keep the app shell thin enough that most behavior lives in reusable Lua modules.

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
local Recent = require("examples.ide.state.recent")
local Source = require("examples.ide.plugins.source")
local Welcome = require("examples.ide.components.welcome")

local app = App.new {
	recent = Recent.new { key = "ide" },
	openFolder = function(self, folder)
		return Source.open(folder, self)
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

## IDE App Layout

- Use `components/` for shared UI bricks.
- Use `state/` for persistence and recent-item adapters.
- Use `plugins/` for concrete editor surfaces.
- Keep `workspace.lua` and `welcome.lua` as compatibility shims if legacy entrypoints still point there.
- Keep the IDE's plugin registry in `examples/ide/plugins/registry.lua`; use
  `IDEKit` only for shared editor chrome.

## IDE-Owned Plugins

The framework provides the Lua/AppKit boundary; the IDE owns the plugin
catalog and loading policy. Keep editor surfaces as Lua modules and let the IDE
select them by file extension, command, or capability:

```lua
local PluginHost = require("examples.ide.plugins.host")
local plugins = PluginHost.new():loadBuiltins()
local surface = plugins:openFile(path, { app = app })
```

Lua plugins can optionally load native controls through the standard Lua
dynamic-module ABI. The IDE registry's `loadNative(path, moduleName)` calls the dylib's
`luaopen_<moduleName>` entry point; the dylib should return a normal Lua module
whose functions create bridge-compatible native views. The dylib is an
extension provider, not the IDE plugin itself:

```lua
local registry = require("examples.ide.plugins.registry")
local controls = registry.loadNative("build/ide-controls.dylib", "ide_controls")
local colorWell = controls.ColorWell()
```

This keeps application code Lua-only while allowing missing AppKit controls to
be added without moving IDE behavior into Objective-C. Native extensions share
the host Lua state and are therefore trusted in-process code, not a security
sandbox.

## Recent State

- Track `recent files` and `recent folders` independently.
- Persist them through the app layer or a small state wrapper such as `examples.ide.state.recent`.
- When adding open actions, record the item kind at the same time the workspace opens.
- Keep path pickers in the app layer so the UI does not need to know how folders/files are chosen.

## Headless Verification

- Set `_G.__headless = true` in tests.
- Load example files with `loadfile` and wrap them in `pcall`.
- Test startup routing by stubbing `openFolder`, `openFile`, and `welcome`.
- Verify recent-store behavior with a temporary storage root so tests do not touch user data.
- Add a smoke test when a new app surface, entrypoint, or persistence path is introduced.
- Test both Lua plugin loading and native provider loading when an IDE plugin
  depends on a dylib; a successful dylib build alone does not verify the Lua
  module ABI.
