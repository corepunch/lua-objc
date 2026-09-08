# SwiftUI parity status

Last updated: 2026-09-08 (P0)

## Completed

- P0 inventory captured in `docs/parity/coverage.md`.
- Apple source ledger and initial mapping decisions recorded.
- Three P1 smoke fixtures entered in `tests/parity/manifest.json`.
- Baseline `make test` executed on the current checkout.

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

## Next batch

P1: build the smallest macOS/iOS reference and etlua harness, beginning with
the three manifest cases. Add readiness, environment metadata, native semantic
frames, screenshots, negative controls, and explicit unavailable-toolchain
artifacts. Do not approve baselines until the reference and candidate captures
are independently produced.
