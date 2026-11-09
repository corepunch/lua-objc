# Online data: Appwrite backend (design)

Status: agreed design, being built. Done: the HTTP request, the Appwrite
client (`lua/data/appwrite/`), remote model declarations with their
schema, `<Backend>`, the person's connected project with its tables created
at launch, the backend service that loads and writes remote rows, the account
page, `demo/cloud-notes`, Lua Studio's Settings for the connection, and the
check that refuses a connected project in builds that ship. Left: Lua
Studio's preview running apps that keep data online (it does not load the
data layer yet).
The "Pieces" table marks each step; the decisions taken are listed at the
end.

An app that keeps its data online declares it the way it declares local data:
a model is a table of rows. A model marked `remote` is a table in an
[Appwrite](https://appwrite.io/docs) TablesDB database and its rows are that
table's rows. Appwrite 1.8 names them as our models do
(`/tablesdb/{db}/tables/{table}/rows`), so this design uses TablesDB, not the
older Databases API of collections and documents. The store holds the rows last
read from it. The app author never creates a table by hand: the models are the
schema, and one command makes the database match.

The Lua client is ported from orca (`share/orca/plugins/appwrite/query.lua`,
`apps/chat/api/appwrite_auth.lua`, `apps/chat/api/orca_transport.lua`), keeping
its request shapes and dropping what is specific to Chat (push targets, the
`orca-chat-api` function envelope, avatars) and the hard-coded IDs.

## Two accounts, decided separately

"Whose account" means two different things:

1. **Where the database lives** — an Appwrite *project*. The developer's.
2. **Whose rows these are** — an Appwrite *Account* inside that project. The
   person using the app.

### Where the database lives

The manifest names the backend in one element; models do not change between
the choices.

```xml
<App name="Notes" startup="notes">
	<!-- the person's own, connected on the device; a database per app -->
	<Backend provider="appwrite" />

	<!-- theirs: Appwrite Cloud or self-hosted -->
	<Backend provider="appwrite" endpoint="https://fra.cloud.appwrite.io/v1"
		project="69f1c06800389dc6a1a0" />
	...
</App>
```

No `<Backend>` means the store stays local, as today. `database` defaults to
the app's folder name.

- **The connected project** is for development: prototypes, demos, Lua
  Studio. There is no project of ours. The person creates their own on
  [Appwrite Cloud](https://cloud.appwrite.io) (or their own server), makes an
  API key with read and write access to databases, tables, columns and
  indexes, and enters the endpoint, the project ID and the key once, as they
  enter the OpenRouter key: in Lua Studio's Settings, or on a Mac with
  `./lua-objc scripts/appwrite/connect.lua <endpoint> <project ID>` (the key is
  read from the input, not the command line). The three are one Keychain
  entry, `appwrite` (`lua/data/appwrite/connection.lua`). Every app gets its
  own database there, and at launch the app creates the database, tables,
  columns and indexes its models need and the project lacks
  (`lua/data/appwrite/provision.lua`): no CLI and no console step.
- **The app's own project** is required for anything that ships, whose people
  have no key. Only the endpoint and the project ID go in the manifest; both
  are public. Its tables are pushed with the Appwrite CLI.

The device and release builds (`make ipad`, `make ipad-deploy`,
`make iphone-deploy` and `make release-build`/`make release`) refuse an app
whose `<Backend>` names no `project`, with a message that says to name one
(`check_backend` in `scripts/ipad/bundle.py`, called for `SDK=iphoneos` and
by `scripts/release/release.py` for every platform). The simulator,
`make run` and the streaming iOS host accept it.

An Appwrite API key (needed to create tables) never ships in an app and
never enters the repository or the manifest. It lives in the device's
Keychain and is sent only by provisioning, over a client of its own: the rows
client carries the person's session and nothing else, so an app reads and
writes only what its signed-in person may. A host that runs code it does not
trust gives it `ns.appwriteConnection` instead of the Keychain, a function
returning the endpoint, the project and a `provision` that holds the key.

Provisioning only adds. A column whose type changed or that the models no
longer name stays as it is: changing or dropping one loses data, which is the
Appwrite CLI's job, asked for on purpose. Appwrite builds a new column in the
background, so after adding columns provisioning asks again every half second
(a one-shot timer, at most 60 times) until they are built, then creates the
indexes; a launch with nothing missing costs one request for the database and
two per table. A refused provisioning (a key without the scopes) is reported
on the page and the account opens all the same.

### Whose rows these are

Every app opens an **anonymous session** at first launch
(`POST /account/sessions/anonymous`): data saves at once, with no sign-up
screen. Registering later (an email and a password) turns that same account
into a permanent one (`PATCH /account/email` on the anonymous account), so the
rows stay with the person. Signing in to an account that already exists is a
move to that account: the anonymous one's rows stay behind with it. Signing
out ends the session; the next launch opens a new anonymous account. Magic
links and OAuth come later; they end in the same kind of session.

The session secret is stored with the existing Keychain bridge
(`ns.Credentials`, `src/shared/credentials.m`) under the account
`appwrite.<project>`, never in the store.

Account is a page, not a sheet: pages are requests, and a sheet would need a
controller class to coordinate it. The framework owns its route
(`require("data.account").route({view = "pages/Account"})` in `routes.lua`);
the app owns its view, as every page's view is the app's. The route checks the
email and the password length (8, Appwrite's minimum) before sending, keeps the
password only while it is typed, and calls the backend's `register`, `signIn`
and `signOut`, which loads wait for like writes. Signing in or out moves to
another account, so the remote rows leave the store and the pages load the new
account's; signing out opens a new anonymous session so the app keeps saving.
An app that never shows the page still works: its people stay anonymous on
that device.

## Remote models

```lua
-- apps/notes/models/Notes.lua
local Model = require("data.model")
local Notes, Note = Model:extend("notes", {
	remote = "private",
	fields = {
		title = "string(255)",
		body = "text?",
		done = {"boolean?", default = false},
		dueAt = "datetime?",
		listId = "string(36)",
	},
	indexes = {{"listId", "dueAt desc"}},
	constraints = {
		title = function(_, title) if title:match("^%s*$") then return "A title is required" end end,
	},
	relations = {{"list", belongsTo = "lists"}},
})
```

- **Table → table.** The model's table name is the Appwrite table ID (Appwrite
  accepts custom IDs of up to 36 characters).
- **`fields`** are Appwrite columns: `string(n)` (a `varchar` of n), `text`,
  `integer`, `float` (Appwrite's `double`), `boolean`, `datetime`, `email`,
  `url`, `enum(a|b|c)`; a trailing `[]` makes a list (`"string(32)[]"`). A
  field ending in `?` is optional; the others are required. The table form
  adds options: `{"integer?", min = 0, max = 3, default = 0}`. Appwrite's
  rules hold at declaration: a required column or a list has no default.
  Fields and indexes are parsed when the model is declared, so a mistake is
  an error at `require`. A local model has no `fields` and keeps working as it
  does; `fields` without `remote` is an error.
- **`indexes`** list columns, each `"name"` or `"name desc"`, and take
  `unique = true` or `fulltext = true` and a `key` (default
  `idx_<columns>`, at most 36 characters). `createdAt` and `updatedAt` may be
  indexed.
- **System fields.** `$id` reads as `id` (the primary key), `$createdAt` and
  `$updatedAt` as `createdAt` and `updatedAt`; the other `$` fields are not
  exposed.
- **Relations** stay ours: a `belongsTo` is a plain `listId` column, not an
  Appwrite relationship column. The models already follow them over the
  store.
- **`remote`** names who may read and write a row:

  | `remote` | table | each row |
  |---|---|---|
  | `"private"` | create: `users` | read, update, delete: `user:<id>` |
  | `"shared"` | create: `users` | read: `users`; update, delete: `user:<id>` |
  | `"public"` | create: `users` | read: `any`; update, delete: `user:<id>` |

  Row security is on for every remote table. Anything finer (teams,
  labels) is out of scope for now.

## Reading: the store is the cache

A page is still a request: `data(state)` is synchronous and reads the store.
The network sits in front of it, not inside it.

A route names the remote rows it needs; the page controller loads them before
it renders, and renders again when they arrive:

```lua
-- apps/notes/pages/notes.lua
return {
	load = function(self)
		return Notes:query({listId = self.params.list}, {order = "dueAt", limit = 100})
	end,
	data = function(self, state)
		return {notes = Notes:select({listId = self.params.list}, {order = "dueAt"}),
			loading = state.loading, failure = state.error}
	end,
}
```

- `Model:query(where, opts)` does not run anything: it returns a description
  of the request. `where` is a table of exact fields (each becomes an `equal`
  query); `opts.order`, `opts.limit` and `opts.after` (a cursor) map to
  `orderAsc`/`orderDesc`, `limit` and `cursorAfter`. A function `where` cannot
  be sent and is an error.
- The page controller runs the route's `load` through the backend service,
  renders once with `state.loading = true`, then **replaces** the store rows
  that match the query's `where` with the returned rows and requests the
  page again. Replacing, not merging by `id`, is what removes a row
  deleted on the server or by another device; rows that do not match `where`
  (another list, another page's query) are left alone. A query with
  `opts.after` loads the next window of the same `where` and appends to it
  instead. A failure leaves the rows as they were, sets `state.error` and
  requests the page again; the view shows it.
- `load` runs on mount and after each action of that page, nowhere else.
  Nothing polls and nothing listens: a page you are only looking at sends no
  requests and uses no CPU.
- A load waits until every write sent has answered: one that overtook a
  create would replace the new row away. Loads also wait for the account at
  launch; offline they run anyway and report it.
- Name the message something other than `error` in template data: a view
  that tests `<% if error %>` finds Lua's `error` function when the page has
  none, and is always true.

A table `<Column>` and every other view read the same store rows as before;
they do not know a row came from the network.

## Writing: change locally, then send

`create`, `row:update` and `row:delete` on a remote model:

1. run the constraints locally (nil, message as today; nothing is sent);
2. change the store at once, so the action's own page request shows it;
3. send the request (`createRow`, `updateRow`, `deleteRow`).
   A new row's `id` is generated on the device (20 characters of
   `[a-z0-9]`), so the stored row and the Appwrite row share it from the start;
4. on failure, undo the local change (a created row leaves, an update's
   fields take their old values, a deleted row returns to its place) and
   request the page again with `state.error` set. A write's message stays
   until the next action; a delete of a row the server no longer has counts
   as done. Without a signed-in user (offline at launch) a create is undone
   at once.

There is no offline queue and no conflict resolution: the server is the truth,
the last write wins, a write made offline fails and is undone. Adding a queue
is a separate decision with its own cost.

## Provisioning: the models are the schema

For the connected project the app provisions itself at launch (above). For
an app's own project:

```sh
./lua-objc scripts/appwrite/schema.lua demo/cloud-notes build/cloud-notes.appwrite.json
appwrite push tables --config build/cloud-notes.appwrite.json
```

`scripts/appwrite/schema.lua` reads the project, endpoint and database from
the app's `<Backend>` (or the connected project when it names none), loads every model in its `models/` folder headlessly
and writes the
[`appwrite.json`](https://appwrite.io/docs/tooling/command-line/tables)
that the official Appwrite CLI pushes: the database, one table per remote
model, its columns, indexes and table permissions. The generated file
lives in `build/` and is not committed; the models are the source.

We do not write our own provisioning: Appwrite's CLI already creates,
changes and removes tables, as `asc` does for App Store Connect. The CLI
signs in with the developer's own credentials.

Per the project rules there are no migrations. Removing or retyping a field
and pushing again makes the table match the model; data in a removed
column is gone.

## Pieces

| Piece | File | What it does |
|---|---|---|
| HTTP (done) | `src/shared/lua_async.m` | `ns.http{method, url, headers, body}` → `done({status, headers, body})` or `done(nil, err)`, on AppKit and UIKit |
| Client (done) | `lua/data/appwrite/client.lua` | endpoint, project header, credential, JSON, one error shape `{type, message, status}` |
| JSON (done) | `lua/data/appwrite/json.lua` | request bodies: empty objects and `null`, which the native encoder cannot write |
| Queries (done) | `lua/data/appwrite/query.lua` | ported from orca, camelCase (`Query.equal`, `Query.orderDesc`) |
| Account (done) | `lua/data/appwrite/account.lua` | anonymous start, stored session, register, sign in/out; the secret store is injected |
| Rows (done) | `lua/data/appwrite/rows.lua` | TablesDB list/create/update/delete, `$` field mapping, row IDs, permissions |
| Schema (done) | `lua/data/appwrite/schema.lua` | remote models → `appwrite.json`: one TablesDB database, a table per model, `create("users")`, row security |
| Backend service (done) | `lua/data/backend.lua` | runs a route's `load`, replaces rows, sends writes, undoes refused ones; built by the launcher (`App.backend`) and connected with `Model.connect` |
| Page controller (done) | `lua/data/pagecontroller.lua` | runs `load()` on mount and after actions; `state.loading`, `state.error` |
| Model (done) | `lua/data/model.lua` | `remote`, `fields`, `indexes` parsed into `columns` and `indexes`; `query()`; remote writes through the backend |
| Manifest (done) | `lua/data/manifest.lua` | `<Backend>` → `manifest.backend` `{provider, endpoint, project, database, connected}` |
| Connection (done) | `lua/data/appwrite/connection.lua` | the person's endpoint, project ID and API key in the Keychain entry `appwrite`; `scripts/appwrite/connect.lua` on a Mac, Settings in Lua Studio |
| Provisioning (done) | `lua/data/appwrite/provision.lua` | creates the missing database, tables, columns and indexes of the connected project at launch |
| Schema script (done) | `scripts/appwrite/schema.lua` | an app folder → its `appwrite.json` |
| Account page (done) | `lua/data/account.lua` | the route of an app's account page: register, sign in, sign out |
| Release check (done) | `scripts/ipad/bundle.py` `check_backend` | device and release builds refuse `<Backend>` without `project` |
| Studio preview (left) | `apps/studio/services/Preview.lua` | load the data layer and hand it `ns.appwriteConnection` and the session entries `appwrite.<project>` only |

### Native HTTP

Done. `ns.http{method, url, headers, body, timeout}` (native
`_httpRequest` in `src/shared/lua_async.m`) serves AppKit and UIKit: every
HTTP answer reaches `done` as `{status, headers, body}` with lowercase header
names and the body as bytes; no cookies or cache are kept, so the Appwrite
session header is the only credential a request carries. `ns.fetch` and
`fetch_json` are built on it, and the old `_httpGet` and UIKit-only
`_httpRequest`/`_cancelRequest` are gone. See "Lua API — HTTP" in
[PROJECT_REFERENCE.md](PROJECT_REFERENCE.md).

## Tests

All headless, with a mock transport that records requests and replies from a
table (the pattern of orca's `apps/chat/api/mock_transport.lua`):

- query encoding: `where`/`order`/`limit`/`after` → the exact `queries[n]=`
  strings; a function `where` is an error;
- `$id`/`$createdAt` mapping both ways; unknown `$` fields dropped;
- schema: a model with every field kind → the expected `appwrite.json`;
  `remote` → the permission table above;
- read: `load` → loading render → rows matching `where` replaced → second
  render; a row deleted on the server disappears; rows outside `where`
  untouched; `after` appends; failure → rows unchanged, `state.error`;
- write: create succeeds; create fails → row removed, error set; update fails →
  old values back; delete fails → row back in place;
- account: first launch opens an anonymous session and stores its secret;
  second launch reuses it; a 401 drops it and opens a new one; sign-out clears
  the Keychain entry.

`demo/cloud-notes/` is the first app built on it (`demo/notes/` is the
local three-column notes demo, unrelated) and exercises it end to end:
headlessly against the mock transport (`tests/cloud_notes.test.lua`), and by
hand against the connected project (its `<Backend>` names no `project`).

It is a manifest app with no controller class: one remote model, `notes`
(`"private"`, a `list` column); the lists are pages of `app.xml` (Inbox, Work,
Home) through one route reading `self.params.list`, whose `load` asks for that
list's notes; actions to add, complete and delete a note; and the Account
page. It covers loading, empty, loaded, a failed load, a refused write that is
undone, and anonymous, registered and signed in. It is in
`tests/examples.test.lua`.

Run by hand with a connected project, it creates its database and its
`notes` table there at launch, opens an anonymous session and keeps it in the
Keychain. Without a connection it does not start and says how to connect.
Enable anonymous sessions in the project's Auth settings (Appwrite Cloud has
them on by default).

## Out of scope for now

- **Realtime.** A websocket that pushes other people's changes means a
  connection kept open while the page is visible and a page request per remote
  change. Worth it for chat-like apps; ask "are you sure?" when one needs it.
- **Offline writes** and conflict resolution.
- **Storage buckets** (files and images) and **Functions**.
- Teams, labels and role-based permissions.

## Decisions

- There is no shared project of ours. Development saves to the person's own
  connected project, whose key creates the tables; shipping builds require
  the app's own project (above). An earlier shared "LuaStudio" project was
  removed for this.
- Remote rows are loaded by a route's `load` field, not inside `before`:
  `data` stays synchronous, and the page controller owns `state.loading` and
  `state.error` (see "Reading").
- A load replaces the store rows matching its `where`; it does not merge by
  `id`, so deletions made elsewhere show (see "Reading").
- The first app is `demo/cloud-notes/` (see "Tests"); the account is a page,
  not a sheet.
