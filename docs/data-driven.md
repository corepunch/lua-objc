# Data-driven apps

An app is described in XML — its pages, its views and its constants — and a page
is a request: the framework asks the page for data and renders the view with it.
There are no bindings and no notifications. A view is etlua over plain data
(`<%= summary %>`, loops, partials); an action is a method of the page, followed by
the same request again, like a form post and the page it shows next. Lua is left for
what is logic: models that query and change the app's data, routes that turn it into
pages, and flows of action code several pages share.

The data layer follows [Lapis](https://leafo.net/lapis/reference.html): a model is a
table of rows (`Model:extend`), a page is a route, and shared action code is a flow.
WPF is the reference for XML names (`App.xaml` for the manifest,
`ResourceDictionary` for resources).

XML is preferred wherever possible because it is data: it can be validated and it
cannot open a file or a socket. etlua templates are Lua, so they render in a
sandbox (below).

| Piece | File | Module |
|---|---|---|
| App manifest | `app.xml` | `lua/data/manifest.lua`, `lua/data/app.lua` |
| Store (the app's data) | `Store.lua` | `lua/data/model.lua` |
| Models | `models/*.lua` | `lua/data/model.lua` |
| Routes (pages) | `routes.lua`, `pages/*.lua` | `lua/data/routes.lua` |
| Flows | `flows/*.lua` | `lua/data/flow.lua` |
| Views | `views/**/*.etlua` | `lua/ui/xml.lua` |
| Resources | `resources.xml`, `<Resources>` | `lua/ui/resources.lua` |
| Generic page controller | — | `lua/data/pagecontroller.lua` |

`demo/storage` is the reference app: a manifest with two pages, two models over a
seeded store, two routes and no controller class. `./lua-objc demo/storage/init.lua
--page=settings --isolated` plays one page alone.

## The store

The store is plain Lua data, the app's database: named tables of rows and whatever
else the app keeps (`home`, the running scan). `Store.lua` beside `app.xml` returns a
function that builds it; the launcher binds a fresh store at each launch, as Lapis
connects to its database.

```lua
-- demo/storage/Store.lua
return function()
	return {
		folders = {{name = "Developer", bytes = 56.4e9}, {name = "Music", bytes = 21.1e9}},
		settings = {{id = "device", deviceName = "My Mac", threshold = 0}},
	}
end
```

Every model reads the bound store, `Model.db`. An app with a root controller builds
and binds its own (`Model.bind(Store.new(home))`). Nothing observes it: a page asks
its models again each time it is drawn.

An app that shows two windows (Diskmap's opened scan beside this Mac) has a store per
window and binds the right one whenever a window's code runs. The page controller
binds its page's store before every request and action, when a menu item it
returned runs and when the page goes; `Model.bound(store, fn)` wraps a callback
that enters from outside (Diskmap's `Provider.bind` wraps every callback a window's
service calls back with). The window's own controller is the third way in (a drop,
the toolbar, the menu bar): Diskmap's root controller binds its store in every one
of its methods and menu commands, in one place at the end of `Controller.lua`.
Nothing else binds a store.

## Models

A model is one table of the store. `extend` returns the class, whose methods query
the table, and the metatable of its rows, whose methods a row answers:

```lua
-- demo/storage/models/Folders.lua
local Model = require("data.model")
local Settings = require("demo.storage.models.Settings")

local Folders, Folder = Model:extend("folders", {primaryKey = "name"})

function Folders:visible()                      -- a query
	local minimum = Settings:current():minimumBytes()
	return self:select(function(folder) return not folder.bytes or folder.bytes >= minimum end,
		{fields = {"name", "icon", size = "sizeText"}})
end

function Folder:sizeText()                      -- a row method
	return string.format("%.1f GB", self.bytes / 1e9)
end
```

- **Queries.** `all()`, `find(key | {field = value})`, `findAll(keys)`,
  `select(where, opts)` and `count(where)`. `where` is nil, a table of fields a row
  must equal, or a function of the row; `opts.order` is `"field"`, `"field desc"` or
  a comparator and `opts.limit` a count. Rows are the stored tables themselves, so
  a change to a row is a change to the store.
- **Plain rows for views.** Native lists read a row's own fields, never its methods.
  `opts.fields` turns rows into the plain tables a list or a template shows: names
  copy fields, `name = "method"` or `name = function(row)` computes one.
- **Changes.** `create(record)`, `row:update(fields)` and `row:delete()`.
  `constraints = {field = function(row, value) ... end}` validate a field on create
  and update: a returned message refuses the change, and nothing changes.
- **Relations.** `{"location", belongsTo = "locations"}`, `{"files", hasMany =
  "files", order = "bytes desc", where = {...}}`, `{"largest", hasOne = ...}` and
  `{"owner", fetch = function(row) ... end}` add row methods; keys default to the
  relation's name, or this table's singular name, plus `Id`.
- **A table that is not stored as one.** `source = function(db) ... end` computes
  the rows (Diskmap's installed applications are the catalog's `.app` locations).
- **Enums.** `Model.enum{"All", "Unused", "Most data"}` names a picker's positions:
  `filters[2]`, `filters:index("Unused")`.

A model owns its domain queries, validation and mutations and never touches `ns`.
Only models read the store. What only computes — formatting, parsers of a
service's output, the figures of a chart — is a helper module in `helpers/`: it is
pure, takes the rows and values it computes over as arguments, and requires no
model, no service and no `data.model`. A helper that needs to look a row up takes
the lookup as an argument (`Guide.presentation(query, Categories.measured)`). IO is
a service in `services/`, injected. `tests/diskmap_layers.test.lua` checks these
rules on Diskmap's source.

## Pages: routes

A page is a route: the view it draws, `data(self, state)` — the request, answering
the table the view reads — and a method per action of the view.

```lua
-- demo/storage/routes.lua
return {
	folders = {
		view = "Folders",
		data = function(self) return {lists = {folders = Folders:visible()}} end,
		rescan = function(self) self.scans = (self.scans or 0) + 1 end,
	},
	settings = {
		view = "Settings",
		before = function(self) self.settings = Settings:current() end,
		data = function(self) return {deviceName = self.settings.deviceName, thresholds = Settings.thresholds} end,
		setDeviceName = function(self, name) Routes.assert(self.settings:update({deviceName = name})) end,
	},
}
```

```xml
<!-- views/Folders.etlua -->
<Label text="<%= summary %>" />
<Button title="Scan Again" action="rescan" />
<List id="folders" ...> <Column id="name" /> </List>
```

- **Self.** `self` is the page built from its route the first time it is shown and
  kept while the app runs, so what a person chose there (a filter, a selection) is
  still there when they come back. `self.id` is the page id, `self.params` its
  manifest attributes, `self.app` the services the app hands its pages.
- **One route, many pages.** Pages that differ by an argument share a route and
  read it from `self.params`: `<Page id="music" route="workflow" workflow="music" />`.
- **Data.** `data(state)` returns the table the view reads, plus `page` (the
  manifest entry) and `actions`. Rows for native tables go in `lists = {id = rows}`:
  they are set on the `<List id>` of that name (`replaceRows`), not copied into the
  template, and a table reuses its cells however many rows there are. `texts`,
  `hidden` and `disabled` set a node's text, visibility and enabled state by id;
  `handlers = {name = function}` are actions the view cannot name in advance (a
  button per row).
- **Actions.** Any `action="name"`/`onChange="name"` in the view is the page's method
  of that name. After it runs the page is requested again; a method that only reads
  (a row's menu, a reveal) lists itself in `queries = {name = true}`.
- **Refusals.** `Routes.fail(message)` or `Routes.assert(value, message)` (Lapis'
  `yield_error` and `assert_error`) stop an action; the page is drawn again with
  `errors = {message}` in its data for the view to show. `Routes.assert(row:update{...})`
  turns a constraint's message into one. Any other error is a bug and propagates.
- **Hooks.** `init` runs once when the page is built (its own tables), `before`
  before every request and action (look up what the params name), `activate` when
  the page appears and `deactivate` when it goes (start and cancel a service request),
  `rendered(refs)` after a draw. Work that finishes later asks the app to draw again;
  nothing observes the page.
- **Shared behaviour.** A route inherits another with `Routes.extend(base, route)`
  (Diskmap's list pages extend `pages/ListRoute.lua`). An app's routes are one
  module; `Routes.include(...)` gathers route files, as Lapis includes
  sub-applications.

The template is retained: unchanged data costs nothing, changed data reconciles the
views that exist, and updates made inside `ns.withAnimation` animate. Only what must
change while work is in progress is updated in place, by code written for that case —
Diskmap's chart while a scan counts — and every list, bar and number is drawn once
its data is computed.

## Flows

A flow is action code several pages share (Lapis' Flow). It wraps a page and reads
the page's fields as its own:

```lua
local Flow = require("data.flow")
local Rows = Flow:extend()

function Rows:resource(id)           -- self.app, self.params: the page's
	return {{title = "Show in Finder", action = function() self.app.service.reveal(id) end}}
end

-- in a route
rowMenu = function(self, _, _, row) return self:flow("Rows"):resource(row.id) end
```

`self:flow(name)` finds `flows/<name>.lua` of the page's app. What a flow assigns
stays on the flow unless the flow class sets `exposeAssigns`. A flow can wrap any
table with the fields it reads (`Rows({app = context})` for the window itself).

## Table cells

A `<Column>` takes no child XML and attributes have no binding syntax. A cell is
one of the table's native kinds, chosen by key attributes that name row fields
(`subtitleKey`, `imageKey`, `loadingKey`, `levelKey` with `valueKey` for a meter,
`lines` for wrapping text). A composed string is a row field the route prepares.
See "Cells are native kinds" in `docs/tableview_swiftui.md`.

## Resources

`<Resources>` declares `Number`, `String`, `Bool` and `Color` constants;
`attr="@name"` takes the value, resolved once when the template renders. An app's
`resources.xml` applies everywhere (passed to a render as `data.resources`; the page
controller does it); a `<Resources>` element scopes to its parent element (its own
attributes and its subtree) and overrides what it inherits. `@` is a reference only
where some resources are in scope; there an undeclared name is an error.

## The manifest

```xml
<App name="Storage" startup="folders">
  <Section title="Storage">
    <Page id="folders" title="Folders" icon="folder.fill" color="systemBlue" key="1" />
    <Page id="settings" title="Settings" icon="gearshape.fill" color="systemGray" key="2" />
  </Section>
</App>
```

`init.lua` returns the launch class built from the manifest
(`return require("data.app").launcher("demo/storage/app.xml")`). From the manifest
and `routes.lua` the framework builds the window, the sidebar, the Go menu and one
generic page controller per page, and binds the store `Store.lua` seeds. Every
manifest app accepts `--page=<id>` and `--isolated` (the page alone).

A page's route is its id unless it names one (`route="workflow"`); the view is the
route's. Other attributes stay in `page.attrs`, the route's `self.params`;
`sidebar="Dev tools"` is a shorter sidebar name (`title` is then the page header) and
`listed="false"` keeps a page out of the sidebar and the Go menu. `<App routes="pages">`
names another routes module. `<App controller="Controller">` names a root controller
that replaces the framework's launcher for an app that coordinates its whole window
(services, scanning, sheets); it still reads its pages, sidebar rows and Go menu from
the manifest and draws each page from its route — Diskmap is built this way.

## Controllers

The generic page controller owns mount, dispose and the request/render cycle. A
controller class is written only to coordinate — a window's services, sheets,
confirmation, multi-step flows; if a page needs a function to express behaviour, it
is a method of its route.

## Template sandbox

etlua templates run in an environment of the template data, the injected helpers
(`partial`, `extends`) and the pure functions `string`, `table`, `math`, `utf8`,
`ipairs`, `pairs`, `next`, `select`, `type`, `tostring`, `tonumber`, `pcall`,
`assert`, `error` and `unpack`. There is no `io`, `os`, `require`, `load` or `debug`:
a view gets what it shows from its page's data.
