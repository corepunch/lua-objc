# Data-driven apps

An app is described in XML — its pages, its views and its constants — and a page
is a request: the framework asks the page's model for data and renders the view
with it. There are no bindings and no notifications. A view is etlua over plain
data (`<%= summary %>`, loops, partials); an action is a method of the model,
followed by the same request again, like a form post and the page it shows next.
Lua is left for what is logic: models that compute, and the few controllers that
coordinate a flow. WPF is the reference for names (`App.xaml` for the manifest,
`ResourceDictionary` for resources).

XML is preferred wherever possible because it is data: it can be validated and it
cannot open a file or a socket. etlua templates are Lua, so they render in a
sandbox (below).

| Piece | File | Module |
|---|---|---|
| App manifest | `app.xml` | `lua/data/manifest.lua`, `lua/data/app.lua` |
| Resources | `resources.xml`, `<Resources>` | `lua/ui/resources.lua` |
| Views | `views/*.etlua` | `lua/ui/xml.lua` |
| Models | `models/*.lua` | `lua/data/model.lua` |
| Generic page controller | — | `lua/data/pagecontroller.lua` |

`demo/storage` is the reference app: a manifest with two pages, a folder list and a
settings form, and no controller class. `./lua-objc demo/storage/init.lua
--page=settings --isolated` plays one page alone.

## Pages

```xml
<Page id="folders" title="Folders" icon="folder.fill" color="systemBlue"
      key="1" view="Folders" model="folders" />
```

```lua
-- models/Folders.lua
local Folders = Model.define({id = "folders", needs = {"settings"}})
function Folders:data(state)               -- the request
	return {summary = "6 folders", lists = {folders = self:rows()}}
end
function Folders:rescan() ... end          -- an action: run, then the request again
```

```xml
<!-- views/Folders.etlua -->
<Label text="<%= summary %>" />
<Button title="Scan Again" action="rescan" />
<List id="folders" ...> <Column id="name" /> </List>
```

- **Data.** `model:data(state)` returns the table the view reads, plus `page` (the
  manifest entry) and `actions`. Rows for native tables go in `lists = {id = rows}`:
  they are set on the `<List id>` of that name (`replaceRows`), not copied into the
  template, and a table reuses its cells however many rows there are.
- **Actions.** Any `action="name"`/`onChange="name"` in the view is the model's
  method of that name. After it runs the page is requested again; a method that only
  reads (a row's menu, a reveal) lists itself in `Model.queries = {name = true}`.
  The template is retained: unchanged data costs nothing, changed data reconciles
  the views that exist, and updates made inside `ns.withAnimation` animate.
- **Lifecycle.** `activate()` runs after the page appears and `deactivate()` when it
  goes (start and cancel a service request). Work that finishes later asks the app
  to draw again (`services.refresh()`); nothing observes the model.
- **Live parts.** Only what must change while the model is busy is updated in place,
  by code written for that case — Diskmap's chart while a scan counts — and every
  list, bar and number is drawn once its data is computed.

## Table cells

A `<Column>` takes no child XML and attributes have no binding syntax. A cell is
one of the table's native kinds, chosen by key attributes that name row fields
(`subtitleKey`, `imageKey`, `loadingKey`, `levelKey` with `valueKey` for a meter,
`lines` for wrapping text). A composed string is a row field the model prepares.
See "Cells are native kinds" in `docs/tableview_swiftui.md`.

## Resources

`<Resources>` declares `Number`, `String`, `Bool` and `Color` constants;
`attr="@name"` takes the value, resolved once when the template renders. An app's
`resources.xml` applies everywhere (passed to a render as `data.resources`; the page
controller does it); a `<Resources>` element scopes to its parent element (its own
attributes and its subtree) and overrides what it inherits. `@` is a reference only
where some resources are in scope; there an undeclared name is an error.

## Models

```lua
local Recommendations = Model.define({
	id = "cleanup",
	needs = {"scan", "applications", "simulatorPlan", "keep"},
})
function Recommendations.new(needs, services) ... end
```

A model declares its dependencies in its own file. The graph builds a page's model
and its dependencies transitively, in order, and nothing else; a cycle is an error
naming its path. Models are plain Lua data that computes and never touch `ns`;
services (IO) are injected through the graph.

## The manifest

```xml
<App name="Storage" startup="folders">
  <Model id="settings" class="models.Settings" />
  <Section title="Storage">
    <Page id="folders" title="Folders" icon="folder.fill" color="systemBlue"
          key="1" view="Folders" model="folders" />
  </Section>
</App>
```

`init.lua` returns the launch class built from the manifest
(`return require("data.app").launcher("demo/storage/app.xml")`). From the manifest the
framework builds the window, the sidebar, the Go menu and one generic page
controller per page. Every manifest app accepts `--page=<id>` and `--isolated` (the
page alone, building only its models).

A `<Page>` with `controller=` may omit `view` and `model`: its controller owns what it
shows. Other attributes stay in `page.attrs` (`workflow="developer"`,
`source="Largest"`); `sidebar="Dev tools"` is a shorter sidebar name (`title` is then
the page header) and `listed="false"` keeps a page out of the sidebar and the Go menu.
`<App controller="Controller">` names a root controller that replaces the framework's
launcher for an app that coordinates its whole window (services, scanning, sheets); it
still reads its pages, sidebar rows and Go menu from the manifest — Diskmap is built
this way.

## Controllers

The generic page controller owns mount, dispose and the request/render cycle. Write a
class only for coordination — sheets, confirmation, multi-step flows, chart
interaction (WPF code-behind): `controller="SheetController"` names a class in
`controllers/` whose `new(context)` receives the generic controller as
`context.generic`. If a page needs a function to express behaviour, write a
controller; the generic one does not grow a configuration language.

## Template sandbox

etlua templates run in an environment of the template data, the injected helpers
(`partial`, `extends`) and the pure functions `string`, `table`, `math`, `utf8`,
`ipairs`, `pairs`, `next`, `select`, `type`, `tostring`, `tonumber`, `pcall`,
`assert`, `error` and `unpack`. There is no `io`, `os`, `require`, `load` or `debug`:
a view gets what it shows from its model's data.
