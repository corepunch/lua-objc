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
# Save real measurements after each completed scan; select categories to measure more.
./lua-objc apps/diskmap/init.lua --write-cache=/tmp/diskmap.json
# Replay without filesystem scans or cleanup; missing/bad caches show an error.
./lua-objc apps/diskmap/init.lua -cache=/tmp/diskmap.json
# Bundled synthetic fixture, never presented as measurements of your computer:
./lua-objc --screenshot=/tmp/diskmap.png apps/diskmap/init.lua \
  -cache=tests/fixtures/diskmap.json
```

Cache files must match the current catalog version (2); regenerate older caches
to avoid replaying totals from before asset categories were split. They contain JSON, ID-keyed measurements and capacity. They are
parsed as data, never executed. Both `-cache=` and `--cache=` work after the app
path. Cache mode disables background checks and cleanup actions, and is visibly
labeled. It does not overwrite the supplied cache. The fixture has invented sizes
for visual verification. Normal startup never uses that fixture.

## Measurement and actions

Startup checks the developer allowlist and exact known system asset classes. Select a category and choose
Measure Category to opt into its known locations; denied access stays unknown.
Scans run in a worker, skip symbolic links and mounted descendants, and report
allocated bytes. Parent buckets exclude separately classified descendant roots.
Hard links are deduplicated within each measurement batch; independent batches,
APFS shared extents and snapshots can still prevent physical-capacity parity.
The signed unreconciled difference is displayed, never called disposable junk.

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
