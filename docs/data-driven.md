# Data-driven apps

An app is described in XML — its pages, its data schemas, its views and its
constants — and views bind to model fields by name. The framework supplies the
generic controller in between. Lua is left for what is logic: models that
compute, and the few controllers that coordinate a flow. WPF is the reference
for names and behaviour (`DataContext`, `Binding`, `StaticResource`,
`ICommand`, `App.xaml`).

XML is preferred wherever possible because it is data: it can be validated and
it cannot open a file or a socket. etlua templates are Lua, so they render in a
sandbox (below).

| Piece | File | Module |
|---|---|---|
| App manifest | `app.xml` | `lua/data/manifest.lua`, `lua/data/app.lua` |
| Schemas | `schemas/<Id>.xml` | `lua/data/schema.lua` |
| Resources | `resources.xml`, `<Resources>` | `lua/ui/resources.lua` |
| Views | `views/*.etlua` | `lua/ui/xml.lua` |
| Models and graph | `models/*.lua` | `lua/data/model.lua` |
| Generic controller | — | `lua/data/pagecontroller.lua`, `lua/data/binder.lua` |

`demo/storage` is the reference app: a manifest with two pages, a folder list
and a settings form, and no controller class. `./lua-objc demo/storage/init.lua
--page=settings --isolated` plays one page alone.

## Bindings

`attr="$field"` binds an attribute; `attr="field"` is the literal string and
`$$` a literal dollar sign. `$size.color` reaches into a field. An attribute is
a literal or exactly one `$path`: no negation, expression or interpolation.

- etlua (`<% %>`) runs once and decides structure; `$field` is live, set by the
  framework when the data changes without re-running the template.
- Conditions use attribute pairs: `visible` beside `hidden`, `enabled` beside
  `disabled`. A composed string is a schema field with `format`.
- Bindings work in a page (with a binder, below) and in `<Column>` cell
  templates (per row, applied natively so scrolling runs no Lua). Without a
  schema a path is read as written; with one, a binding to an undeclared field
  or to an attribute that is not bindable is an error when the template renders.

Bindable attributes are listed in `docs/tableview_swiftui.md` (“Row bindings”);
add one by extending `TAG_BINDINGS` in `lua/ui/xml.lua`.

### Data context

Every page has a context: its model, projected through its schema. A
`<List items="$rows">` gives each row its row as the context (and validates its
columns against the `<List>` field's `of` schema). `context="$lead"` narrows a
container to a `<Record>` field.

### Commands

`<Button action="$mark" />` dispatches the schema's `<Command id="mark">` to the
model (`model:mark()`), then the views rebind. The control follows the command's
`enabled` field (`enabled="markable"`: a model key), so a menu or button needs
no separate validator. `action="mark"` beside a command is a literal and an
error. Commands are page-level; cells do not bind them.

### Two-way binding

`<Toggle isOn="$history">`, `<TextField text="$query">`,
`<SearchField text="$query">` and `<Picker selection="$filter">` write back.
The schema marks the field `writable="true"`; binding a control two-way to any
other field is a render error. A write calls the model's `set<Field>` setter
(`setHistory(value)`); returning `false` refuses it. Either way the views are
set again, so a refused edit shows the model's value.

## Schemas

```xml
<Schema id="StorageRow" extends="Base">
  <String  id="name" />
  <Bytes   id="size" source="bytes" missing="Not measured">
    <State id="calculating" text="Calculating…" />
    <State id="denied" text="No access" icon="lock.fill" color="systemOrange" />
  </Bytes>
  <Percent id="share" source="relative" digits="0" below="&lt;1%" />
  <Date    id="lastUsed" style="relative" format="Used $value" />
  <String  id="accessibility" format="$name: $size $share" />
  <Bool    id="history" writable="true" />
  <Command id="mark" enabled="markable" />
  <List    id="rows" of="StorageRow" />
  <Record  id="lead" of="StorageRow" />
</Schema>
```

- **Type tags convert, `format` composes.** `<Bytes>`, `<Number>`, `<Percent>`
  and `<Date>` run on the system formatters (`src/shared/formatters.m`), so
  output follows the person's locale; `format` arranges already converted
  fields (`$name`, and `$value` for the field itself). Cycles are errors.
- **States belong to the type.** The model names the active state in
  `<source>State` (or `state="key"`); the field then shows the state's text and
  exposes `size.icon`, `size.color`, `size.state` and `size.calculating`.
- **Typed binding.** A text attribute reads the formatted string, a numeric
  attribute (`Gauge value`) the raw number (`$share` binds `share.value`).
- **Validation.** `schema:check(model)` fails a model that lacks a declared
  field, a command method or a setter. A field is optional with `optional`,
  `missing` or `format`. The model graph checks every model it builds.
- **Composition.** `extends` copies the base schema's fields first.

## Resources

`<Resources>` declares `Number`, `String`, `Bool` and `Color` constants;
`attr="@name"` takes the value, resolved once when the template renders. An app's
`resources.xml` applies everywhere; a `<Resources>` element scopes to its parent
element (its own attributes and subtree) and overrides what it inherits.

## Models and propagation

```lua
local Recommendations = Model.define({
	id = "cleanup", schema = "Recommendations",
	needs = {"scan", "applications", "simulatorPlan", "keep"},
})
function Recommendations.new(needs, services) ... end
```

A model declares its dependencies in its own file. The graph builds a page's
model and its dependencies transitively, in order; a cycle is an error naming
its path. Models are plain data and are not observed: whoever changes one calls
`graph:changed(id)`; the graph calls `invalidate` on each built dependent and
rebinds the pages bound to stale models (WPF's `PropertyChanged` with an empty
property name). Commands and accepted writes do this automatically. Animation
stays the caller's choice (`ns.withAnimation`).

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
(`return require("data.app").launcher("demo/storage/app.xml")`). From the manifest the framework builds the
window, the sidebar, the Go menu and one generic page controller per page. Every
manifest app accepts `--page=<id>` and `--isolated` (the page alone, building
only its models).

### Code-behind pages and a root controller

A `<Page>` with `controller=` may omit `view` and `model`: its controller owns
what it shows. Other attributes stay in `page.attrs` for the app
(`workflow="developer"`, `source="Largest"`); `sidebar="Dev tools"` is a shorter
sidebar name (`title` is then the page header) and `listed="false"` keeps a page
out of the sidebar and the Go menu. `<App controller="Controller">` names a root
controller that replaces the framework's launcher for an app that coordinates its
whole window (services, scanning, sheets); it still reads its pages, sidebar rows
and Go menu from the manifest. **Diskmap** is built this way: `apps/diskmap/app.xml`
lists its 24 pages and 6 sections; `NavigationController.destinations`, the Go
menu and the root controller's page table are all derived from it, and each page
is built by `Controller.new(context, entry)` from one shared context
(`model`, `service`, `actions`, `open`, `show`, `rescan`, `pages`, …). Pages that
only copy model values to views (the SDK sheet) bind through schemas; the others
are still hand-written controllers.

## Controllers

The generic page controller owns mount, dispose, staleness and command dispatch.
Write a class only for coordination — sheets, confirmation, multi-step flows,
chart interaction (WPF code-behind): `controller="SheetController"` names a
class in `controllers/` whose `new(context)` receives the generic controller as
`context.generic`. If a page needs a function to express behaviour, write a
controller; the generic one does not grow a configuration language. A
controller may also own a bound view directly, as `SdksController` does: it
renders `views/Sdks.etlua` with a `Binder` and `SdkList`, and starts discovery.

## Template sandbox

etlua templates run in an environment of the template data, the injected
helpers (`partial`, `extends`) and the pure functions `string`, `table`,
`math`, `utf8`, `ipairs`, `pairs`, `next`, `select`, `type`, `tostring`,
`tonumber`, `pcall`, `assert`, `error` and `unpack`. There is no `io`, `os`,
`require`, `load` or `debug`.
