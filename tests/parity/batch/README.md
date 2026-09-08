# SwiftUI batch reference host

Build the persistent macOS reference renderer:

```sh
scripts/parity/batch_reference_build.sh
scripts/parity/batch_reference_build.sh --ios
```

Run every case in one process. JSON records are always written; pass `--png`
to also write one image per case. Both paths must be absolute (including paths
inside an iOS Simulator app data container):

```sh
build/parity/batch/SwiftUIBatchReference \
	--input /tmp/batch-input.json \
	--output /tmp/batch-output \
	--png
```

The input schema is:

```json
{"schema":1,"runId":"fresh-nonce","cases":[{"id":"example","width":320,"height":120,"tree":{"id":"root","kind":"text","text":"Hello"}}]}
```

`size` is the system font point size for `text` nodes. `padding` applies to all
edges. `width` and `height` use SwiftUI's fixed `frame` dimensions. Modifiers
are applied in that order: font size, frame, then padding, followed by the probe. Stack alignment uses
SwiftUI defaults, and omitted stack spacing passes `nil` so SwiftUI chooses its
native adaptive spacing.

Every non-spacer node ID must be unique within its case. Probe coordinates are
SwiftUI points in a named coordinate space whose origin is the top-left of the
fixed-size, default-centered viewport. Cases are rendered in input order through
one reusable native window (ordered out after each case), and output probes are sorted by ID for deterministic
JSON. The required `runId` is copied unchanged into every output record so the
caller can reject stale results.

Both platforms force light appearance, preserve the current system locale, use LTR
layout direction, and the `large` dynamic type size. Results record those values
and `coordinateSpace: "root-top-left-points"`. After every case result is
atomically written, the host atomically writes `done.json` containing only the
run ID and case count. A render/write failure also produces `error.json` when
the input and output directory were successfully opened.

The iOS mode emits `build/parity/batch/SwiftUIBatchReference-iOS.app`. Install
that bundle once, use `simctl get_app_container` to place the input and select
an output directory under the app's Documents container, then pass those paths
after the bundle identifier in `simctl launch`. One app launch renders every case through a
real `UIHostingController`; no per-case install or redeploy is needed.
The bundle identifier is `org.luaobjc.parity.batch-reference`.

Use `scripts/parity/batch.py capture` for managed launches, validation, and
cleanup. The full workflow, cache contract, comparison semantics, and Luna
handoff are in `docs/SWIFTUI_PARITY_PLAN.md`, section 11.
