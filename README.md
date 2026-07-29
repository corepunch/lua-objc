# lua-objc

SwiftUI-like declarative UI written in Lua and rendered by native AppKit or
UIKit controls. Lua examples do not require recompilation; native bridge
changes do.

## Quick start

Requirements: macOS and Lua 5.4.

```sh
make
make test
make run ARGS="examples/hello.lua"
make run-ide
```

Render a script without opening a window:

```sh
./lua-objc --preview --width=800 --height=600 \
  --out=/tmp/preview.png examples/layout.lua
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

## Repository map

```text
src/                    native runtimes and bridges
  main.m                AppKit translation-unit root and module registration
  appkit/               focused AppKit bridge fragments included by main.m
  appkit/canvas_eval.m  isolated preview evaluation
  uikit/                focused UIKit bridge fragments
  shared/               state ownership, async services, common Lua errors
lua/embedded/           public declarative framework layers
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
