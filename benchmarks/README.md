# Large collection benchmark

Both implementations render the same `Item N` text rows at 1,000 and 5,000
items. The Mac harness compares an eager stack with native `List`, plus a
SwiftUI eager stack, `LazyVStack`, and `List`:

```sh
make
benchmarks/run_list.sh
```

Each scenario runs in a fresh process. The reported time covers construction
and one initial 800 × 600 layout without a window. `/usr/bin/time -l` reports
peak process resident memory. It is not a first-frame or scroll benchmark.

## iPhone ProMotion run

`apps/list-benchmark/` is a bundled iPhone benchmark app. Its native probe
programmatically scrolls a `UITableView` or `UIScrollView` at 1,500 points per
second. It reports the first four seconds and keeps scrolling for 30 seconds
so Instruments can attach. `benchmarks/swiftui_device.swift` applies the same
scroll path to SwiftUI `VStack`, `LazyVStack`, and `List`. Both use
`CADisplayLink` with a 120 Hz preference and sample process `phys_footprint`.
The host Info.plist enables the full ProMotion frame-rate range using
`CADisableMinimumFrameDurationOnPhone`.

`BENCH_RESULT` reports the delay from controller/scene construction to the
first display-link callback, callback cadence, gaps longer than two display
periods, longest callback gap, and peak sampled footprint. A display-link
callback is a pacing proxy, not proof that every frame was presented. Use an
Instruments Animation Hitches trace for rendered-frame confirmation.

On a physical iPhone 14 Pro Max (iOS 26.6.2, 120 Hz display), one run on
2026-09-23 produced:

| Container | Rows | First callback | Callback rate | Gaps over 16.7 ms | Peak footprint |
|---|---:|---:|---:|---:|---:|
| lua-objc eager VStack | 1,000 | 111 ms | 120.2/s | 0 | 40.3 MiB |
| lua-objc native List | 1,000 | 49 ms | 119.7/s | 2 | 23.8 MiB |
| lua-objc eager VStack | 5,000 | 489 ms | 72.8/s | 42 | 137.1 MiB |
| lua-objc native List | 5,000 | 128 ms | 119.6/s | 1 | 32.1 MiB |
| SwiftUI eager VStack | 1,000 | 127 ms | 120.2/s | 0 | 49.4 MiB |
| SwiftUI LazyVStack | 1,000 | 39 ms | 120.2/s | 0 | 15.4 MiB |
| SwiftUI List | 1,000 | 80 ms | 120.1/s | 1 | 16.8 MiB |
| SwiftUI eager VStack | 5,000 | 549 ms | 118.1/s | 1 | 193.8 MiB |
| SwiftUI LazyVStack | 5,000 | 31 ms | 120.1/s | 0 | 15.5 MiB |
| SwiftUI List | 5,000 | 54 ms | 119.7/s | 1 | 16.9 MiB |

The simple-row native List stays far below the reported 440 MB anecdote, but
that anecdote used unspecified row complexity and is not a controlled
comparison. SwiftUI's lazy containers used less memory than lua-objc List in
this run. Callback cadence is a pacing measurement, not presented FPS.

An Instruments **Animation Hitches** trace of the 5,000-row lua-objc List on
the same phone reported 116, 120, 120, 119, 120, 118, and 120 display surface
swaps in the seven full seconds from trace time 2 through 9 (119 per second on
average). It attributed two 8.34 ms potential hitches to the benchmark
process in the first two seconds. The display swap table is device-wide, so
this is evidence of near-120 Hz foreground presentation rather than an exact
per-app frame count. Record with `xcrun xctrace record --template 'Animation
Hitches' --device DEVICE_ID --attach PID --time-limit 10s --output
/tmp/list.trace`; use `xcrun xctrace export --input /tmp/list.trace --toc` to
locate `displayed-surfaces-per-second` and `hitches`.

Build a self-contained lua-objc benchmark bundle and a matching SwiftUI bundle:

```sh
make -f scripts/ipad/build.mk SDK=iphoneos APP=list-benchmark \
  DEVICE_FAMILY=1 FILE_SHARING=0 app
benchmarks/build_swiftui_device.sh
```

Sign both with `scripts/ipad/sign.py`, install with `xcrun devicectl device
install app`, and launch each with `xcrun devicectl device process launch
--console`. Set `DEVICECTL_CHILD_LUA_OBJC_BENCH_KIND` and
`DEVICECTL_CHILD_LUA_OBJC_BENCH_ROWS` for lua-objc; use
`DEVICECTL_CHILD_SWIFTUI_BENCH_KIND` and
`DEVICECTL_CHILD_SWIFTUI_BENCH_ROWS` for SwiftUI.
