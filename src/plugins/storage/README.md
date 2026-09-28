# StorageScan native Lua plugin

The Diskmap Xcode project builds this as a standalone `StorageScan.dylib`
target and embeds it beside `AppKit.dylib` in `Contents/Frameworks`. It is a
service module, not a second AppKit runtime. Lua symbols resolve from the host's
runtime. Diskmap loads it through `App.loadNativePlugin`.
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
- `treeDepth = N`, `treeMinimumBytes = B`: `folders[i]` is root i as a tree
  `{name, kb, used, directory, children, otherKb, otherCount}` listing N levels.
  Each folder keeps its 200 largest children of at least B bytes, largest
  first, and sums the rest into `otherKb`/`otherCount`; pruning happens as
  each folder finishes, so memory stays bounded. A folder below the depth has
  `deeper = true` and no `children`. `used` is the latest use of anything
  inside. Diskmap's Folder Map scans a deeper folder on its own when opened.
- `logicalRoots = {[physical] = logical}` reports a root under the path people
  know, as the startup disk's Data volume is known as `/`.

`progress(job)` returns the number of items met so far while a scan runs; the
snapshot itself is published only as each root finishes.

Hard-linked files count once in every summary, as in `trees`. Dates come from
the same `getattrlistbulk` records; no file is opened.

`scan(roots, exclusions)` runs the same engine synchronously for command-line tools
and small headless regression fixtures. UI code must use `start`/`poll`.

`exportStart(roots, exclusions, outputPath, metadata)` streams only file paths and
allocated byte counts into a private temporary versioned binary file, then atomically
renames it to `outputPath`. The uncompressed 72-byte `DMOCK002` header records format
version, flags, disk capacity, available bytes, item count, scan errors, visited count,
creation time (Unix seconds) and the length of the compressed body. The body is one
LZFSE stream (Compression.framework) of records; each stores a common UTF-8 path prefix,
the remaining path bytes, allocated size, and a `countedBytes` value so hard links do not
inflate mock totals. Prefix-shared paths compress to about a fifth of their raw size.
`metadata.logicalRoots` can map a physical scan root to its user-visible path. The writer
does not retain the full file list in memory and does not open file contents.
`poll(job)` reports the exported file count when the job completes; cancellation
publishes a valid partial snapshot when the file writer itself is healthy.

`snapshotRecords(path)` returns a function that yields the snapshot's decoded record
bytes in chunks, then `nil`. It checks the recorded body length against the file, so
truncated, corrupt and trailing data raise an error. The Lua reader parses the header
and records (`apps/diskmap/services/Mock.lua`).

All paths must be absolute UTF-8 strings without NUL, `.` or `..` components.
Exclusions apply to descendants; an explicitly requested root is always attempted.
Hard links and duplicate roots share a device/inode ledger within one scan. A new
scan always creates a new ledger and rereads metadata. No persistence is involved.

Snapshots contain `trees` (allocated `kb`, `partial`), `rootStates`,
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
exclusive APFS clone/snapshot allocation: a clone's blocks are reported under
every file sharing them. A root that is a volume's mount point is therefore
capped at the space the volume uses (`ATTR_VOL_SPACEUSED`, the figure Disk
Utility shows): its tree carries `volumeKb` and `sharedKb`, the amount the file
sum exceeded it by, and its breakdown children are scaled to add up to the
capped total. Other roots report `volumeKb = 0`.

Values keep their types in Lua: flags are booleans, counts are integers, sizes
in kilobytes are floats, and strings keep embedded NUL bytes.

See [the investigation](../../../docs/research/STORAGE_SIZING.md) for the private
Apple-service probes and timing evidence, and `tests/storage_scan.test.lua` for
fixtures covering allocation, repeated scans, cancellation, and metadata parsing.

`commandStart(argv)` / `commandPoll(job)` provide asynchronous Foundation task
execution for storage-owner tools such as simctl. Arguments are a validated UTF-8
array; no shell interpolation is involved. Poll returns `(done, {ok, output})`.
Output combines stdout/stderr, is capped at 8 MiB, and a 60-second watchdog asks the
process to terminate. The worker drains pipes independently of the Lua event loop.
Only the app's model chooses allowed actions and exact resource identifiers.
