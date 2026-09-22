# Diskmap: an explainable macOS storage manager

Status: proposed product and implementation design. September 21, 2026.
This document describes the replacement for the current folder-oriented app;
it does not claim that the capabilities below already exist.

## Product decision

Diskmap answers: **What uses my storage, why is it there, do I need it, and what
can I do about it?** Its primary interface is an expandable inventory of macOS
storage categories, applications, features, and resources. Users should never
need to discover a hidden directory before they can understand its contents.

The app knows the conventions of macOS and the tools installed on it. It turns
that knowledge into useful names, explanations, ownership, and supported
management actions. Expanding Developer → Xcode → Simulator Runtimes lists
runtimes; expanding Developer → AI Coding Tools → Codex lists recognized kinds
of Codex data. Neither operation walks the user through directory levels.

The ambition is to explain every byte. The contract is to show the boundaries
of what we actually know: measured, estimated, inaccessible, and unclassified
storage remain distinguishable. A familiar directory name is insufficient
evidence that its contents are disposable.

### Basis in the supplied discussions

- [Product and category discussion](https://chatgpt.com/share/6ab12d6f-337c-83eb-863e-c78a1117c107):
  move from graphical directory exploration to semantic categories; explain
  System Data; expose developer tools and hidden application data; make routine
  maintenance repeatable; keep paths available as evidence.
- [Actual storage investigation](https://chatgpt.com/share/6ab12d85-d6ec-83ed-9b90-65fb1daed9d7):
  confusing System Data totals, protected feature assets, hidden home data,
  and the need to preserve useful simulators while removing other material.

The discussions establish user needs, not verified deletion recipes. Their
example sizes, usage dates, version numbers, and suggested savings are not
product facts. Broad cache deletion and disabling system protection do not
become app features. Feature shutdown is not a promise of immediate asset removal.

## Five core user stories

| User need | Product flow | Completion criterion |
| --- | --- | --- |
| “What is this huge System Data category?” | Open System Data; expand feature assets, caches, diagnostics, backups, and the unexplained remainder. | Every row explains ownership, measurement status, and available action; discrepancies are visible. |
| “Find developer junk without breaking my iOS setup.” | Open Developer; inspect Xcode, package managers, containers, and AI coding tools. Mark needed resources Keep. | Caches, SDKs, runtimes, simulator devices, archives, and user work are distinct; retained resources never enter cleanup selections. |
| “I do not use Siri or Dictation; why are their assets here?” | Select the feature; read its purpose and local footprint; open its supported management destination. | No manual deletion of protected assets; after returning, remeasure and report whether storage changed. |
| “I want a quick routine cleanup.” | Open Cleanup or Changes; review new growth and eligible resources, respecting previous Keep and Ignore choices. | The user can repeat maintenance without rediscovering paths or reviewing the same dismissed recommendation every launch. |
| “Can I trust these numbers and actions?” | Inspect a category's contributing resources, classification evidence, locations, and last measurement; compare before and after. | No double counting within an accounting view, no invented zeroes, and no claim that moving to Trash has freed space. |

## Navigation and category hierarchy

The sidebar contains Storage, Cleanup, Developer, Applications, Changes, and
Settings. Storage is the initial destination. Developer and Applications are
focused views of the same inventory, not independent scans or additional totals.
Large Files is a filter within an inventory view, not a competing navigation model.

The following is the target category vocabulary. Children appear when detected;
unmeasured supported categories remain available with an explicit status.

```text
Storage
├── Applications
│   └── Application → Installation / User Data / Offline Content / Caches
├── Documents & Downloads
│   └── Documents / Downloads / Installers & Archives
├── Photos, Music & Video
│   └── Libraries / Local Downloads / Creative Projects
├── Developer
│   ├── Xcode
│   │   ├── Installation & Bundled SDKs
│   │   ├── Simulator Runtimes → Platform and version
│   │   ├── Simulator Devices → Named device and associated runtime
│   │   ├── Build Data → Project when reliably identified
│   │   ├── Device Support → Platform and version
│   │   ├── Archives → App, version, and archive date
│   │   └── Documentation & Optional Components
│   ├── AI Coding Tools → Codex / OpenCode / Other recognized tools
│   │   └── Cache / Sessions & History / Generated Files / Worktrees / Settings
│   ├── Editors & IDEs → Application and recognized data kinds
│   ├── Package Managers → Downloads / Installed Packages / Environments
│   └── Containers & Virtual Machines → Managed resources and local disk images
├── System Data
│   ├── Apple Intelligence & Siri
│   ├── Dictation & Downloaded Voices
│   ├── Other Feature Assets → Recognized feature
│   ├── Application Support → Owner not classified elsewhere
│   ├── Caches → Owner not classified elsewhere
│   ├── Logs & Diagnostics
│   └── Temporary Data
├── Backups → Device Backups / Local Snapshots
├── macOS & Required System Data → System / Boot & Recovery / Virtual Memory
├── Other Users & Shared Data
├── Trash
└── Unclassified
```

These are semantic relationships, not assumed on-disk containment. An Xcode
runtime in a system-managed asset store belongs to Developer, not automatically
to macOS. Preboot is explained as boot-related system storage, never offered as
a cleanup target. Archives remain personal release history, not build cache.

Diskmap's taxonomy is intentionally its own. Apple's System Data is a broad
residual category ([Apple storage guidance](https://support.apple.com/en-us/102624));
we cannot claim to reproduce its private classification. A “What macOS may call
System Data” explanation can link to Developer, Backups, and other categories,
but those links are references, not additional counted children. The dedicated
System Data category contains only resources not already owned elsewhere.

### Expansion behavior

Use a native outline with disclosure triangles. Expansion reveals semantic
subcategories, then identifiable resources. There is no arbitrary four-level
limit and no recursive folder expansion in the primary outline. A leaf may
represent one item, a package, or multiple physical locations.

Selection changes the inspector; disclosure changes expansion. Activating a
group expands it, while activating a resource opens its detail, never deletes
it. Preserve selected and expanded IDs through refresh, sorting, and filtering.
Search matches category names, application names, resource names, and known
terms such as “SDK” or “Siri,” retaining ancestors to explain each match.

Paths are available under the inspector's Locations disclosure, with Copy Path
and Reveal in Finder. Unclassified entries may expose contributing locations
there. There is no separate folder-hunting workflow required to finish cleanup.

## Window and interaction design

Use a native three-pane macOS window: source-list navigation, a flexible main
content pane, and a collapsible inspector. The owning NSSplitViewItems supply
sidebar appearance and geometry. All screens and partials are etlua.

The main pane contains a compact volume summary and an edge-to-edge native
outline/table. Columns are Name, On Disk, Cleanup Status, and optionally Change.
Use native SF Symbols and semantic colors; all statuses also have text. The
outline and exact numbers are the primary visualization. No sunburst, treemap,
or custom folder diagram is necessary.

The volume summary shows scope, used capacity, available capacity, coverage, and
last update. “Available” and raw free space must retain the meaning supplied by
their respective system APIs. Do not present overlapping values as additive
segments. A coverage disclosure explains inaccessible and unreconciled storage.

The inspector answers, in order:

1. What is this, and which application or system feature owns it?
2. What contributes to its size, and how certain is the classification?
3. What happens if it is removed or its feature is disabled?
4. Which action is supported, and what must be kept or reviewed first?
5. Where is it, when was it measured, and how was it recognized?

Toolbar actions are volume scope, Refresh, Cancel, Search, and pane visibility.
Remove Scan Folder and Enclosing Folder. If Back/Forward is retained, it tracks
semantic selections, never directory history. Cleanup actions remain local to
the selected resource or explicit selection review.

Keyboard selection, disclosure, sorting, contextual actions, focus, and VoiceOver
use native behavior. Delete does not bypass review. At small window sizes, hide
the inspector and optional columns before constraining the main content.

### Representative flow: keep simulators, reduce developer storage

The user opens Developer and expands Xcode. They mark the required runtime and
SDK installation Keep, then inspect Build Data. Diskmap explains that rebuilding
and indexing will take longer after removal. The user reviews an exact measured
selection and moves eligible build data to Trash. Xcode archives and simulator
device data remain untouched.

Next, the user expands AI Coding Tools. Recognized caches are separated from
history, generated work, settings, and worktrees. An abandoned worktree can
contain uncommitted work; it is never inferred to be a cache. This flow must
work without knowing that `.codex` or `.opencode` exists.

## Actions and cleanup policy

Classification and action eligibility are separate decisions. Knowing what a
resource is does not establish that it is safe to remove.

| Status | Meaning | Offered action |
| --- | --- | --- |
| Rebuildable | Verified generated material with an explicit regeneration consequence. | Review Cleanup, then an exact supported action. |
| Review | Personal data, retained history, downloaded resources, or uncertain need. | Review Items or Open in Owning App. |
| Manage Feature | Storage associated with a macOS or application feature. | Open Settings / Open Component Manager. |
| System Managed | Required or protected storage without a supported Diskmap removal operation. | Explanation and appropriate system management destination, if one exists. |
| Unknown | Ownership or data purpose has not been established. | Inspect Locations; no Clean action. |

“Keep” suppresses removal recommendations for the selected stable resource.
“Ignore Recommendation” suppresses a suggestion without implying that the
resource is essential. Both are reversible in Settings, remain visible in the
inventory, and do not reduce accounted usage. A category-level Keep applies to
its descendants, including newly discovered descendants, until removed.

Cleanup ranks eligible suggestions by measured size, action confidence, and
actual evidence of disuse. Age is supporting evidence, never deletion authority.
Modification time is not last use; if reliable usage evidence is unavailable,
show “Usage unknown.” Selections start empty. Do not combine “reviewable” bytes
with rebuildable bytes under a single “safely reclaimable” headline.

Before executing an action, construct a review showing exact resources,
measurement time, exclusions, consequences, prerequisites, and recoverability.
Revalidate identity, classification, access, active-use constraints, and size at
execution. Reject changed or stale targets. Recheck path boundaries and symbolic
links at the service boundary; do not execute commands assembled from display
labels or broadly delete a parent directory because its children look eligible.

Supported owner operations take precedence over manipulating owner internals.
The initial release retains only narrowly verified Trash actions; new direct
operations require an independently tested adapter. Mixed batches report results
per item and do not imply transactional rollback. Opening another app is a
handoff, not a completed cleanup.

Moving to Trash is reported as “Moved to Trash,” not “Freed.” Reclassify the
resource into Trash and remeasure; Finder handles permanent removal. Capacity
changes are observed separately and may include unrelated activity. This follows
[Apple's distinction between moving and emptying Trash](https://support.apple.com/en-us/102624).

### Feature and developer-specific boundaries

- Siri, Apple Intelligence, Dictation, and downloaded voices are separate
  feature entries when evidence permits. Show the relevant management destination
  and effects of disabling a feature. Do not implement a fake Diskmap toggle or
  infer a switch's current state from the presence of asset files.
- Feature assets may remain after a setting changes. Report “Still present” or
  “Awaiting macOS management” after remeasurement, with no countdown or promised
  savings. Shared or unidentified assets remain unattributed within their owner.
- Boot, Recovery, protected MobileAssets, and virtual memory have no manual
  delete action. Unsupported orphaned assets are explained, not forcibly removed.
- SDKs bundled with Xcode are distinct from optional simulator runtimes and
  device support. List bundled SDKs as installation contents and manage them
  through the installation, not individual directory deletion. Verify component
  capabilities for the installed Xcode before enabling management shortcuts.
- AI-tool adapters must identify the installed product and layout version.
  A tool's whole home directory is never a cleanup unit. Unknown children are
  “Other tool data — review,” and configuration or credentials are not read to
  generate explanations.
- Container disk images are opaque owner-managed stores unless a supported
  inventory interface exposes their internal resources. Docker data can include
  persistent volumes and databases ([Docker backup guidance](https://docs.docker.com/desktop/settings-and-maintenance/backup-and-restore/)).
- Photos libraries, mail stores, and similar packages stay intact. Manage their
  content through the owning application; filenames inside a package do not
  establish independently removable items.
- Local snapshots are explained separately from ordinary file allocation.
  They are not routine cleanup targets or guaranteed savings; macOS manages
  their lifetime ([Apple snapshot guidance](https://support.apple.com/en-us/102154)).

## Storage accounting and trust

Maintain an inventory ledger independent of every UI view. Each measured resource
has one canonical accounting owner. References in Applications, Developer,
Cleanup, search, or an explanatory System Data view point to that same resource.

Rules must prevent overlapping roots from duplicating allocation. For example,
an Xcode installation and its SDK children cannot both contribute their full
sizes; a general cache category excludes already assigned tool caches. Parent
totals consist of owned children plus a separately represented residual.

Deduplicate hard links across the entire scan scope, using volume and file
identity, rather than once per scanner root. Recognize alternate paths to the
same data, including system/data-volume aliases. A deterministic owner receives
the accounting allocation; other references explain sharing. APFS clones and
shared extents cannot be made exclusive merely by deduplicating inodes.

Store integer bytes internally. Use decimal GB consistently in the main UI;
expose exact bytes and measurement method in details. Migrate the current `kb`
format explicitly rather than retaining mixed unit conventions.

Three quantities remain distinct:

- **On-disk allocation:** measured filesystem allocation, respecting sparse
  files, hard links, scan exclusions, and the limits of shared-extent accounting.
- **Cleanup candidates:** allocation belonging to currently eligible resources;
  an estimate of material to act on, not guaranteed physical recovery.
- **Capacity change:** before/after system capacity observations for the same
  scope and metric, not proof that Diskmap caused the entire difference.

For a comparable scan scope and generation:

```text
Measured allocation = Classified allocation + Measured unclassified allocation
Reported used capacity = Measured allocation + Signed reconciliation difference
```

The second line is an accounting explanation, not proof that file allocation
equals exclusive physical usage. The difference may reflect snapshots, shared
blocks, inaccessible data, filesystem metadata, other volumes in a shared
container, or concurrent changes. Preserve negative differences as a mismatch;
never clamp them away or label all positive differences “junk.” Do not assign
an exact size to denied access merely from the residual.

Scope volume capacity carefully on APFS: a mounted root's file usage is not
necessarily the container's total usage. Show the selected volume group or
container and distinguish other-volume consumption. Never total independently
reported free space from volumes sharing a container.

Display classification coverage only with a stated denominator, for example
“94% of measured allocation classified,” not “94% of your Mac understood.”
Do not claim byte-for-byte parity with System Settings.

Each measurement retains `notMeasured`, `calculating`, `complete`, `partial`,
`denied`, `failed`, `skipped`, or `unsupported` status. A missing path confirmed
by enumeration is different from an inaccessible path. Partial results show
known allocation as a lower bound. Refresh clears old measurements; only fresh
completed locations survive cancellation or failure. Each pending category shows
a native spinner and “Calculating…” in place of its size. Zero is reserved for
a completed empty measurement.

## macOS knowledge catalog

Ship a versioned, locally evaluated catalog of focused classifiers. Each rule
contains a stable ID, supported OS/application versions, detection method,
recognized locations or owner inventory adapter, category, resource identity,
explanation, evidence requirements, exclusions, management destination, action
policy, and verification references. Catalog changes ship with reviewed app
updates; no remotely supplied executable cleanup recipes.

Evidence precedence is explicit: supported owner inventory and stable IDs,
validated product metadata and known layout, then conservative structural
recognition. Generic extensions or names provide presentation hints only.
Conflicts resolve deterministically by specific ownership; unresolved conflicts
remain review-only and visible in diagnostics.

Known locations are discovery hints, not exhaustive truths. Custom installation
and cache locations require supported owner configuration or a user-granted
location associated with a named category. Do not scan arbitrary paths found in
untrusted files. Unknown application versions can be measured conservatively,
but destructive capabilities stay disabled until their layout is validated.

The pipeline is:

```text
Discover owners → Inventory resources → Measure → Classify and deduplicate
→ Aggregate categories → Derive recommendations → Review action → Remeasure
```

A normalized resource carries `id`, `ownerId`, `categoryId`, `kind`, `locations`,
`volumeId`, `allocatedBytes`, `measurementStatus`, `measuredAt`, `generation`,
`classificationRuleId`, `classificationConfidence`, `evidence`, `actionPolicy`,
and optional supported usage/dependency facts. Physical locations are separate
from UI identity. An action plan contains resource IDs and expected identities,
not just mutable path strings.

## Discovery, permissions, and routine use

Startup shows capacity and any saved real inventory immediately, with timestamps.
It measures every known path and residual roots in one background batch. Named
roots exclude separately classified descendants; the batch deduplicates hard
links across categories. Missing paths are confirmed zero; inaccessible paths
remain partial or unknown. Full Disk Access is optional and cannot make exclusive
snapshot allocation attributable to a file walk.

Background checks run every 15 minutes while the app is open and the preference
is enabled. All refresh actions use the same complete ledger, preserving ownership
across categories. Cancellation is prompt and old generations cannot overwrite
current results. Each category replaces its size with a native spinner while its fresh measurement is pending.

Do not follow symbolic links, traverse additional mounted filesystems implicitly,
read personal file contents, or materialize cloud-only files. Application metadata
reads must be narrowly specified by each adapter. Persist only Keep/Ignore choices and the background-check preference. Inventory
summaries, diagnostics, and timestamps stay in memory for the current launch. No network classification or telemetry is required.

Every launch recalculates the complete inventory. There is no saved-scan replay,
result cache, or persistent measurement history.

## Implementation in this repository

The implementation uses semantic categories and stable resource IDs throughout.
`Catalog.lua` composes nine independent providers. The root controller only wires
services, feature controllers, template refs, navigation and the window.

| Area | Current responsibility |
| --- | --- |
| `init.lua` | Thin entry point returning the Controller class. |
| `Model.lua` | Indexed state and aggregate byte arithmetic. |
| `models/` | Inventory transitions, categories, cleanup eligibility, tips, inspector data and preferences. No native widgets. |
| `catalog/` | Category definitions, explanations, paths, ownership and policies. |
| `knowledge/CleanupRules.lua` | Resource-specific review thresholds and advice with consequences. |
| `controllers/` | Independently testable scan, category, cleanup, tips, inspector and settings coordinators. |
| `services/` | Injected native IO, persistence, permissions and owner-management integration. |
| `services/Scanner.lua` + `StorageScan.dylib` | Metadata-only enumeration, exclusions, cross-root hard-link ownership and diagnostics. |
| `Controller.lua` | Composition root, navigation and template/action binding. |
| `views/` | etlua window, category outline, resource inspector, opportunities, contextual tips and settings. |

Only the framework-invoked root `createWindow()` creates a window. Controllers
never assemble view trees. Shared `ui.template` retains evaluated etlua descriptions
and scopes, preserves unchanged native subtrees, and replaces changed boundaries
with callback disposal. Keyed child reconciliation remains future framework work.
Native outlines retain stable selection and disclosure IDs. Shared framework
contracts own semantic padding, disclosure spacing, label wrapping and scroll
position through resizing; there are no Diskmap-specific native layout hooks.

The following sequence describes the broader product roadmap; Changes comparison,
automatic arbitrary-owner discovery and richer owner adapters remain future work.

### Delivery sequence

1. **Ledger and semantic UI:** canonical ownership, explicit unknown states,
   category expansion, inspector evidence, and the current verified Xcode and
   package-cache sources. Replace the folder-first launch experience completely.
2. **Developer inventory:** distinguish installations/SDKs, runtimes, devices,
   archives, package installations, container stores, and verified AI-tool data.
   Add Keep and owner-management destinations. Unverified layouts stay review-only.
3. **System explanations:** feature assets, boot/recovery, snapshots, permissions,
   and capacity reconciliation. Add only version-validated feature destinations.
4. **Routine maintenance:** reviewed cleanup plans, persistent preferences,
   fresh measurements and post-action results.

Each stage must be useful without implying that later catalog coverage exists.
Broad application/media ownership is added through the same catalog contracts,
not a second scanner or a return to folder-based navigation.

## Verification and acceptance

Every implementation step includes fast headless Lua regressions using TestKit
and injected fixtures. Tests must cover:

- Semantic expansion across multiple physical roots, stable selection, sorting,
  filtering, and ID-keyed results arriving in a different order.
- Nested ownership exclusions, cross-root hard links, path aliases, sparse files,
  zero-size resources, integer-byte formatting, and shared-storage uncertainty.
- Inaccessible, missing, partial, failed, stale, unsupported, and conflicting
  classifications; none silently becomes zero or a cleanup candidate.
- Xcode runtime/device/SDK distinctions, retained dependencies, and AI-tool
  histories, settings, generated work, and worktrees excluded from cache cleanup.
- Keep/Ignore round trips; fresh measurements on every launch;
  cancellation, late callbacks, and invalidation after a mutation.
- Exact action plans, replaced targets, symlink ancestors, active-owner refusal,
  mixed outcomes, and preserved unrelated resources. Use fake action services;
  no test cleans the real user's machine.
- Trash reclassification, lack of guaranteed savings from feature changes,
  non-additive focused views, and signed reconciliation differences.

UI implementation also requires screenshots and native layout dumps at small
and large sizes in light and dark appearances. Exercise loaded, loading, empty,
partial, denied, selected, disabled, error, and long-name states. Verify keyboard
disclosure, focus preservation, VoiceOver labels, truncation, and native selection.
Use fixture inventories for repeatable visual QA; no simulated scan sleeps.

The redesign is complete when all five user stories work without directory
navigation, every displayed total exposes its scope and uncertainty, and no
removal action is derived solely from size, age, a hidden filename, or category
membership. A user can repeatedly reduce unwanted storage while intentionally
keeping their working developer environment.

## Reference and capability validation

The linked conversations and the existing
[storage research notes](../../docs/research/DISKMAP_STORAGE_SUGGESTIONS.md)
provide context. Vendor documentation, installed-version capability checks, and
fixture-backed behavior establish executable policy.

Before enabling each adapter, verify its current management API, configuration
locations, identity scheme, and supported OS/application versions. In particular,
consult [Xcode component management](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
for optional resources. Exact Settings links and AI-tool data schemas remain
implementation validation tasks, not assumptions embedded in cleanup rules.
