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

1. Compute `totalColumnWidth` from `tableColumns`
2. Compare to `viewport.width` (the clip view's visible area)
3. If `totalColumnWidth > viewport.width`:
   - `hasHorizontalScroller = YES`
   - `_tableView.frame.width = totalColumnWidth` (table is wider than visible area)
   - Do **not** call `sizeLastColumnToFit` (columns keep their explicit widths)
4. If columns fit:
   - `hasHorizontalScroller = NO`
   - `_tableView.frame.width = viewport.width`
   - Call `sizeLastColumnToFit` → autoresizing distributes remaining space

This gives us the SwiftUI-equivalent behaviour with zero Lua changes:
columns with explicit `width`/`minWidth` get a horizontal scrollbar when
the view is too narrow; auto-sized columns proportionally fill the space.

## Column widths — initial sizing

### Default widths

When no explicit `width` is given in the column spec, each column gets
`tableWidth / columnCount`. This approximates SwiftUI's behaviour where
columns without explicit `width` divide the remaining space equally.

### `sizeLastColumnToFit`

Called after all columns are added and data is loaded. With
`NSTableViewUniformColumnAutoresizingStyle`, this distributes any
"leftover" width proportionally, not just to the last column.

### Minimum column width

Every column gets `minWidth = kTableColumnMinWidth` (currently 40 pt).
NSTableView enforces this — columns never shrink below it, even with
proportional autoresizing. This is the mechanism that triggers the
horizontal-scrollbar fallback: when the view is too narrow for all
`minWidth` columns to fit, rows overflow and scrolling becomes available.

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
| `TableColumn` with custom `content`  | `viewForTableColumn:row:` returning custom NSView | Not yet mapped |
| Drag-to-reorder rows | `NSTableViewDataSource` drag methods | Not yet mapped |

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
