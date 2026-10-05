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

All 74 Diskmap test files passed across the final group and targeted reruns.
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

## Favorites follow-up

The persisted watchlist now appears as Favorites. A shortcut opens its original
location destination: the saved SDK installation's sheet, Derived Data's Xcode
page, or the exact saved folder in Folder Map. The favorite's native sidebar
menu retains View Size Changes and offers Remove from Favorites. Visible pin
buttons are present on selected Storage Map and Largest Locations entries,
Folder Map, and SDK installations; individual SDK folders are pinnable from
native row menus. Long favorite names keep their full path in native help.

All 75 Diskmap test files passed in the Favorites group run. Subsequent targeted
checks passed after the final sidebar/help/menu changes. The new Favorites test
has 50 assertions covering minimum-width layout, persistence, dedicated SDK destinations, exact folder
paths in Back/Forward, selection versus hover, removal, missing locations, and
menu actions retained across two windows. An unsigned Diskmap bundle builds.

Final native captures were inspected at 950 × 580 and 1400 × 900 in light and
dark appearances under `/tmp/diskmap-favorites/min/` and
`/tmp/diskmap-favorites/large/`. These cover Storage Map and Largest Locations
selection actions, Folder Map, size changes, and the SDK sheet. SDK rows use
synthetic names and sizes. Favorites use the existing native source-list
truncation; full names and paths remain available through help and accessibility.

Live checks against a temporary synthetic app confirmed one-click SDK and
Derived Data shortcuts, adding an individual SDK through its native context
menu, and opening size changes from the favorite's sidebar menu. No real SDKs
or build data were modified. The existing complete-live-review limits above
still apply.

Overview correction: removed the duplicate exploration buttons and map
explanation above the storage summary, along with the unused folder action.
The navigation regression now checks that exploration remains accessible from
the sidebar without those duplicate controls. All four affected test files
passed (680 assertions). Native Overview screenshots were inspected at
950 × 580 and 1400 × 900 in light and dark under
`/tmp/diskmap-overview-clean/`; the unsigned bundle rebuilt successfully.


Adaptive header correction: more than two visible buttons always follow the
heading on a separate row. One or two move below when their combined native
width exceeds 30% of the available header width; action groups wrap further
with FlowStack. The shared AppKit/UIKit HStack rule measures and lays out the
same native children on every resize. Removed the dedicated FavoriteActions
partial and use the shared page header for size changes. Stacked headings
keep their intrinsic height, fixing the initial oversized first row.

Nine focused test files passed across the layout and final targeted runs
(551 assertions). The adaptive header test has 33 assertions covering the exact
threshold, narrow/wide/zero-width round trips, hidden/disabled buttons, changed
titles, wrapping, intrinsic heading height and retained property changes.
Native screenshots and layout dumps at 950 × 580 and 1400 × 900 in light and
dark were inspected under `/tmp/diskmap-adaptive/final-min/` and
`/tmp/diskmap-adaptive/final-large/`. All 40 captured page headers have no
clipped text or children outside their bounds. The rebuilt temporary synthetic
app also showed the corrected compact SDK favorite header before and while
opening its SDK sheet. Both bridges and the unsigned Diskmap bundle build.
