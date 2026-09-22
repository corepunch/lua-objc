# Storage Settings sizing investigation

Investigated locally on 2026-09-22, macOS 27.0 build 26A428. This is evidence
from the installed binaries and runtime, not a claim about every macOS release.
Diskmap continues to target macOS 26 and later.

## What the installed Storage panel does

`/System/Library/ExtensionKit/Extensions/Storage.appex/Contents/MacOS/Storage`
links `SpaceAttribution`, `StorageManagement`, `DiskManagement`, and `StorageUI`.
Its ARM64 disassembly references `SAVolumeSizer`, `SAAppSizer`, and
`STMSizeDirectoryWithExcludedChildURLs`. Imported symbols also include
`NSMetadataQuery` and `kMDItemPhysicalSize`; a predicate string identifies the
large-file query. This does not establish that Spotlight supplies all category totals.

Runtime inspection of SpaceAttribution exposes:

- `SAAppSizer.startObservingWithUpdateHandler:` and
  `startObservingWithScanOptions:updateHandler:`.
- `SAURLSizer.startObservingURLs:updateHandler:`.
- `SAVolumeSizer.computeSizeOfVolumeAtURL:completionHandler:`.
- `SAAppSizerCacheManager.getLastCachedAppSizes:maxAge:reply:`.
- `SASupport.getDirStatInfoForPath:orFD:withOptions:info:`.

The Storage binary contains `Caching volume sizes: Mount Point: %s, sizes: %s`.
The `spaceattributiond` binary contains diagnostics for directory-stat counters,
clone groups, purgeable allocation, multiple scanning threads, and cached versus
non-cached queries. Taken together, these support a mixed system accounting and
scanning architecture. They do not prove which source served a particular number
shown on screen, or how recently it was calculated.

## Ordinary-process probes

The supplied probes load the framework and request sizing with default options.
They do not call internal APIs that change scan policies, write caches, enable
filesystem counters, register paths, or alter security settings.

Both the app and URL observers returned `NSCocoaErrorDomain` 4099 (could not
communicate with helper) in approximately 9 ms outside the tool sandbox. The
volume callback returned no result. Focused unified logs showed the
framework-to-daemon connection being invalidated. Running inside the sandbox
also failed; removing that sandbox did not fix the service connection.

The Storage extension's signed entitlements include `com.apple.storage-data`
and private TCC allowances. This is evidence that its privileges differ from
Diskmap's, but the observed error alone does **not** identify an entitlement
check as the cause. The private helper may also be unavailable on this build.
No private entitlement was forged or added to Diskmap.

Read-only directory-stat queries for `/Applications`, the user's home,
`~/Library/Developer`, and `/System/Volumes/Data` returned errno 45 (`ENOTSUP`)
outside the sandbox and reported no enabled statistics hierarchy. These
locations therefore provided no usable fast directory totals to this probe.

## Implemented outcome

Diskmap loads `StorageScan.dylib` through `App.loadNativePlugin`. It uses the
public Darwin `getattrlistbulk(2)` API to read many entries' metadata per call,
replacing the Perl scanner and its temporary JSON/worker-process protocol.
A user-initiated worker queue performs the scan; Lua polls immutable snapshots. Worker code
never holds or calls a Lua state. Cancellation and garbage collection signal
only that job, and abandoned/incomplete roots are never marked complete.

The complete catalog retains one shared device/inode ownership ledger. Native
bulk allocation sizes include file forks; directories are measured with `fstat`.
Unavailable per-entry attributes are checked with `fstatat`. Symbolic links are
not followed, root ancestors are opened individually with `O_NOFOLLOW`, mounted
descendants are skipped, and catalog exclusions prevent parent/child overlap.
No file content is read and no scan result is saved or reloaded. APFS clone and
snapshot allocation still cannot be reconciled exclusively by summing file
metadata; the existing unreconciled accounting remains necessary.

The local SDK `getattrlistbulk(2)` and `getattrlist(2)` manuals define the buffer
contract. One observed detail matters: directory records omit the file-attribute
section even with `FSOPT_PACK_INVAL_ATTRS`, so the parser selects the fixed record
size by object type before locating variable-length names.

Initial same-path comparison (`/Applications` and this repository): both scanners
reported 372,561 visited entries, zero errors, and identical allocated totals;
old wall time was 9.79 s and native scan time 5.985 s. The old scan ran first, so
filesystem warming can influence this comparison. This is not a benchmark of
System Settings or a guarantee of whole-disk speed.

## Reproduce inspection

```sh
otool -L /System/Library/ExtensionKit/Extensions/Storage.appex/Contents/MacOS/Storage
nm -arch arm64e -u /System/Library/ExtensionKit/Extensions/Storage.appex/Contents/MacOS/Storage
otool -arch arm64e -tvV /System/Library/ExtensionKit/Extensions/Storage.appex/Contents/MacOS/Storage > /tmp/storage-disassembly.txt
clang -fobjc-arc -framework Foundation docs/research/storage-sizing/introspect.m -o /tmp/storage-introspect
/tmp/storage-introspect
clang -fobjc-arc -framework Foundation docs/research/storage-sizing/probe.m -o /tmp/storage-probe
/tmp/storage-probe
clang -fobjc-arc -framework Foundation docs/research/storage-sizing/dirstats.m -o /tmp/storage-dirstats
/tmp/storage-dirstats
```

The probe source records inferred callback signatures, verified against runtime
method encodings and the panel's block metadata where available. These private
interfaces are investigation tools, not production dependencies. The runnable
probe waits at most ten seconds; regression tests never depend on these services.

A second same-path comparison ran native first: 6.889 s native versus 16.05 s
old wall time. Both visited 372,567 entries with identical totals and zero
errors. The six additional entries reflect the intervening repository edits;
no edits were made between the two scanners in that comparison. Timings varied,
but the native scanner was faster in both orders.

A complete fresh native catalog scan finished all 153 roots in 44.329 s,
visited 2,062,816 entries, and reported 989 unavailable locations with no overall
scan failure. Unavailable locations remain partial/unknown in the UI. These
measurements describe this machine and its then-current filesystem state only.

Live UI verification also exercised the production `System.await` polling path:
all 153 roots completed successfully in 84.864 s after selecting user-initiated
worker priority and suppressing unchanged progress refreshes. An earlier live
run on a utility queue took 94.214 s. These runs were not controlled sufficiently
to attribute the entire difference to those changes; the live app times also show
why the synchronous 44-second scan must not be presented as a UI latency promise.
The packaged app's signature and native plugin loading were verified. Desktop
window capture was unavailable, so its loading state was inspected through the
runtime's internal native-content screenshot instead.
