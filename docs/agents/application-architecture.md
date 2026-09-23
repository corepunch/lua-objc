---
layout: default
title: Application architecture
---

# Application architecture

lua-objc apps are ordinary Lua programs that describe their interfaces in
etlua templates and control real AppKit or UIKit widgets. A small app can use
one model and one controller. A larger app can compose feature controllers,
focused models, and injected services. Both shapes use the same entry point,
view rules, and native runtime.

The aim is clear ownership, not a prescribed number of files. Create a model,
controller, or service when it owns behavior; keep static data and markup
simple.

## How an app is assembled

```text
init.lua
   │ returns the root controller class
   ▼
Host creates the controller and calls createWindow()
   │
   ├── root controller creates the app's one window
   ├── feature controllers coordinate models and services
   └── controllers render etlua templates and connect actions
                    │
                    ▼
       ui.xml / ui.template → AppKit or UIKit controls
```

The app controller and its Lua state stay alive while the native window is
open. Controllers respond to selections, edits, navigation, and asynchronous
results over that lifetime; they are not recreated for each screen as in a
request/response web app.

## Choose the smallest useful structure

A small app usually starts here:

```text
apps/<app>/
  init.lua
  Model.lua             # optional when the app has domain state
  Controller.lua
  services/             # optional IO/runtime integrations
  views/
    Window.etlua
    Detail.etlua
    partials/            # optional reusable view fragments
```

When responsibilities become independent, group them by feature:

```text
apps/<app>/
  init.lua
  Controller.lua        # app startup and feature composition
  Model.lua             # optional shared domain state
  models/                # focused domain or presentation models
  controllers/           # feature-level coordinators
  services/              # injected IO and runtime integrations
  catalog/               # optional static domain data
  views/                 # all screen templates and partials
```

Folders such as `catalog/` are optional; use names that describe the app's
domain. Do not create a controller for every template or a model for every
piece of static display data. A static view can remain a partial. Split a
feature when it has its own state, domain rules, IO, callbacks, or lifecycle.

## Responsibilities

### Entry point and root controller

`init.lua` only requires and returns the root controller class:

```lua
return require("apps.example.Controller")
```

The host instantiates that class and calls `createWindow()`. The root
controller owns app startup, creates the one `ns.Window`, and composes the
top-level features. It coordinates across features when a user workflow
crosses their boundaries. `init.lua`, feature controllers, and view components
do not create windows.

### Feature controllers

A feature controller coordinates one cohesive user-facing flow. It can:

- query or mutate models and call injected services;
- prepare plain data for templates;
- render templates and keep returned refs for native callbacks;
- connect template actions to controller methods;
- update native controls or navigate when the user acts.

It does not construct `ns.VStack`, `ns.Button`, or other view trees. The XML
renderer is the application layer that maps template tags to native controls.

### Models

Models own domain data, queries, validation, formatting, and mutations. They
use plain Lua and do not depend on `ns`, native views, or `ui.xml`. Use module
tables for simple stateless queries or instances when each app/session needs
separate state. Inject dependencies rather than reading global app state.

### Services

Services isolate platform or runtime work such as filesystem access, scanning,
persistence, networking, or an embedded interpreter. Inject them into the
controller or model that needs them. Services keep IO out of domain models and
make feature behavior easier to exercise with fakes.

### Views

All app presentation lives in `.etlua` templates under `views/`. Templates
describe the complete native view branch using the shared XML vocabulary.
Reusable structure belongs in partials; repeated siblings belong in etlua
loops. Templates receive presentation data and action callbacks, not models or
services.

## Rendering and updates

Use `xml.renderFile(path, data, ns)` for a one-time render. It returns a native
view or window configuration plus a `refs` table for named `ref="..."`
elements. The injected `ns` selects AppKit or UIKit; templates using shared
tags do not need platform conditionals.

For a template mounted in a host container and updated over time, use
`ui.template`:

```lua
local Template = require("ui.template")

local page = Template.new(host, "apps/example/views/Results.etlua", ns)
local view, refs = page:update(data)
-- Later, after app state changes:
page:update(nextData)
-- When the mounted screen ends:
page:dispose()
```

An unchanged template and data keep the mounted native view and refresh its
actions. Changed template data renders a new branch and replaces the mounted
subtree, disposing the old branch's scope. This is an explicit retained
template boundary, not automatic model observation or keyed diffing: the
controller decides when to call `update`.

Use `ref` for the small amount of imperative wiring that native widgets need.
Pass action functions in the template data's `actions` table and refer to them
by name in template attributes such as `action="save"`. Keep callbacks and
native refs in controllers, not models.

## Ownership and screen lifetime

Lua controllers and models own app state; native containers own their mounted
views and geometry. A Lua handle retains its native object, so dropping a
variable does not necessarily remove a view from its parent. Avoid storing
native handles in models.

Callbacks, timers, watchers, and requests need deterministic cleanup. Use
`ns.Scope` to bind these resources to the window or screen that owns them, then
dispose the scope when that owner ends or is replaced. A callback can retain a
controller that retains its view; relying on garbage collection alone does
not break that cycle. See [runtime ownership](https://github.com/corepunch/lua-objc/blob/main/ARCHITECTURE.md#object-and-state-ownership)
for the native lifetime details.

## Examples in this repository

- [Adventure Arena](https://github.com/corepunch/lua-objc/tree/main/apps/adventure-arena)
  separates catalog and session models, library and session controllers, and
  the ZIL runtime service. It is a compact example of composed MVC.
- [Diskmap](https://github.com/corepunch/lua-objc/tree/main/apps/diskmap)
  composes controllers for scanning, categories, cleanup, inspection, and
  settings. It shows the domain-heavy form of the pattern.
- [Studio](https://github.com/corepunch/lua-objc/tree/main/apps/studio)
  composes pane controllers and uses `Window.etlua` to assemble the workspace.
  Some panes are visual placeholders; promote them to independent models and
  controllers as they gain behavior.

## Testing boundary

Test model rules and mutations with plain Lua data. Test controllers with fake
services and callbacks where useful. Exercise etlua rendering through the
headless UI tests. For visual changes, inspect the real app at smaller and
larger window sizes, in light and dark appearances, and across relevant empty,
loading, error, selected, disabled, and long-text states. Use screenshots or
layout dumps when geometry or clipping is involved.

## Keep these boundaries

- Do not build view trees in controllers or models; put them in etlua.
- Do not pass `ns` or native handles into domain models.
- Do not let feature controllers create windows.
- Do not add a layer that only forwards calls or stores static data without
  owning behavior.
- Do not imitate native controls with labels, emoji, drawing, or custom
  shadows; use the platform controls and semantic system styling.
- When a shared control or layout behavior is missing, improve the framework
  instead of adding an app-specific workaround.

For the full widget and XML contracts, see the
[project reference](../PROJECT_REFERENCE.md). For runtime layers and native
ownership, see the [repository architecture](https://github.com/corepunch/lua-objc/blob/main/ARCHITECTURE.md).
