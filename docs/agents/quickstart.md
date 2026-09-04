---
layout: default
title: Agent quickstart
---

# Agent quickstart

This page is an operating guide for an agent creating or changing a lua-objc
app. Read it before writing application code.

## 1. Choose the app shape

Create a folder under `examples/`:

```text
examples/weather/
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
return require("examples.weather.Controller")
```

Put network calls, sample data, formatting, and mutations in `Model.lua`. Keep
callbacks and view state in `Controller.lua`. Put reusable visual structure in
`views/*.etlua` or ordinary Lua component functions.

## 2. Start with native structure

Use a semantic window split when the app has navigation and primary content:

```lua
local ns = require("AppKit")
local xml = require("ui.xml")

local cfg = xml.renderFile("examples/weather/views/Window.etlua")
local sidebar = ns.VStack {
    ns.SearchField { placeholder = "Search", accessibilityLabel = "Search locations" },
    ns.List {
        style = "sourceList",
        header = false,
        flexGrow = 1,
        columns = {{ id = "name", title = "Location" }},
    },
}

return ns.Window {
    title = "Weather",
    sidebar = sidebar,
    content = ns.VStack { flexGrow = 1, ns.Text "Select a location" },
    sidebarWidth = 240,
    toolbar = cfg.toolbar,
}
```

The semantic sidebar owns its native appearance and split geometry. Do not
wrap it in a visual-effect material or manually set pane frames.

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

The same `examples/<app>/` tree runs on iOS. The Simulator host is a runtime;
Lua, templates, and assets stream from a Mac packager. After `make ios-run`,
a save reloads the running app **without quitting**:

```sh
make ios-run ARGS=examples/hello
```

Do not copy Lua into the `.app`. Do not rebuild the host because a view or
asset changed. See [iOS host and hot reload](../ios.md).

## 7. Validate before handoff

```sh
make test
./lua-objc --dump-layout=/tmp/layout.xml examples/weather/init.lua
rg -n 'cropped="true"|outsideParent="true"|contentClipped="true"' /tmp/layout.xml
./lua-objc --screenshot=/tmp/weather.png examples/weather/init.lua
```

For visual changes, inspect small and large window sizes plus light and dark
appearances. Add a fast `tests/*.test.lua` regression test for every behavior
change. Tests must run headlessly, without windows or pauses.
