---
layout: default
title: Application architecture
---

# Application architecture

## What lua-objc is

lua-objc is a lightweight way to write **native macOS and iOS apps in Lua**.
You describe screens as XML templates (etlua) and the framework turns them
into real AppKit or UIKit controls: `NSTableView`, `NSSplitView`,
`UITabBarController`, SF Symbols, system fonts and colors. It is not a web view
and not a second UI toolkit. Apple's frameworks scroll, animate, select and
focus; an idle app uses no CPU. There is no build step: save a file and the
running app reloads.

The shape of an app is Laravel's, not SwiftUI's:

| Laravel | lua-objc |
|---|---|
| Database | the **store**: plain Lua tables the app's data lives in (`Store.lua`) |
| Eloquent model | a **model**: one table of the store, queried and changed by methods (`models/`) |
| Route + controller action | a **route**: the page's `data(state)` and one method per action (`pages/`) |
| Blade template | an **etlua view** (`views/`) |
| Blade component | a **component**: a new XML tag written as etlua (`components/`) |
| Flow / service class | a **flow** (action code pages share, `flows/`) and a **service** (IO, `services/`) |

**A page is a request.** The framework asks the page's route for its data and
renders the view with it. An action in the view is a method of the route; after
it runs, the page is asked again. Nothing is bound, nothing observes anything,
no model notifies a view. A value reaches the screen only when etlua writes it
while rendering. Drawing again is cheap: pages are retained templates, so
unchanged data costs nothing and changed data updates the views that exist.

```text
                        ┌──────────── the app, kept alive while the window is open ───────────┐
 user taps ──► action ──┤ route method ──► models change the store ──► page asked again       │
                        │                                                │                    │
                        │      etlua view ◄── data(state) ◄──────────────┘                    │
                        └────────────────┬────────────────────────────────────────────────────┘
                                         ▼
                      ui.xml / ui.template → AppKit or UIKit controls
```

## Folder structure

Every app is one folder with `init.lua` as its entry point: products in
`apps/<name>/`, framework demos in `demo/<name>/`, test apps in `test/<name>/`.
Flat `apps/<name>.lua` files are forbidden. A small app is `init.lua`,
`Model.lua`, `Controller.lua` and `views/`; it grows into this:

```text
apps/<app>/
  init.lua          the entry point: one line, never starts anything
  app.xml           the manifest: sections and pages, each naming its route
  resources.xml     constants (numbers, strings, colors), referenced as @name
  Store.lua         the store's seed: the tables the models read
  routes.lua        gathers pages/*.lua into the app's routes
  Controller.lua    the root controller: window, menu, sheets (only if needed)

  models/           Lapis models, one per kind of row (stored or computed)
  pages/            routes: a view, data(state), and a method per action
  flows/            action code several pages share
  helpers/          pure computation and formatting over values given to it
  services/         IO and runtime integration, injected
  controllers/      coordination only: navigation, sheets, commands
  components/       new XML tags, each an etlua template (+ a .lua for its data)
  views/            etlua templates only, sorted like a web frontend:
    layouts/          the app shell: window, sidebar, content frame
    pages/            one template per screen
    sections/         large blocks a page composes (hero, decision, details)
    components/       small reusable partials (header, button row, tile)
    sheets/           modal dialogs and popovers
    <kind>/           a folder per other kind (topics/); no loose files
  catalog/ knowledge/ static domain data, named for the domain
```

A view name is a path under `views/` (`view = "pages/Overview"`). A partial
resolves relative to the including template:
`partial("../components/Footnote.etlua")`.

### What goes where

| If you are writing… | It belongs in | It may use | It must never |
|---|---|---|---|
| a table of rows, a query, a validation, a mutation | `models/` | `data.model`, other models | touch `ns`, files, or the network |
| a value computed from rows (a chart's figures, "3.2 GB") | `helpers/` | only its arguments | require a model, a service or the store |
| a screen: what it shows, what its buttons do | `pages/` (route) + `views/pages/` | models, flows, `self.app` | build views, touch `ns` |
| action code two pages share | `flows/` | models, `self.app` | know which page called it |
| reading a file, scanning a disk, HTTP, saving | `services/` | the platform | be required by a model |
| opening a sheet, a menu command, a drop, navigation | `controllers/` or the root controller | models, services, `ns.presentSheet` | construct `ns.VStack`, `ns.Button`… |
| a new visual building block | `components/` (etlua) | other tags | read the store, call a model |
| layout, text, buttons, lists | `views/**/*.etlua` | its data, `partial()` | `require`, `io`, `os` |
| a constant (width, color, label) | `resources.xml`, or `<Resources>` | — | live in a Lua table at the top of a template |

Only the entry point or the root controller creates the one `ns.Window`; a
component or a page that creates a window is wrong. `tests/app_architecture.test.lua`
and `tests/diskmap_layers.test.lua` enforce the layering from source.

## The pieces, with examples

### `init.lua`

```lua
return require("data.app").launcher("apps/diskmap/app.xml")
```

The framework calls `class.new():createWindow()` on what it returns. A manifest
app with no `Controller` attribute gets its window, sidebar, Go menu and one
generic page controller per page for free.

### `app.xml`: the manifest

```xml
<App name="Diskmap" startup="overview" controller="Controller">
  <Page id="overview" title="Overview" icon="chart.pie.fill" color="systemBlue" key="1" />
  <Section title="Developer">
    <Page id="music" route="workflow" title="Music" icon="pianokeys" workflow="music" />
    <Page id="video" route="workflow" title="Video" icon="film.fill" workflow="video" />
  </Section>
  <Page id="watched" title="Watched" listed="false" />
</App>
```

A page's route is its id unless it names one. Other attributes become the
route's `self.params`, so pages that differ by an argument are **one route**
(`route="workflow" workflow="music"`), never a class per page. `listed="false"`
keeps a page out of the sidebar. `controller="Controller"` names a root
controller for an app that coordinates its whole window.

### `Store.lua` and models

The store is plain data; models are the only code that reads it.

```lua
-- Store.lua
return function()
  return { folders = {{name = "Developer", bytes = 56.4e9}, {name = "Music", bytes = 21.1e9}} }
end
```

```lua
-- models/Folders.lua
local Model = require("data.model")
local Folders, Folder = Model:extend("folders", {primaryKey = "name"})

function Folders:visible()                 -- a query: a class method
  return self:select(function(f) return f.bytes >= 1e9 end, {order = "bytes desc"})
end
function Folder:sizeText()                 -- a row method
  return string.format("%.1f GB", self.bytes / 1e9)
end
return Folders
```

Few models, one per kind of row. A table computed from others is a model too
(`source = function(db) ... end`), as a database view is.

### Pages: routes and views

```lua
-- pages/Folders.lua
local Folders = require("apps.storage.models.Folders")
return {
  folders = {
    view = "pages/Folders",
    data = function(self) return { rows = Folders:visible(), scans = self.scans or 0 } end,
    rescan = function(self) self.scans = (self.scans or 0) + 1 end,   -- an action
  },
}
```

```xml
<!-- views/pages/Folders.etlua -->
<VStack>
  <Label text="<%= #rows %> folders, scanned <%= scans %>×" />
  <% for _, row in ipairs(rows) do %>
    <Label text="<%= row.name %>" />
  <% end %>
  <Button title="Scan Again" action="rescan" />
</VStack>
```

`routes.lua` gathers route files: `return Routes.include("apps.storage.pages.Folders", ...)`.
A route may also define `init`, `before`, `activate`/`deactivate`, `rendered(refs)`,
`queries = {name = true}` for actions that only read, and refuse an action with
`Routes.fail(message)`. Per-row buttons name their actions in the data
(`handlers = {open_1 = function() ... end}`).

### Flows

Action code several pages share, wrapping the page and reading its fields:

```lua
-- flows/Opening.lua (Adventure Arena)
local Opening = require("data.flow"):extend()
function Opening:game(id, origin)
  if not Adventures:find(id) then return false end
  self.app.focus(origin)                       -- self.app: the services the window hands pages
  self.app.push("detail", { id = id, origin = origin })
  return true
end
-- in any route:  self:flow("Opening"):game(game.id, "library")
```

### Components

A new tag is an etlua template beside a small module that computes its data:

```xml
<!-- components/SymbolRow.etlua -->
<HStack spacing="<%= symbol.gap %>" alignment="center">
  <SystemImage name="<%= name %>" width="<%= symbol.column %>" />
  <ContentPresenter />
</HStack>
```

```lua
-- components/SymbolRow.lua
local SYMBOL = {column = 26, gap = 10}
return {props = {name = "str"}, data = function() return {symbol = SYMBOL} end}
```

Views then write `<SymbolRow name="folder.fill"><Label text="Documents" /></SymbolRow>`.
See [components](../components.md).

### Controllers: coordination only

Write a controller only to coordinate: present a sheet, confirm a delete, route
a menu command, own a service that calls back. Diskmap's root `Controller.lua`
owns the window and delegates to `controllers/SheetController`,
`NavigationController`, `CommandsController`; every page is still a route.
Controllers never build views.

## Two shapes

**A sidebar app** (macOS; Diskmap, `demo/storage`): `app.xml` lists the pages,
the framework builds the window, sidebar and Go menu, and each page is drawn by
its route. The root controller is optional.

**A tab-bar app** (iOS; Adventure Arena): the tabs and navigation stacks are
an etlua layout (`views/layouts/Tabs.etlua`), so `app.xml` lists every page
with `listed="false"` and the root controller owns the window. Pages are still
routes: `controllers/PageHost.lua` draws each one, mounted in a tab or shelf
(`pages:mount("bookshelf", host)`) or pushed on a stack
(`pages:render("detail", {id = ...})`), and asks every mounted page again after
an action. Stateful, per-frame screens (the story reader) stay controllers.

```text
apps/adventure-arena/
  init.lua  app.xml  routes.lua  Store.lua  Controller.lua
  models/       Adventures SavedGames Session ReadingSettings Onboarding
  pages/        Discover Bookshelf Search Settings Detail Collection
  flows/        Opening
  controllers/  PageHost SessionController OnboardingController ReadingSettingsController
  services/     ZILRuntime JsonDocument CompassGesture
  views/        layouts/ pages/ sections/ sheets/ components/
```

## Rendering and updates

`xml.renderFile(path, data, ns)` renders once and returns the view and its
`refs` (views named with `id="..."`). `ui.template` mounts a retained template
into a host: `update(data)` reconciles, `dispose()` ends it. The injected `ns`
selects AppKit or UIKit; shared tags need no platform conditionals. Pass
actions in `data.actions` and name them in attributes (`action="save"`). Keep
callbacks and native refs out of models.

Callbacks, timers and watchers belong to `ns.Scope`, disposed when their owner
ends. Nothing redraws, polls or ticks on its own: a user action, a finished
async result or a controller setting a value is the only trigger.

## Testing

Every change ships fast headless tests (`tests/*.test.lua`, run by `make test`):
query models with plain data, call a route's `data` and actions through the page
host or generic controller, render views and inspect refs, and verify layout with
`./lua-objc --dump-layout`. `tests/adventure_arena_pages.test.lua` and
`tests/diskmap_pages.test.lua` are examples. For visual changes also check a
screenshot at small and large sizes, in light and dark, and in empty, loading,
error and long-text states.

## Examples in this repository

- [Diskmap](https://github.com/corepunch/lua-objc/tree/main/apps/diskmap):
  the reference for the sidebar shape, thirteen models, pages as routes, flows,
  components and sheets.
- [Adventure Arena](https://github.com/corepunch/lua-objc/tree/main/apps/adventure-arena):
  the reference for the tab-bar shape on iOS, with a ZIL interpreter as a service.
- [`demo/storage`](https://github.com/corepunch/lua-objc/tree/main/demo/storage):
  the smallest manifest app: two pages, two models, no controller.
- [Coin Quest](https://github.com/corepunch/lua-objc/tree/main/apps/coin-quest):
  a SceneKit game ([SceneKit scenes and games](../scenekit.md)).
- [Studio](https://github.com/corepunch/lua-objc/tree/main/apps/studio): pane controllers
  assembled by `Window.etlua`.

## Keep these boundaries

- No view trees in controllers, models, routes or flows: put them in etlua.
- No `ns` or native handles in models, routes, flows or helpers.
- No bindings, observers or notifications; a page is asked again.
- No compatibility layers: when the design changes, delete the old path.
- Do not imitate native controls; use the platform's. When a control or layout
  is missing, improve the framework instead of patching the app.

Reference: [data-driven apps](../data-driven.md), [components](../components.md),
[project reference](../PROJECT_REFERENCE.md), [runtime architecture](../../ARCHITECTURE.md).
