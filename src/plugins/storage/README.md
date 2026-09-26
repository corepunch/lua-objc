# StorageScan native Lua plugin

Built by `make` as `build/StorageScan.dylib`. This is a standalone service module,
not a second AppKit runtime. Lua symbols resolve from the host's existing runtime.
Diskmap loads it through `App.loadNativePlugin` and bundles it beside AppKit.dylib.
The plugin depends on public Foundation/Darwin APIs, not SpaceAttribution.

```lua
local App = require("App")
local scan = App.loadNativePlugin(assert(package.searchpath("StorageScan", package.cpath)), "StorageScan")
local job = scan.start({"/Applications"}, {})
-- Poll from the application's async loop; polling itself does not block.
local done, result = scan.poll(job)
scan.cancel(job)
```

`start(roots, exclusions)` returns native userdata. `poll(job)` returns a boolean
and either nil (no completed root yet) or a plain Lua snapshot. `cancel(job)` is
idempotent. Job GC also requests cancellation. Only immutable Foundation snapshots
cross the worker boundary; no worker calls Lua, so callbacks cannot reach a closed
Lua state. The code image is pinned until process exit to cover workers completing
filesystem calls after state teardown. The worker releases its per-scan identity
ledger when it finishes.

`start(roots, exclusions, options)` and `scan(roots, exclusions, options)` accept
optional summaries computed during the same walk, published only with the final
snapshot:

- `files = N`, `minimumFileBytes = B`: `largeFiles`, the N largest counted
  regular files of at least B bytes (capped at 2,000), each `{path, bytes,
  modified, used}`; `used` is the later of modification and access time.
- `oldBefore = seconds`: `oldFiles` ranks files last used before that time the
  same way, and `oldBytes`/`oldCount` total all of them.
- `extensions = true`: `extensions`, one `{extension, bytes, count, oldBytes}`
  row per lowercase extension (at most 4,096 rows; the rest join `""`).
- `breakdown = true`: `breakdowns[i]` lists root i's immediate children as
  `{name, kb, directory}` (at most 5,000 per root), excluding excluded paths.

Hard-linked files count once in every summary, as in `trees`. Dates come from
the same `getattrlistbulk` records; no file is opened.

`scan(roots, exclusions)` runs the same engine synchronously for command-line tools
and small headless regression fixtures. UI code must use `start`/`poll`.

`exportStart(roots, exclusions, outputPath, metadata)` streams only file paths and
allocated byte counts into a private temporary versioned binary file, then atomically
renames it to `outputPath`. The `DMOCK001` header records format version, disk
capacity, available bytes, item count, scan errors, and visited count. Each record
stores a common UTF-8 path prefix, the remaining path bytes, allocated size, and a
`countedBytes` value so hard links do not inflate mock totals. `metadata.logicalRoots`
can map a physical scan root to its user-visible path. The writer does not retain the
full file list in memory and does not open file contents. `poll(job)` reports the
exported file count when the job completes; cancellation publishes a valid partial
snapshot when the file writer itself is healthy.

All paths must be absolute UTF-8 strings without NUL, `.` or `..` components.
Exclusions apply to descendants; an explicitly requested root is always attempted.
Hard links and duplicate roots share a device/inode ledger within one scan. A new
scan always creates a new ledger and rereads metadata. No persistence is involved.

Snapshots contain `trees` (allocated `kb`, optional `partial`), `rootStates`,
`completed`, `total`, `visited`, `bulkCalls`, `seconds`, `errors`, `issues`, and
`failure`. The root-state array supplies ordering even when a tree entry is nil.
States are `measured`, `missing`, `skipped`, or `unreadable`. A failure or cancellation
leaves unfinished roots out of the result. Issues are capped at 1,000 records while
the error count continues to grow. The engine has a ten-minute deadline and a
256-directory depth limit; exceeding the depth marks that root partial.

`getattrlistbulk` returns allocated file sizes in directory batches. File metadata
missing from a bulk record is read through `fstatat`; no file contents are opened.
Mounted descendants and symlinks are skipped. Unsupported directory enumeration
is reported as an issue, not silently converted to zero. File sums do not provide
exclusive APFS clone/snapshot allocation.

See [the investigation](../../../docs/research/STORAGE_SIZING.md) for the private
Apple-service probes and timing evidence, and `tests/storage_scan.test.lua` for
fixtures covering allocation, repeated scans, cancellation, and metadata parsing.

`commandStart(argv)` / `commandPoll(job)` provide asynchronous Foundation task
execution for storage-owner tools such as simctl. Arguments are a validated UTF-8
array; no shell interpolation is involved. Poll returns `(done, {ok, output})`.
Output combines stdout/stderr, is capped at 8 MiB, and a 60-second watchdog asks the
process to terminate. The worker drains pipes independently of the Lua event loop.
Only the app's model chooses allowed actions and exact resource identifiers.
