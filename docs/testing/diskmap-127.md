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
- Overview exposes Find Largest Locations and Inspect a Folder.

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
