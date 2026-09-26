# Diskmap

A native macOS 26 storage manager organized by semantic categories, not folders.
The sidebar has five sections — Storage, Clean Up, Developer, System and
Learn — with one question per destination:

- **Overview — what uses my storage?** A donut of the whole startup disk by
  category, with free space as the empty track and unattributed usage in gray,
  the used total in its hole, and a legend that opens each category. Below it:
  categories ranked by size with share bars, the six largest individual items,
  and the rebuildable-versus-review cleanup headline with a prominent
  Review Cleanup button.
- **Largest Items** — the hundred largest measured locations across every
  category, each with its semantic owner, cleanup status and share bar.
- **Large Files** — the individual files over 50 MB found by the same scan,
  with when each was last used, filtered by All, Unused for a year, Installers &
  archives and Media. Your own documents (not files inside ~/Library, hidden
  tool folders or packages such as a Photos library) can be moved to the Trash
  after confirmation.
- **File Types** — every measured byte grouped by kind (videos, disk images
  and installers, archives, AI models, virtual machine disks, …) in a donut,
  with advice for the largest actionable kind and the top twelve extensions.
  Opening a kind shows its largest files.
- **Clean Up (Recommendations)** — rebuildable and review suggestions from the
  cleanup rules, pointers to unused documents, installers, unused apps and app
  leftovers, the full checklist of known space hogs that were measured within
  their limits (or kept, or absent), and contextual tips.
- **Applications** — each app in /Applications and ~/Applications with the data
  it keeps in Containers, Group Containers, Application Support and Caches,
  its version and when it was last opened (Spotlight's Last Opened), filtered
  by All, Unused for 6 months and Most data. Possible leftovers are data
  folders named like a bundle identifier that no app Spotlight knows claims.
- **Developer — what can I do about Xcode and friends?** Sections for Xcode &
  simulators, packages & toolchains, projects & editors, containers & virtual
  machines, and AI tools & models, each a ranked list of catalog locations.
- **Simulators** — every simulator device with its runtime, state, last use
  and data size, filtered by All, Unavailable or Unused for 90 days, with
  Erase, Delete and Delete Unavailable. Installed runtimes come from
  `xcrun simctl runtime list`: size, build, last use and the devices each one
  serves. Runtimes simctl reports as deletable can be deleted after a
  confirmation that names the devices they strand; Keep protects them.
- **Disks & Volumes** — drive health (SMART), FileVault, the sealed system
  volume and drive type from `diskutil info -plist /`; every APFS volume of the
  startup container from `diskutil apfs list -plist`; other mounted disks; and
  a shortcut to Disk Utility's First Aid. Read-only.
- **Updates & Snapshots** — what Software Update last found (from its own
  preferences, without contacting Apple), the measured storage an update passes
  through (downloaded assets, the Update volume, Preboot), full "Install macOS"
  apps, and the local Time Machine snapshots held on the disk, with shortcuts to
  Software Update and Time Machine settings.
- **Storage Guide — where does macOS keep things?** Topics on the APFS volume
  layout, Preboot, Recovery, where software updates are downloaded and staged,
  swap, local snapshots, free versus available space, System Data, caches,
  containers, device backups and developer storage; common culprits people
  report (runaway logs, local AI models, restore images, app leftovers, the
  Spotlight index, document versions); and what classic disk utilities
  (defragmenting, Disk Doctor, secure wipe, undelete, cleaners) mean on a
  modern Mac. Each topic shows its live size and opens the category that
  manages it.

Every ranking uses one list design: icon, name and location, a status column,
a share bar, the size and a "More" (⋯) button. A row's actions — its primary
action, Show in Finder, the owning category, Keep and Copy Path — live in that
menu and in the row's contextual menu, so lists never scroll inside a page and
no buttons sit beneath them.

Categories open their resources in a sheet with Safe/rebuildable, Needs review
and Essential to keep filters. Refresh, Stop, Clean Up, Settings and Search live
in the toolbar; search applies to the current page. The window subtitle shows
free space. `--page=<id>` (for example `--page=files`) opens a destination at
launch for screenshots and walkthroughs.

```sh
make
./lua-objc apps/diskmap/init.lua
make diskmap-app
```

Launch against a bundled synthetic disk for development and UI walkthroughs:

```sh
./lua-objc --mock apps/diskmap/init.lua
# The equivalent app-argument form also works:
./lua-objc apps/diskmap/init.lua --mock
```

Create a local Mock HDD snapshot of this Mac's internal volumes, then launch
Diskmap against that saved metadata:

```sh
./lua-objc --export-mock=/private/tmp/diskmap-mock-hdd.bin apps/diskmap/init.lua
./lua-objc --mock-file=/private/tmp/diskmap-mock-hdd.bin apps/diskmap/init.lua
```

The export is a versioned binary file (`DMOCK001`) containing file paths,
allocated sizes, disk capacity, hard-link accounting, and scan completeness.
Paths are UTF-8 and prefix-compressed against the preceding path. It never opens
file contents, invokes a shell, or uploads the snapshot. The file is written
with owner-only permissions. macOS may request access while the one-time export
traverses protected folders; the saved mock can then be reopened without
scanning the real disk. If some locations stay inaccessible, the snapshot is
marked partial and remains a lower bound. Restarting Mock HDD restores the
saved snapshot before simulated deletes or Trash operations.

`--mock` uses `~/Library/Application Support/Diskmap/mock-hdd.bin` when that
one-time export exists, and otherwise the bundled synthetic `mock-hdd.bin`.
`--mock-file` reads only the selected binary snapshot. Headless tests always
use the synthetic fixture. Both modes avoid the native scanner and shell commands, and show
“Mock HDD” in the window title. File sizes, installed apps, project outputs,
simulators, capacity and snapshots are synthetic. Trash, cache and simulator
actions change only the provider's in-memory copy; restarting restores the
fixture. Finder, owner apps, System Settings and real device commands are not
launched. The real provider remains the default when the mock switch is absent.

Every launch starts a fresh inventory. The category list follows macOS Storage: Applications, Trash, Books, Developer, Documents, iCloud Drive, iOS Files, Mail, Messages, Music, Music Creation, Photos, Podcasts, TV, Other Users & Shared, macOS and System Data, plus AI agents and snapshot backups. Photos, Music, TV and known media support locations are excluded by default; opt in for the current session in Settings. Excluded sizes are unknown, never zero. Diskmap has no directory
argument or live scan-result cache. The explicit mock fixture is a synthetic
filesystem for repeatable testing; use `--export-mock` to create a local snapshot
of this Mac.

`Catalog.lua` composes independent providers in `catalog/` into the macOS knowledge tree, including Xcode runtimes, devices, bundled SDKs, archives, package managers, a separate AI agents category for coding tools, Apple Intelligence and Siri, mobile toolchains, system assets, app support, backups, media and boot data. Startup also discovers project-local generated folders when their parent project marker exists and application bundles directly inside `/Applications` and `~/Applications`; each discovered path is measured as its own review-only resource and excluded from its broader residual measurement.
New layouts remain review-only until their ownership and cleanup policy are
verified. Nested app bundles and arbitrary custom installations are not
automatically discovered. Known asset classes give Siri, Dictation/shared speech recognition, voices,
Apple Intelligence, translation, Photos models, wallpapers, fonts and dictionaries
separate totals. Dictation and downloaded voices remain under System Data's
speech resources. Unrecognized classes remain in an explicit residual bucket.
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
gap without double counting folders. The overview ring names the seven largest
measured categories and groups the rest; Not attributed is separate from
measured Other files, and free space is the ring's empty track. When measured
allocation exceeds reported usage the ring draws no partition and explains why.

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
difference from macOS storage usage is labeled Not attributed; it can include
access gaps, snapshots and filesystem accounting differences, and is never
presented as disposable storage. Partial resource measurements show a lower
bound. Search in Storage matches category names, descriptions, resource names
and paths; matching resources appear under their semantic categories.
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

The same scan also ranks the 500 largest files over 50 MB, the largest files
not used for a year, per-extension totals and each location's immediate
children (see the [StorageScan options](../../src/plugins/storage/README.md)).
Nothing about individual files is kept after the app quits. Individual files
may be moved to the Trash only when `Files.validateTrash` accepts them: in the
home folder, outside ~/Library, hidden folders and packages, below no kept,
essential or system-managed location, and measured by the latest scan. A
possible app leftover may be moved to the Trash only while it is still an
unclaimed, measured data folder (`Applications.validateLeftover`); its
confirmation warns that an app on another disk would lose that data.
Applications reads each bundle's Info.plist and one `mdls` query for last-used
dates; leftovers compare against `mdfind`'s list of every installed app.
Disks & Volumes runs `diskutil info -plist /` and `diskutil apfs list -plist`.

The app and framework changes are described in [DESIGN.md](DESIGN.md); the research behind the features and their sources are in [VISION.md](VISION.md).

## Component boundaries

The root controller composes focused controllers: sidebar navigation, one page
controller per destination (overview, largest items, large files, file types,
clean up, applications, developer, simulators, disks and volumes, updates and
snapshots, guide), category management sheets, the SDK sheet, scan lifecycle,
category presentation, Keep persistence, contextual tips, row menus
(`ActionsController`), inspector actions, and settings. Pages
mount retained templates into the content pane; the root disposes the previous
page before mounting the next. The guide re-renders only when its search
changes, so scan progress never collapses the topic being read. Their
models contain no native controls. Services are injected, so tests can exercise
cancellation, preference persistence failures, action routing and fresh startup independently.

| Module | Owns |
| --- | --- |
| `catalog/` | Independent category definitions, paths, ownership and consequences |
| `Model.lua` | Live measurements, Keep state, scan state and byte aggregation |
| `models/Resources.lua` | Per-model canonical resource collection, ordered relations and registration |
| `models/Constraints.lua` | Named validation results for registration, Keep changes and Trash mutations |
| `models/Inventory.lua` | Scan plans, measurement transitions and current diagnostics |
| `models/Categories.lua` | Category queries, rolled-up rows and capacity distribution |
| `models/Overview.lua` | Volume summary, donut marks and legend, cleanup headline, ranked categories and largest items |
| `models/Developer.lua` | Developer sections: catalog groups, ranked rows and rebuildable total |
| `models/Files.lua`, `knowledge/FileKinds.lua` | Large and unused files, kinds by extension, file ages and per-file Trash eligibility |
| `models/Applications.lua` | Installed apps, their data folders, last use, possible leftovers and Spotlight date parsing |
| `models/Recommendations.lua` | Clean Up sections: suggestions, file and app pointers, and the checked knowledge list |
| `models/Volumes.lua` | Drive health facts, APFS volume rows and other mounted disks |
| `models/Guide.lua`, `knowledge/Guide.lua` | Storage Guide topics, search and live topic sizes |
| `models/Simulators.lua` | Device and runtime inventory, filters, summaries and validated `simctl` commands |
| `models/Updates.lua` | Software Update record, update staging storage, installers and local snapshots |
| `models/Cleanup.lua`, `knowledge/CleanupRules.lua` | Recognized resources, review thresholds, evidence and tailored advice |
| `models/Tips.lua` | Contextual access, capacity, Keep and system-storage guidance |
| `models/Inspector.lua`, `models/Preferences.lua` | Resource details and action eligibility |
| `controllers/` | Small coordinators with injected IO and navigation callbacks |
| `services/Provider.lua`, `services/Mock.lua`, `services/System.lua`, `services/Scanner.lua`, `src/plugins/storage/StorageScan.m` | Provider selection, synthetic filesystem, actual system integration and native bulk metadata enumeration |
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

Simulator devices are the UUID folders under `~/Library/Developer/CoreSimulator/Devices`.
Each row's size is that folder's measured allocation, already included in the
Simulator devices total. Names, runtimes and last use come from `device.plist`
when the file is present; a mock snapshot without plist contents shows the UUID
and the snapshot size. Bundled SDKs are the `*.sdk` directories inside Xcode
and the Command Line Tools. Erase and delete still go through `simctl` on a
real Mac, and through the in-memory snapshot in mock mode, using one validated
UUID at a time. Running devices are disabled. Delete unavailable lists the
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
