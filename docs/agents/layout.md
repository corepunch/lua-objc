# Layout guidelines

How a page uses the width and height it is given. Read before changing a
page's sizing; the rules are short so that every page follows them.

## Width: fill or read

A page is one of two kinds, and its kind decides what a wider window does.

| Page | Wider window | Examples |
| --- | --- | --- |
| **Table page**: its primary content is a native table or a chart pane | fills the window; the spare width goes to the name column or the chart | Large Files, Largest Locations, Storage Map, Folder Map |
| **Card page**: grouped cards, a hero, rows of label and value, prose | no wider than `@readableWidth` (960pt), centered | Overview, File Types, Disks, Updates, guides |

A card page wraps its content in the readable column (Diskmap's
`views/components/ReadableWidth.etlua` declares the constant):

```xml
<ScrollView id="page" vertical="true" ...>
  <VStack padding="24" alignment="center">
  <%- partial("../components/ReadableWidth.etlua") %>
  <VStack id="pageContent" maxWidth="@readableWidth" spacing="24" alignment="leading">
    ...
  </VStack>
  </VStack>
</ScrollView>
```

Why: Apple caps reading width in its own layouts (UIKit's
`readableContentGuide` is 672pt at the default text size; a grouped SwiftUI
`Form` on macOS 15 is capped at 600pt and centered; System Settings cannot
be made wider). In a stretched card a label and its value end up a screen
apart. Lines of prose read best at 45–90 characters. Backgrounds and real
tables are the only things that should reach the window edges.

Do not:

- cap single rows or legends with their own `maxWidth` to fight the
  stretch: cap the page once;
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
- Gray means "the rest": free space (the track, `quaternaryLabel`), what is
  not attributed (`tertiary`), folded categories (`systemGray`). Fold
  late enough that the named sectors hold most of the used space (the
  Overview names seven categories).

## Verify

- `--capture-plan` with one launch per window size; switch pages inside
  the plan with `app:show(page)`. Never start one app instance per page.
- Check 760×468 (minimum), 1280×800 and 1900×1000, light and dark.
- `rg 'outsideParent="true"|cropped="true"'` in the `.layout.xml`.
- Headless tests: `tests/diskmap_ring_sizing.test.lua`,
  `tests/sector_chart_sizing.test.lua`, `tests/diskmap_palette.test.lua`.
