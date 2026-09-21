# Verification — September 21, 2026

## Passing

- Diskmap regression suite: 84 assertions, including native three-pane resizing,
  stale result rejection, cancellation, startup access restrictions, native
  selection/activation, hard links, and filenames with quotes/tabs/newlines.
- Native bridge suite: 188 assertions.
- Mail workspace suite: 14 assertions.
- UIKit compile check with the installed iPhone Simulator SDK.
- App bundle: embedded Lua dependency, strict deep code-signature verification,
  and actual launch/scan of a disposable fixture.
- Actual window screenshots: large/small layouts, light/dark appearances, loaded,
  loading, empty, error, suggestions, settings, large files and file types. Search
  and suggestion selection were also exercised through the accessibility UI.
- Native layout dump at 1000×600 confirms the footer remains inside its pane and
  the trailing table cell stays within the viewport. Long names truncate; the
  inspector and Settings scroll when necessary.

## Folder percentage and layout review

- Added native colored percentage indicators, stable through filtering, with
  zero/unknown/tiny-share handling and bounds checks.
- Reviewed 36-point table rows, blue folder symbols, compact inspector headers,
  semantic gray chart segments, and grouped actions. Toolbar retained.
- Verified light and dark screenshots at 1440×880 and 1000×600; native level
  indicators stay inside cells. The focused Diskmap and bridge suites pass.
- Repeated the bounded full suite: unchanged 62 passes, four failures and five
  timeouts listed below.

## Repository-wide result

`make test` stalled in existing run-loop tests. A bounded rerun of all 71 test
files (six seconds per file) produced 62 passes, four failures and five timeouts:

- Failures: `adventure_arena_zil`, `glass_materials`, `layout_dump`,
  `stocks_workspace`.
- Timeouts: `gestures_haptics`, `navigation`, `perf_large_list`, `reorder`,
  `webpage`.

The layout-dump and Stocks failures were reproduced with a comparison native
runtime that omits Diskmap's native changes. The adventure test reports missing
bundled Zork data; the glass test requests a missing `views/Main.etlua`. These
failures have not been changed as part of Diskmap.

## Distribution still required

The generated bundle has a local ad-hoc signature. Public release requires a
Developer ID Application identity, notarization/stapling, and verification on
other supported macOS versions/architectures. No claim of notarization is made.
The scanner depends on macOS's system Perl and JSON::PP. Permissions can restrict
coverage; APFS shared blocks mean measured bytes are not guaranteed savings.
