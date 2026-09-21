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
- Screenshot QA used `tests/fixtures/diskmap.json`, explicitly synthetic and
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
