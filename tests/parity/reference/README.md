# SwiftUI reference host (P1 scaffold)

This directory contains the independent macOS SwiftUI host for the three MVP
cases in `tests/parity/manifest.json`:

- `text.single.default` — one `Text` view;
- `stack.h.spacing.default-text-spacer` — two `Text` views and a `Spacer`;
- `button.standard.action-counter` — a native `Button` and an action counter.

The host is deliberately independent of lua-objc. It emits a small JSON
readiness record containing the fixture ID, scene name, generation, action
count, and measured semantic probe frames. The `--activate` option performs
one programmatic Button activation for the action-counter fixture.

## Build and run

From the repository root:

```sh
scripts/parity/reference_build.sh
CASE=text.single.default scripts/parity/reference_run.sh
CASE=button.standard.action-counter scripts/parity/reference_run.sh --activate
```

To capture the reference window non-interactively, pass `--screenshot path`
and provide the window ID obtained from the desktop capture integration. This
uses macOS `screencapture` and may require Screen Recording permission:

```sh
CASE=stack.h.spacing.default-text-spacer \
  REFERENCE_WINDOW_ID=12345 \
  scripts/parity/reference_run.sh --screenshot /tmp/swiftui-reference.png
```

The script deliberately refuses to enter `screencapture`'s interactive window
picker when no ID is provided.

`REFERENCE_BUILD_DIR`, `REFERENCE_READY_FILE`, `REFERENCE_GENERATION`, and
`REFERENCE_DURATION` can be set by a harness without changing the source.

## Prerequisites and failure behavior

The host requires the full Xcode installation, a macOS 26 SDK, and a macOS
window server. The scripts select `/Applications/Xcode.app/Contents/Developer`
when present; otherwise set `DEVELOPER_DIR` explicitly. They fail nonzero with
`blocked` diagnostics when `swiftc`, the SDK, or `screencapture` is unavailable.

This is a bounded source/build/run contract, not yet the complete paired
comparison harness. It does not edit the Makefile, package an iOS target, or
write baselines/reports.
