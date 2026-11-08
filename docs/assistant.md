# Assistant: asking an app in plain words (design)

Status: proposal, not agreed and not implemented. The open decisions are
listed at the end.

A person should be able to type "who owes us more than fifty thousand" or
"close March" into an app and get the rows or the action they meant. This
document proposes how lua-objc does that without a hand-built language
parser and without a character on screen. An app declares what it can do
as typed **intents**. Three front ends use them: the Help menu search
AppKit already ships, a command palette, and Apple's on-device language
model. Whichever one reads the request, it can only pick from the app's
intents, and the app validates and runs what was picked.

## Prior art: Ledger's assistant in orion-ui

orion-ui (`corepunch/orion-ui`, `apps/ledger/share/addons/assistant/`) has a
working local assistant for the Ledger accounting app. It has three layers,
and we keep only one of them.

| Layer | Ledger | Here |
|---|---|---|
| Character | Clippy, 43 animated clips, an Office 97 balloon | **Dropped.** It is a drawn imitation of a control, and its idle animations need a timer, so an idle app would not use 0% CPU. |
| Grammar | A verb/noun/qualifier parser modelled on zilscript; vocabularies, inflection tables and number words for en/de/ru; one unknown word rejects the command; topic words as a fallback | **Dropped.** Every app would need its own vocabulary in every language, and it still breaks on wording nobody wrote down. A language model handles wording; the parser stays in `apps/adventure-arena`, where the parser is the game. |
| Typed layer | Commands, filters and sorting over real models; menu command search; the Home page's checks as suggestions; `ledger.settle(id)`; input never evaluated as Lua | **Kept**, as intents declared next to the routes that already implement them. |

Ledger's other good ideas are kept too. Follow-up requests refine the last
result ("only posted ones", "open the first"). Results are rows that open
the record they show. The app's own checks are offered as suggestions, and
choosing one does what the check offers.

## Intents

An intent is a route action or query with a name, a sentence describing it,
and typed parameters. It is declared in the manifest, next to the page whose
route implements it, so the declaration is data and the behaviour stays the
route method it already is:

```xml
<App name="Ledger" startup="home">
	<Section title="Books">
		<Page id="customers" title="Customers" icon="person.2.fill">
			<Intent action="search" summary="Find customers, optionally by debt">
				<Parameter name="name" type="String" optional="true" />
				<Parameter name="minimumDebt" type="Number" optional="true" />
				<Parameter name="sort" type="Choice" values="name debt" optional="true" />
			</Intent>
		</Page>
		<Page id="closing" title="Month Closing" icon="calendar">
			<Intent action="close" summary="Close an accounting month">
				<Parameter name="month" type="Month" />
			</Intent>
		</Page>
	</Section>
</App>
```

```lua
-- routes.lua: the methods the intents name are ordinary route methods
customers = {
	view = "pages/Customers",
	queries = {search = true},
	search = function(self, args)
		return {rows = Customers:search(args), open = "customer"}
	end,
},
closing = {
	view = "pages/Closing",
	close = function(self, args) Routes.assert(Months:close(args.month)) end,
},
```

- **Parameters are typed.** `String`, `Number`, `Bool`, `Choice` (from
  `values`), `Date`, `Month`, and `Row model="customers"` for a record the
  person names. Before anything runs, the framework checks each argument
  against its type. A `Row` argument is resolved through the model's
  `find`/`select`, so the model can never invent an id.
- **Reads run; writes ask first.** A route already marks its read-only
  methods in `queries = {name = true}`. An intent backed by a query runs at
  once and shows its rows. Any other intent is shown as a row saying what it
  will do ("Close March 2026"), and it runs only when the person chooses it.
  Refusals (`Routes.fail`, constraint messages) come back as the answer's
  message, as they do on the page.
- **Results are rows.** A query returns rows plus the page that opens one
  (`open = "customer"`). Choosing a row navigates there with the row's id as
  the page's params. No new view is involved.
- **Suggestions are a query too.** A route may declare `suggestions(self)`,
  which returns rows the way Ledger's Home checks do: each one has a title
  and the intent that settles it. The assistant lists them before anything
  is typed.

## Front ends

### Help menu search (exists)

`_setMainMenu` hands AppKit the `help` role menu, so the Help search field
already finds every menu item by its title. Ledger built a menu command
search ("нов док" finds New Document); AppKit gives us that for free. There
is nothing to build for this front end.

### Command palette

The command palette is a framework-bundled sheet: an etlua template with a
`<TextField>` and a grouped plain `<List>`. It opens from a menu command
with a key equivalent (proposed: ⇧⌘K, as in Ledger). Typing matches intent
summaries and page titles by word prefix, with no grammar. Up and Down move
the list selection while focus stays in the field, Return runs the selected
row, and Escape closes the sheet. The sheet is a page like any other: its
route's `data()` lists suggestions, matches and the last answer's rows.

The palette works with no model at all. It is the floor on every platform
and OS version.

### On-device model

When Apple's Foundation Models framework is available (macOS 26 / iOS 26
with Apple Intelligence on), the palette also sends text it cannot match to
a `LanguageModelSession`. Each intent becomes one tool, whose description
is the intent's summary and whose arguments are its parameters. The model
only *proposes* calls. A proposed call goes through the same argument
checks and the same read/ask-first rule as a palette row, so the model can
never do more than a person could do by choosing rows.

- The session lives for as long as the palette is open, so follow-ups
  ("only those over a hundred thousand", "open the first") refine the
  previous call. The previous result's rows are passed to the model as
  context, not stored anywhere new.
- It runs locally: no network, no API key, no data leaving the device.
- When the model is unavailable, or declines, the palette says so and keeps
  its own matches. There is no fallback grammar.

Lua Studio's cloud agent (`apps/studio/services/Agent.lua`) has a different
job (it edits code), but it could later be given the same intents as tools
to drive a preview app.

## Cost

Foundation Models is a Swift-only API, and the bridge has no Swift today.
This needs:

- one Swift file under `src/shared/` exposing an `@objc` class (start a
  session with a tool list, send text, get back a proposed call or an
  answer), plus a `swiftc` step and Swift runtime linking in the Makefile
  for the Mac, iOS host and bundled-app targets;
- tool schemas built at run time from the manifest, because intents are
  only known once the Lua app has loaded (see open questions).

Everything else is Lua: manifest parsing of `<Intent>`, argument
validation, the palette route and its template, and headless tests. Nothing
runs while the palette is closed. While it is open, work happens only when
the person types or a model answer arrives.

## Tests

The tests are headless, as usual, and no test calls the model:

- Manifest intents are parsed into typed declarations, and an unknown
  parameter type is an error.
- Argument validation: a wrong type, a missing required argument, an
  unknown `Choice`, or a `Row` id the model does not find is refused.
- A query intent runs and returns rows; a write intent returns an ask-first
  row and runs only when chosen; `Routes.fail` becomes the answer's message.
- Palette matching by word prefix, keyboard selection, and Return on a row.
- The model path is tested with a fake session that returns fixed proposed
  calls, including malformed ones.

## Open decisions

1. **Where intents are declared.** This document proposes `<Intent>` in
   `app.xml`. The alternative is an `intents` table on the route, which
   keeps declaration and code in one file but moves data into Lua.
2. **Runtime tool schemas.** Foundation Models tools normally get their
   argument schema from Swift types at compile time. Intents need a schema
   built at run time. The framework's dynamic generation schema should
   allow it; confirm this before committing to the Swift shim.
3. **App Intents / Shortcuts / Spotlight.** App Intents are discovered from
   compiled Swift, so per-app Lua intents cannot each become one. A single
   generic "Ask <App>" intent that forwards text to the palette may be
   enough. Decide whether this is worth a second Swift surface.
4. **iOS presentation.** On iPhone the palette is a sheet with a search
   field. Decide whether it is also reachable from the tab bar accessory
   Lua Studio prototypes, or only from a toolbar button.
5. **Is the model worth the Swift step at all?** The palette with intents
   and suggestions may be enough for most apps. The model is opt-in per app
   (`<App assistant="model">`) until it proves itself.
