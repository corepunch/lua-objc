# Feature-oriented MVC and controller composition

The app structure used by Diskmap and Lua Studio is **feature-oriented MVC
with controller composition** (short form: **composed MVC**). It keeps the
familiar Model–View–Controller responsibilities, then groups larger app work by
feature and lets a small root controller compose focused controllers.

This describes an application organization pattern, not a framework requirement
that every small screen must have several layers. Start with the smallest
structure that has clear ownership; split a feature when it gains its own state,
presentation, or interaction flow.

## Shape

Every app has an entry point and a root controller. Larger apps organize
independent feature responsibilities into `models/`, `controllers/`, and
`services/`. All presentation stays in etlua templates under `views/`.

```text
apps/<app>/
  init.lua                 # Return the root Controller class
  Model.lua                # Root domain state when the app has shared state
  Controller.lua           # Create the window and compose top-level features
  models/                  # Focused domain or presentation models
  controllers/             # Feature-level coordinators
  services/                # Injected IO and platform/runtime integrations
  views/
    Window.etlua           # Top-level composition
    Feature.etlua          # Feature screen or reusable partial
```

The exact files depend on the app. A small app can keep one `Model.lua` and one
`Controller.lua`. A larger app can split domain models and feature controllers
without changing the entry-point contract.

## Responsibilities

- **Entry point:** `init.lua` requires and returns the root controller class. It
  does not start the app or build views.
- **Root controller:** owns app-level startup, creates the one window, and
  composes feature controllers. It coordinates across features only when a
  workflow crosses their boundaries.
- **Feature controller:** coordinates one user-facing area. It reads or mutates
  models, calls injected services, supplies view data, and connects native
  callbacks to controller methods.
- **Model:** owns domain data, queries, validation, formatting, and mutations.
  Models use plain Lua and do not depend on `ns` or native widgets. A small
  presentation model may instead provide plain data for a view.
- **Service:** isolates IO or runtime integration such as filesystem access,
  scanning, persistence, networking, or device APIs. Inject services so
  controllers and models can be worked with independently.
- **View:** owns all presentation in `.etlua` templates. Templates describe the
  native view tree and use `partial()` for reusable structure. Controllers pass
  plain data and retain refs for callbacks; they do not build view trees.

## Principles

1. **Organize around feature ownership.** Keep a feature's controller, model,
   and templates easy to locate. Use shared root state only for data genuinely
   owned across features.
2. **Compose; do not centralize every behavior.** The root controller is the
   app coordinator. Delegate feature work to small controllers instead of
   growing a single controller into a catalog of unrelated callbacks.
3. **Keep domain rules out of the UI.** Models decide what data means and
   whether mutations are valid. Controllers decide when to call them and how to
   respond to results. Views decide how information is presented.
4. **Keep platform IO at the boundary.** Services wrap IO and native runtime
   operations. Pass them into the part that needs them; do not let models reach
   into global app state.
5. **Keep templates declarative.** An `.etlua` template is the complete
   description of its view branch. Reusable UI belongs in partials, not
   controller-side view builders or fallback trees.
6. **Pass plain presentation data.** Models and controllers prepare values for
   templates. Views should not need to query the domain or know how IO works.
7. **Split only for a real boundary.** A pane with independent state or actions
   can justify its own model and controller. Static markup with no independent
   behavior may remain a partial supplied by its parent.
8. **Keep lifecycle ownership clear.** Only the app entry/root lifecycle
   creates the window. Feature controllers and view components never create
   windows.

## Examples

### Diskmap: domain-heavy composed MVC

Diskmap's root controller composes scan, categories, cleanup, tips, inspector,
management, simulators, and settings controllers. Domain models under
`apps/diskmap/models/` own resource data and rules; services isolate scanning
and system operations; `apps/diskmap/views/` contains the etlua presentation.
This is useful when features have independent domain behavior and interactions.

### Studio: pane-oriented composition

Studio's root controller assembles sidebar, preview, and chat pane controllers.
Each pane has a presentation model in `apps/studio/models/` and an etlua
template in `apps/studio/views/`. The top-level `Window.etlua` composes those
templates with `partial()`. The pane buttons are currently visual placeholders;
the separation establishes ownership for future pane behavior without putting
all layout and state in one window template or root controller.

## Practical test boundary

Test model rules and mutations as plain Lua. Test controllers with fake services
and callbacks where useful. Template/view behavior belongs in the existing
headless UI tests; visual changes also need visual review under the repository's
UI verification workflow.

See [ARCHITECTURE.md](../ARCHITECTURE.md#app-layer) for the runtime and app-layer
contracts, and [Diskmap](../apps/diskmap/Controller.lua) and
[Studio](../apps/studio/Controller.lua) for concrete examples.
