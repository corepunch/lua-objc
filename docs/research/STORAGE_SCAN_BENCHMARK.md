# StorageScan benchmark

Issue #37 item 7 asked how Diskmap's scanner (`src/plugins/storage/StorageScan.m`)
compares with BlitzTree's published method, and to write the answer down.

## Method

`benchmarks/storage_scan.lua` runs the plugin synchronously on one folder and
prints entries visited (files and directories), `getattrlistbulk` calls,
elapsed seconds and allocated size. Peak memory comes from `/usr/bin/time -l`.
The baseline is `du -skx` on the same folder, which BlitzTree also uses.

```sh
make
/usr/bin/time -l ./lua-objc benchmarks/storage_scan.lua "$HOME/Developer"
/usr/bin/time du -skx "$HOME/Developer"
```

"Warm" means the folder was just scanned, so the kernel's metadata caches are
full. A true cold run needs a reboot, because purging caches requires root.
The only cold figure below is from the first run after a period of other
work, and it is labelled that way.

Machine: MacBook with Apple M1, 8 cores, internal SSD, macOS 26.

## Results

| Folder | Entries | Scanner | Seconds | Entries/s | Peak RSS |
|---|---|---|---|---|---|
| `~/Developer` | 492,006 | sequential (before) | 10.2 | 48,000 | 61 MB |
| `~/Developer` | 492,006 | concurrent (now) | 2.05 | 240,000 | — |
| `~/Developer` | — | `du -skx` | 11.9 | — | — |
| `~` | 967,473 | sequential (before), warm | 25.5 | 38,000 | 81 MB |
| `~` | 967,474 | concurrent (now), warm | 12.9 | 75,000 | 88 MB |
| `~` | 967,456 | concurrent (now), first run | 99.6 | 9,700 | 67 MB |
| `~` | — | `du -skx`, warm | 29.5 | — | — |

For comparison, BlitzTree publishes 3.1 million entries in 10.2 s on an M4
(about 300,000 entries/s), against 65 s for `du -skx`. That is 6.4 times `du`.
Diskmap is now 5.8 times `du` on `~/Developer` and 2.3 times `du` on the
whole home folder. The home folder has fewer, larger directories, and TCC
refuses some of them. Both runs report identical entry counts and sizes.

## What changed

- **Several directories in flight.** The scanner was a single recursive walk,
  so every `getattrlistbulk` call waited for the previous one. User CPU time
  was 0.5 s out of 10 s: the walk was waiting on the kernel, not computing.
  Subdirectories within four levels of a root are now walked concurrently
  with `dispatch_apply` at user-initiated QoS. Deeper levels continue on the
  thread that reached them, which bounds the number of threads.
- **Shared state behind one lock.** The hard-link identity table, counters,
  issues and file summaries are guarded by an `os_unfair_lock`. A file
  reachable through several hard links is still counted exactly once
  (`tests/storage_scan.test.lua` checks this across concurrent folders).
- **Exports stay sequential.** `--export-mock` writes paths with prefix
  compression, which needs path order, so export scans walk one directory at
  a time.
- **Metadata only, never downloads.** Scan threads set
  `IOPOL_MATERIALIZE_DATALESS_FILES_OFF`, and folders iCloud evicted are
  counted, not entered. Evicted files and the logical size of sparse files
  are reported per root (items 9 and 10 of #37).

## Considered and not adopted

- **Flat arrays across the C interface.** BlitzTree hands Swift the whole tree
  as flat arrays. StorageScan returns one total per catalog root, plus
  bounded summaries (largest files, extensions, one level of breakdown). No
  tree crosses into Lua, so there is nothing to flatten.
- **Memoized widening (remeasuring only changed parents).** Diskmap measures a
  fixed catalog of roots on each refresh, and the concurrent scan of a whole
  home folder takes about 13 s warm. Correct incremental remeasurement needs
  a durable FSEvents event ID per root and a fallback full scan when history
  is dropped. The gain does not yet justify a second path that could report
  stale sizes. The directory watcher added to the framework for #37 (see
  `ns.watchDirectory`) is the building block if it becomes worthwhile.

## Target

Issue #36 set a target of a whole-Mac inventory in 20 s or less on Apple
silicon. The home folder, where Diskmap spends nearly all of its time, now
takes about 13 s warm on an M1.
