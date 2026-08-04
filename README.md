# lua-objc

SwiftUI-like declarative UI written in Lua and rendered by native AppKit or
UIKit controls. Lua examples do not require recompilation; native bridge
changes do.

## Quick start

Requirements: macOS and Lua 5.4.

```sh
make
make test
make run ARGS="examples/hello"
make run-ide

# Or directly (directory path auto-discovers init.lua):
./lua-objc examples/hello
./lua-objc examples/mail
```

Render a script without opening a window:

```sh
./lua-objc --preview --width=800 --height=600 \
  --out=/tmp/preview.png examples/layout/init.lua

# Dump AppKit's computed native hierarchy, frames, and table-cell cropping.
./lua-objc --dump-layout=/tmp/layout.xml examples/stocks/init.lua
```

## Where to work

| Task | Start here |
|---|---|
| Maintain native framework `.m` code | `skills/maintain-lua-objc-framework/SKILL.md`, then `src/README.md` |
| Add or compose a Lua widget | `lua/embedded/AppKit.lua` |
| Add a macOS native bridge primitive | `src/README.md`, then the matching `src/appkit/*.m` fragment |
| Change flex layout | `src/appkit/layout.m` |
| Change lists or outlines | `src/appkit/table_data_source.m`, `src/appkit/outline_data_source.m`, `src/appkit/controls.m`, `src/appkit/outline.m`, `docs/tableview_swiftui.md` |
| Change async state ownership, HTTP, timers, or JSON | `src/shared/lua_async.m` |
| Change isolated canvas evaluation | `src/appkit/canvas_eval.m` |
| Change editor highlighting | `src/appkit/syntax_highlight.m` |
| Add an IDE editor surface | `examples/IDEKit/plugins/` |
| Write or modify XML view templates | `lua/ui/xml.lua`, `examples/<app>/views/` |
| Use template inheritance or partials | `views/AppWindow.etlua`, `views/partials/` |
| Work with view descriptions/diffing | `lua/ui/viewdesc.lua` |
| Add a new example app | `examples/<app>/init.lua`, `AGENTS.md` (MVP layout rules) |
| Change app startup or recents | `lua/App.lua`, `examples/IDEKit/app.lua` |
| Add UIKit coverage | `src/uikit/`, `src/uikit_module.m`, `lua/embedded/UIKit.lua` |
| Understand runtime ownership | `ARCHITECTURE.md` |
| Look up the Lua API or bridge rationale | `docs/PROJECT_REFERENCE.md` |
| Research Xcode parity | `docs/research/XCODE_UI_ARCHITECTURE.md` |

Search for the symbol you need instead of loading a whole subsystem:

```sh
rg -n 'bridge_tableview|List' src lua tests docs
```

## Runtime shape

```text
Lua script -> require("AppKit") -> build/AppKit.dylib -> AppKit objects
                                   native bridge +
                                   embedded AppKit.lua
```

`src/host.c` is a small loader. `build/AppKit.dylib` owns the Lua state, AppKit
bridge, layout engine, async services, and embedded declarative layer.
`IDEKit.dylib` and `UIKit.dylib` expose the corresponding embedded modules.

See [ARCHITECTURE.md](ARCHITECTURE.md) for lifecycle and ownership details.

## Template system

Templates use etlua (Lua embedded in XML) with cross-platform tags:

```xml
<Window title="My App" width="640" height="420">
    <VStack padding="24" spacing="12">
        <Label text="<%= greeting %>" size="24" weight="bold" />
        <Button title="Click me" />
    </VStack>
</Window>
```

Key features:

- **Cross-platform**: same template renders on AppKit (macOS) and UIKit (iOS)
- **Window config from XML**: `<Window>` and `<Toolbar>` tags define window properties
- **Template inheritance**: `extends()` / `block()` / `yield()` for layouts
- **Partials**: `partial()` for reusable components
- **View diffing**: `viewdesc` module for efficient updates (React-style)

```lua
-- Template inheritance
<% extends("views/AppWindow.etlua", { title = "Mail" }) %>
<% block("content", [[
    <HSplit>...</HSplit>
]]) %>

-- Partials
<%= partial("views/partials/SimpleList.etlua", { columns = {...} }) %>
```

## Repository map

```text
src/                    native runtimes and bridges
  main.m                AppKit translation-unit root and module registration
  appkit/               focused AppKit bridge fragments included by main.m
  appkit/canvas_eval.m  isolated preview evaluation
  uikit/                focused UIKit bridge fragments
  shared/               state ownership, async services, common Lua errors
lua/embedded/           public declarative framework layers
lua/ui/                 cross-platform XML template renderer
lua/vendor/             vendored Lua libraries (etlua submodule)
lua/App.lua             app lifecycle and recent-item persistence
examples/               runnable Lua applications
tests/                  headless Lua integration tests
docs/                   detailed, opt-in reference material
```

## Documentation policy

`AGENTS.md` is deliberately short because it is loaded on every agent task.
Put durable explanations in the focused documents above and link to them from
the task map. Do not copy complete API references or research notes back into
the root instructions.
