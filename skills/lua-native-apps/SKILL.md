---
name: lua-native-apps
description: Build, redesign or refactor a Lua macOS/iOS app in lua-objc — manifest pages, routes, Lapis models, etlua views and components, window chrome (sidebar, toolbar, sheets) — and verify it against what was asked with captures and headless tests. Use for any app-level UI or architecture change in apps/, demo/ or test/.
---

# Lua Native Apps

An app is Lua and etlua over Apple's own controls. Most mistakes in this
repository were not syntax errors: they were a correct-looking change that
did something other than what the person asked, verified by tests written to
match it. This skill is mostly about not doing that.

SwiftUI-shaped review belongs to `skills/swiftui-parity`; framework (bridge,
renderer, layout engine) work belongs to `skills/maintain-lua-objc-framework`.

## Read first

The rules live in the repository, not here. Read what the task touches:

- [AGENTS.md](../../AGENTS.md) — the non-negotiable rules. They win over this file.
- [docs/agents/application-architecture.md](../../docs/agents/application-architecture.md)
  — what goes where: manifest, store, models, routes, flows, components, controllers.
- [docs/data-driven.md](../../docs/data-driven.md) — pages as requests, `@name` resources.
- [docs/components.md](../../docs/components.md) — a new tag is an etlua component.
- [docs/agents/layout.md](../../docs/agents/layout.md) — page width, chart sizing and colors.
- [references/vocabulary.md](references/vocabulary.md) — tags that exist. Never invent
  a tag or modifier; add a component or extend `xml.registry` with a test.

## The shape of an app, in one breath

`app.xml` names the pages; each page is a route (`pages/*.lua`) whose
`data(state)` feeds one etlua view (`views/pages/*.etlua`); an action is a
method of the route, after which the page is requested again. Models are
Lapis models over the bound store and never touch `ns`. IO is a service,
shared action code a flow. A controller exists only to coordinate (sheets,
confirmations, window chrome). There are no bindings, observers or
notifications: a value reaches the screen when the template renders it, or
when a controller sets it on a retained ref because it changes every tick.

Append with `table.insert(items, value)`, never `items[#items + 1] = value`;
parenthesize multi-value calls: `table.insert(items, (fn()))`.

## Designing screens

### One look, one template

Pages that look alike are one template over different data, never parallel
templates that each arrange shared pieces. When asked "make these pages look
like that one", the deliverable is a single `views/pages/<Shape>.etlua` whose
inputs are documented at its top, and routes that only differ in `data()`.
Shared components alone are not enough: each page template drifts (a missing
header here, a title repeated three times there).

Diskmap's breakdown pages are the worked example:
`apps/diskmap/views/pages/Breakdown.etlua` serves Overview, Storage Map, File
Types and Folder Map. Its order is the house layout for a page about one
thing:

1. a heading at the top of the page — trail to the levels above, title,
   the page's own picker beside the title, a one-line detail, warnings;
2. a decision the page leads with, if any;
3. the main figure (a card: chart with a compact legend, or rectangles
   filling the card);
4. what explains the figure;
5. lists, each the full width of the page.

Titles and pickers belong to the page heading, not inside a card. A name
appears once per screen: if the heading says "Developer", neither the card
nor a breadcrumb repeats it as a current step.

### Window chrome: each thing in one place

| Surface | Holds | Never holds |
|---|---|---|
| Sidebar | Destinations; a count or size badge on the row (a mailbox's unread count) | Actions |
| Toolbar | Window-wide actions and view options that apply to every page of a kind (Refresh, Search, rings/rectangles) | A destination the sidebar already lists; per-row or selection actions |
| Rows and charts | Opening (double-click), flagging (the row's button), menus (`rowMenu`) | — |
| Menu bar | Every command, with its shortcut | — |
| Sheet | Short, blocking work with its own Stop/Cancel (scan progress, confirmation) | Anything with page history |
| Page | Anything a person navigates to and back from | — |

A view preference that several pages share (chart style) is one control in
the toolbar affecting all of them, not a toggle on each page. A collection the
person builds up (flagged items) is a sidebar destination with a count.

Moving something between these surfaces — sheet to page, inline to toolbar,
toolbar to sidebar — is a design decision. Ask before making it unless the
request names it.

## Working discipline

- **Do what was asked; ask about the rest.** A restyle request does not cover
  converting sheets to pages or moving actions into the toolbar. List such
  ideas in your reply instead of shipping them. AGENTS.md also requires
  "are you sure?" before adding machinery.
- **Write the request down as checks before coding.** Turn each sentence of
  the request into an observable fact ("the legend is right of the ring", "the
  list spans the page", "one toolbar button switches every breakdown page")
  and assert those. A test that restates your implementation ("the badge
  follows `app.marked`") proves nothing about the request.
- **Changing a test is a claim.** When a test fails because you changed
  behavior, update it only if the request asked for that change, and say
  which request sentence it follows. Otherwise the test is right.
- **Prefer deletion.** When a design replaces another, delete the old
  templates, routes, flags and tests in the same change (no backwards
  compatibility). Rename command-line flags and callers together.
- **Keep the change reviewable.** One concern per commit; do not leave
  a large uncommitted rewrite for the next agent.

## Verifying a UI change

Headless tests are necessary and never sufficient. Follow
[references/verification.md](references/verification.md), and for a layout
or restyle in particular:

1. Capture every affected page in one launch with a capture plan, in each
   state the change touches (both chart styles, focused and unfocused, empty,
   measuring), light and dark, at the default and minimum window sizes.
2. When the request names a reference ("like the Overview"), capture the
   reference beside the candidates and compare them region by region: heading,
   card, legend, lists, toolbar.
3. Read the captures for repeated titles, clipped values (`100` for `100%`),
   controls that moved surface, and gaps. Compare `--capture` layout XML, not
   PNG diffs, for geometry.
4. Then run the headless suite.

## Model and route boundaries

- Models own lookup, validation and mutation; they read the bound store and
  never import AppKit/UIKit, render, or navigate.
- Routes turn models into view data and name actions; formatting that
  several routes share is a pure helper (`helpers/`), IO a service.
- Templates never query models, perform IO or mutate state. A missing tag is
  a component (`components/` in the app, `lua/components/` in the framework).
- Only the entry point creates `ns.Window`.

## Cross-pane alignment

Peer elements in a split view (a sidebar search field and a detail header)
share one top edge. Verify with `--dump-layout` at the default and minimum
size and compare their window `y`; derive the shared offset from one named
constant instead of tuning each pane's padding.

## Headless tests

- `_G.__headless = true`; tests live in `tests/*.test.lua` and run under a second.
- Drive the real controller in-process (`Controller.new(Mock.new()):createWindow()`),
  then call page actions (`app.page.actions.x`) and window actions
  (`app:toggleChartStyle()`) as the UI would; never spawn `./lua-objc` subprocesses.
- Assert refs by id and their native properties; assert structure that the
  request depends on (which view contains which: the warning is in the
  heading, not the card).
- Add new entry points to `tests/examples.test.lua`.
