# Documentation map

Open the narrowest document that answers the task:

- `index.md` — published documentation home and agent-facing entry point.
- `agents/quickstart.md` — step-by-step workflow for creating a tested app.
- `agents/xml-syntax.md` — XML/etlua tags and attributes from `lua/ui/xml.lua`.
- `agents/apple-ui-checklist.md` — native Apple UI, layout, accessibility, and
  visual QA checklist.
- `PROJECT_REFERENCE.md` — detailed AppKit API, UI requirements, conventions,
  build/test notes, and bridge rationale.
- `stocks_app_example.md` — a visual app example built in native AppKit with
  hot-reloadable Lua and XML layout, plus the recommended MVC structure.
- `weather_app_example.md` — async HTTP, native table loading, selection, XML
  detail views, and the framework gaps exposed by the example.
- `tableview_swiftui.md` — NSTableView sizing, scrolling, and style behavior.
- `ios.md` — iPhone Simulator host, UIKit coverage for AdventureArena-class
  apps, streamed Lua/assets, and in-process reload (the host does not quit).
- `research/XCODE_UI_ARCHITECTURE.md` — Xcode inspection notes for IDE parity
  work; this is research, not the lua-objc implementation contract.
- `archive/OFFSCREEN_CANVAS_PLAN.md` — historical implementation plan retained
  for decision context. The preview and watcher work described there is already
  implemented.

Current runtime architecture lives at the repository root in
`ARCHITECTURE.md`. Native symbol routing lives in `src/README.md`.

## Stocks app example

![Stocks app example](stocks-example.png)

This is the clearest proof that the stack can deliver a rich, native-feeling app
without a compile step: edit Lua, update XML, and rerun. The example sits in
`examples/stocks/` and demonstrates a production-style split between model,
controller, and declarative XML views.
