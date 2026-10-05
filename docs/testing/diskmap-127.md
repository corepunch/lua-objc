# Diskmap issue 127 verification

5 October 2026. All storage screenshots and navigation checks used synthetic
showcase data, with the current repository runtime and freshly built bundle.
The earlier review artifact in `docs/research/diskmap-ux-review/` was left untouched.

## Behavior

- Storage Map leaves use the same location destination as Largest Locations.
  Category sheets retain the originating leaf selection.
- Selected locations expose an explicit destination action and Inspect Folder
  Contents. Developer projects names Review Build Data separately and shows
  measured folder contents alongside generated build bytes. Folder totals
  rejoin the disjoint catalog scan roots; they are measured bytes, not a claim
  of complete access to every file.
- Search names its page scope and clears on page transitions, including history.
  Refresh keeps the query. Storage Map states that only its list is filtered,
  including in Rectangles. Folder Map disables the unused search field.
- Large Files defaults to All. Its no-results message names query, filter and
  any selected kind. Selected files expose Show in Finder; Folder Map exposes
  Inspect Folder Contents or Preview File.
- Back/Forward visit pages. Both maps expose Up for exploration levels.
  Hover points at native rows without replacing the kept action selection.
- Overview leads with its storage summary; exploration destinations remain in
  the sidebar without duplicate buttons or explanatory text above the summary.

## Automated checks

The original navigation changes passed all Diskmap test files. Final removal verification is recorded below.
`tests/diskmap_ux_navigation.test.lua` adds 50 assertions for destinations,
selection, history/search state, discovery defaults and folder/build scope.

The full 260-file suite initially found five affected tests, all subsequently
corrected and passing. Its remaining unrelated failure is
`tests/workspace_size.test.lua`: HEAD already contains 89.1 MB of tracked source,
above that test's 80 MB headroom threshold (the hard budget is 100 MB).
No workspace policy was changed.

`make` and the unsigned local `make diskmap-app` build succeeded.
`git diff --check` passed.

## Native visual and live checks

Native captures and layout dumps were inspected at 950 × 580 and 1400 × 900,
including Overview, Projects, Large Files All/no-results, selected Largest
Locations, selected Folder Map, and Storage Map selected/search/Rectangles.
Storage Map was also inspected in dark appearance at both sizes. Paths:
`/tmp/diskmap-issue127/min/` and `/tmp/diskmap-issue127/large/`.

Live mouse/accessibility checks exercised all 22 destinations available in the
showcase sidebar or Go menu. Photography, Design and 3D & Engines were correctly
disabled because their workflows are absent in that fixture. Checked native
map drill and selection, the Review Build Data action, Command-F, query entry,
query clearing through sidebar navigation, and the explicit Downloads action
arriving in its sheet with Downloads selected.

A temporary copy of the current bundle used the showcase provider with real
folder scanning, Finder reveal and Quick Look services for a generated text file
under `/private/tmp/diskmap-issue127/local-files/`. Preview File opened a real
Quick Look window displaying that text. Show in Finder opened the folder and
selected Preview Test.txt. No personal files were moved or deleted.

This is focused verification of the changed journeys. It does not claim a
complete live walkthrough of every existing non-destructive button on every
page, VoiceOver operation, or all access/error/loading states. Return on a
selected native table row retained selection; the explicit destination button
was used to open it. Existing loading/error/empty/selection/cleanup headless
coverage passed.

## Header and chart layout

More than two visible header actions follow the heading on a separate row.
One or two move below when their combined native width exceeds 30% of the
available header width; FlowStack wraps long groups. Stacked headings keep
intrinsic height. Shared AppKit/UIKit layout tests cover the exact threshold,
narrow/wide/zero-width round trips, hidden and disabled buttons, changed titles,
wrapping and retained property changes.

Ring charts render in their final shape. The shared path animator, animation
properties/constants, cross-level arc matching and chart-specific geometry
patching are deleted. Arc shape/color changes disable implicit layer actions.
Changed chart records or geometry create a fresh chart. Navigation disposes
its page controller and mounts a new controller/template; model state remains
separate from native elements. The generic reconciler preserves native overlays
alongside record children. SectorChart has 109 regression assertions and the
Diskmap page lifecycle has 21 assertions.

## Final navigation surfaces

Favorites and per-location size tracking are removed completely: sidebar
shortcuts, route, buttons, menus, model, service and persistence provider APIs.
The SDK sheet contains search, SDK rows, status and Done. Storage Map and
Largest Locations retain their explicit destination/folder actions; Folder Map
retains exploration and preview. The 30-assertion navigation-surfaces test checks
these native controls, clean sidebar, resource/folder menus and Back/Forward.
Shared Application Support API coverage was moved to its own three-assertion
test before deleting the old location-tracking test.

Final removal verification: all 81 selected test files passed (74 Diskmap and
seven shared chart/template/layout/storage-directory files). The unsigned bundle
built successfully. Twenty native captures at 950 × 580 and 1400 × 900 cover
Overview, selected Storage Map, selected Largest Locations, Folder Map and the
SDK sheet in light and dark under `/tmp/diskmap-clean/`. The sidebar begins with
Overview and no pin controls or location-tracking pages remain.

## Suggestion action typography

The Worth a look actions use declarative native button labels with the same
12-point font as the adjacent name and size. The original native button cell
placed its title below the row's label baseline; matching the font alone did
not correct it. No pixel offsets or shared layout changes were added.
The alignment test checks matching font, text height, baseline and accessibility
title at both window widths, including Mark → Marked → Mark round trips.
All eight selected alignment, page, environment, navigation, template and button
regression files passed; the expanded alignment test has 538 assertions.
Eight native screenshots and layout dumps at 950 × 580 and 1400 × 900 cover
Mark and Marked in light and dark under `/tmp/diskmap-mark-align/`. The action
label and adjacent labels have identical native text rectangles and baselines.

## Storage Map pane widths

Removed the list's 330-point maximum width. Both ring-mode panes now share
the available width with equal flex weights and a zero basis, keeping their
300-point minimums. Rectangles still use the full row. At 1400 × 900 the
list/chart widths change from 330/780 to 555/555 points: the ring no longer
sits in a much wider pane, and long location names use the reclaimed space.
The native layout calculates this split on resize without app callbacks.

The new 30-assertion map-split test covers narrow, large and wide/short sizes,
resize round trips, chart diameter, the native list's width and switching
between rings and rectangles while keeping exploration focus. All four
selected split/page/alignment/navigation test files pass. Twelve native
screenshots and layout dumps cover 950 × 580, 1400 × 900 and 1600 × 650,
including light/dark and Mark/Marked states, under `/tmp/diskmap-split/`.

## Grouped row alignment audit

The Overview explanation used a different inset, symbol column and gap from
the category list: its text was 4 points farther right and its symbols were
centered 5 points farther right. Its header symbol was also clipped.
`GroupedRowMetrics.etlua` now supplies the native list's 6-point cell inset,
28-point image column and 8-point text gap to the explanation, recommendation
cards, Clean Up tips, and Updates status/stage/snapshot rows. These are ordinary
template row dimensions; no positional offsets or layout callbacks were added.
At both supported widths the Overview symbols center at x=275 and its text
starts at x=297, matching the adjacent category cells. The header symbol is
no longer clipped.

Reviewed native screenshots for all 25 destinations at 950 × 580 and
1400 × 900, including empty workflows and disabled actions, with light and
dark captures under `/tmp/diskmap-alignment-audit/`. Final captures cover
the seven affected pages in both appearances and sizes, plus scrolled Clean Up
tips and Updates snapshots. Other page headers, table rows, guide/help symbol
rows, disclosures and empty states retain their consistent columns.

All 77 Diskmap and shared component/resource test files passed. After the final
Updates adjustment, all six affected page/alignment test files passed again;
the alignment regression has 582 assertions and compares card columns against
real AppKit table cells. The unsigned app bundle and `git diff --check` pass.
