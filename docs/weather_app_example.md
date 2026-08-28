---
layout: default
title: Weather app example
---

# Weather app example

The weather example is a useful end-to-end reference because it combines a
native data table, asynchronous HTTP, loading state, selection, an XML detail
view, and a graceful offline/error path.

Run it with:

```sh
make run-weather
# or
./lua-objc examples/weather
```

The service is `wttr.in`; when the request fails, the app keeps its native table
usable and shows `--` or `unreachable` values instead of crashing.

The condition artwork lives in `examples/weather/assets/` as four original SVG
assets created for this example (`sunny.svg`, `cloudy.svg`, `rain.svg`, and
`snow.svg`). The requested Orca checkout was not present at the supplied local
path, so these are not copied or attributed as Orca assets.

![Weather app example](weather-example.png)

## App shape

```text
examples/weather/
  init.lua                  returns the controller class
  Model.lua                 city list and wttr.in response parsing
  Controller.lua            loading, rows, selection, and detail mounting
  views/Window.etlua        window configuration and Refresh toolbar item
  views/CityDetail.etlua   selected-city detail and forecast layout
```

`Model.lua` owns the network boundary. It returns a normalized city record with
stable keys such as `temp`, `cond`, `humid`, `wind`, and `forecast`, so the
controller and template do not need to understand the upstream JSON shape.

`Controller.lua` owns the native list and detail pane. It calls
`showLoading()` before the asynchronous fetch and `hideLoading()` afterward,
then replaces all rows in one operation. Selection calls `showDetail()` and
mounts the selected city into the detail container.

## Why the view is split between Lua and etlua

The stable visual structure belongs in `views/CityDetail.etlua`:

```etlua
<VStack flexGrow="1" padding="24" spacing="16" alignment="leading">
    <Label text="<%= city.city %>" size="24" weight="bold" />
    <HStack spacing="24" alignment="top">
        <Label text="<%= tostring(city.temp or "--") %>°C" size="32" />
        <Label text="<%= city.cond or "unreachable" %>" size="16" />
    </HStack>
</VStack>
```

The dynamic location list remains in `Controller.lua` because the current XML
registry can declare `List` and `Column`, but it cannot yet declare a row schema
with cell formatters, selection callbacks, or a runtime data source. That is a
framework documentation/API gap, not an application mistake. Until a schema
API exists, use this pattern:

The seven-day forecast is different: it is stable structure and therefore lives
in etlua. Its seven 100-point cards occupy 772 points, so the native
`ScrollView` keeps the cards readable and reveals a horizontal scroller when a
window is narrower than the forecast.
Open-Meteo supplies daily high/low, precipitation probability, wind, and UV values for the full week.

```lua
local list = ns.List {
    style = "sourceList",
    flexGrow = 1,
    columns = {
        { id = "city", title = "City", width = 150 },
        { id = "temp", title = "Temperature", width = 110, alignment = "right" },
    },
}
list:onRowSelect(function(_, _, row)
    controller:showDetail(controller.weatherData[row._id], row._id)
end)
list:replaceRows(rows)
```

## Agent checklist

- Keep the city list and response parsing in a headless model.
- Normalize incomplete API responses before rendering.
- Use `ns.async` for network work; do not block the window or add sleeps.
- Show the table's native loading spinner during fetches.
- Use `replaceRows()` for a completed batch of results.
- Keep primary data in a `fullWidth` or `plain` table.
- Use semantic system colors and native controls; do not use emoji weather icons
    as a substitute for a missing native image API. The example's local SVGs are
    explicit image assets loaded through the native `Image` view.
- Provide a selected, empty, loading, and unreachable state.
- Test with a stubbed `ns.fetch_json` so tests never depend on the network.

## Current framework gaps exposed by this example

1. **Declarative table row schemas:** XML can describe columns, but not typed
   row fields, cell secondary text, formatters, or selection behavior.
2. **Declarative async state:** templates do not currently bind directly to a
   loading/error/result state. Controllers own the state transition.
3. **Semantic weather/icon assets:** the XML registry has `Image` and
   `SystemImage`, but no weather-condition symbol mapping or remote image
   policy. The example intentionally uses text conditions.
4. **Cross-platform HTTP contract:** `fetch_json` is shared by the platform
   layers, but this example is currently demonstrated and tested on AppKit.

These gaps are documented so contributors can improve the framework without
making every application invent a different pattern.

## Test it

```sh
make test
./lua-objc tests/weather_controller.test.lua
```

The controller test stubs both `ns.async` and `ns.fetch_json`, verifies loading
lifecycle and row formatting, and runs without opening a window.
