# lua-objc agent guide

lua-objc exposes SwiftUI-like Lua APIs backed by real AppKit/UIKit controls.
It is a lightweight framework: Apple's frameworks do the work and an idle
app burns no CPU (see "A lightweight framework"). Most application work
belongs in `.lua`; native bridge work belongs in `src/`.

## Start here

Read only the material needed for the current task:

- [README.md](README.md) — commands and task-to-file map
- [ARCHITECTURE.md](ARCHITECTURE.md) — runtime layers, state lifetime, layout,
  plugins, and previews
- [docs/agents/application-architecture.md](docs/agents/application-architecture.md) — how an app is
  built: what goes where, with examples; folder structure; sidebar and
  tab-bar shapes
- [docs/agents/layout.md](docs/agents/layout.md) — page width (fill or
  readable), chart sizing, chart colors, how to verify a layout
- [src/README.md](src/README.md) — native bridge subsystem and symbol map
- [docs/PROJECT_REFERENCE.md](docs/PROJECT_REFERENCE.md) — detailed API and
  implementation reference; consult the relevant heading, not the whole file
- [docs/tableview_swiftui.md](docs/tableview_swiftui.md) — table behavior
- [docs/retained-templates.md](docs/retained-templates.md) — motion, retained
  template reconciliation and steady live updates
- [docs/reels.md](docs/reels.md) — making 3-D promo reels with Reel and
  SceneKit: captures, component motion, camera, traps, performance
- [docs/data-driven.md](docs/data-driven.md) — manifests, pages as requests over
  models, `@name` resources, the model graph
- [docs/components.md](docs/components.md) — components: new XML tags
  written as etlua templates, the bundled set, resolution
- [docs/scenekit.md](docs/scenekit.md) — `<SceneView>` 3-D scenes: scene
  records, reconciliation by id, per-frame poses, game architecture
- [docs/ios.md](docs/ios.md) — iPhone Simulator host, streamed Lua/assets,
  in-process reload (the host does not quit)
- [docs/research/XCODE_UI_ARCHITECTURE.md](docs/research/XCODE_UI_ARCHITECTURE.md)
  — research notes; only relevant to Xcode/IDE parity work
- [.agents/skills/lua-objc-hig/SKILL.md](.agents/skills/lua-objc-hig/SKILL.md) — Apple HIG adapted for lua-objc declarative UIs (use for design and review of screens)

Use `rg` before reading a large file. Typical entry points:

```sh
rg -n 'function_name|LuaClassName' src lua tests
rg -n '^### `Widget|WidgetName' docs/PROJECT_REFERENCE.md
```
