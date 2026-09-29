# NSTableView / SwiftUI Table — architecture & behaviour notes

This file collects findings about how SwiftUI's `Table` maps to AppKit's
`NSTableView`, so we can keep the Lua bridge faithful to platform behaviour
without rediscovering the same details every time.

## SwiftUI `Table` is `NSTableView` under the hood

On macOS, SwiftUI's `Table` renders as a view-based `NSTableView` inside an
`NSScrollView`. The mapping is straightforward:

| SwiftUI | AppKit |
|---|---|
| `Table` | `NSTableView` (view-based, `NSTableViewStyle.fullWidth` by default) |
| `TableColumn` | `NSTableColumn` with identifier, title, optional width |
| `.tableStyle(.inset)` | `NSTableView.Style.inset` |
| `.alternatingRowBackgrounds()` | `usesAlternatingRowBackgroundColors = true` |
| `.contextMenu()` | `NSTableView.menu` |

## Column autoresizing

SwiftUI sets `NSTableView.columnAutoresizingStyle` to
`NSTableViewUniformColumnAutoresizingStyle`. This means **all** columns resize
proportionally when the table view's frame changes — not just the last column.

### Styles (for reference)

| Constant | Behaviour |
|---|---|
| `NSTableViewNoColumnAutoresizing` | Columns never resize |
| `NSTableViewUniformColumnAutoresizingStyle` | All columns resize proportionally (SwiftUI's choice) |
| `NSTableViewSequentialColumnAutoresizingStyle` | Leftmost columns resize first |
| `NSTableViewReverseSequentialColumnAutoresizingStyle` | Rightmost columns resize first |
| `NSTableViewLastColumnOnlyAutoresizingStyle` | Only the last column (AppKit default) |
| `NSTableViewFirstColumnOnlyAutoresizingStyle` | Only the first column |

### What we use

`NSTableViewUniformColumnAutoresizingStyle` — so columns shrink/grow
together when the parent container resizes the view, matching what SwiftUI
apps see.

## Horizontal scrolling when columns don't fit

### SwiftUI behaviour

SwiftUI's `Table` does **not** automatically gain horizontal scrolling.
If columns are wider than the available space, they are compressed
proportionally (unless explicit `minWidth` constraints prevent further
shrink). To get horizontal scrolling, the developer must wrap the `Table`
in an explicit `ScrollView(.horizontal)`.

### AppKit equivalent

`NSScrollView` wrapping `NSTableView` supports horizontal scrolling via
`hasHorizontalScroller = YES`. The table view as the document view can be
**wider** than the scroll view's clip view; when it is, the horizontal
scroller appears automatically.

The key: **do not clamp** `_tableView.frame.size.width` to the viewport
width when columns overflow. Instead, let the table frame be the sum of
column widths. Cocoa's scroll machinery handles the rest.

### Our implementation

In `updateTableFrame` (called on every row insertion and every layout pass):

**When any column omits `width` (flex column):**

1. Columns with an explicit `width` are treated as fixed — they keep their
   specified width.
2. Columns without `width` are flexible — they split the remaining viewport
   space equally among themselves.
3. If the viewport is narrower than the sum of all fixed-column widths,
   all columns shrink to their `minWidth` and a horizontal scroller appears.

**When every column has an explicit `width` (legacy, no flex columns):**

1. Compute `totalColumnWidth` from `tableColumns`
2. If `totalColumnWidth > viewport.width`:
   - `hasHorizontalScroller = YES`
   - `_tableView.frame.width = totalColumnWidth` (table is wider than visible area)
   - Do **not** call `sizeLastColumnToFit` (columns keep their explicit widths)
3. If columns fit:
   - `hasHorizontalScroller = NO`
   - `_tableView.frame.width = viewport.width`
   - Call `sizeLastColumnToFit` → autoresizing distributes remaining space

This gives us the SwiftUI-equivalent behaviour: columns with explicit
`width`/`minWidth` get a horizontal scrollbar when the view is too narrow;
columns without `width` stretch to fill the available space.

## Column widths

### Stretch column (no `width`)

Omitting `width` on a column makes it a stretch column that fills the
remaining viewport space. This follows the same contract as other lua-objc
controls: no explicit size means "consume available space."

Multiple stretch columns split the remaining space equally.  To prevent
a stretch column from collapsing below a readable size, set `minWidth`:

```lua
columns = {
    { id = "from",    title = "From",    width = 120 },
    { id = "subject", title = "Subject" },               -- stretch column
    { id = "date",    title = "Date",    width = 60, minWidth = 40 },
}
```

When the viewport is too narrow for all fixed columns at their `minWidth`,
a horizontal scroller appears — keeping every column at least its
`minWidth` and restoring the scrollable overflow behaviour.

### Legacy table (all columns have `width`)

When every column has an explicit `width`, the old `sizeLastColumnToFit`
behaviour is preserved: the last column stretches to fill the viewport,
or a horizontal scroller appears when columns overflow.

## Scroll view geometry (`tile` and bounds staleness)

After setting `NSScrollView.frame`, the internal clip-view and scroller
geometry may be stale until the next display cycle. In our layout engine,
we call `[(NSScrollView *)view tile]` **before** reading `clipView.bounds`
in `updateTableFrame` so the viewport width reflects the new frame.

`-[NSScrollView tile]` is a synchronous layout pass that recalculates the
clip view and scroller positions. Without it, `clipView.bounds.size` may
return the **previous** viewport dimensions, causing columns to be sized
for a width the scroll view no longer occupies.

## SwiftUI table modifiers (not yet mapped)

| SwiftUI modifier | NSTableView equivalent | Status |
|---|---|---|
| `TableColumn.width(min:ideal:max:)` | `NSTableColumn.minWidth / width / maxWidth` | `width` mapped |
| `TableColumn.width(_:)` | `NSTableColumn.width` | Mapped |
| `.tableStyle(_:)` | `NSTableView.style` | Mapped |
| `.alternatingRowBackgrounds(_:)` | `usesAlternatingRowBackgroundColors` | Mapped |
| `.tableColumnHeaders(.hidden)` | `headerView = nil` | Mapped |
| `TableRow.init(_:)` with selection binding | `NSTableView.selectedRow` + delegate | Not yet mapped |
| `.onDeleteCommand` / `.onInsertCommand` | NSTableView row actions | Not yet mapped |
| `DisclosureTableColumn` / `.disclosureTableColumn` | `NSTableView.indentationPerLevel` | OutlineView exists |
| Column sorting (`SortDescriptor`) | `NSTableColumn.sortDescriptorPrototype` | Not yet mapped |
| `.searchable` | `NSSearchField` in toolbar/header | Not yet mapped |
| `TableColumn` with custom `content`  | `viewForTableColumn:row:` returning a reusable template cell | `<Column>` child XML; see "Column content templates" (AppKit) |
| Drag-to-reorder rows | `NSTableViewDataSource` drag methods | `<List reorderable="true" reorderContainer="actionName">` sends a `ui.reorder.Difference` |

## Key takeaways

1. **Always use `NSTableViewUniformColumnAutoresizingStyle`** — it's what
   SwiftUI uses and keeps all columns visible during resize.
2. **Only enable horizontal scrolling when columns explicitly overflow**
   their minimum widths — don't preemptively show a scroller.
3. **Call `[NSScrollView tile]` before reading clip-view geometry** after
   a frame change, or bounds will be stale.
4. **`sizeLastColumnToFit` + UniformAuto = all columns resize**, not just
   the last one. The method name is misleading with this style.
5. **SwiftUI Table wraps itself in vertical-only `ScrollView` by default.**
   Horizontal scroll requires explicit `.horizontal` modifier. Our
   `NSScrollView` handles both axes natively.

## Column content templates (AppKit)

A `<Column>` with child XML is SwiftUI's `TableColumn { row in ... }`, or a
WPF `DataTemplate` given as the column's content. The child is one view,
built from the ordinary tag vocabulary and laid out by the framework's layout
engine; the column renders it in every row. A column without children keeps
the text cell that shows `row[id]`.

```xml
<List id="volumes" rowHeight="44">
  <Column id="name" title="Volume" />
  <Column id="usage" title="Used" width="220">
    <VStack spacing="3">
      <HStack maxWidth="infinity">
        <Label text="{used}" truncation="tail" />
        <Spacer />
        <Label text="{share}" color="secondary" fixedSize="horizontal" />
      </HStack>
      <Gauge value="{fraction}" tint="{color}" disabled="{!fraction}"
             accessibilityLabel="Used space on {name}" maxWidth="infinity" />
    </VStack>
  </Column>
</List>
```

### Row bindings

etlua expressions (`<%= %>`) run once, when the screen renders. An attribute
written in braces is resolved for each row instead:

| Form | Meaning |
|---|---|
| `{field}` as the whole value | The row's value, typed: a `Gauge` value stays a number, a colour is a semantic colour name |
| `"Used {a} of {b}"` | Text interpolation; a missing field reads as empty |
| `{!field}` | For true/false attributes: true when the field is missing, `false` or `""`. Zero is a value |
| `{{` | A literal brace |

There are no expressions. A value derived from several fields is a row field
the model prepares, as in any MVC view. A row without the field returns the
attribute to the value the view was built with, so a reused cell never shows
its previous row.

Bindable attributes:

| Tag | Attributes |
|---|---|
| any view | `hidden`, `opacity`, `disabled`, `help`, `accessibilityLabel` |
| `Label` | `text`, `color` |
| `SystemImage` | `name`, `color`, `badgeColor`, `appIcon` |
| `Gauge` | `value`, `tint` |
| `ProgressView` | `value` |

Binding any other attribute, interpolating into a number or colour, or
writing an expression fails when the screen renders. To make an attribute
bindable, add it to `TAG_BINDINGS` in `lua/ui/xml.lua` with the native
property it sets and its kind (`string`, `number`, `bool`, `color`); if the
native class has no such property, add a semantic accessor to the exported
class, as `LuaSymbolImageView.symbolName` does.

An `id` inside a template becomes the view's accessibility identifier in
every cell. It is not in the screen's `refs`: a template's views belong to
cells, which come and go.

### How a cell is made

1. When the screen renders, `xml.lua` keeps the column's child XML as a
   factory and validates its bindings. Nothing is built yet.
2. When AppKit has no cell to reuse (`makeViewWithIdentifier:owner:` returns
   nil), the native source calls the factory once. Lua builds the views with
   the ordinary constructors and returns them with a list of bindings: view,
   native property, kind and field.
3. `LuaTemplateCellView` hosts the views. Its `layout` gives the content the
   column's width inside the text cells' insets and its own measured height,
   centred in the row, and runs the framework layout engine. No frames are
   set by hand.
4. Each time the cell is given a row, the bindings are applied natively
   through KVC from the row's `NSDictionary`.

Lua runs once per cell built, never per row shown. Scrolling a 10,000-row
table builds about one screen of cells (11 for ten visible rows) and makes no
Lua calls; `tests/table_cell_template.test.lua` asserts both. This keeps the
reason key-based cells were chosen over per-cell Lua callbacks (see "Design
rationale" in [PROJECT_REFERENCE.md](PROJECT_REFERENCE.md)).

A template costs more than a hand-written cell, because it has more views
and they are measured by the general layout engine. Measured on the Diskmap
meter (eight views) while scrolling 10,000 rows: about 1.3 ms to bind, attach
and lay out one cell, against 0.4 ms for the native meter it replaced. The
bindings themselves are under 2% of that. Keep templates shallow in tables
that scroll fast.

### What the table still owns

- Selection, keyboard navigation, type-to-select, row menus, drag and swipe
  actions are the row's, and do not change.
- The selected row's emphasis reaches every label in the template, so text in
  `label` and `secondary` colours inverts as in a text cell.
- The cell's `textField` and `imageView` outlets are the template's first
  label and first image; AppKit reads them for the cell's accessibility.
- Truncation is the labels' own: `truncation="tail"` on the label that gives
  way, `fixedSize="horizontal"` on the one that keeps its width.
- `List.rowHeight` sets the row height. A template does not size its row.

Lua column specs take the same factory: `template = function() return view,
bindings end`. Application code uses the XML form.

UIKit does not render templates yet; a templated column shows its row text
there.

### Example: Diskmap's size meter

`apps/diskmap/views/cells/Meter.etlua` is one meter, like Spectrum's Meter:
the size (`52.3 GB`) leads and its share (`39%`) trails in secondary colour
on a line above a full-width `Gauge`. The bar is always drawn: a row without
a fraction leaves it empty and disabled, so a size never floats in an empty
cell; out-of-range values are clamped by the gauge. While a row is measured
(`calculating`), a small spinner leads the size; a size that is a state
(`sizeIcon`, `sizeColor`: Diskmap's "No access") shows its symbol in the
spinner's square and tints the word to match. VoiceOver reads the bar as the
column's title, the size and the share. Columns include it with
`partial("cells/Meter.etlua")`, naming other row fields where a list differs.

The remaining key attributes (`subtitleKey`, `imageKey`, `imageColorKey`,
`badgeKey`, `loadingKey` and the rest) still configure the text cell.
