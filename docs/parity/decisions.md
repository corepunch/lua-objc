# SwiftUI parity decisions

## P0 mapping decisions

- `Label` in etlua is plain text and maps to SwiftUI `Text`. A symbol-plus-title
  SwiftUI `Label` needs a separate fixture and must not reuse the plain-text ID.
- The existing XML `List` is a column-oriented native table contract. It is
  tracked separately from SwiftUI `List` and SwiftUI `Table`.
- AppKit and UIKit are separate evidence targets. A UIKit API test or a macOS
  screenshot cannot establish support on the other platform.
- Exported APIs begin as `implemented-unverified`; API presence alone is not a
  passing parity result.
- The current machine cannot run Simulator capture: `xcode-select` points to
  Command Line Tools, the iOS SDK is unavailable, and `simctl` is not present
  through that path. Full Xcode is installed, but CoreSimulator currently
  refuses connections even when `DEVELOPER_DIR` points at it.
  P1 must emit an explicit unavailable result rather than silently skip iOS.

## Open decisions

- Exact SwiftUI reference host packaging and semantic frame export are P1 work.
- UIKit native diagnostics (semantic IDs, frames, safe areas and readiness)
  are not yet proven by this inventory and remain a P1 prerequisite.
- Platform-specific controls without a public counterpart will be documented as
  differences with evidence, not counted as passing equivalents.
