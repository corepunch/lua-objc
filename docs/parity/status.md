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

## Next batch

P1: add the independent SwiftUI reference host and a fail-closed capture/report
script. Add readiness, environment metadata, native semantic frames, paired
screenshots, negative controls, and explicit unavailable-toolchain artifacts.
Do not approve baselines until the reference and candidate captures are
independently produced.
