# SwiftUI parity status

Last updated: 2026-09-08 (P1 in progress)

## Completed

- P0 inventory captured in `docs/parity/coverage.md`.
- Apple source ledger and initial mapping decisions recorded.
- Three P1 smoke fixtures entered in `tests/parity/manifest.json`.
- Baseline `make test` executed on the current checkout.
- Deterministic `examples/swiftui_parity/` gallery added with the three P1
  smoke cases selected by `LUA_OBJC_PARITY_CASE`.
- `make parity-check` now validates manifest version, required fields, IDs,
  families, statuses, platforms, and evidence arrays.
- `make parity-case CASE=<id>` now runs a fail-closed macOS screenshot/layout
  capture for each seeded case; it now uses the in-process
  `--internal-screenshot` renderer, so missing screenshots are errors, not
  passes and desktop pixels are never sampled.
- Independent SwiftUI reference host scaffold added under
  `tests/parity/reference/`; it builds as a real macOS `.app`, emits readiness
  JSON with semantic probe frames, and supports the three seeded cases.
- UIKit host now has an internal PNG renderer and `make ios-internal-screenshot`
  copies its live-window capture out of the app container without `simctl io
  screenshot`.
- The three seeded cases have now run on iPhone 17 / iOS 26.5: each produced a
  402×874 in-app content PNG, and each also produced a 1206×2622 device-frame
  PNG through `make ios-screenshot`.
- The live iOS button was activated through the Simulator accessibility tree;
  its visible/accessibility counter changed from `Count: 0` to `Count: 1`, and
  the activated device-frame screenshot was captured.
- Headless example loading passes and AppKit layout dumps were captured for all
  three smoke cases under `build/parity/p1-macos/`.

## Baseline and environment

- Branch: `feature/adventure-arena-port`
- Baseline build: existing build was present; P0 did not modify framework code.
- Baseline tests: **17 test files, 15 passed, 2 failed**.
- Existing failures: `tests/bridge_schema.test.lua` (`horizontal ScrollView does
  not add a vertical scroller`) and `tests/layout_dump.test.lua` (`edge-to-edge
  list gives spare width to stock names`).
- Toolchain: the active `xcode-select` resolves to Command Line Tools;
  `xcodebuild` cannot run and the iOS Simulator SDK/`simctl` are unavailable
  through the active developer directory. Full Xcode 26.6 is installed at
  `/Applications/Xcode.app/Contents/Developer`; using `DEVELOPER_DIR` locates
  the iOS Simulator SDK 26.5, but CoreSimulator currently refuses connections.
- The active `xcrun --sdk macosx --show-sdk-version` query returned `26.5`.

## Current fixture state

All seeded fixtures are `implemented-unverified`; no fixture is passing yet.
The candidate-side AppKit layout evidence exists, but the independent SwiftUI
reference and paired comparison are still absent.

Live AppKit screenshot capture was attempted for all three cases and failed with
`could not create image from window` plus HIServices connection-invalid errors.
The command must fail closed; no missing PNG is accepted as evidence. Preview
mode cannot render the MVC entry point because it correctly requires a view
return value, so it is not substituted for a window screenshot.

The desktop Simulator integration is available and has produced a live
Adventure Arena screenshot plus accessibility tree on an iPhone 17 / iOS 26.5
simulator. That is valid integration evidence, but it is not yet one of the
three independent SwiftUI reference captures required by the seeded manifest.

The SwiftUI host was built with Xcode 26.6 and emitted readiness for all three
macOS cases. Observed probes include `text.node` at 61.5×16 points,
HStack `left`/`right` frames at x=20/428, and the activated button case with
`actionCount: 1`. Its screenshot option now fails closed unless a window ID is
provided; the desktop capture integration remains the supported UI capture
path.

The iOS artifacts are candidate evidence only: an independent SwiftUI iOS
reference host and semantic frame export are still required before these cases
can be marked passing for parity.

Shared native surface styling now maps XML/Lua `background`, `cornerRadius`,
and `clipsToBounds` to AppKit and UIKit views; the rounded-surface fixture is
registered and awaits fresh cross-platform capture evidence.

The grid phase now measures native child widths per column and shares those
widths across GridRow HStacks; the two-by-two macOS capture shows aligned
columns. iOS capture remains pending while the simulator packager port is
occupied by stale background processes.

The long-text fixture now exercises native italic fonts, centered alignment,
single-line trailing ellipsis, and intrinsic label measurement; the macOS
capture visibly shows all four behaviors.

The imagery phase adds a native `star.fill` SF Symbol fixture with semantic
accent tint and an accessibility label; its macOS capture confirms the real
symbol rendering.

AppKit now supports native `paddingTop` and `paddingBottom` semantics; the
padding fixture's layout dump records the expected asymmetric label frame.

The independent SwiftUI reference host now has scene definitions for all eight
registered fixtures, including Grid, surface styling, long text, SF Symbols,
and edge padding. The host rebuilds successfully; this environment's current
LaunchServices invocation fails with `kLSNoExecutableErr`, so no reference
readiness or screenshot is claimed from that failed run.

The reference bundle now includes explicit version and high-resolution metadata;
LaunchServices still returns the same error after rebuild and ad-hoc signing,
so the runtime blocker is external to the SwiftUI source and remains recorded.

Semantic surface colors are now normalized across AppKit and UIKit, including
the `systemGreen`/`background` values used by the cross-platform fixtures;
both native hosts rebuild successfully.

UIKit now exposes native `UISlider` and `UIStepper` constructors with bounded
values, step size, and value-change callbacks; the API regression suite covers
their bridge registration and native control types.

AppKit ScrollView axis inference now matches SwiftUI: omitted axes are
vertical, `horizontal=true` selects horizontal-only unless `vertical=true` is
explicit, and both-axis scrolling remains available. UIKit retains its
existing vertical-default contract for compatibility.

The baseline table-width failure is resolved: explicit NSTableView column widths
are no longer redistributed by AppKit, while declared flexible columns remain
managed by the Lua table layout source.

Secure text entry is now native on both platforms: AppKit selects
`NSSecureTextField`, and UIKit sets `UITextField.secureTextEntry` through the
shared XML/Lua `secure` property.

Section and GroupBox containers are now available in the cross-platform XML
vocabulary, with a nested macOS capture showing native stack composition and a
rounded semantic surface. Internal screenshots now honor explicit requested
dimensions, preventing taller fixtures from being clipped.

DisclosureGroup is now represented by a native button plus retained expanded
content state on both platforms; the expanded macOS fixture captures its
header and content, and the independent SwiftUI reference host includes the
matching scene.

## Next batch

P1: add the independent SwiftUI reference host and a fail-closed capture/report
script. Add readiness, environment metadata, native semantic frames, paired
screenshots, negative controls, and explicit unavailable-toolchain artifacts.
Do not approve baselines until the reference and candidate captures are
independently produced.

## Continuation: 2026-09-08

The following ordered parity phases are now implemented, tested, and pushed on
`feature/adventure-arena-port`:

- `4e9f5c77`: cross-platform `Form`, `LabeledContent`, and `ControlGroup`
  composition, with focused headless coverage.
- `e9903011`: combined Form fixture, SwiftUI reference scene, manifest entry,
  and macOS candidate screenshot/layout capture. The capture visibly contains
  the labeled row and native Cancel/Save buttons with no clipping flags.
- `6fb365ab`: native UIKit `Picker` backed by `UIPickerView`, including
  zero-based selection and selection callbacks; the iOS host compiles and the
  bridge/API tests pass.
- `81db0591`: native UIKit `TextEditor` backed by `UITextView`, including
  text/value, editable/selectable state, wrapping, font, and background
  behavior; the iOS host compiles and the bridge/API tests pass.
- The current follow-on change adds UIKit `SearchField` backed by
  `UISearchTextField`, with XML registration and bridge coverage; it is
  committed as `28c3d045`. No simulator screenshot is claimed because the same
  packager bind failure remains active.

The input fixture `input.native-editor-picker-search` is now registered as the
12th manifest case. Its SwiftUI reference host builds, and the macOS candidate
layout dump records native `NSSearchField`, `NSPopUpButton`, and
`LuaTextScrollView` frames. The headless PNG visibly renders the editor text,
but does not visibly render all control chrome, so the image is retained as
candidate evidence without marking the fixture passing.

`OutlineGroup` is now available on both platforms as a recursive composition of
native `DisclosureGroup` and text nodes over `data`/`items` tree input. Its
construction and recursion contract are covered by a focused headless test.

UIKit `ProgressView` now selects native `UIProgressView` for determinate
`value` input and retains the native activity indicator for indeterminate use;
XML registration, bridge coverage, and the iOS host build all pass.

UIKit buttons now map `plain`, `bordered`, `borderedProminent`, and `link` to
native `UIButton.Configuration` styles; the current iOS SDK host build and
focused bridge test pass.

Native `Link` is now available on AppKit and UIKit. It validates the URL and
uses `NSWorkspace` or `UIApplication` to open it from a native button target;
the shared XML tag and both bridge paths are covered by a focused test.

Native `DatePicker` and `ColorPicker` controls are now available on both
platforms, using `NSDatePicker`/`NSColorWell` and `UIDatePicker`/`UIColorWell`.
They accept timestamp/semantic-color inputs and optional native value-change
callbacks; the current macOS and iOS hosts compile without deprecated API
warnings.

The full headless suite is now 35 test files passing, and the parity manifest
validates with 12 cases. An internal iOS Simulator capture was retried for the
new Form fixture using the in-app screenshot channel; it remains unavailable
because the local packager cannot bind port 8081 (`Operation not permitted`)
after stale packager activity. No iOS screenshot is claimed for that attempt,
and the failed run was cleaned up without leaving a screenshot window open.
