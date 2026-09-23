---
layout: default
title: lua-objc documentation
---

# lua-objc

Build native macOS and iOS interfaces with SwiftUI-style declarative Lua,
AppKit/UIKit controls, and no compile cycle for every UI change.

## Start here

- [Agent quickstart](agents/quickstart.md): the shortest path from an idea to a tested app.
- [Application architecture](agents/application-architecture.md): small-app MVC, feature composition, etlua rendering, and native lifetimes.
- [XML syntax](agents/xml-syntax.md): the supported etlua/XML tags and attributes.
- [Apple UI checklist](agents/apple-ui-checklist.md): design and accessibility rules for polished native apps.
- [Stocks app example](stocks_app_example.md): a complete Model/Controller/views example with a screenshot.
- [Weather app example](weather_app_example.md): async HTTP, loading, selection, and normalized API data.
- [Project reference](PROJECT_REFERENCE.md): detailed Lua API, bridge behavior, and layout contracts.
- [Component reference](reference/generated/index.md): one page per widget, generated from `---` docblocks in Lua sources (start with [Button](reference/generated/Button.md), [Text](reference/generated/Text.md), [VStack](reference/generated/VStack.md)).
- [Table behavior](tableview_swiftui.md): list sizing, styles, columns, and loading state.
- [iOS host and hot reload](ios.md): iPhone Simulator host, UIKit coverage, streamed Lua/assets, and in-process reload (the app does not quit).

## The core loop

1. Describe the view in Lua or an etlua template.
2. Run it: `./lua-objc apps/<app>` on macOS, or `make ios-run ARGS=apps/<app>` on the iPhone Simulator. Framework demos live under `demo/`; test harness apps live under `test/`.
3. On iOS, save a Lua/etlua/asset file; the running host reloads in place (no quit, no rebuild).
4. Exercise the behavior with a headless Lua test.
5. Inspect a screenshot or native layout dump when the change is visual.

The runtime uses real AppKit/UIKit controls. Use semantic system colors, SF
Symbols, native lists, native toolbars, and platform-owned containers instead of
simulating them with text or custom drawing.

## Repository layout

```text
apps/<app>/     product application
demo/<name>/     runnable framework demo
test/<name>/     runnable test harness
  init.lua        entry point; returns the controller class
  Model.lua       pure data and domain logic
  Controller.lua  screen coordination, actions, and template wiring
  views/          etlua/XML templates
```

## Build and test

```sh
make
make test
./lua-objc --screenshot=/tmp/app.png apps/stocks/init.lua
./lua-objc --dump-layout=/tmp/layout.xml apps/stocks/init.lua
```

Contributors are very welcome. See the repository README for contribution
paths and open an issue or pull request when you find a missing widget, unclear
API, design improvement, or documentation gap.
