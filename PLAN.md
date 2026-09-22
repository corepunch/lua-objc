# Diskmap: resource models, relations, and constraints

Status: proposed implementation plan. This document does not change runtime behavior.

## Objective

Give Diskmap's in-memory catalog a clear collection/row API, centralize its tree
relations, and make mutation validation named, discoverable, and unavoidable.
Keep the existing feature models and injected services. Do not introduce a database
or turn every feature into an ActiveRecord class.

The repository vendors **etlua**, not the full Lapis framework. `.gitmodules` points
at leafo/etlua, and `lua/ui/xml.lua` already uses its parser/compiler/load/run
pipeline. No templating migration or additional Lapis dependency is needed.

## Findings that affect the design

- `apps/diskmap/Model.lua` constructs the catalog once per model instance, indexes
  `tree`, `byId`, and `leaves`, and owns measurements, Keep preferences, and scan
  state. `ScanController` reuses that model across scans.
- `models/AgentFiles.lua` discovers additional resources before scans and directly
  updates all three catalog structures. Relations must handle these insertions.
- `models/Preferences.lua` walks `parentId` for inherited Keep and exposes
  `canTrash`. The actual filesystem action currently lives in
  `controllers/InspectorController.lua`.
- `knowledge/CleanupRules.lua` defines **review thresholds**, not deletion
  constraints. `Cleanup.suggestions` deliberately accepts partial lower bounds;
  moving to Trash requires a complete, positive measurement and a permitted action.
- `Categories` and `Cleanup` copy catalog fields into presentation tables. Adding
  owner references directly to rows would leak internal state through these copies.
- Simulator devices come from a separate `simctl` inventory. They are not catalog
  rows, and their sizes must never be added to the storage ownership ledger.

## Design decisions

### 1. Introduce one resource collection and one row metatable

Add `apps/diskmap/models/Resources.lua`. Keep its collection methods and row methods
in separate tables inside the module. Each collection belongs to one application
model; every catalog row in that collection shares its row metatable.

Use the useful separation from Lapis's `extend()` without copying its SQL-oriented
factory or inventing a general model inheritance framework. A literal reusable
`extend()` API is deferred until another real entity type needs it.

Proposed surface:

| API | Responsibility |
| --- | --- |
| `Resources.new(model, definitions)` | Validate and index the initial tree; bind row behavior |
| `model.resources:find(id)` | Return the canonical row or `nil` |
| `model.resources:roots()` | Return ordered root rows |
| `model.resources:leaves()` | Return ordered leaves for inventory and feature queries |
| `model.resources:add(parentId, definition)` | Validate and register a discovered resource atomically |
| `row:getParent()` | Return the canonical parent or `nil` for a root |
| `row:getChildren()` | Return ordered canonical children, or an empty sequence for a leaf |
| `row:isLeaf()` | Distinguish a leaf from a group, including an empty group |
| `row:getMeasurement()` | Read the latest measurement from the owning model |
| `row:isKept()` | Resolve direct and inherited Keep through the shared relation API |
| `row:validateTrash()` | Return the same domain validation result used by the mutation |

Collection indexes become private implementation details. Remove `model.tree`,
`model.byId`, and `model.leaves` once all callers use `model.resources`; do not retain
aliases. `Model.lua` continues to own `measurements`, `kept`, `scan`, and session
preferences. `Catalog.lua` and its providers continue to supply plain definitions.

Store ownership outside enumerable row fields, for example in a collection-local
metatable closure. Plain presentation results must not contain model references,
relation caches, or row metatables. Replace generic copying with explicit field
projections where needed. Models remain independent of `ns` and widgets.

Do not add `row:sizeLabel()` initially: size text varies between aggregate rows,
management rows, and the inspector. If formatting is consolidated, use a pure
`models/Measurement.lua` formatter that accepts bytes/status, including aggregate
values. Do not make a row method silently compute subtree totals or change existing
status labels as part of this refactor.

### 2. Make relations part of the catalog's identity contract

The existing ID index and ordered child lists already provide in-memory relation
storage. Use those as the relation cache; do not add a second lazy cache or scan the
entire catalog on each lookup. Parent lookup is constant time and child access
returns the registered sequence.

- Every reference to a resource ID resolves to the same row object within a model.
- Parent/child relations stay within their owning collection, even when two models
  contain identical IDs.
- Roots have no parent. Leaves and empty groups remain distinguishable.
- Structural writes go through collection construction or `add`; returned sequences
  are read-only by API contract. Feature code never appends children directly.
- `add` updates the parent relation, ID index, and leaf index together. Reject
  duplicate IDs, conflicting exact paths, invalid parents, and cyclic/malformed
  definitions before changing any state. Preserve ordered traversal and inherited
  icon/color/application metadata.
- Repeated metadata discovery remains idempotent: `AgentFiles.add` recognizes an
  already registered path and skips it; conflicting IDs are not silently overwritten.
- Do not cache measurements, eligibility, or inherited Keep. These change during
  scans and user actions; row methods read current model state each time.
- Keep scan-generation cancellation in `ScanController`. A rescan updates
  measurements without replacing row identity. Removal/reparenting APIs are outside
  this scope; future structural operations must preserve these same invariants.

### 3. Add named constraints at mutation boundaries

Add a small pure-Lua `apps/diskmap/models/Constraints.lua` evaluator. Constraints
are named validator functions grouped by operation with an explicit evaluation
order. Validators return `true`, or `false` with a human-readable message. The
evaluator returns `true`, or `false, {code = name, message = message}` for the first
failure. Tests assert stable codes as well as meaningful messages.

Use operation names rather than fake SQL columns. Initial groups cover resource
registration, Keep changes, and moving a resource to Trash. A missing ID must return
a structured failure through the collection/model entry point, before calling a
row method.

Trash constraints must require a registered leaf, an explicit `action == "trash"`,
a valid nonempty absolute path, a complete positive measurement, and no direct or
inherited Keep. Preserve existing protected/system-managed behavior and the native
service's filesystem/symlink checks. A review threshold never grants trash authority.

Add `Cleanup.moveToTrash(model, id, service)` as the domain mutation entry point.
It resolves the current resource, runs the constraints, and only then invokes the
injected trash service. Return structured domain/service failures to the caller.
The controller still coordinates confirmation, error presentation, and refresh:

1. Validate for availability and prepare the confirmation from the selected row.
2. Ask for confirmation through the existing service.
3. Call the model mutation, which validates again after confirmation and immediately
   before IO. A stale button state or changed Keep/measurement must not authorize IO.
4. Refresh after success; preserve current service-error reporting on failure.

`Inspector.details` uses the same validation result for `canManage`. Remove
`Preferences.canTrash` and update its callers in the same change. Keep
`Preferences` focused on preference mutations and persistence coordination; replace
its duplicated ancestor walk with `row:isKept()` and remove the old traversal API.
Do not route filesystem mutations through an unvalidated alternate controller path.

Keep suggestion eligibility explicitly separate in `Cleanup`: recognized rule,
threshold reached, complete or partial evidence, non-Essential policy, and no Keep.
Avoid a vague `isEligibleForCleanup()` method that could mean either review or deletion.

Simulator validation remains in `Simulators`; use the same named-result convention
for supported action, exact UUID, shutdown state, availability for erase, and
catalog Keep protection. Keep devices as plain inventory records. Preserve explicit
confirmation, exact target lists, busy/error guards, and validation before command
dispatch; never introduce wildcard operations or count device detail sizes twice.

## Implementation sequence

Each step includes its regression tests and updates every affected caller without
compatibility shims.

1. **Characterize current behavior.** Extend the diskmap tests around complete versus
   partial measurements, inherited Keep, threshold boundaries, repeat discovery,
   and unchanged presentation outputs. Record the existing status-label differences
   so this refactor does not silently alter them.
2. **Introduce Resources and migrate ownership.** Update `Model.lua`, `AgentFiles`,
   `Inventory`, `Categories`, `Cleanup`, `Inspector`, controller lookups,
   `System.agentEntries`, and test fixtures together. Search the whole repository
   for diskmap consumers before removing old fields. Feature projections use row
   relations; provider construction can still recurse over plain definitions.
3. **Centralize validation and mutation.** Add named constraints, move Trash execution
   behind `Cleanup.moveToTrash`, migrate inspector availability and controller calls,
   and align simulator validation results. Preserve confirmations and service guards.
4. **Remove redundant paths and document the contract.** Delete replaced accessors
   and duplicated policy checks. Update `apps/diskmap/README.md` with collection/row
   ownership, relation lifetime, and the review-versus-mutation distinction. Keep
   feature-specific queries in their current focused modules.

## Regression coverage and acceptance criteria

Add `tests/diskmap_resources.test.lua` and `tests/diskmap_constraints.test.lua`, using
`TestKit` and `_G.__headless = true`. Use fixture data and fake IO services; no windows,
sleeps, filesystem deletion, or live simulator commands in these new tests.

| Area | Required checks |
| --- | --- |
| Identity and relations | Roots, leaves, empty groups, canonical parent/children, two-model isolation, insertion visible after prior relation access |
| Registration | Repeat discovery, duplicate IDs/paths, missing or leaf parent, malformed/cyclic definitions, failed registration leaves all indexes unchanged |
| Live state | Existing rows see measurement replacement, scan cancellation/failure, and Keep/unkeep immediately; unrelated measurements stay unchanged |
| Trash constraints | Unknown ID, group, forbidden action, invalid path, missing/zero measurement, partial/failed/denied/excluded/calculating status, kept ancestor |
| Mutation boundary | Invalid calls never reach IO, direct model calls validate, cancellation causes no IO, state changed during confirmation blocks IO, valid action runs once and refreshes |
| Service failures | Symbolic-link rejection and trash failure surface correctly without reporting success or clearing measurements |
| Suggestions | Below/at threshold, partial review without trash authority, Essential exclusion, inherited Keep, existing priority/size ordering |
| Presentation and accounting | No leaked owner/caches, preserved size/status text, category totals and residual exclusions unchanged, simulator sizes not double-counted |
| Simulators | Invalid UUID/action, running or unavailable device restrictions, Keep protection, exact confirmed targets, busy guard, error propagation |

Run `make` and `make test` after implementation. Existing diskmap inventory,
features, loading, privacy, sections, management, startup, and CLI coverage must
continue to pass. New headless tests must meet the project's subsecond target.

If validation messages or enabled states change the UI, exercise the affected
inspector and simulator flows and inspect screenshots in light/dark appearances
at small and large sizes, including loading, empty, selected, disabled, error, and
long-text states. Check focus and keyboard behavior. Use native layout dumps before
and after any layout correction. Keep all view changes in etlua.

Completion means that structural registration has one owner, relation reads remain
current after discovery, every Trash action validates at its model boundary, and
the existing catalog accounting and review policy remain intact.

## Explicit exclusions

- No SQL backend, ORM, one class per catalog category, or full Lapis dependency.
- No `include_in`/`preload`: the collection already holds all resources in memory.
- No SQL-style paginator or artificial wire-paging abstraction.
- No persistence timestamps or automatic `updated_at`; retain the meaningful
  `scan.completedAt` timestamp already used for scan reporting.
- No new template engine, native bridge changes, generic relation DSL, or framework
  extraction until another application demonstrates the same concrete need.
