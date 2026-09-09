# SwiftUI visual and behavioral parity — Luna execution plan

Prepared 2026-09-08. This document is the implementation handoff, not a claim
that parity has already been verified. Follow root `AGENTS.md` throughout.

**Verification update, 2026-09-09:** neither delivery gate is complete.
Production constructors now pass **222/224 macOS** and **218/224 iOS** geometry
cases without batch-only normalization. All 13 gallery cases remain unverified.
Adventure Arena now has catalog fidelity, single-root navigation, MVP separation
and a typed-command session; persistent saves and full screen/interaction parity
remain open. See [implementation progress](parity/progress-2026-09-09.md) and the
[earlier source audit](parity/audit-2026-09-09.md). Historical counts below are
dated results, not current verification.

Execution strategy updated 2026-09-08: use persistent batch hosts and cached
SwiftUI measurements as described in section 11. That section supersedes the
per-case launch/deployment workflow below. Both delivery gates remain intact.

## 1. Outcome and scope

Build a repeatable reference suite that runs equivalent SwiftUI and etlua
scenes, measures their layout, compares their appearance, exercises their
interactions, and drives fixes in lua-objc. Start with individual controls,
then compositions, then real screens. A matching full screen alone is not
sufficient evidence that the framework works correctly.

There are two delivery gates:

- **Core parity:** every currently exported visual Lua API and XML tag is
  inventoried, and all applicable stacks, text, images, buttons, inputs,
  scrolling, collections, and existing navigation/presentation surfaces have
  passing fixtures on the platforms where they are supported. Missing common
  controls listed in Gate B remain visible gaps; they cannot count as passes.
- **Common SwiftUI coverage:** complete the additional standard layout,
  control, collection, and presentation families in section 6, including
  currently missing implementations. Finish this gate before describing the
  common UI suite as complete.

Record the wider SwiftUI surface in an explicit extension backlog. “Everything”
must mean a versioned, enumerated coverage contract, not every API Apple might
add or every possible combination of views. Do not silently shrink either
delivery gate to make a report green. A blocked feature remains incomplete.

Target native AppKit and UIKit. Compare macOS SwiftUI with macOS lua-objc,
and iOS SwiftUI with iOS lua-objc on the same Simulator device and runtime.
Do not use iOS screenshots as macOS references. The current Makefile sets
`IOS_MIN := 26.5`; the project requires macOS 26+. Verify the installed SDKs
and runtimes instead of inferring them from this document.

SwiftUI is the public behavioral and visual reference. It is not a promise
that every SwiftUI view has an identical public UIKit/AppKit counterpart.
If the native-control requirement prevents an exact match, document the
specific difference and public-API constraint. Keep it out of the pass count;
request a product decision only after the evidence and alternatives exist.
Never fake a system control or use private APIs to improve a screenshot.

## 2. Verified repository starting points

The following were inspected while writing this plan. Recheck before editing:

| Surface | Current evidence | Consequence |
|---|---|---|
| AppKit | `lua/embedded/AppKit.lua`; `src/appkit/`; native layout dump and screenshot commands | Reuse existing diagnostics and actual native tests. |
| UIKit | `lua/embedded/UIKit.lua`; `src/uikit/`; `ios/LuaRuntime/`; `scripts/ios-run.sh` | A real host already exists. Extend it; do not implement the historical host proposal again. |
| XML | `lua/ui/xml.lua`, exported `schema` and `registry` | Audit each tag, property, default, and constructor on each platform. Registry presence is not platform support. |
| Existing tests | `tests/bridge.test.lua`, `tests/xml.etlua.test.lua`, `tests/uikit_api.test.lua` | UIKit API tests inspected here largely search source strings; these do not prove native construction or layout. |
| iOS diagnostics | No screenshot/layout-dump entry point found in the inspected host sources | Confirm this gap, then add native capture/measurement support before claiming iOS parity. |
| Documentation | `docs/ios.md` mixes earlier design and implemented work | Trust executable code and measurements; update stale claims as each affected section is verified. |

Specific mapping traps:

- etlua `<Label>` is plain text: compare it to SwiftUI `Text`. SwiftUI `Label`
  combines an icon and title. Give the latter its own mapping and fixtures.
- XML includes Slider, Stepper, Picker, and TextEditor tags, but corresponding
  public constructors were not found in the inspected UIKit Lua layer. Verify
  the complete exported module, including native registrations, before marking
  them supported or missing.
- UIKit exposes `NavigationStack`, while the inspected XML schema does not
  contain that tag. Lua support and etlua support need separate columns.
- `List` currently has a column-oriented XML contract. Do not assume its name
  makes it equivalent to both SwiftUI `List` and SwiftUI `Table`.
- The layout engine is flex-like. `flexGrow`, `fillWidth`, and fixed dimensions
  are not automatically equivalent to SwiftUI proposals, flexible frames,
  `fixedSize`, or `layoutPriority`.
- UIKit exposes ZStack; the inspected AppKit Lua constructors do not. Check
  actual platform support before constructing shared fixtures.

Read only relevant sections of `ARCHITECTURE.md`, `src/README.md`, and
`docs/PROJECT_REFERENCE.md`. Before native implementation, read
`skills/maintain-lua-objc-framework/SKILL.md` as directed by the README.

## 3. Apple reference syllabus

Use the following primary sources. The documentation categories define the
inventory; the tutorials supply composition ideas. Running SwiftUI on the
pinned OS provides the visual baseline. Tutorials are not an exhaustive API
specification, and old screenshots are not current appearance baselines.

| Read when | Apple source | Extract into fixtures |
|---|---|---|
| Inventory | [SwiftUI documentation](https://developer.apple.com/documentation/swiftui) | Public UI families, platform availability, styles and modifiers. |
| First layout batch | [Layout fundamentals](https://developer.apple.com/documentation/swiftui/layout-fundamentals) and [Building layouts with stack views](https://developer.apple.com/documentation/swiftui/building-layouts-with-stack-views) | Stacks, grids, spacing, alignment, adaptive composition. |
| Layout semantics | [Layout adjustments](https://developer.apple.com/documentation/swiftui/layout-adjustments) and [Laying out a simple view](https://developer.apple.com/documentation/swiftui/laying-out-a-simple-view) | Frames, padding, placement, safe areas, modifier order. |
| Measurement design | [A guide to layout in SwiftUI](https://developer.apple.com/videos/play/meet-with-apple/271/) | Layout concepts and debugging techniques. |
| Advanced containers | [Compose custom layouts with SwiftUI](https://developer.apple.com/videos/play/wwdc2022/10056/) and [its sample](https://developer.apple.com/documentation/swiftui/composing-custom-layouts-with-swiftui) | Grid, Layout, ViewThatFits, adaptable compositions. |
| Typography and input | [Text input and output](https://developer.apple.com/documentation/swiftui/text-input-and-output) | Text versus Label, text styles, selection, editable and secure fields. |
| Controls inventory | [Controls and indicators](https://developer.apple.com/documentation/swiftui/controls-and-indicators) | Inspect each relevant control's own documentation and supported styles. |
| Collection batch | [Lists](https://developer.apple.com/documentation/swiftui/lists), [Tables](https://developer.apple.com/documentation/swiftui/tables), [View groupings](https://developer.apple.com/documentation/swiftui/view-groupings) | Rows, sections, selection, forms, control groups, disclosure. |
| Chrome batch | [Navigation](https://developer.apple.com/documentation/swiftui/navigation) and [Modal presentations](https://developer.apple.com/documentation/swiftui/modal-presentations) | Navigation paths, splits, sheets, popovers, alerts, dismissal state. |
| Integration batch | [Develop in Swift](https://developer.apple.com/tutorials/develop-in-swift), [SwiftUI tutorials](https://developer.apple.com/tutorials/swiftui) | Build fresh small reference scenes inspired by tutorial compositions. |
| Every visual batch | [HIG](https://developer.apple.com/design/human-interface-guidelines), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Platform conventions, safe areas, text scaling, keyboard and accessibility audit. |

Some Apple pages require JavaScript and may return only a shell to a fetcher.
Use their rendered documentation, Xcode documentation, or Apple's documentation
data when available; do not claim to have read inaccessible content. Keep a
source ledger with URL, access date, relevant API, availability, and the exact
fixture decisions it informed. Read the current API page for each style before
implementation. Verify availability against the selected SDK; use no deprecated
navigation or appearance fallback paths.

## 4. Deliverables and fixture architecture

Create these artifacts incrementally; names below are proposed new paths:

```text
docs/parity/
  coverage.md                 human-readable coverage and platform gaps
  sources.md                  Apple source ledger
  decisions.md                mapping decisions and evidence for differences
  status.md                   completed work, failures, exact next batch
tests/parity/
  manifest.json               shared fixture IDs, inputs, states, environments
  schema.json                 manifest validation rules
  reference/                 SwiftUI reference source; macOS and iOS targets
  baselines/                 small approved reference artifacts + provenance
scripts/parity/
  run.*                      reproducible build/run/capture orchestration
  compare.*                  frame and image comparisons
  report.*                   local HTML evidence report and machine JSON
examples/swiftui_parity/
  init.lua                   requires and returns Controller class
  Model.lua                  deterministic fixture inputs/state
  Controller.lua             fixture selection, actions, single root window
  views/                     etlua scenes and Lua component functions
tests/parity_manifest.test.lua
tests/parity_layout.test.lua
tests/parity_controls.test.lua
build/parity/<run-id>/        generated captures, dumps, logs, reports
```

Keep discovered regression scripts directly in `tests/*.test.lua` so `make test`
runs them. Files under `tests/parity/` are fixtures and reference code, not
implicitly discovered tests. Add the example to `tests/examples.test.lua`.

Compile a small reference app once per source/SDK change, with launch-selectable
fixture and state IDs. Avoid a new Xcode project or build per fixture. The
reference must use actual SwiftUI primitives, without lua-objc implementation
code or offsets chosen to match current lua-objc output. Keep separate platform
hosts where necessary; do not use Catalyst as the macOS reference.

Use the same fixture data and explicit parameters in both renderers. Write
SwiftUI and etlua view descriptions independently so a shared layout generator
cannot encode the same mistake into both. Components return view trees;
only the controller/app root creates the window. Inject `ns` into shared XML.
Use ForEach for repeated sibling views and ordinary components for reuse,
consistent with AGENTS.md. Do not add a second template engine.

Each manifest case must include:

- Stable ID, family, purpose, Apple reference, gate, platform applicability.
- SwiftUI scene and etlua scene, semantic node IDs, expected native control
  family, and the explicit API/property mapping.
- Identical text/assets/data, initial state, actions, and final state assertions.
- Proposed container dimensions in points, appearance, direction, locale,
  text-size category, control style/size, and safe-area mode.
- Named geometry assertions, expected wrapping/truncation, screenshot regions,
  tolerances, and any justified dynamic masks.
- Status separately for Lua API, XML, native behavior, geometry, visual review,
  interaction, and accessibility. Evidence paths and blockers are mandatory.

Use statuses `unassessed`, `missing`, `implemented-unverified`, `failing`,
`passing`, `blocked`, and `not-applicable`. An exported symbol starts at
implemented-unverified, never passing. `not-applicable` requires a platform or
scope reason and is excluded from the denominator. Explicit product exceptions
remain separately counted; they are not passing fixtures.

## 5. Measurement and capture contract

### Environment and repeatability

Record git revision plus dirty diff hash, reference source hash, fixture hash,
Xcode build, SDK, OS build, Simulator UDID/device, display scale, dimensions,
locale, time zone, appearance, text size, accessibility settings, window active
state, and capture method. OS/Xcode changes create a new baseline family.
Incompatible environments fail comparison rather than quietly sharing goldens.

Use deterministic local data and bundled fixture assets. No live HTTP, random
content, current timestamps, or artificial loading sleeps. Drive loading,
success, empty, and failure directly through the model. Set identical simulator
status-bar state or crop only the explicitly excluded system-bar region.

Capture after a fixture-ready signal containing fixture ID, state ID, and
generation, after layout and outstanding presentation transitions finish.
Use a bounded readiness timeout that emits logs and a failure artifact. Stable
geometry across consecutive frames is additional evidence, not a replacement
for readiness. Never accept a stale screenshot from the previous fixture.

Measure both implementations using public APIs. SwiftUI semantic node frames
can be observed using non-layout-affecting geometry observation, preferences,
or anchors. Probe fixtures must demonstrate that enabling diagnostics does
not alter layout. Do not insert a GeometryReader as a sizing child in every
stack or require SwiftUI's private hierarchy to match the native hierarchy.

Extend native UIKit diagnostics if absent: semantic IDs, class, frame,
intrinsic/fitting size, safe-area insets, scroll viewport/content size, text
layout information and clipping where measurable. Export the native tree;
application Lua must not fabricate the diagnostic hierarchy. Separate
unavailable measurements from successful assertions.

The iOS runtime continues streaming Lua/assets from the packager. Lua changes
must not require rebuilding, reinstalling, or terminating the host. Add a
test-only fixture/state selection mechanism if needed. Each selection resets
fixture state and emits a new generation; structural changes use the existing
host lifecycle or retained descriptions/reconciliation as appropriate, not
control-specific subtree mutation hooks.

### Three independent checks

1. **Behavior:** construction, property round-trip, callbacks, enabled state,
   focus, selection, state transitions and unrelated-state preservation.
2. **Geometry:** semantic frames, baselines where observable, spacing, content
   extents, safe areas, expected wrapping/truncation and clipping.
3. **Appearance:** reference, candidate, overlay and difference image, followed
   by actual visual inspection. Native colors, symbols, control surfaces and
   typography must match the chosen context.

Compare geometry in points in a common content-root coordinate system, handling
AppKit coordinate orientation. Compare raster output at its original scale;
never rescale or auto-align the candidate to hide layout errors. Produce
per-node/per-region metrics as well as a whole-scene metric: a large blank
background must not hide a broken small button.

Start with a geometry tolerance of one physical pixel (`1 / scale` points)
for frame edges and baseline measurements that support that precision. This
is a proposed project threshold, not an Apple guarantee. Calibrate appearance
tolerances with at least three unchanged captures of each representative family.
Keep thresholds explicit and versioned. Wrong text, line count, state, control
style, missing content or unexpected clipping is a failure regardless of score.
If native text measurement cannot provide baseline/line count, use image
evidence and mark that measurement unavailable.

Mask only narrowly identified time-varying pixels, such as an indeterminate
spinner's moving strokes or a caret. Assert the spinner's position, size,
presence, and loading semantics independently. Never mask the entire failing
control. Review diffs before approving new baselines; never regenerate
references from lua-objc or update goldens merely to clear a failure.

### Environment matrix without an unbounded cross product

- Every fixture: canonical size, light and dark on every applicable platform.
- Every layout/text fixture: constrained, canonical, and expanded widths;
  short, empty, multiline and long unbroken content where applicable.
- iOS: at least two available phone sizes and portrait/landscape for applicable
  scenes; normal, largest non-accessibility, and one accessibility text size
  for text-bearing families. Add iPad as a declared extension unless the
  inventory identifies it as an already supported product target.
- macOS: each affected example's supported minimum, default, and substantially
  larger content dimensions; active/inactive window and keyboard-focus cases.
- Direction/localization: an RTL fixture per layout/control family, plus a
  mixed-direction text fixture and long localized button/title cases.
- Accessibility: representative Increased Contrast, Reduce Transparency,
  Bold Text and Reduce Motion cases where the OS supports them; record which
  settings apply to each platform rather than inventing unavailable settings.
- Controls: all declared styles and sizes at canonical dimensions; pairwise
  combinations of environment variations, plus known troublesome combinations
  such as long text + narrow width + accessibility text size.

Every supported loading, loaded, empty, selected, disabled, error and long-text
state must be exercised in each affected example where that state exists.
Record a reason for non-applicable states. A tiny zero-size test belongs in
headless layout checks, not in a claim that the app supports a zero-size window.

## 6. Ordered fixture catalogue

The rows below are required families, not one screenshot each. Expand variants
into stable case IDs such as `stack.h.spacing.default.text-button` and
`text.wrap.two-lines.narrow`. Inventory every exported property and style;
require coverage links so newly added APIs cannot disappear from the suite.

| Batch | Required cases | What passing proves |
|---|---|---|
| A1 HStack/VStack | Empty; one child; equal/unequal intrinsic children; nested horizontal/vertical stacks; omitted/zero/explicit spacing; leading/center/trailing; top/center/bottom; first/last text baseline; mixed text sizes, symbols and controls | Measurement, placement, alignment and sibling spacing; no implicit outer margins. |
| A2 Flexibility | One/multiple Spacers; minimum spacer; fixed and flexible siblings; min/ideal/max constraints; finite/zero/unconstrained proposals where applicable; overflow; shrink/compression; competing flexible labels; priorities; nested fill | SwiftUI-equivalent size negotiation, not just proportional flex allocation. |
| A3 Layout modifiers | Padding all/axis/edge; frame alignment; padding before/after frame; fixedSize; layoutPriority; hidden versus absent child; background/overlay versus ZStack; offset versus layout position; clipping; aspect ratio fit/fill | Correct modifier semantics and measurement effects; missing representational support is exposed. |
| A4 ZStack/grouping | Empty/single/multiple layers; all standard 2D alignments; largest-child size; constrained layers; drawing order and hit testing; nested Group/ForEach; conditional insertion/removal/reorder | Layer geometry, no unintended wrapper spacing, stable identity and state. |
| A5 Scroll/safe area | Vertical/horizontal/both where supported; content smaller/larger than viewport; nested stacks; insets; indicators; top/bottom edges; safe-area inclusion/ignoring; keyboard avoidance; resize and state update preserving offset | Correct viewport/content measurement and no duplicated insets or unwanted resets. |
| B1 Text | System semantic font roles; explicit size/weight; body/title/caption; multiline alignment; line limits; truncation modes; empty/newline/long words; Unicode, emoji, CJK, RTL; selectable text; inherited font/color; disabled context | Correct text metrics, baselines, wrapping, semantic appearance and environment propagation. |
| B2 Label/images | Plain etlua Label versus SwiftUI Text; actual icon-title Label equivalent; title-only/icon-only where supported; symbol scale/weight/rendering/tint; decorative versus accessible image; local raster sizing; fit/fill/clipping; missing asset | Correct semantic mapping, symbol/text alignment and intrinsic image sizing. |
| B3 Button | Automatic/plain/bordered/borderedProminent and other current platform styles; supported control sizes; text/icon/compound labels; role; disabled/pressed/focused/default/cancel; long labels; constrained width; click/tap/keyboard; one callback per activation | Native style and hit target, context-sensitive defaults, correct actions and focus behavior. |
| B4 Input | Toggle on/off/disabled and label layout; TextField empty/value/prompt/focus/edit/submit; secure input; SearchField; TextEditor multiline/selection/scroll; Slider min/mid/max/step; Stepper limits/increment; Picker selection and available styles | Actual native controls, state round-trip, bounds, labels and keyboard interaction. |
| B5 Feedback | Divider in both stack axes; ProgressView determinate/indeterminate; loading table centered spinner; progress label; disabled controls; content-unavailable state | Native presentation, intrinsic sizing and state change without fabricated latency. |
| C1 Lists/tables | Plain/full-width/inset/sidebar as applicable; zero/one/many rows; short/long cells; headers/sections/footers; separators; single/multiple selection; disabled rows; sorting; row add/remove/reorder/update; column min/flex widths; scroll retention; loading/error/empty | Real native collection semantics, expected row geometry and no cell clipping. Distinguish SwiftUI List from Table explicitly. |
| C2 Containers | Form, Section, GroupBox, LabeledContent, ControlGroup, DisclosureGroup, OutlineGroup; expanded/collapsed and nested states; Grid/GridRow; LazyV/HStack and LazyV/HGrid; ViewThatFits | Common SwiftUI composition coverage, correct grouping and adaptive sizing. Lazy containers also need realization/state behavior tests. |
| D1 Navigation | NavigationStack push/pop/back; NavigationSplitView applicable columns/collapse/selection; tabs and page style; toolbar placement/title/actions; search in navigation context; long titles; state retention | Native platform chrome and content geometry under transitions, resizing and selection. |
| D2 Presentation | Sheet presentation/dismissal/detents; popover anchoring/adaptation; alert and confirmation actions; menus/context menus; macOS windows, tabs and panels; keyboard focus return | Correct native presentation, action wiring, dismissal state and focus restoration. |
| D3 Additional common controls | DatePicker, ColorPicker, Link, Menu, disclosure controls and any remaining current exported visual API | Common control inventory has no untracked holes; platform styles are explicitly mapped. |
| E Integration | Settings form; searchable selectable list/detail; toolbar + flexible content; scrolling detail + actions; tab/navigation flow; text composer + keyboard; existing problematic screen | Components remain correct when combined, including live state and native container geometry. |

Gate A (core parity) covers the applicable A–E fixtures for existing exported
surfaces, plus shared layout/text/button semantics needed to make them correct.
Gate B (common SwiftUI coverage) closes missing A–D families and repeats E.
Both require an inventory reconciliation; a fixed number of screenshots alone
cannot establish completeness.

Track advanced scope separately: custom Layout protocol surface, AnyLayout,
animations/transitions/matched geometry, advanced gestures, drag/drop,
Canvas/Shape/Path/gradients/effects beyond current exports, rich attributed text,
AsyncImage loading behavior, Charts, MapKit, media, documents/scenes/settings,
system pickers, platform-specific integrations, widgets, watchOS/tvOS/visionOS.
Every currently exported member of these families still needs core regression
coverage. Reimplementing every Apple framework is outside the two gates above.

## 7. Work packages, dependencies and acceptance

Execute in order. Work in small reviewable changes, typically one infrastructure
piece or one family of fixes. Do not defer all testing to the final package.
Execute the cases inside each package in one process per platform/engine,
not one app installation or launch per case. Cache the independent reference
batch and rerun candidate batches while fixing shared causes.

### P0 — Inventory and freeze the contract

1. Read repository instructions and inspect git status; preserve unrelated work.
2. Enumerate public Lua constructors, native registrations, XML tags/attributes,
   defaults, aliases, available styles and current tests. Read implementation,
   not just function names. Exclude async/data-only services from visual counts.
3. Populate coverage rows per API/property/platform, with separate Lua/XML and
   supported/missing/unverified states. Map each to the right SwiftUI concept.
4. Record local toolchain/runtime availability and baseline `make` / `make test`
   results. Distinguish pre-existing failures from new ones.
5. Expand section 6 into manifest cases. Record out-of-scope APIs explicitly.

Acceptance: every discovered visual surface is accounted for, no unverified API
is marked passing, and missing features have ordered work items. Do not spend
this package making UI fixes or copying all Apple documentation locally.

### P1 — Build the smallest trustworthy comparison harness

1. Add macOS/iOS SwiftUI reference hosts and the MVP etlua example.
   The batch hosts interpret a shared data specification independently; they
   must not share measurement, placement, or expected-output implementation.
2. Start with three fixtures: single Text; HStack of two texts and a Spacer;
   a standard Button with an action counter. Add fixed geometry diagnostic
   shapes only as test probes, never as replacement production controls.
3. Implement manifest validation, fixture/state selection, readiness, environment
   metadata, native/SwiftUI semantic frame export, and screenshots.
4. Add report output with side-by-side images, overlay, diff, frame deltas,
   action assertions, status and reproduction command per case.
5. Validate the harness with an intentional one-point displacement, wrong text,
   missing child, disabled-state mismatch and stale generation. They must fail.
   An unchanged recapture must pass after repeatability calibration.
6. Generate the systematic batch matrix, record process count and elapsed time,
   and confirm that rerunning the candidate does not rebuild the reference.
   Keep full scenes and input-driven tests as a separate coverage layer.

Acceptance: one command reproduces each pair on each applicable platform;
negative controls fail; there is no manual image renaming/cropping; no app Lua
is bundled into the iOS runtime. Capture failure exits nonzero with evidence.

### P2 — Establish layout semantics before visual tuning

Implement A1–A5. Start with the smallest failure from the current problematic
screen, then systematically cover the catalogue. For every mismatch:

1. Run the independent SwiftUI reference and capture before evidence.
2. Inspect the native layout dump before changing constants.
3. Classify XML coercion/default, Lua mapping, native property/configuration,
   layout algorithm, environment inheritance, or reference/harness error.
4. Add a failing fast regression assertion for the underlying contract.
5. Fix the owning layer; rerun the paired fixture and regression tests.
6. Recheck neighboring compositions, constrained/expanded sizes and appearance.

If unordered XML attributes cannot express an important modifier-order
difference, design explicit compositional wrappers or retained descriptions
and migrate callers. Do not pretend padding+frame are interchangeable or
introduce fixture-specific flags. Structural state changes must use retained
descriptions/reconciliation, not per-feature view replacement APIs.

Acceptance: stack/layout fixtures pass with measured geometry; text wrapping
contributes to parent sizing correctly; zero/overflow cases are safe; no screen
offset compensates for a framework bug. Record unsupported semantics as work,
not as numerical tolerances.

### P3 — Typography, symbols, buttons, inputs and feedback

Implement B1–B5 after P2. Start with native defaults, then supported styles and
environment overrides. Check controls both isolated and inside Form/List/
Toolbar contexts: the same SwiftUI automatic style may look different there.
Use current public native configuration APIs and semantic fonts/colors.

Add missing platform constructors and XML vocabulary through existing extension
points. New classes belong in Lua where possible; native code exposes Cocoa
capabilities Lua cannot supply. No fake buttons, checkboxes, tab bars or fields.

Acceptance: all declared styles/states have passing native, geometry and visual
evidence; input actions are exercised, not merely set programmatically. Every
fix includes headless regression tests plus Simulator evidence for UIKit.

### P4 — Collections and additional containers

Implement C1–C2. Resolve List/Table mapping before changing row schemas. Let
native tables and split containers own their geometry. Test column distribution
and row mutation independently from image comparisons. Preserve user selection,
scrolling and focus when unrelated content changes.

Acceptance: resize, loading, empty, error, long rows, grouping and selection
fixtures pass; dynamic cases do not leak callbacks or reset unrelated state;
new XML and Lua callers move together with no compatibility shims.

### P5 — Navigation, presentation and remaining common controls

Implement D1–D3 using public native controllers/containers. Respect macOS
NSWindow tabbing, NSSplitView ownership, NSToolbar, and ordinary native NSPanel
frames. Do not add legacy materials or custom panel shadow/corner APIs.

Acceptance: push/pop/tab selection/presentation/dismissal are exercised through
real input; content follows native safe areas; focus returns correctly; state
and callbacks remain valid through repeated transitions.

### P6 — Real-screen integration and accessibility

Add E compositions and the current screen under discussion once identified from
the working example. Use local fixture data to prevent network variance. Test
every example affected by the changed framework paths; common layout/control
changes can affect many examples, not just the parity gallery.

Inspect actual screenshots at small/default/large sizes, light/dark, relevant
states and keyboard focus. Use real input for native selection, focus, editing,
scrolling and activation. Audit accessible names, roles, values, enabled and
selected states, grouping and traversal with Accessibility Inspector or an
appropriate test interface; perform representative VoiceOver/keyboard checks.

Acceptance: no unexplained new cropping or alignment defects, native keyboard
behavior works, and integration issues are reduced to reusable regression
fixtures before being fixed. The original screen has paired before/after proof.

### P7 — Automation, coverage audit and final handoff

Expose documented commands for inventory validation, fast regression tests,
one-fixture comparisons and complete platform suites. Suggested interfaces
(these do not exist yet):

```sh
make parity-check
make parity-case CASE=stack.h.spacing.default.text-button PLATFORM=ios
make parity-smoke PLATFORM=macos
make parity-full PLATFORM=ios
make parity-report
```

Keep Simulator/visual suites separate from `make test`. Require manifest checks
and fast tests on normal changes; run smoke fixtures on framework changes and
the full applicable matrix before declaring a gate complete. If a CI runner
lacks the pinned runtime, report unavailable, never a pass or silent skip.

Acceptance: commands work from a clean build with documented prerequisites;
each coverage row resolves to evidence; report totals separate passes,
failures, missing implementations, blocked cases, exceptions and not-applicable
cases. Publish exact runtime scope and remaining extension backlog.

## 8. Testing rules and safeguards

Every implementation/bugfix includes fast headless tests using `TestKit`.
Prefer native AppKit assertions and pure Lua/XML behavior assertions over
source-string checks. Do not claim macOS headless tests execute UIKit.
Provide native UIKit assertions in the Simulator test harness, outside the
subsecond headless lane. Mocks can verify argument mapping, not native sizing.

Use existing helpers such as `_viewSize`, `_setContentSize`, `_layout`, and
`_tableColumnWidths` where available. Verify create → mutate → inspect and
unchanged sibling/model state. Add semantic read-only diagnostics when current
helpers cannot express a needed assertion; avoid broad product-only test APIs.

No sleeps/windows in `tests/*.test.lua`. Measure the actual fast-suite duration;
do not promise that Simulator startup fits that budget. Keep generated images
and reports in `build/parity/`; version only deliberate reference artifacts
and their provenance. Never delete or rewrite unrelated user files.

Use tabs in `.lua` and `.m`. Place visual/layout constants in platform roots
(`src/main.m`, `src/uikit/bridge.m`) as the project requires. Keep one runtime
image per platform. Fix canonical APIs completely and update callers/tests/docs
together; do not add old-name forwarding stubs.

## 9. Completion checklist and continuation protocol

A gate is complete only when:

- Every API/property in its frozen coverage inventory has applicable fixtures.
- Missing expected constructors/tags are implemented for that gate, or the gate
  remains incomplete with an explicit blocker.
- Actual reference and candidate captures exist on matching environments.
- Behavior, geometry, visual and applicable accessibility checks pass.
- Every implementation fix has a fast regression test; UIKit behavior has real
  Simulator evidence in addition to any headless argument-mapping tests.
- Every affected example has required visual/state/resize/input QA.
- The harness detects intentional regressions and rejects stale/missing output.
- No unexplained threshold increases, broad masks, fake controls, legacy paths,
  or screen-specific alignment compensations remain.
- A final report states verified platform/runtime/style scope and incomplete
  extension work without claiming universal SwiftUI equivalence.

After each package, update `docs/parity/status.md` with completed case IDs,
changed files, commands and actual results, evidence locations, decisions,
known failures, and the exact next batch. If interrupted, resume from that
ledger; do not restart research or regenerate accepted baselines blindly.
For a blocker, provide the smallest reproducer, observed output, expected
reference output and the concrete missing prerequisite or decision. Continue
independent work while it is unresolved.

Suggested initial instruction to Luna:

> Execute docs/SWIFTUI_PARITY_PLAN.md, beginning with P0 and P1, then continue
> through P7 to finish both the core-parity and common-SwiftUI-coverage gates.
> Preserve the repository's native-control, etlua, MVP and testing rules.
> Use paired SwiftUI/etlua fixtures as the reference, fix framework causes, and
> keep docs/parity/status.md current. Report measured results and incomplete
> cases honestly; API presence or a plausible screenshot is not a pass.

## 11. Persistent batch harness — current execution strategy and Luna runbook

### 11.1 Architecture and why it is faster

Run two independent interpreters of the same fixture data. The Swift interpreter
constructs real `Text`, `HStack`, `VStack`, `ZStack`, and `Spacer` views. The Lua
interpreter constructs the corresponding production AppKit/UIKit API calls.
Share only case descriptions, stable IDs, and the output protocol. Never reuse
the candidate layout algorithm in the reference, substitute mocked expected
frames, or copy candidate output into a reference directory.

Each engine processes the entire case list in ONE process and writes one result
per case. SwiftUI compilation happens when its interpreter changes, not when a
case's text, nesting, spacing, or dimensions change. The native Lua runtime is
rebuilt only after native code changes. Lua source is read directly on macOS
and streamed from the packager on iOS. Each iOS host is installed once per
native build, then handles the complete batch without any per-case install or
launch. A new batch may launch the host once; keeping it alive across separate
batch invocations is a further optimization, not a current requirement.

Batch outputs are cached reference measurements, not approved visual baselines.
Rerun only the candidate during a sequence of native layout fixes. Use a new
output directory each time so files from a previous attempt cannot become
evidence for the current attempt. Reference and candidate need separate output
directories even when run in the same session.

Do not display hundreds of simultaneous scenes in a huge stack or grid: that
changes their proposals, safe areas, focus, and realization behavior. Replace
one host's content sequentially, keeping each case's viewport independent.
Parallelize source investigation or independent devices/platforms, not two
foreground cases competing for the same Simulator's state.

### 11.2 Files and ownership

| File | Responsibility |
|---|---|
| `scripts/parity/batch.py` | Validate/generate cases; launch one process per batch; cache provenance; reject stale/incomplete evidence; compare results |
| `tests/parity/batch/BatchReferenceHost.swift` | Independent SwiftUI interpreter, geometry preferences, bounded layout stabilization, optional reference PNGs |
| `scripts/parity/batch_reference_build.sh` | Build macOS executable or iOS reference app |
| `lua/parity/batch.lua` | Production Lua view construction and sequential candidate measurement |
| `scripts/parity/batch_candidate.lua` | macOS candidate batch entry point |
| `examples/parity_batch/` | Streamed iOS candidate batch entry point; no application Lua bundled in the host |
| `src/appkit/parity_batch.m`, `src/uikit/parity_batch.m` | Native coordinate conversion and measurement of actual views |
| `src/shared/parity_batch.m` | Shared JSON/output helpers |
| `tests/parity/batch/test_protocol.py` | Evidence acceptance negative controls |
| `tests/parity_batch_protocol.test.lua` | Integrates protocol tests with `make test` |

The previous 13-case gallery and its report files remain useful historical UI
evidence. They are not the batch oracle: their fixture parameters were not all
equivalent and their old comparison mixed parent-local AppKit coordinates with
root-relative SwiftUI coordinates. Do not use their failure totals as proof of
framework defects. Batch evidence uses new runs and a single coordinate contract.

### 11.3 Fixture protocol (schema 1)

```json
{
  "schema": 1,
  "cases": [{
    "id": "stack.nested.example",
    "width": 320,
    "height": 160,
    "tree": {
      "id": "root",
      "kind": "hstack",
      "spacing": 8,
      "padding": 12,
      "children": [
        {"id": "title", "kind": "text", "text": "Hello", "size": 17},
        {"id": "space", "kind": "spacer"},
        {"id": "detail", "kind": "vstack", "spacing": 0, "children": [
          {"id": "first", "kind": "text", "text": "One"},
          {"id": "second", "kind": "text", "text": "Two"}
        ]}
      ]
    }
  }]
}
```

Supported kinds are currently only `text`, `hstack`, `vstack`, `zstack`, and
`spacer`. IDs are unique within each case; case IDs must also be unique. Safe
IDs contain letters, digits, dots, underscores, and hyphens and start with a
lowercase letter or digit. File separators are forbidden. The command rejects
unknown fields rather than treating them as supported coverage.

Common node dimensions are optional `width`, `height`, and uniform `padding`.
`text` additionally accepts literal `text` and optional system-font `size`.
H/V stacks accept `spacing` and `children`; ZStack accepts `children` and has
no sibling spacing. A missing spacing value means the engine's default, not
zero. Dimensions must be finite; node dimensions may be zero, viewport
dimensions must be positive. Negative/unconstrained proposals require a later
explicit protocol extension; they are not encoded as made-up negative sizes.

The SwiftUI modifier order is **font → fixed frame → padding → measurement
probe**, then an outer fixed viewport centered on its content. The outer
viewport is not itself the measured tree node. The Lua engine uses its current
production properties; any inability to express that modifier order is a real
tracked mismatch, never an excuse to change the reference ordering. Baseline
alignment, per-edge padding, line limits, colors, images, controls, grids,
actions, and explicit appearance variants are not yet fields in this batch
schema. Add them to both interpreters and validation together before adding
their generated cases.

The generator currently emits **224 structural cases**: H/V stacks at four
widths × three spacings × two paddings × four child arrangements; ZStacks at
four widths × two paddings × four arrangements. Empty, single, mixed font-size,
and nested arrangements test different contracts. ZStack has no artificial
spacing variants. This is a starting layout matrix, not the complete section 6
catalogue. Every required family still needs inventory and coverage links.

### 11.4 Geometry and evidence contract

Each result includes `schema`, `runId`, `id`, viewport `width`/`height`, native
`platform`, `os`, display `scale`, and `probes`. Every non-Spacer semantic node
must appear exactly once, including empty containers. Each probe supplies its
ID, x/y/width/height in **root-relative, top-left, logical points** and text for
text nodes. Spacer geometry can be inferred for the current cases; direct
Spacer measurements require a future probe implementation.

SwiftUI measures through geometry preferences in a named root coordinate
space. Probe modifiers must not add siblings, spacing, fixed dimensions, or
replace SwiftUI containers. The reference waits for the expected node-ID set
and repeated stable measurements with a bounded deadline. This is sufficient
for static local text/layout fixtures only. Future asynchronous images,
animations, lazy realization, and stateful cases require explicit semantic
readiness and action-generation acknowledgments in addition to stable frames.

The native candidate converts each view's bounds to the viewport using native
coordinate conversion and flips the AppKit Y axis when necessary. It must not
compare raw child `.frame` values from different parents. Complete the native
layout before measuring. Preserve the tested tree's intrinsic/fixed dimensions
inside a separate viewport; assigning the viewport rectangle directly to a
Text node invalidates the comparison.

This initial matrix uses a fixed content viewport: the SwiftUI hosting view's
`safeAreaRegions` is empty. It does not test safe-area layout. Both engines use
light appearance, LTR, large dynamic type, and the actual system locale
(recorded and compared, not globally overwritten). Reference PNGs have a
semantic system background; transparent text-only images are not the default.

The coordinator generates a fresh run UUID, hashes the input specification and
source/native binary provenance, verifies every expected output, and writes
`complete.json` last. No completion marker means the batch is invalid. A
missing file, unexpected/duplicate probe, wrong literal text, NaN, wrong
generation, changed source, changed result hash, or different platform/OS/scale
invalidates the comparison. Do not repair bad evidence by editing JSON.

The comparison checks origins, sizes, and trailing/bottom edges so two small
component errors cannot hide a larger edge displacement. Default tolerance is
half a physical pixel (`0.5 / scale` points), capped by the optional
`--tolerance` point limit. A one-point displacement must fail. Inspect
physical-pixel rounding at the actual scale before any tighter calibration.
Never widen a tolerance to cover incorrect size negotiation.

Results say `geometry-pass` or `geometry-fail`, with `visual` and `interaction`
still `unverified`. Equal rectangles do not establish equal glyphs, wrapping,
ellipsis, clipping, colors, controls, accessibility, or behavior. Add screenshots
and actual input-driven tests for those contracts. Keep the suite's final
SwiftUI parity status separate from geometry-only pass counts.

### 11.5 macOS commands — first run and fast iteration

Run from the repository root, with full Xcode available:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make
scripts/parity/batch_reference_build.sh --macos
python3 scripts/parity/batch.py generate --out build/parity/batch-cases.json

python3 scripts/parity/batch.py capture --engine reference \
  --spec build/parity/batch-cases.json --out build/parity/runs/reference-001
python3 scripts/parity/batch.py capture --engine candidate \
  --spec build/parity/batch-cases.json --out build/parity/runs/candidate-001
python3 scripts/parity/batch.py compare \
  --spec build/parity/batch-cases.json \
  --reference build/parity/runs/reference-001 \
  --candidate build/parity/runs/candidate-001 \
  --out build/parity/runs/comparison-001.json
```

Exit status **0** means valid geometry agreement for the supplied cases;
**1** means valid evidence with geometry mismatches; **2** means invalid or
incomplete input/evidence/host execution. Inspect `stderr.log`/`stdout.log`
for a failed capture. Each capture output path must be new. A failed output
directory is retained for diagnosis and must not be reused as an accepted run.

For subsequent native fixes, rebuild the candidate with `make`, capture to
`candidate-002`, and compare against `reference-001`. For Lua changes, run the
candidate again (rebuild embedded modules on macOS if they changed). Rebuild
and recapture SwiftUI only when its interpreter, spec, SDK/OS/environment, or
reference semantics change. Changing input parameters changes the spec hash;
that correctly requires a new reference batch.

`--screenshots` on reference capture requests per-case PNGs without relaunching.
Use a small spec subset for visual investigation. Candidate geometry runs do
not yet produce screenshots; use the native screenshot paths for corresponding
integration fixtures until candidate screenshot support is added. Do not
claim image comparison from a geometry report. The batch CLI does not need
Pillow, Screen Recording permission, desktop pixel capture, or private APIs.

### 11.6 iOS commands — install once, execute batches

The Simulator must already be booted. Select one exact UDID when multiple
devices exist. Simulator service access and a listening local packager may
require execution outside the command sandbox; request that escalation rather
than treating sandbox `Operation not permitted` as a framework failure.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make ios-host ios-packager
scripts/parity/batch_reference_build.sh --ios
xcrun simctl install booted build/ios/LuaRuntime.app
xcrun simctl install booted build/parity/batch/SwiftUIBatchReference-iOS.app

python3 scripts/parity/batch.py capture --platform ios --device booted \
  --engine reference --spec build/parity/batch-cases.json \
  --out build/parity/runs/ios-reference-001
python3 scripts/parity/batch.py capture --platform ios --device booted \
  --engine candidate --spec build/parity/batch-cases.json \
  --out build/parity/runs/ios-candidate-001
python3 scripts/parity/batch.py compare \
  --spec build/parity/batch-cases.json \
  --reference build/parity/runs/ios-reference-001 \
  --candidate build/parity/runs/ios-candidate-001 \
  --out build/parity/runs/ios-comparison-001.json
```

Capture never installs a bundle. It copies fixture JSON into the installed
app's data container, launches once, waits for a nonce-matched `done.json`,
copies results back, and terminates the batch app. The native application
contains no Lua fixtures/assets. Candidate execution uses a dedicated packager
on a dynamically selected local port and streams `examples/parity_batch`.
The coordinator owns and closes that packager; it does not kill unrelated
port-8081 listeners. Installation is repeated only when the corresponding
native host changes. Reference captures can be reused across candidate fixes.

`--bundle-id` overrides the selected engine's default identifier. Data and logs
remain available after failures. The coordinator terminates only its selected
batch app and its owned packager. It does not close unrelated applications or
erase Simulator data. A geometry batch can run with no Simulator window open;
use `simctl io screenshot` for device screenshots when needed, and close any
windows opened for visual inspection afterward.

### 11.7 Luna's failure-driven loop

1. Run protocol tests and the existing headless suite before trusting results.
2. Generate/capture the reference once. Recapture it unchanged to calibrate
   repeatability; run the intentional regressions before approving evidence.
3. Capture the candidate and inspect comparison failures by node kind and
   shared delta pattern. Start with the smallest reproducer (empty/single-child
   before nested stacks). Distinguish interpreter/protocol defects from actual
   framework defects before changing layout.
4. Add a native regression for the underlying behavior. Fix the owning layer
   once, rerun the candidate batch, and examine all improved/regressed cases.
   Never patch a case's expected data or insert case-ID branches in production.
5. Verify representative affected UI screenshots and input states. Extend the
   grammar and add cases for the next ordered family only after the current
   failure is understood. Keep semantic IDs stable when expanding the suite.
6. Record runtime, counts, failure examples, exact commands/output directories,
   and remaining scope here and in `docs/parity/status.md`. Commit each coherent
   phase on the current branch. Do not infer gate completion from case count.

### 11.8 Architecture review and deliberate boundaries

- **Independent oracle:** reference output comes from actual SwiftUI. Cache
  reuse replaces repeated reference work, not actual reference measurement.
- **Portable coordinate contract:** native root conversion fixes the previous
  parent-local/Y-axis issue; do not recover positions by adding arbitrary
  native subview offsets in Python.
- **Strict coverage:** unsupported fields fail validation, so 224 generated
  cases cannot masquerade as coverage for grids, images, or controls.
- **Source-bound evidence:** a native binary hash alone misses streamed Lua
  changes; record source hashes too. Retain the exact input with every run.
- **Bounded work:** one deadline per batch, one completion nonce, local input,
  fresh state per fixture, owned-process cleanup. Stateful scenarios must be
  sequences inside one case so fresh-fixture setup cannot hide state loss.
- **Three verification layers:** bulk geometry; representative visual evidence;
  real interaction/accessibility/integration. Passing the first cannot replace
  the other two.
- **No private-runtime dependency:** debugger/native hierarchy inspection may
  help diagnose a failure, but private SwiftUI internals are not the expected
  data format. Arbitrary uninstrumented apps cannot reliably expose every
  semantic SwiftUI node through a UIKit subview walk.
- **Next improvements:** add XML-path parity alongside direct Lua construction;
  explicit ordered modifier nodes; per-edge padding and baseline probes;
  geometry diagnostics for text overflow; real controls and action sequences;
  environment variants; per-node screenshot crops and pixel metrics; source-
  coverage links and minimized failure reproduction specs. Avoid implementing
  an overly generic SwiftUI runtime interpreter before these concrete families.

The existing 13 gallery cases and the generated batch matrix are different
coverage sets. Do not add their counts and call the sum passing parity tests.

### 11.9 Verified handoff — 2026-09-08

Both native hosts build. `make test ios-host` passed **51 test files** and built
the UIKit host; the Python evidence protocol's eight regression tests
also pass. The following are actual 224-case runs, not time estimates:

| Platform | SwiftUI oracle | Candidate | Geometry result |
| --- | ---: | ---: | --- |
| macOS 26.6.2, scale 1 | 13.42 s | 0.63 s | 0 pass / 224 fail |
| iOS 26.5 Simulator, scale 3 | 15.68 s | 5.74 s | 0 pass / 224 fail |

These times include launch and result collection, but exclude build/install.
Warm iOS candidate captures varied from 4.04 to 5.74 seconds. Each batch uses
one app launch, with no per-case deployment. A cached reference means only the
candidate cost is paid during the fix loop. These are geometry measurements,
not screenshot timings or a claim that all SwiftUI behavior is covered.

Evidence under `build/parity/runs/` (local, intentionally not committed):

- `reference-final`, `candidate-verified`, `comparison-verified.json` — macOS.
- `reference-verified-repeat` — unchanged final oracle, identical probe sets
  in all 224 cases compared with `reference-final`.
- `ios-reference-final`, `ios-candidate-verified`,
  `ios-comparison-verified.json` — installed iPhone 17 simulator hosts.
- `visual-smoke-final/results/hstack.visual-smoke.png` — inspected actual
  SwiftUI content PNG with mixed-size labels and an opaque semantic background.

Every comparison completed validation and reported actual geometry failures.
For example, a single-child HStack expands to the offered width in the native
candidate while SwiftUI fits its content. Native text fitting also differs.
Start Luna's implementation loop with those smallest cases before nested
containers. No expected values were adjusted to make the framework pass.
No visual or interaction parity gate is closed by these runs.

The simulator batch apps and owned packager exited after capture; no screenshot
window remains open. The earlier port-8081 failure recorded in the status log is
not a current batch blocker: the coordinator uses its own available port.

Before recapturing, build/install changed native code once. Source hashes bind
evidence to native, shared Lua, and streamed fixture-app sources, but are not a
substitute for building them: the coordinator cannot prove an arbitrary supplied
binary was built from the current checkout. Existing captures intentionally
become invalid when their recorded source or executable changes.
