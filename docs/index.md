---
layout: default
title: lua-objc documentation
---

# lua-objc

Build native macOS and iOS interfaces with SwiftUI-style declarative Lua,
AppKit/UIKit controls, and no compile cycle for every UI change.

## Start here

- [Agent quickstart](agents/quickstart.md): the shortest path from an idea to a tested app.
- [XML syntax](agents/xml-syntax.md): the supported etlua/XML tags and attributes.
- [Apple UI checklist](agents/apple-ui-checklist.md): design and accessibility rules for polished native apps.
- [Stocks app example](stocks_app_example.md): a complete Model/Controller/views example with a screenshot.
- [Weather app example](weather_app_example.md): async HTTP, loading, selection, and normalized API data.
- [Project reference](PROJECT_REFERENCE.md): detailed Lua API, bridge behavior, and layout contracts.
- [Table behavior](tableview_swiftui.md): list sizing, styles, columns, and loading state.

## The core loop

1. Describe the view in Lua or an etlua template.
2. Run it directly with `./lua-objc examples/<app>`.
3. Exercise the behavior with a headless Lua test.
4. Inspect a screenshot or native layout dump when the change is visual.

The runtime uses real AppKit/UIKit controls. Use semantic system colors, SF
Symbols, native lists, native toolbars, and platform-owned containers instead of
simulating them with text or custom drawing.

## Repository layout

```text
examples/<app>/
  init.lua        entry point; returns the controller class
  Model.lua       pure data and domain logic
  Controller.lua  state, actions, and view composition
  views/          etlua/XML templates
```

## Build and test

```sh
make
make test
./lua-objc --screenshot=/tmp/app.png examples/stocks/init.lua
./lua-objc --dump-layout=/tmp/layout.xml examples/stocks/init.lua
```

Contributors are very welcome. See the repository README for contribution
paths and open an issue or pull request when you find a missing widget, unclear
API, design improvement, or documentation gap.
