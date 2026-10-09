# Layout guidelines

How a page uses the width and height it is given. Read before changing a
page's sizing; the rules are short so that every page follows them.

## Width: one frame for every page

Diskmap pages use exactly two shells, all with the same 960pt centered
column, 24pt margin and 16pt section spacing from
`apps/diskmap/views/layouts/PageResources.etlua`:

- `ContentPage`: one scrolling surface for reading, cards and sectioned lists.
- `TablePage`: a fixed header and controls above a native scrolling table that
  fills the remaining height.

```xml
<ContentPage id="page">
  ...
</ContentPage>
```

The shell owns the content stack. A page never declares its own outer stack,
page scroll view, outer margin, width cap or body-height constant. Table
bodies use `flexGrow="1" flexBasis="0" maxHeight="infinity"`. There are no
window footers or conditional item-count bars; flags use the Review toolbar
badge. Selection details belong within the page beside their related content.
Never cap the window's content host (`layouts/Content.etlua`): a scrolling
page keeps its scroll bar at the window edge.

Overview, Storage Map, Folder Map and File Types compose the same `Breakdown`
widget in `ContentPage`: a compact native chart on the left, a concise legend
on the right, and the complete list below. The icon button shows the alternate
chart mode. In rectangle mode the chart spans the whole widget, with no side legend.
Switching modes never removes the complete list below. Page and selection operations belong in `NSToolbar`;
row flags and context menus stay local.

Why: Apple caps reading width in its own layouts (UIKit's
`readableContentGuide` is 672pt at the default text size; a grouped SwiftUI
`Form` on macOS 15 is capped at 600pt and centered; System Settings cannot
be made wider). In a stretched card a label and its value end up a screen
apart. Lines of prose read best at 45–90 characters. Backgrounds and real
tables are the only things that should reach the window edges.

Do not:

- cap single rows or legends with their own `maxWidth` to fight the
  stretch: cap the page once;
- let a page fill the window because its content is a table or a chart;
- add a multi-column layout for wide windows. Apple's utilities do not, and
  it is machinery. Grids of equal tiles are the exception.

## Charts: one ideal size

A ring or chart beside text has **one** size number: its `diameter`, the
ideal square. Pick it so the ring is about as tall as the text column
beside it, and neither leaves the card empty above and below the other.

- `flexGrow="0"` and `fixedSize="vertical"`: the ring never grows past its
  diameter and reserves no height it does not draw.
- `flexShrink="1"` and `minWidth`: below the ideal it shrinks for the text
  column's `minWidth`, which the HStack reserves before it sizes the ring.
- The center text is in the units of the diameter, so ring and total
  shrink together. Never give a chart a `diameter` and then a different
  `maxWidth`: that is two sizes for one thing.
- A chart that *is* the page content (Storage Map, Folder Map) fills its
  pane instead: `maxWidth`/`maxHeight="infinity"`, and the pane, not a
  constant, decides.
- The minimums in one row must add up to no more than the row's width at
  the window's minimum size. If they cannot, the design needs to change
  (stack the ring above the text), not the constants.

## Chart colors

No two colored sectors of one ring share a hue, and a ring is mostly color,
not gray.

- Ring sectors claim hues through `helpers/Palette.lua`: a sector keeps its
  catalog color while that hue is free, else takes the next free one. Claim
  largest first (`Categories:hues`).
- The legend and every list beside the ring use the ring's colors, never
  the catalog colors again.
- Look-alike hues are one hue: pink reads as red and cyan as teal beside
  each other, so the palette claims them together. A ring colors at most
  `Palette.distinct` sectors (ten); smaller ones fold into its gray
  "N smaller" sector rather than repeat a hue.
- Gray means "the rest": free space (the track, `quaternaryLabel`), what is
  not attributed (`tertiary`), folded categories (`systemGray`). Fold
  late enough that the named sectors hold most of the used space (the
  Overview names seven categories).

## Verify

- `--capture-plan` with one launch per window size; switch pages inside
  the plan with `app:show(page)`. Never start one app instance per page.
- Check the window's minimum (Diskmap: 950×580, 724×580 with
  `--isolated`), 1280×800 and 1900×1000, light and dark. A requested size
  below the window's `minWidth`/`minHeight` is clamped to it, as a drag
  is, so a capture never shows a size no one can reach.
- `rg 'outsideParent="true"|cropped="true"'` in the `.layout.xml`.
- Headless tests: `tests/diskmap_ring_sizing.test.lua`,
  `tests/sector_chart_sizing.test.lua`, `tests/diskmap_palette.test.lua`.
