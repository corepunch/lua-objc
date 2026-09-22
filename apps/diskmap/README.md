# Diskmap

A native macOS 26 storage manager organized by semantic categories, not folders.
Expand Developer, System Data, Applications, Backups and other categories to
understand ownership and consequences. Settings stays at the bottom of the
native sidebar. The inspector exposes locations only as supporting evidence.

```sh
make
./lua-objc apps/diskmap/init.lua
make diskmap-app
```

`Catalog.lua` contains the macOS knowledge tree: more than 140 named resources,
including Xcode runtimes, devices, bundled SDKs, archives, package managers,
AI coding tools, system assets, app support, backups, media and boot data.
New layouts remain review-only until their ownership and cleanup policy are
verified. Arbitrary custom installations and every third-party app are not yet
automatically discovered. Known asset classes give Siri, Dictation/shared speech recognition, voices,
Apple Intelligence, translation, Photos models, wallpapers, fonts and dictionaries
separate totals. Unrecognized classes remain in an explicit residual bucket.
Rounded semantic badges use white SF Symbols; app-owned resources use artwork
resolved from installed application bundles, with a symbol fallback.

## Fast repeatable UI tests

```sh
# Save real measurements and scanner diagnostics after each complete scan.
./lua-objc apps/diskmap/init.lua --write-cache=/tmp/diskmap.json
# Replay without filesystem scans or cleanup; missing/bad caches show an error.
./lua-objc apps/diskmap/init.lua -cache=/tmp/diskmap.json
# Bundled synthetic fixture, never presented as measurements of your computer:
./lua-objc --screenshot=/tmp/diskmap.png apps/diskmap/init.lua \
  -cache=tests/fixtures/diskmap.json
```

Cache files must match the current catalog version (3); regenerate older caches. They contain JSON, ID-keyed measurements, capacity, completion time, entry count,
duration and up to 1,000 access-failure paths. Normal launches save the latest
scan to `~/Library/Application Support/Diskmap/last-scan.json`; `--write-cache`
selects another destination. They are
parsed as data, never executed. Both `-cache=` and `--cache=` work after the app
path. Cache mode disables background checks and cleanup actions, and is visibly
labeled. It does not overwrite the supplied cache. The fixture has invented sizes
for visual verification. Normal startup never uses that fixture.

## Measurement and actions

Startup and refresh measure every catalog path in one background batch, including
Applications, Documents, media, backups, Trash, developer projects, system data,
and residual roots for files outside named categories. Parent buckets exclude
all separately classified descendants. This closes the former startup allowlist
gap without double counting folders. Every measured category has its own bar
segment; Unreconciled is separate from measured Other files.

Scans inspect allocated file blocks, skip symlinks (including linked root ancestors)
and mounted descendants, and deduplicate hard links across the whole batch.
Confirmed missing paths count as zero, permission failures remain partial or
unknown, and snapshot exclusive allocation is explicitly system managed. APFS
shared extents and snapshots can still prevent physical-capacity parity. The
signed unreconciled difference is displayed, never called disposable junk.
Category refresh also scans the full ledger so independent batches cannot
reassign hard-link ownership and corrupt totals.

Only DerivedData, npm downloads, pip cache and Homebrew downloads offer reviewed
Move to Trash. Other entries reveal their location or open the owner/system
settings. Diskmap never empties Trash, deletes SDK internals, removes protected
assets, or disables system protections. Moving to Trash does not free space.
Keep suppresses suggestions for a resource and its descendants and persists
locally. Background checks run every 15 minutes while open and can be paused.
No file contents are read or uploaded; cloud-only files are not downloaded.

The app and framework changes are described in [DESIGN.md](DESIGN.md).

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
