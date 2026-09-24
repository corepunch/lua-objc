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

## Pixel comparisons

The generated batch contains 224 SwiftUI-versus-lua-objc layout scenes. Build
the native PNG comparator once, then request screenshots from both engines and
pass `--visual` to `compare`:

```sh
make parity-visual
make parity-visual PLATFORM=ios DEVICE=booted
make parity-visual PLATFORM=ios DEVICE=booted SPEC=tests/parity/batch/visual-smoke.json
```

That target builds the hosts, captures all 224 scenes, compares their geometry
and PNG pixels, and prints the artifact directory. The iOS run expects an
already booted Simulator and installs the two batch hosts on that device. To
capture a smaller subset or reuse a reference run, use the lower-level commands
below:

```sh
make parity-image-diff
python3 scripts/parity/batch.py generate --out build/parity/batch-cases.json
scripts/parity/batch_reference_build.sh --macos
python3 scripts/parity/batch.py capture --engine reference --screenshots \
	--spec build/parity/batch-cases.json --out build/parity/runs/reference-visual
python3 scripts/parity/batch.py capture --engine candidate --screenshots \
	--spec build/parity/batch-cases.json --out build/parity/runs/candidate-visual
python3 scripts/parity/batch.py compare --visual \
	--spec build/parity/batch-cases.json \
	--reference build/parity/runs/reference-visual \
	--candidate build/parity/runs/candidate-visual \
	--out build/parity/runs/comparison-visual.json
```

Each case report counts exact RGBA pixel differences, reports mean and maximum
channel error, and links a red-on-transparent difference PNG under the matching
`comparison-visual-images/` directory. Pixel equality is a strict signal; an
image difference does not by itself identify whether the cause is layout,
font rasterization, or a control appearance change. The geometry probes remain
a separate result in the same report.

For iOS, use `--ios` when building the SwiftUI reference, install both host
bundles once on the booted Simulator, and add `--platform ios --device booted`
to each capture command. The Simulator app window can stay closed; `simctl`
launches each batch host and the coordinator retrieves its result files.
