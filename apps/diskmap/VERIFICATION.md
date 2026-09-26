# Sidebar redesign — September 26, 2026

Overview, Largest Items, Developer and Storage Guide destinations; donut
overview; `SectorChart`, `Gauge`, `help`, `monospacedDigit`, window
`subtitle`, `borderedProminent`, `controlSize`, native disclosure triangles
and source-list section rows in the framework.

- Written in a Linux container without Xcode, so `make`, `make test`,
  screenshots and layout dumps were **not** run for this change.
- Run with stock Lua 5.4 and a stub view layer: the real controllers,
  models and etlua templates rendered every page, navigated the sidebar,
  opened each sheet route and filtered by search, for both a scripted
  inventory and the Mock HDD provider. `tests/diskmap_overview.test.lua`
  (148 assertions) and the `SectorChart` geometry pass under stock Lua.
- Before merging on macOS: `make && make test`, then screenshots of each
  destination in light and dark at 880×580 and 1400×900, a layout dump of
  the overview, and a VoiceOver pass over the chart, gauges and sidebar.

# Cache removal — September 22, 2026

Saved-inventory replay and scan-result persistence have been removed. Every
launch starts a fresh scan; tests inject current scanner responses directly.
The earlier verification notes below describe historical implementations.

# Category redesign verification — September 21, 2026

- `make` and `make diskmap-app` pass; the bundle has a local ad-hoc signature.
- Diskmap: 567 assertions pass. Covers catalog policies, partial/denied/stale
  measurements, ancestor Keep, cache replay, chart accounting, scan cancellation,
  cross-root exclusions, hard links, small-window geometry, and Settings return
  navigation. The scanner fixture uses disposable temporary files.
- Native outline cells: 27 assertions pass for subtitle/symbol cells, clearing
  reused values, disclosure/selection preservation, viewport widths, native
  NSBox, determinate progress and ancestor layout invalidation.
- Bridge: 189 assertions pass. Outline sizing now tests the native cell's
  extent rather than assuming declared column width includes AppKit insets.
- Scroll content layout: 12 assertions pass.
- Screenshot QA used a saved synthetic inventory (since removed), explicitly synthetic and
  visibly labeled as test cache. Inspected small/large windows, light/dark,
  expanded Developer, selection, Settings, empty search and native loading.
- Native layout dumps confirmed the dashboard remains inside the minimum-size
  window. Long outline subtitles truncate; full descriptions are in the inspector.
- Computer Use verified real outline disclosure, arrow-key selection and the
  bottom-left Settings button. A Settings-to-Storage selection bug found during
  that pass is now covered by a regression test.
- Colored capacity breakdown restored, including Other/unmeasured and free space.
  Its weights sum to capacity; conflicting allocation totals disable the chart
  rather than fabricating proportions.

`make test` stalls in existing run-loop tests. A bounded per-file sweep reproduces
previously recorded issues: adventure_arena_zil (missing source), glass_materials
(missing template), layout_dump, stocks_workspace; timeouts in gestures_haptics,
navigation, perf_large_list, reorder and webpage. No blanket full-suite pass is
claimed. Focused affected suites pass.

Coverage is a catalog of known locations, not exhaustive discovery of every app
version or custom installation. Shared storage and independent measurement
batches can differ from physical capacity; the unreconciled difference stays
visible. Protected resources and mixed application data remain review-only.

Icon/feature follow-up: verified white rounded badges, square intrinsic sizing,
installed app artwork (NSWorkspace requires Launch Services access), missing-app
fallback, Siri/Dictation independent rollups, exact-path uniqueness, and rejection
of obsolete unsplit caches. Screenshots cover System Data expanded in light and
dark appearances. Known asset classes were checked against this Mac’s AssetsV2
directory; unrecognized classes and preinstalled assets remain residual.

## Compact layout polish

- Default window is 1024 × 768; verified at 1000 × 640 and 1440 × 900.
- Capacity remains the toolbar subtitle. Inline toolbar content now measures its
  natural size, with no fixed title-block width/height or fallback dimensions.
  Regression coverage checks two lines plus growth and shrink after text changes.
- Navigation and Settings use matching native source-list cells. The legend uses
  one row of category labels; outline disclosure controls center on each row.
- Focused headless suites pass: Diskmap, toolbar intrinsic sizing, outline cells,
  scroll content, bridge, XML templates, stack contracts, and ZStack.
- Real screenshots checked default/light, minimum/dark, and large/light layouts.
  Live accessibility/keyboard checks covered selection, expansion, Settings return,
  empty search, and the native measurement spinner. Cache screenshots use synthetic
  data. Normal app startup was also inspected with partial measurement results.
- Long category subtitles intentionally truncate in the outline; selection exposes
  the description in the inspector. Native scrollers retain access at smaller sizes.

## 2026-09-22 — spacing and framework contract

Added shared leading/trailing padding on AppKit and UIKit and an 8 pt native
outline disclosure/content gap. The coverage pane has a 16 pt trailing inset.
Settings retains its native source-list row metrics with no extra bottom padding.
Verified screenshots at 1024×768, 1000×640 dark, and 1440×1000 light; the
minimum-size layout dump confirms the coverage inset and bottom Settings frame.
Regression coverage checks edge overrides, explicit zero, mutation isolation,
disclosure geometry, and app insets. Both platform runtimes build.

## 2026-09-22 — full inventory

Startup plans all 153 file-backed roots and excludes separately owned descendants,
mounted volumes and symlinks. Fast regressions cover every catalog target, absent
roots, symlink ancestors, hard links across categories, interruption and cache replay.
The real scan inspected 2,054,792 entries in 65 seconds: 182.1 GB measured versus
195.9 GB used, with 13.8 GB unreconciled and 988 access failures. Local diagnostics
were saved to `/tmp/diskmap-live.json` (not checked in). Screenshots verified real
measurements, the synthetic fixture, and the minimum-size dark layout. The bar
now includes every measured category and a separate unreconciled segment.

## 2026-09-22 — feature components and knowledge-based recommendations

- Nine independent catalog providers compose the same versioned ownership ledger.
  Scan, categories, cleanup, tips, inspector and settings each have focused
  controllers; pure models and injected services are exercised independently.
- Cleanup rules now require recognized ownership, a complete measurement and a
  resource-specific review threshold. Tests cover threshold boundaries, excluded
  large projects/installations, uncertain measurements, Keep ancestors, stable
  action IDs, persistence failures, cancellation generations and stale warm caches.
- Shared `ui.template` retains unchanged native subtrees and owns scoped replacement
  and callback disposal. Tests cover structural changes, live action rebinding,
  parent disposal, render failures, native identity and immutable caller bindings.
- Native scroll views preserve reading position through growing/shrinking viewports.
  Label measurement includes native field insets and retains declared wrapping
  through text mutation. Long paths support character wrapping on both platforms.
- AppKit and UIKit build; `make diskmap-app` rebuilds the standalone app. Final
  targeted suites: Diskmap 687 assertions, feature components 56, inventory 23,
  template mounts 13, native image/text 17, scroll layout 14, XML 106, outline 33.
- Final regression sweep: 68/68 previously passing and affected suites pass with
  native Launch Services access. A bounded sweep of all 77 files also reproduced
  four existing failures (adventure_arena_zil, glass_materials, layout_dump,
  stocks_workspace) and five existing run-loop timeouts (gestures_haptics,
  navigation, perf_large_list, reorder, webpage). The four failures were confirmed
  on untouched incoming baseline `f4769008`. `make test` therefore has no blanket
  pass claim. Sandbox-only app-icon failures pass with Launch Services access.
- Screenshot inspection covered 1024×768, 1000×640 and 1440×1000, light/dark,
  real loaded inventory, native loading, empty search, invalid-cache errors,
  selected/disabled inspector actions, Settings and long text. The final native
  layout dump and long-text screenshot verify all inspector words and path
  characters remain accessible. Content below the viewport uses native scrolling;
  compact outline subtitles intentionally truncate.
- Computer Use exercised native search, disclosure, arrow-key selection/collapse,
  Settings and Cleanup navigation in the app. The standalone bundle was captured
  again using the saved real inventory. No real cleanup action was performed.

Real scans retain local diagnostics and refresh every category. Access-denied
files, APFS shared extents and exclusive snapshot allocation still limit physical
reconciliation; these remain explicit, rather than invented measured values.


## 2026-09-22 management and privacy pass

- All Diskmap headless suites and the native sheet regression pass, including
  media opt-in boundaries, unique accounting paths, runtime MobileAssets,
  partial review evidence, dynamic agent children, simulator command validation,
  cancellation, Keep protection, busy/error state and stale async responses.
- Built AppKit, StorageScan and the signed local Diskmap.app; UIKit compile check
  completed (no UIKit native source change).
- Live native sheets inspected through accessibility and screenshots. The real
  read-only simctl service returned 11 devices. No device or file was deleted.
- Visual fixtures cover selected/disabled, empty, loading, long names, light/dark,
  and smaller/larger layouts. Offscreen renders cannot capture the native tab
  selector correctly (black); the live screenshot confirms native tabs render.
- Full `make test` stalls on existing event-loop test entrypoints. A bounded run
  of 88 suites passed 78. Remaining failures: stocks_workspace, adventure_arena_zil
  (missing bundled source), layout_dump, outline_cells (app artwork under sandbox),
  glass_materials (missing views/Main.etlua). Timeouts: navigation, reorder,
  perf_large_list, webpage, gestures_haptics. The native sheet and typed table-selection suites passed. These broad-suite results are not a clean full-suite pass.

- Final live sheet uses an opaque semantic `controlBackgroundColor` surface and a native default Done button. Both row selection and activation preserve booleans/numbers; shutdown simulator actions enable correctly.
