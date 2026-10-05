# Diskmap

A native macOS 26 storage manager organized by semantic categories, not folders.
Overview and Clean Up lead the sidebar without a header (Clean Up's badge is
what it could recover); then Free Up Space (Applications, Large Files,
Duplicates and, on a developer's Mac, Simulators, Worktrees and Projects),
Explore (the maps, Largest Locations, File Types), System, the kinds of work
and Learn, with one question per destination. Diskmap is for everyone, so the
developer pages appear only on a Mac with developer data: Xcode or
`~/Library/Developer` present, or at least 500 MB measured in the Developer
category.

Every cleanup destination leads with one decision (`views/sections/Decision.etlua`):
what to review and why, its amount labelled *could recover* or *to review*,
and the button that starts it, before any chart or inventory; a page with
nothing to remove says why and routes to Clean Up. Meters are capsules half
the height of AppKit's capacity cell.

- **Overview — what uses my storage?** The rebuildable-versus-review cleanup
  headline and Review Cleanup button lead above a compact donut of the whole
  startup disk. Free space is the empty track, unattributed usage is gray, and
  the legend opens each category. Below it are categories ranked by size with
  share bars and the six largest individual items.
- **Folder Map** — any folder or disk, measured in one scan and shown as
  DaisyDisk and GrandPerspective show a disk: rings or rectangles beside a list
  of the focused folder's contents, largest first. Drop a folder or disk from
  the Finder anywhere on the window or on the Dock icon, choose File › Open
  Folder… (⌘O), or launch with `--folder=<path>`. Color the map by Folders,
  Kinds of file or Last Used, with a legend. Rows offer Quick Look (⌘Y, with
  the arrow keys stepping through the folder), Show in Finder, **Move to…**
  (offload to another folder or disk, off the main thread, never replacing an
  item), Move to Trash and Mark for Cleanup; a move or Trash updates the map
  without scanning again. Only items in the home folder or on other disks can
  be moved, never system locations, standard folders, mount points, package
  contents or catalog locations marked Keep, Essential or system managed. A
  scanned folder that is a catalog location (such as Xcode's DerivedData) is
  labelled with its owner and policy. The startup disk is measured through its
  Data volume and reports the space no folder accounts for.
- **Largest Locations** — the hundred largest measured locations across every
  category, each with its semantic owner, cleanup status and share bar.
- **Large Files** — the individual files over 50 MB found by the same scan,
  with when each was last used, filtered by Yours (the files you can act on,
  shown first), All, Unused for a year, Installers & archives and Media. Your own documents (not files inside ~/Library, hidden
  tool folders or packages such as a Photos library) can be moved to the Trash
  after confirmation.
- **File Types** — every measured byte grouped by kind (videos, disk images
  and installers, archives, AI models, virtual machine disks, …) in a donut,
  with advice for the largest actionable kind and the top twelve extensions.
  Opening a kind shows its largest files.
- **Clean Up** — candidates from every screen ranked by one rule (eligible
  bytes × confidence ÷ effort, `models/Suggestions.lua`): rebuildable data first,
  then *your decisions* (unused documents, user-owned installers, unused apps
  with a known last use, high-confidence leftovers, the minimal simulator set,
  leftover worktrees), then system-managed context and the checklist of known
  space hogs within their limits, both collapsed. The headline keeps estimated
  recoverable bytes apart from bytes to review; a group agrees with its
  children (device support holding only the newest version is not a
  suggestion). Every page's totals state their scope and coverage
  (`helpers/Scope.lua`); `knowledge/Audit.lua` records each destination's first
  conclusion and next step, or why it has none. The page opens with the
  top-ranked suggestion as a decision; each row's meter shows what it could
  recover, or what there is to review. Select a suggestion to read its full
  guidance in the panel below the list and use its visible Open button; the
  panel is hidden while nothing is selected, and selection survives live
  measurement updates.
- **Applications** — each app in /Applications and ~/Applications with the data
  it keeps in Containers, Group Containers, Application Support and Caches,
  its version and when it was last opened (Spotlight's Last Opened; an app with
  no recorded date reads "Last use unknown", is never called unused, and a
  running app is in use), filtered
  by All, Unused for 6 months and Most data. Possible leftovers, data
  folders named like a bundle identifier that no app Spotlight knows claims,
  come first, under a decision to mark the high-confidence ones.
- **Simulators — minimal device set.** Keep one standard iPhone and one
  standard iPad on a chosen iOS runtime (models identified by device type, not
  name); every other device is *redundant for this setup*, listed with size, last
  use and running state, with Keep choices, a keep-pair override, one batch
  confirmation and per-device revalidation (`helpers/SimulatorPlan.lua`). The
  keep pickers, the amount the removal could recover and Review sit in one
  card; the full device and runtime inventory is collapsed below it.
- **Worktrees** — linked Git worktrees found with `git worktree list --porcelain -z`
  (custom paths, `.claude/worktrees`, Codex worktrees), classified by evidence:
  ready, in use (a confirmed process only), recently touched (a timestamp, not
  ownership), changes, unpublished commits, submodules, locked, missing. The
  page lists removable linked worktrees first, then those needing review, then
  missing ones; the repositories they came from are collapsed context and are
  neither measured nor queried. Facts are read four worktrees at a time, with
  progress, and timestamps before `git status` refreshes the index.
  Removal is `git worktree remove` without force, one confirmation, each worktree
  rechecked first; missing registrations are pruned in their own review
  (`helpers/Worktrees.lua`, `services/Worktrees.lua`).
- **Developer — what can I do about Xcode and friends?** Sections for Xcode &
  simulators, packages & toolchains, projects & editors, containers & virtual
  machines, and AI tools & models, each a ranked list of catalog locations.
- **Storage Map** — the same semantic tree as a sunburst or a squarified
  treemap (segmented Rings / Rectangles), beside a list of the focused node's
  children. Click a group to look inside, click the center or the breadcrumb
  to go back, hover for the path, size and share; the hovered sector brightens in place, and
  selecting a row in the list highlights its sector. Colors are muted category
  colors that lighten with depth; hatching marks rebuildable data. "Worth a
  look" lists the largest rebuildable resources under the focus.
- **Xcode** — Device Support per OS version (the newest per platform is
  kept), DerivedData per project with projects that no longer exist flagged,
  and Archives oldest first. Bulk actions mark older device support and
  build data of missing projects.
- **Projects** — build folders found beside their project files (Node, Rust,
  Maven, Gradle, CMake, SwiftPM, CocoaPods, Python `.venv`/`venv`, Dart,
  Next.js, Turborepo, Godot, Zig, Elixir, Stack, Unity), grouped by project with
  git state (via `git status`, only when the developer tools are installed) and
  when it was last worked on: the newest of `.git/index`, `.git/HEAD` and the
  project's own files, skipping generated folders, within a budget of 5,000
  files. Projects inside a repository are named from it
  (`my-app/apps/mobile/ios`). Projects with uncommitted or unpushed work are
  never marked in bulk.
  Folders are searched where people keep projects (`~/Developer`, `code`,
  `Projects`, `src`, `dev`, `repos`, `GitHub`, `Sites` and folders you add), and
  in Documents, Desktop and iCloud Drive only when Full Disk Access is already
  granted, so macOS never asks once per folder. The search prunes `.git`, the
  Trash, apps and other packages, and stops six levels down. A second proof
  inside the folder (npm's `.package-lock.json`, Cargo's `CACHEDIR.TAG`,
  SwiftPM's `workspace-state.json`, CocoaPods' `Manifest.lock`, Next.js's
  `BUILD_ID`) makes node_modules, Cargo `target`, `.build`, `Pods` and `.next`
  Rebuildable; otherwise they stay Review.
  The same folders also add up per ecosystem, one group under Developer each
  ("Node modules: 1.2 GB in 34 projects"), on the Map, the Developer page and
  Clean Up. Clean Up suggests an ecosystem once its folders together reach
  500 MB, so many small folders are no longer hidden by a per-folder
  threshold.
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
- **Diskmap Help — how do I use Diskmap?** Task-based topics in the style of
  Apple's user guides (get started, see what uses space, free up space
  safely, apps and developer tools, your Mac's disk, privacy and shortcuts),
  each with numbered steps and a button to the page or command it describes.
  The keyboard-shortcut topic is generated from the menu bar.

**First launch** without Full Disk Access opens one sheet before the first
scan: measure everything, move nothing without asking. Open System Settings
goes straight to Full Disk Access (with the "Not in the list? Click +" note).
While the sheet is open Diskmap checks access every second, and once it is on
the sheet closes and the first scan starts by itself. After Settings opens, a
Restart Diskmap link starts a new instance and quits only once it runs, for
when macOS applies access only after a restart. Continue Without Access is
always there. The Overview then lists up to six folders the scan could not
read ("and N more") with a button to the setting. Access is detected by
reading the TCC database, which never makes macOS ask.

The menu bar keeps every classic macOS entry (About, Settings…, Services,
Hide, Quit; Close; Undo through Find; toolbar, sidebar and full screen;
Minimize, Zoom and the window list) and adds **Go** (every page, ⌘1–⌘9, with a
checkmark on the current one) and **Storage** (Refresh ⌘R, Stop Measuring ⌘.,
Empty Trash… ⇧⌘⌫, Storage and Full Disk Access settings, Disk Utility). The
Help menu opens Diskmap Help (⌘?) and the Storage Guide, and its search field
finds help and guide topics as well as menu items.

Every ranking uses one list design: icon, name and location, a status column,
a share bar, the size and a "More" (⋯) button. A row's actions — its primary
action, Show in Finder, the owning category, Keep and Copy Path — live in that
menu and in the row's contextual menu. Clean Up also exposes the selected
suggestion's full explanation and primary Open action beneath the scrolling page.

**Mark, review, act, confirm.** Mark for Cleanup on the Map, Largest Items,
Applications, Xcode, Projects, Duplicates, Disks and Updates pages, or a drop on
the collector revealed during a drag or when items are marked, adds items to one basket;
marking never touches the disk. The Marked toolbar sheet lists them with their
consequences and full paths in a bounded selected-item inspector, starting with
the first pending item. A file inside a marked folder is included through that
folder: its action opens the enclosing mark for review, and unmarking a leaf
never unmarks its whole folder. The sheet moves items to the Trash one at a time, checking each again
first. Marking and moving both refuse the disk root, system folders, mount
points, your home's standard folders, `/tmp` and `/private/var`, the shared
folder and other users' homes, the iCloud Drive and cloud storage roots, Photos,
Music and TV libraries, and anything in Keychains, Preferences, Mail, Messages,
Accounts, Cookies or `~/.ssh`. Paths are compared without regard to case and
through the root's links (`/tmp` is `/private/tmp`), and symlinks are never
followed. Nothing is measured again: each item leaves the model with the
size it was marked with, and each item is checked just before it moves: one whose app is
running (Xcode for DerivedData, a browser for its cache, the parent app of a
helper), whose project file has gone, that was replaced since it was marked
(its inode changed), whose app is installed again (a leftover) or that lies in
a protected system location is skipped with its reason. The sheet then reports
what moved, the skips grouped by reason and free space before, now and after
emptying the Trash. It then offers to empty the
Trash and reports how much more free space macOS actually sees. Every action
is appended to `~/Library/Logs/Diskmap/operations.log` and shown in History.

**Add to Favorites** pins a location at the top of the sidebar with its current
size. The selected location on Storage Map or Largest Locations offers this
action directly, as do the Folder Map and SDK installation sheet. Row menus
can also favorite individual SDK folders or a project's Derived Data folder.
Clicking a favorite opens the same dedicated destination as its source:
an installation's SDK sheet, Derived Data's Xcode page, or the exact folder's
Folder Map. Back and Forward remember favorite folder paths.

A favorite's sidebar menu offers **View Size Changes** and **Remove from
Favorites**. Size changes compare complete measurements with the previous
session, so an interrupted scan never looks like shrinkage. A missing folder
stays listed as Missing, and a bookmark follows a moved or renamed folder.
Favorites persist across launches and are measured on demand or after a scan;
they introduce no background polling.

Categories open their resources in a sheet with Safe/rebuildable, Needs review
and Essential to keep filters. Back, Forward, Refresh, Stop, Clean Up,
Marked, Settings and Search live in the toolbar; search applies to the current
page (on the Map it narrows the list beside the chart, which keeps the whole
level so its proportions stay true). The field names its scope and clears when
changing pages, including Back and Forward. Folder Map has no search filter.
Large Files opens on All measured files; Yours narrows to documents eligible
for review. Both maps offer Up for their parent level; Back and Forward visit
pages. Storage Map and Largest Locations open the originating location
through the same destination, retaining leaf selection in category sheets.
Selected-item buttons name the destination without requiring a double-click.
Inspect Folder Contents opens a location's exact path in Folder Map; Review
Build Data opens Projects. Their amounts distinguish measured folder contents
from generated build data. Overview exposes both discovery entry points.
`--page=<id>` (for example `--page=files`) opens a destination at launch for
screenshots and walkthroughs. The window subtitle shows free and available space (available includes
purgeable storage) and how many items are marked. Sidebar rows show sizes as
badges. The overview explains space no scan can attribute: purgeable storage,
local snapshots and unreadable locations. With **Keep storage history** on in
Settings, category totals are recorded after each scan (no file names), and
the overview shows what grew.

Pages switch instantly and scan progress never animates. The only motion is
the donut and map rings turning to a new level (the arcs' own animation),
and the tour's system push transition; Reduce Motion turns both off.

Launch a page by itself with `--page=<id> --isolated`. Cross-page actions
replace the content in that window; Back and Forward still work. The native
toolbar, search, collector and page actions remain available. Isolated launches
skip onboarding, the tour, process watchers, automatic refresh, Dock opens and
storage-history writes. The default size is 1100×760; the minimum is 724×580
(950×580 with the sidebar). Unknown page ids and `--isolated` without `--page`
are errors.

```sh
./lua-objc apps/diskmap/init.lua --showcase --page=developer --isolated
./lua-objc --capture=/tmp/xcode apps/diskmap/init.lua --showcase --page=xcode --isolated
./lua-objc --dump-layout=/tmp/xcode.xml apps/diskmap/init.lua --showcase --page=xcode --isolated
mkdir -p /tmp/diskmap-pages
DISKMAP_CAPTURE_DIR=/tmp/diskmap-pages ./lua-objc --capture-plan=apps/diskmap/capture.lua apps/diskmap/init.lua --showcase --page=overview --isolated
```

The capture plan visits every sidebar destination in light and dark at both
supported sizes, then captures a larger map, rectangles, empty search and
selection. Omit `--isolated` to capture the full app.

`controllers/Environment.lua` owns one store, checked provider, scan, Keep
choices, basket, operations, inventories and memoized requests. It loads
preferences before constructing sheet requests. Inventories refresh when the
scan finishes, independent of which page is visited. The window controller
owns native presentation, navigation, search and process facilities; only the
primary full window attaches those facilities. Pages receive a router and use
named parameters such as `show("files", {filter = "Installers & archives"})`
or `show("map", {focus = "developer"})`. Templates receive plain data and
explicit actions; there are no field bindings or observation subscriptions.

For tests, `tests/support/diskmap.lua` builds a finished environment with a
recording router and scripted sheet presenters, and mounts any manifest page.
`Mock.new{deferred = true}` queues completions for `step()` or `settle()` so
staleness can be checked without timers. Test providers use `Contract.stub{}`;
System, Mock and showcase implement the same checked contract.

Child previews compute data from those real presentation queries. Supported
fixtures are `hero`, `notMeasured`, `decision`, `kinds`, `changes`, `tips` and
`settings`:

```sh
DISKMAP_FIXTURE=hero ./lua-objc --preview --width=1100 --height=580 --out=/tmp/hero.png tests/support/diskmap_preview.lua
DISKMAP_FIXTURE=settings ./lua-objc --preview --width=460 --height=684 --out=/tmp/settings.png tests/support/diskmap_preview.lua
```

Preview page skeletons and Review with the real isolated window so their
retained refs and native table rows are filled by their controllers.

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

The export is a versioned binary file (`DMOCK002`) containing file paths,
allocated sizes, disk capacity, hard-link accounting, scan completeness and the
time it was taken. Paths are UTF-8 and prefix-compressed against the preceding
path, and the records are LZFSE-compressed: a 218,000-file snapshot takes
1.7 MB instead of 8.4 MB. It never opens
file contents, invokes a shell, or uploads the snapshot. The file is written
with owner-only permissions. macOS may request access while the one-time export
traverses protected folders; the saved mock can then be reopened without
scanning the real disk. If some locations stay inaccessible, the snapshot is
marked partial and remains a lower bound. Restarting Mock HDD restores the
saved snapshot before simulated deletes or Trash operations.

`--mock` uses `~/Library/Application Support/Diskmap/mock-hdd.bin` when that
one-time export exists, and otherwise the bundled synthetic `mock-hdd.bin`.

`--showcase` is the bundled synthetic disk with presentable names, for
screenshots and promotional captures: the volume is “Macintosh HD”, the home
folder is `/Users/appleseed`, demo apps and projects have ordinary names, and
the window title carries no Mock HDD marker. The disk is a family's Mac with a
developer in it: photos, documents, games, device backups, mail and messages
outweigh the Xcode data, simulators and package caches, and the Photos, Music
and TV libraries are measured as if Settings included them. It never reads a
personal export.
`--map-style=rectangles` opens the Map as a treemap. The showreel in
[reels/diskmap](../../reels/diskmap/README.md) is captured this way.

### Changes since the snapshot

The saved export is also the previous state of this Mac. After a live scan,
Diskmap measures the snapshot once with the same catalog — including the apps,
projects and tool files the live scan discovered — and lists the locations
that grew or shrank by 50 MB or more. The overview shows the four largest
changes; Show All lists every one. The per-location totals are cached in
`snapshot-summary` against the snapshot's creation time, so later launches
compare without decoding it again. Export again to move the baseline forward.
File › Compare with Scan… compares with any other export without touching the
cached baseline.
`--mock-file` reads only the selected binary snapshot. Headless tests always
use the synthetic fixture. Both modes avoid the native scanner and shell commands, and show
“Mock HDD” in the window title. File sizes, installed apps, project outputs,
simulators, capacity and snapshots are synthetic. Trash, cache and simulator
actions change only the provider's in-memory copy; restarting restores the
fixture. Finder, owner apps, System Settings and real device commands are not
launched. The real provider remains the default when the mock switch is absent.

Every launch starts a fresh inventory. The category list follows macOS Storage: Applications, Trash, Books, Developer, Documents, iCloud Drive, iOS Files, Mail, Messages, Music, Music Creation, Photos, Podcasts, TV, Other Users & Shared, macOS and System Data, plus AI agents and snapshot backups. Photos, Music, TV and known media support locations are excluded by default, which the Overview says; Include media libraries in Settings measures them and is remembered between launches. Excluded sizes are unknown, never zero. The inventory always covers the whole startup disk (`--folder=<path>` only opens the Folder Map on a folder), and no live scan results are cached. The explicit mock fixture is a synthetic
filesystem for repeatable testing; use `--export-mock` to create a local snapshot
of this Mac.

Scans publish live file and extension findings before a location finishes.
The progress window's bar shows how much of the used space is measured; the
line under it names only the location being measured (`~/.gradle`). Live
rankings say they are incomplete; incomplete coverage is not called unexplained
disk use. When less than 10% of the disk is free, launch bypasses the automatic
tour and offers Review Cleanup while measuring. The Help menu still opens the
tour, and the saved startup preference is preserved.

Simulator devices use `simctl list devices -j` for their current state and
availability. Missing usage dates say Last use unknown. Failed device or
runtime reads show an error and a Retry action, rather than claiming zero
runtimes or available devices. Erase and Delete require a known shutdown state.

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
its fresh result once all of its locations finish. No live scan results or
diagnostics are retained between launches. What persists is what you chose:
Keep choices, watched locations with their last size, the settings (background
checks, media libraries, storage history and notifications), folders added to
Projects, and, once you export a snapshot, that snapshot with its cached
per-location totals (`snapshot-summary`), in Diskmap's Application
Support folder (resolved by `NSFileManager`, so a sandboxed build uses its container).

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

The Xcode `StorageScan` target builds the native `StorageScan.dylib` plugin and
embeds it beside the AppKit runtime in the app's Frameworks directory. Its
worker uses `getattrlistbulk` to fetch metadata
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
Finder performs the deletion and Diskmap takes it out of its totals.

The disk is measured once, at launch or on Refresh. Moving an item to the
Trash, moving it elsewhere, emptying the Trash, removing a worktree or a
simulator changes the model (`Scans:remove` in `models/Scans.lua`): its
location shrinks, a Trash move grows the Trash by as much, and every page is
drawn from the model again without a rescan. A package manager's cache
command changes an unknown amount, so only that one location is measured
again. Diskmap never
deletes SDK internals, removes protected assets, or disables system
protections. Moving to Trash does not free space.
Keep suppresses suggestions for a resource and its descendants and persists
locally. Background checks run every 15 minutes while open and can be paused.
No file contents are read or uploaded; cloud-only files are not downloaded.

The same scan also ranks the 500 largest files over 50 MB, the largest files
not used for a year, per-extension totals and each location's immediate
children (see the [StorageScan options](../../src/plugins/storage/README.md)).
Nothing about individual files is kept after the app quits, except the
locations you watch: their path and last measured size. Individual files
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

Diskmap follows Lapis ([docs/data-driven.md](../../docs/data-driven.md)): every
sidebar destination is a page drawn from a route, and every sheet is a route plus a
view. A route answers `data(state)`, the framework's page controller draws the etlua
view with it, and an action in the view is a method of the route followed by the
same request again. The seven kinds of work are one `workflow` route and the guide
and help are one `topics` route, each page naming its argument in `app.xml`. The
root controller is only the window's code-behind: it wires services, the scan and
the shell (sidebar, menus, history, the cleanup collector). A running scan shows in
one small progress window, which `controllers/ScanProgressController` renders once
and then updates by setting the bar's value and the status text; the pages are
drawn when it finishes. Pages mount retained templates into the content pane; the
root disposes the previous page before mounting the next. The guide re-renders only
when its search changes, so scan progress never collapses the topic being read.
Routes contain no native controls. Services are injected, so tests can exercise
cancellation, preference persistence failures, action routing and fresh startup
independently.

| Module | Owns |
| --- | --- |
| `Store.lua` | The store: the catalog's locations, measurements, Keep, scan state and what services report. Each window binds its own |
| `models/` | The ten Lapis models (`Model:extend`), one per kind of row. Seven are stored tables; `Categories`, `Suggestions` and `Scans` are computed from them, as database views are. Only models read the store |
| `models/Locations.lua` | The catalog's locations: find by id or path, tree relations, registration of discovered locations, Keep and where opening one goes |
| `models/Files.lua`, `knowledge/FileKinds.lua` | Large and unused files, kinds by extension, file ages and per-file Trash eligibility |
| `models/Applications.lua` | Installed apps, their data folders, last use and possible leftovers |
| `models/Projects.lua` | Project build folders grouped by project, git state and age |
| `models/Marks.lua` | Marked items, location refusals and parent/child de-duplication |
| `models/Watchlist.lua` | Watched resources and folders, their previous-session baseline and change |
| `models/Workflows.lua`, `knowledge/Workflows.lua` | The kinds of work (Developer, Music Production, …): a page's ranked rows per section, totals, presence on this Mac and sidebar badge |
| `models/Scans.lua` | The running or last scan and what it writes: each location's measurement, the ranked files, coverage, what could not be read |
| `models/Categories.lua` | The location tree with measurements rolled up: category rows, the overview's chart and shares, the map's nodes, history of totals |
| `models/Suggestions.lua` | Cleanup suggestions ranked by eligible bytes, confidence and effort; the Clean Up page's presentation |
| `helpers/Simulators.lua`, `helpers/Worktrees.lua`, `services/Simulators.lua` | Device, runtime and worktree inventories: filters, summaries and validated commands over an inventory a service read |
| `catalog/` | Independent category definitions, paths, ownership and consequences |
| `routes.lua`, `pages/` | Every page by route name, one route file per page or small group; `pages/ListRoute.lua` is the base route of the list pages. `pages/Sheets.lua` gathers the sheets in `pages/sheets/`, which extend `pages/SheetRoute.lua` |
| `flows/Rows.lua`, `flows/Keep.lua`, `flows/Manage.lua` | Row menus and marks, Keep, and acting on one location: action code every page shares |
| `helpers/` | Pure computation and formatting over rows given as arguments: file kinds, path guards, the folder tree, the simulator plan, parsers of service output. No helper reads the store, a model or a file (`tests/diskmap_layers.test.lua`) |
| `helpers/Constraints.lua` | Named validation results for registration, Keep and Watch changes and Trash mutations |
| `controllers/` | The shell: sidebar navigation, menu commands, the scan's progress window, and `SheetController`, which presents every sheet |
| `views/pages/Page.etlua` | The list page. Every page that ranks storage in lists is this template and a `layout` table: header buttons, stat tiles, sections (title, filter, buttons, empty states, list) and a footnote |
| `services/Provider.lua`, `services/Mock.lua`, `services/System.lua`, `services/Scanner.lua`, `src/plugins/storage/StorageScan.m` | Provider selection, synthetic filesystem, actual system integration and native bulk metadata enumeration |
| `views/` | All presentation, etlua loops and reusable partials |

`Locations` owns one row for every catalog location. Use `Locations:find(id)`,
`Locations:roots()`, `Locations:leaves()` and `Locations:owner(path)` for queries;
rows answer `parent()`, `children()`, `isLeaf()`, `measurement()`, `isKept()`,
`validateTrash()` and `destination()`. Relation sequences are snapshots for reading,
and structural registration goes through `Locations:add(parentId, definition)` so
IDs, exact paths and parent links remain atomic within the store. Discovered agent
metadata uses the same registration path, making repeated discovery idempotent.
Routes explicitly project row fields into presentation tables, so relations never
leak into views.

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

## Opening a resource, and pages for kinds of work

Every list, menu and link opens a resource by its own id through
`Controller:open(id)`, and `Location:destination()` decides where that goes.
The catalog declares the exceptions on the resource itself: `page` names the
sidebar page that presents it and everything under it (Developer projects and
build folders on Projects, Simulator devices on Simulators, DerivedData,
device support and archives on Xcode, apps on Applications) and `sheet` a
sheet of its own (an Xcode installation's SDKs). Anything else opens its
category's list, largest first: a group as itself, a location in its group
with its row selected. No page routes on its own.

A kind of work is one entry in `knowledge/Workflows.lua`: its name and
symbol, the sections of its page, and the catalog groups, roots or single
locations each section lists. The `workflow` route presents an entry from
`models/Workflows.lua` for the page that names it in `app.xml`, so adding a page for another
profession is a table entry plus the catalog locations it cites
(`catalog/MusicCreation.lua`, `catalog/Creative.lua`, `catalog/Games.lua`).
A page appears in the sidebar only on a Mac that has its data: one of its
`markers` exists, or its locations measure at least `visibleBytes`.

A page that ranks storage in lists has no template of its own. It is a
`layout` table rendered by `views/pages/Page.etlua`: Largest Items, Large Files,
Duplicates, Clean Up, Applications, Disks & Volumes, Xcode, Projects, a
watched location and every kind of work. Its route extends `pages/ListRoute.lua`
with a `layout`, `present(self, state)` and its actions. A page that reads
folders, runs a search or keeps a filter keeps that state on its page and starts
its service requests in `activate`. Only pages with a presentation of their own keep a template: the Overview,
the two maps, File Types, Simulators, Updates & Snapshots and macOS Folders.

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

## Added for issues #36 and #37

- **Applications** leftovers carry High, Medium or Low confidence in their
  evidence. The leading action counts likely leftovers still available to mark
  in the current search, then offers Review Marked Items. Marking stages items;
  removal follows the separate final review.
- **Duplicates** compares files byte for byte, only in folders you add, and
  counts only unshared (non-clone) blocks as reclaimable.
- **Disks & Volumes** analyzes an external disk's top level on request and
  explains `.Trashes`, `.Spotlight-V100` and other hidden system folders.
- **File › Open Scan…, Compare with Scan… and Export Scan…** use the
  metadata-only format of `--export-mock`.
- **Settings › Notifications**: an opt-in monthly reminder of what grew, and an
  opt-in offer to mark an app's leftovers when it is moved to the Trash. Both
  need the app bundle (`make diskmap-app`).
- The scan reports logical sizes (sparse files) and iCloud-only files and never
  downloads them; see `docs/research/STORAGE_SCAN_BENCHMARK.md` for the
  concurrent scanner's benchmark.
- Lists and the map drag as Finder items; the map takes keyboard navigation
  and type-to-filter; mouse back/forward buttons and ⌘[ ⌘] navigate.
