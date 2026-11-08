# Online data: Appwrite backend (design)

Status: agreed design, not implemented yet. The decisions taken are listed at
the end.

An app that keeps its data online declares it the way it declares local data:
a model is a table of rows. A model marked `remote` is a collection in an
[Appwrite](https://appwrite.io/docs) database, its rows are documents, and the
store holds the rows last read from it. The app author never creates a table
by hand: the models are the schema, and one command makes the database match.

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
	<!-- ours: the lua-objc project, a database per app -->
	<Backend provider="appwrite" />

	<!-- theirs: Appwrite Cloud or self-hosted -->
	<Backend provider="appwrite" endpoint="https://fra.cloud.appwrite.io/v1"
		project="69f1c06800389dc6a1a0" />
	...
</App>
```

No `<Backend>` means the store stays local, as today. `database` defaults to
the app's folder name.

- **Our project** is for development only: prototypes, demos, Lua Studio. No
  sign-up, nothing to configure; every app gets its own database in it. Its
  end-user accounts are shared by every app that uses it, which is fine while
  developing and wrong for anything people rely on.
- **Their project** is required for anything that ships. Only the endpoint and
  the project ID go in the manifest; both are public.

The device and release builds (`make ipad`, `make ipad-deploy`,
`make iphone-deploy` and the App Store packaging) refuse an app whose
`<Backend>` names no `project`, with a message that says to create one. The
simulator, `make run` and the streaming iOS host accept it.

An Appwrite API key (needed to create collections) never ships in an app and
never enters the repository. It lives in the Mac's Keychain and is used only
by the provisioning command, as the `asc` profile is.

### Whose rows these are

Every app opens an **anonymous session** at first launch
(`POST /account/sessions/anonymous`): data saves at once, with no sign-up
screen. Signing in later with email, a magic link or OAuth turns that same
account into a permanent one (`PATCH /account/email` on the anonymous account),
so the rows stay with the person. Signing out ends the session; the next launch
opens a new anonymous account.

The session secret is stored with the existing Keychain bridge
(`ns.credentials`, `src/shared/credentials.m`) under the account
`appwrite.<project>`, never in the store.

The sign-in sheet is a bundled etlua component (`lua/components/`), and the
account actions are a flow (`Flow:extend`) any page can call. An app that never
shows sign-in still works: its people simply stay anonymous on that device.

## Remote models

```lua
-- apps/notes/models/Notes.lua
local Model = require("data.model")
local Notes, Note = Model:extend("notes", {
	remote = "private",
	fields = {
		title = "string(255)",
		body = "string(100000)",
		done = "boolean",
		dueAt = "datetime",
		listId = "string(36)",
	},
	indexes = {{"listId", "dueAt"}},
	constraints = {
		title = function(_, title) if title:match("^%s*$") then return "A title is required" end end,
	},
	relations = {{"list", belongsTo = "lists"}},
})
```

- **Table → collection.** The table name is the collection ID (Appwrite
  accepts custom IDs of up to 36 characters).
- **`fields`** are Appwrite attributes: `string(n)`, `integer`, `float`,
  `boolean`, `datetime`, `email`, `url`, `enum(a|b|c)`; a trailing `[]` makes
  an array (`"string(32)[]"`). A field ending in `?` is optional; the others
  are required. A local model has no `fields` and keeps working as it does.
- **System fields.** `$id` reads as `id` (the primary key), `$createdAt` and
  `$updatedAt` as `createdAt` and `updatedAt`; the other `$` fields are not
  exposed.
- **Relations** stay ours: a `belongsTo` is a plain `listId` attribute, not an
  Appwrite relationship attribute. The models already follow them over the
  store.
- **`remote`** names who may read and write a row:

  | `remote` | collection | each document |
  |---|---|---|
  | `"private"` | create: `users` | read, update, delete: `user:<id>` |
  | `"shared"` | create: `users` | read: `users`; update, delete: `user:<id>` |
  | `"public"` | create: `users` | read: `any`; update, delete: `user:<id>` |

  Document security is on for every remote collection. Anything finer (teams,
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
			loading = state.loading, error = state.error}
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
  that match the query's `where` with the returned documents and requests the
  page again. Replacing, not merging by `id`, is what removes a document
  deleted on the server or by another device; rows that do not match `where`
  (another list, another page's query) are left alone. A query with
  `opts.after` loads the next window of the same `where` and appends to it
  instead. A failure leaves the rows as they were, sets `state.error` and
  requests the page again; the view shows it.
- `load` runs on mount and after each action of that page, nowhere else.
  Nothing polls and nothing listens: a page you are only looking at sends no
  requests and uses no CPU.

A table `<Column>` and every other view read the same store rows as before;
they do not know a row came from the network.

## Writing: change locally, then send

`create`, `row:update` and `row:delete` on a remote model:

1. run the constraints locally (nil, message as today; nothing is sent);
2. change the store at once, so the action's own page request shows it;
3. send the request (`createDocument`, `updateDocument`, `deleteDocument`).
   A new row's `id` is generated on the device (20 characters of
   `[a-z0-9]`), so the stored row and the document share it from the start;
4. on failure, undo the local change and request the page again with
   `state.error` set.

There is no offline queue and no conflict resolution: the server is the truth,
the last write wins, a write made offline fails and is undone. Adding a queue
is a separate decision with its own cost.

## Provisioning: the models are the schema

```sh
./lua-objc --appwrite-schema=build/notes.appwrite.json apps/notes/init.lua
appwrite push collections --config build/notes.appwrite.json
```

`--appwrite-schema` loads the app's models headlessly and writes the
[`appwrite.json`](https://appwrite.io/docs/tooling/command-line/collections)
that the official Appwrite CLI pushes: the database, one collection per remote
model, its attributes, indexes and collection permissions. The generated file
lives in `build/` and is not committed; the models are the source.

We do not write our own provisioning: Appwrite's CLI already creates,
changes and removes collections, as `asc` does for App Store Connect. The CLI
signs in with the developer's key from the Keychain.

Per the project rules there are no migrations. Removing or retyping a field
and pushing again makes the collection match the model; data in a removed
attribute is gone.

## Pieces

| Piece | File | What it does |
|---|---|---|
| HTTP (done) | `src/shared/lua_async.m` | `ns.http{method, url, headers, body}` → `done({status, headers, body})` or `done(nil, err)`, on AppKit and UIKit |
| Client | `lua/data/appwrite/client.lua` | endpoint, project header, session header, JSON, error shape |
| Queries | `lua/data/appwrite/query.lua` | ported from orca as is |
| Account | `lua/data/appwrite/account.lua` | anonymous session, sign in/up/out, upgrade, Keychain |
| Documents | `lua/data/appwrite/documents.lua` | list/create/update/delete, `$` field mapping, permissions |
| Schema | `lua/data/appwrite/schema.lua` | models → `appwrite.json` |
| Backend service | `lua/data/backend.lua` | runs a route's `load`, merges rows, sends writes, undoes failures |
| Model | `lua/data/model.lua` | `remote`, `fields`, `indexes`, `query()`; writes go through the backend |
| Manifest | `lua/data/manifest.lua` | `<Backend>` |
| Sign-in | `lua/components/SignIn.etlua`, a bundled flow | the sheet and its actions |

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

`demo/notes/` is the first app built on it and exercises it end to end:
headlessly against the mock transport, and by hand against our development
project (its `<Backend>` names no `project`).

It is a manifest app with no controller class: two remote models, `lists`
(`"private"`) and `notes` (`"private"`, `belongsTo` a list); a sidebar page
per list through one route reading `self.params`, whose `load` asks for that
list's notes; actions to add, rename, complete and delete a note; and the
bundled sign-in sheet in the toolbar. It covers every state the page has:
loading, empty, loaded, a failed load, a refused write that is undone, and
anonymous versus signed in. It is added to `tests/examples.test.lua`.

## Out of scope for now

- **Realtime.** A websocket that pushes other people's changes means a
  connection kept open while the page is visible and a page request per remote
  change. Worth it for chat-like apps; ask "are you sure?" when one needs it.
- **Offline writes** and conflict resolution.
- **Storage buckets** (files and images) and **Functions**.
- Teams, labels and role-based permissions.

## Decisions

- Our shared project is for development only; shipping builds require the
  app's own project (above).
- Remote rows are loaded by a route's `load` field, not inside `before`:
  `data` stays synchronous, and the page controller owns `state.loading` and
  `state.error` (see "Reading").
- A load replaces the store rows matching its `where`; it does not merge by
  `id`, so deletions made elsewhere show (see "Reading").
- The first app is a new `demo/notes/` (see "Tests").
