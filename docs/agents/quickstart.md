---
layout: default
title: Agent quickstart
---

# Agent quickstart

Read [application architecture](application-architecture.md) first. It defines
the non-negotiable split between models, focused controllers, and etlua views.

This page is an operating guide for an agent creating or changing a lua-objc
app. Read it before writing application code.

## 1. Choose the app shape

Create a product app under `apps/` or a framework example under `test/`:

```text
apps/weather/
  init.lua
  Model.lua
  Controller.lua
  views/
    Window.etlua
    Detail.etlua
```

Keep `init.lua` thin. It returns the controller class; it does not create a
window or start the application.

```lua
return require("apps.weather.Controller")
```

Put domain queries, validation, formatting inputs, and mutations in
`Model.lua`. Keep callbacks, navigation, and template refs in `Controller.lua`.
Put all reusable visual structure in `views/*.etlua` partials. Controllers may
prepare data and bind refs after rendering, but must not construct view trees.

## 2. Start with native structure

Use a semantic window split when the app has navigation and primary content:

```lua
local ns = require("AppKit")
local xml = require("ui.xml")

local config, refs = xml.renderFile("apps/weather/views/Window.etlua", data, ns)
local window = ns.Window(config)
```

All view trees come from `.etlua` templates rendered through `ui.xml`.
Controllers must not call `ns` view constructors (`VStack`, `Text`, `List`,
`Button`, and similar); they may create the top-level `ns.Window` and use
non-view services and operations. The semantic sidebar owns its native
appearance and split geometry. Do not wrap it in a visual-effect material or
manually set pane frames.

## 3. Prefer XML for stable view structure

Use etlua for declarative structure and Lua for stateful behavior. Render a
file with `xml.renderFile(path, data, ns)`. See [XML syntax](xml-syntax.md)
for the complete supported tag list.

```xml
<Window title="Weather" width="900" height="620" minWidth="760" minHeight="520">
    <Toolbar>
        <ToolbarItem id="refresh" label="Refresh" icon="arrow.clockwise"
                     tooltip="Refresh weather" />
    </Toolbar>
</Window>
```

Use `ref="name"` on an XML element when the controller needs to attach a
callback or mutate the resulting native view after rendering.

## 4. Apply layout deliberately

- Stacks add sibling spacing, not outer margins.
- Use `padding` only when content needs separation from its container.
- Give primary tables `flexGrow = 1` and use `plain` or `fullWidth`.
- Use `sourceList` only for navigation sidebars.
- Use `inset` only for grouped/settings content.
- Let `NSSplitView` and native windows own pane geometry.
- Put window-wide actions in the toolbar and row actions near the row.
- Keep numeric layout values in a named table in the controller.

## 5. Make every state explicit

Implement loading, loaded, empty, error, selected, disabled, and long-text
states where the feature supports them. For tables, call `showLoading()` before
fetching and `hideLoading()` after rows are available. Do not add sleeps to
simulate progress.

## 6. iPhone Simulator

The same `apps/<app>/` and `test/<app>/` trees run on iOS. The Simulator host is a runtime;
Lua, templates, and assets stream from a Mac packager. After `make ios-run`,
a save reloads the running app **without quitting**:

```sh
make ios-run ARGS=demo/hello
```

Do not copy Lua into the `.app`. Do not rebuild the host because a view or
asset changed. See [iOS host and hot reload](../ios.md).

## 7. Validate before handoff

```sh
make test
./lua-objc --dump-layout=/tmp/layout.xml apps/weather/init.lua
rg -n 'cropped="true"|outsideParent="true"|contentClipped="true"' /tmp/layout.xml
./lua-objc --screenshot=/tmp/weather.png apps/weather/init.lua
```

For visual changes, inspect small and large window sizes plus light and dark
appearances. Add a fast `tests/*.test.lua` regression test for every behavior
change. Tests must run headlessly, without windows or pauses.
