# Diskmap

A native macOS 26 storage browser with measured cleanup suggestions. All screens
are etlua; domain rules live in Model.lua and filesystem IO in services/.

## Run and package

```sh
make
./lua-objc apps/diskmap/init.lua
# Explicitly scan a folder:
./lua-objc apps/diskmap/init.lua /path/to/folder
make diskmap-app
open build/Diskmap.app
```

The bundle includes Lua, the runtime, templates and worker. It does not need a
Homebrew Lua installation on the destination machine. The worker uses macOS's
`/usr/bin/perl` and its core JSON::PP module. The build targets the build machine's
architecture; verify on each architecture before distributing it.

`make diskmap-app` produces an ad-hoc signed local build. Set
`DISKMAP_SIGN_IDENTITY` to a Developer ID Application identity for hardened-runtime
signing. Public distribution also requires notarization and stapling with your
Apple developer credentials; those steps are not performed by the build.

## Permissions and privacy

Startup does **not** recursively scan the home folder. It shows volume capacity
and checks a small allowlist of developer/cache paths. Background checks repeat
every 15 minutes while the app is open and can be paused in Settings. That choice
is saved in `~/Library/Application Support/Diskmap/background`.

Backups, Docker's container, application caches, logs and Trash are on-request
suggestions. “Measure This Location” opts into checking that location. “Scan
Folder” uses the native folder chooser; folder navigation scans only after a user
action. macOS may request access for protected descendants. Denied access remains
unknown or a partial measurement, never a fabricated zero. Full Disk Access is
optional for broader coverage. Background checks retain only aggregate sizes,
not per-file result lists. No scan opens file contents, follows symbolic links,
downloads cloud-only content, or sends data off the machine.

## Measurement and cleanup

- Allocated blocks, not logical file lengths. Sparse holes do not count.
- Hard links count once per scanned root. Filesystem boundaries are not crossed.
- A folder scan provides immediate child totals, the largest 500 files of at least
  1 MB, application bundles and file-extension totals.
- APFS shared/cloned extents, snapshots and concurrent changes mean measured
  bytes are not guaranteed recovered bytes. Permission failures are reported.
- Only four exact locations can be moved to Trash: Xcode DerivedData, npm's
  `_cacache`, pip cache and Homebrew downloads. Each requires a native confirmation
  explaining consequences. Symbolic-link ancestors are rejected.
- Archives, device backups, simulator data, Docker volumes and general app caches
  require review in Finder or the owning app. They are never bulk-deleted.
- Moving to Trash does not free storage. Finder controls emptying and restoration.
- Time Machine snapshots are explained in Settings and never deleted.

The allowlist covers standard locations. Custom package-cache locations, alternate
Docker stores, and every possible creative/media application are not auto-detected.
Missing standard paths are omitted after checking; unreadable ones remain unknown.

## Verification

```sh
./lua-objc tests/diskmap.test.lua
./lua-objc tests/bridge.test.lua
./lua-objc tests/mail_workspace.test.lua
```

Diskmap tests cover scanner metadata, hard links and unusual filenames, policy
allowlists, unknown/partial sizes, startup access boundaries, real native tables,
three-pane geometry, search, cancellation, stale completions and navigation.
See [research and source notes](../../docs/research/DISKMAP_STORAGE_SUGGESTIONS.md).
