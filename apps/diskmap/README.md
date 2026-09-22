# Diskmap

A native macOS 26 storage manager organized by semantic categories, not folders.
Open Developer, System Data, Applications, Backups and other categories in native management sheets. Search names, owners and paths, and filter by Safe/rebuildable, Needs review or Essential to keep. Settings stays at the bottom of the
native sidebar. The inspector exposes locations only as supporting evidence.

```sh
make
./lua-objc apps/diskmap/init.lua
make diskmap-app
```

Every launch starts a fresh inventory. Photos, Music, Movies and known media support locations are excluded by default; opt in for the current session in Settings. Excluded sizes are unknown, never zero. Diskmap has no directory
argument, saved-inventory replay, or scan-result cache.

`Catalog.lua` composes independent providers in `catalog/` into the macOS knowledge tree, including Xcode runtimes, devices, bundled SDKs, archives, package managers, AI coding tools, mobile toolchains, system assets, app support, backups, media and boot data. Startup also discovers project-local generated folders when their parent project marker exists, and full macOS installer apps directly inside `/Applications`; each discovered path is measured as its own reviewable resource and excluded from its broader residual measurement.
New layouts remain review-only until their ownership and cleanup policy are
verified. Arbitrary custom installations and every third-party app are not yet
automatically discovered. Known asset classes give Siri, Dictation/shared speech recognition, voices,
Apple Intelligence, translation, Photos models, wallpapers, fonts and dictionaries
separate totals. Unrecognized classes remain in an explicit residual bucket.
Rounded semantic badges use white SF Symbols; app-owned resources use artwork
resolved from installed application bundles, with a symbol fallback.

## Fresh measurements

Every startup and refresh recalculates the inventory. Each pending category
shows a native spinner and “Calculating…” in place of its size, then displays
its fresh result once all of its locations finish. No scan results or diagnostics
are retained between launches. Only Keep choices and the background-check setting persist.

Headless tests inject scanner results through the service interface, without
reading saved inventories, opening windows, or waiting for live disk scans.

## Measurement and actions

Startup and refresh measure every catalog path in one background batch, including
Applications, Documents, media, backups, Trash, developer projects, system data,
and residual roots for files outside named categories. Parent buckets exclude
all separately classified descendants. This closes the former startup allowlist
gap without double counting folders. Every measured category has its own bar
segment; Unreconciled is separate from measured Other files.

The app loads the native `StorageScan.dylib` plugin built by `make` and included
in `make diskmap-app`. Its worker uses `getattrlistbulk` to fetch metadata
in batches and publishes results directly to Lua without temporary scan files.
See [the Storage Settings investigation](../../docs/research/STORAGE_SIZING.md)
for the Apple framework findings and local timing evidence.

Scans inspect allocated file blocks, skip symlinks (including linked root ancestors)
and mounted descendants, and deduplicate hard links across the whole batch.
Confirmed missing paths count as zero, permission failures remain partial or
unknown, and snapshot exclusive allocation is explicitly system managed. APFS
shared extents and snapshots can still prevent physical-capacity parity. The
signed unreconciled difference is displayed, never called disposable junk.
Category refresh also scans the full ledger so independent batches cannot
reassign hard-link ownership and corrupt totals.

DerivedData, recognized agent download caches and user-owned offline developer documentation offer reviewed Move to Trash. npm and pip caches invoke their package manager's cache command after confirmation; Homebrew remains a reversible Trash review because its cleanup command also removes installed old versions. Other entries reveal their location or open the owner/system
settings. Your Trash offers reviewed Empty Trash with the measured size up front;
Finder performs the deletion and Diskmap remeasures afterward. Diskmap never
deletes SDK internals, removes protected assets, or disables system
protections. Moving to Trash does not free space.
Keep suppresses suggestions for a resource and its descendants and persists
locally. Background checks run every 15 minutes while open and can be paused.
No file contents are read or uploaded; cloud-only files are not downloaded.

The app and framework changes are described in [DESIGN.md](DESIGN.md).

## Component boundaries

The root controller composes focused controllers for category management sheets, simulator management, and scan lifecycle, category
presentation, cleanup, contextual tips, inspector actions, and settings. Their
models contain no native controls. Services are injected, so tests can exercise
cancellation, preference persistence failures, action routing and fresh startup independently.

| Module | Owns |
| --- | --- |
| `catalog/` | Independent category definitions, paths, ownership and consequences |
| `Model.lua` | Live measurements, Keep state, scan state and byte aggregation |
| `models/Resources.lua` | Per-model canonical resource collection, ordered relations and registration |
| `models/Constraints.lua` | Named validation results for registration, Keep changes and Trash mutations |
| `models/Inventory.lua` | Scan plans, measurement transitions and current diagnostics |
| `models/Categories.lua` | Category queries and capacity distribution |
| `models/Cleanup.lua`, `knowledge/CleanupRules.lua` | Recognized resources, review thresholds, evidence and tailored advice |
| `models/Tips.lua` | Contextual access, capacity, Keep and system-storage guidance |
| `models/Inspector.lua`, `models/Preferences.lua` | Resource details and action eligibility |
| `controllers/` | Small coordinators with injected IO and navigation callbacks |
| `services/System.lua`, `services/Scanner.lua`, `src/plugins/storage/StorageScan.m` | Native integration and bulk metadata enumeration |
| `views/` | All presentation, etlua loops and reusable partials |

`Model.resources` owns one canonical row for every catalog resource. Use
`resources:find(id)`, `resources:roots()` and `resources:leaves()` for collection
queries; rows expose `getParent()`, `getChildren()`, `isLeaf()`, `getMeasurement()`,
`isKept()` and `validateTrash()`. Relation sequences are snapshots for reading,
and structural registration goes through `resources:add(parentId, definition)` so
IDs, exact paths and parent links remain atomic and model-local. Discovered agent
metadata uses the same registration path, making repeated discovery idempotent.
Rows do not expose mutable child arrays, parent IDs or model references. Feature
models explicitly project row fields into presentation tables, so relation caches
and collection ownership never leak into views.

Review suggestions and filesystem mutations are separate policies. Cleanup rules
decide when measured storage is worth reviewing, including partial lower bounds;
`Cleanup.moveToTrash` independently validates the current leaf, action, absolute
path, complete positive measurement and inherited Keep immediately before calling
the injected service. Controllers may confirm and present errors, but they do not
provide an alternate filesystem mutation path.

Cleanup thresholds are review criteria, not claims that data is unnecessary.
Complete measurements and explicit partial lower bounds qualify for review. Partial measurements never authorize Move to Trash. A large unrecognized folder or required app
installation does not become a suggestion simply because it is large. Every
suggestion explains its owner, measured evidence and consequences; Keep suppresses
it and its descendants.

`ui.template` owns retained etlua component mounts and callback scopes. Identical
descriptions retain native views and scroll state; changed descriptions replace
the scoped subtree. It is boundary-level reconciliation, not keyed child diffing.
The application does not clear and rebuild native container children itself.

## Verification

```sh
./lua-objc tests/diskmap.test.lua
./lua-objc tests/outline_cells.test.lua
make test
```

The native framework now shares subtitle/symbol cells between tables and outlines,
preserves outline disclosure and selection by ID, uses NSBox for GroupBox,
supports determinate ProgressView, remeasures ancestors on nested layout updates,
and provides `view:scrollIntoView()` through AppKit. No Swift or SwiftUI is used.

## Category management

Simulator devices are read asynchronously with `xcrun simctl list --json`: name,
runtime, installed apps/data allocation and last use (UTC, or Not recorded).
Erase/delete use validated individual UUIDs, confirmation with impact, and no
wildcard selectors. Running devices are disabled. Delete unavailable lists the
exact devices before confirmation; unavailable does not mean disposable.
Installed runtimes remain Essential to keep. CoreSimulator images, registered
bundles and MobileAsset iOSSimulatorRuntime downloads share one runtime category
and a disjoint accounting ledger. Device-detail sizes are never added twice.

AI tool coverage follows verified on-disk layouts: Codex sessions, archived
sessions, worktrees, plugins and skills; OpenCode snapshots, logs, sessions,
worktrees and generated output; Claude transcripts, file history, plugins and
caches; Cursor caches split from settings and work; Grok cache and residuals.
Root-level diagnostic databases, logs and settings are discovered by name
without reading credentials, conversations or file contents. Caches offer
reviewed Move to Trash; sessions, histories, snapshots, worktrees and
databases stay review-only with tool-specific advice and thresholds.
Arbitrary custom locations and cloud-only conversations are outside this
inventory.

Siri, Dictation and voice assets link to their relevant Settings panes. Turning
features off is not a promise that shared models disappear immediately. Downloaded
voices can be managed in Accessibility > Read & Speak. Protected Apple developer
documentation links to Storage Settings; user-owned offline docs may be moved to
Trash. No protected asset directory is directly deleted.

Selecting System Data decodes the measured total into its ranked contributors
with virtual memory reported separately; opening its management sheet annotates
the live local snapshot count and recent snapshot date identifiers, which remain system managed and unattributable
to exclusive file allocation. Permission errors and unreconciled allocation
appear directly below the storage summary. Review candidates may use partial lower bounds marked ≥, while filesystem
cleanup remains disabled for incomplete measurements. Photos/Music/Movies can be
included explicitly for a session; normal scans exclude both their roots and known
media support paths from residual traversal. Other protected folders can still
require macOS access. System Settings can show its own media totals without giving
Diskmap access.

Native sheets use the shared `<Sheet>` / `AppKit.presentSheet` API and AppKit
window presentation. Their views are etlua; controllers do not build view trees.
