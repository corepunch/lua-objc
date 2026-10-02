# Retained templates, live updates and motion

lua-objc has **no animation engine**. There is no `withAnimation`, no
transitions, and no transaction that snapshots and diffs the layout of a
subtree: such an engine animated whole pages on every progress tick and
fought scrolling. Motion is what the platform already provides, or one
view's own business:

| Motion | Where |
|---|---|
| `Arc` and `SectorChart` turn, grow and change rings along their circles | the arc itself: `ArcAnimator` in `src/shared/arc_path.m`; a chart builds its arcs with `animated = true`. Honours Reduce Motion. |
| The welcome tour slides its pages | `ns._pushTransition(view, edge)` in `src/shared/view_tree.m`: Core Animation's own `CATransition`, played by the system |
| Scrolling to an item | native: `NSAnimationContext` on macOS, `setContentOffset:animated:` on iOS |
| Table rows, navigation pushes, sheets | the platform's own animated APIs |

Everything else applies at once. A feature that would add motion beyond this
needs an "are you sure?" first (see AGENTS.md).

| Piece | Where |
|---|---|
| Retained templates and reconciliation | `lua/ui/template.lua`, `xml.mount` / `xml.reconcile` in `lua/ui/xml.lua` |
| Structural edits (`_insertSubview`, `_removeSubview`), `opacity`, `offsetX/Y` | `src/shared/view_tree.m` |
| Automatic layout after writes | `src/appkit/layout.m` (“Automatic invalidation”), `src/uikit/layout.m` |
| Charts that update in place | `lua/ui/sectors.lua` |
| Tests | `tests/template_mount.test.lua`, `tests/auto_layout.test.lua`, `tests/sector_chart.test.lua`, `tests/diskmap_motion.test.lua` |

## Retained templates and reconciliation

Screens are etlua templates mounted once through `ui.template`; later
`template:update(data)` calls reconcile the new description against the
mounted views instead of rebuilding them. An update whose data is unchanged
does nothing.

How nodes match and what happens to them:

1. **Matching.** Nodes match by tag and `id` (or `key`), otherwise by tag
   and order among their siblings.
2. **Patch in place.** A matched node keeps its native view, state and focus
   when every changed attribute can be applied to it:
   - any view: `hidden`, `opacity`, `offsetX`, `offsetY`, `cornerRadius`,
     `background`, `disabled`, `accessibilityLabel`, and `key`;
   - layout: `width`, `height`, `min…`/`max…`, `flexGrow`, `flexShrink`,
     `flexBasis`, and on stacks `padding…`, `spacing`, `alignment`;
   - per tag: `Label`/`Paragraph`/`TextField` `text`, `Paragraph`
     `revealedCharacters` (typewriter reveal), `Button` `title`,
     `ProgressView`/`Gauge`/`Slider`/`Picker` `value`.
3. **Stacks** (`VStack`, `HStack`, `ZStack`, `FlowStack`) insert, move and
   remove children individually; keyed children move rather than being
   rewritten.
4. **Records** (`SectorMark`, `TreemapNode`, `Column`, …) configure their
   parent. A tag whose schema entry has `updateRecords(view, records)` takes
   changed records in place: `SectorChart` moves its existing arcs to the new
   angles (each arc animates itself), adds or removes arcs below its overlay, and keeps its hover and
   keyboard handling (`Sectors.update` in `lua/ui/sectors.lua`). Attributes
   named in the entry's `recordLayout` (`innerRadius`, `angularInset`) are
   applied with the records instead of rebuilding the chart. Its other
   children reconcile normally. Any other record change rebuilds the parent.
5. **Rebuild.** Any other change rebuilds that one node: a new native view
   replaces the old one.

Planning builds new subtrees and validates every change before touching the
screen, so a render error keeps the old view.

### Layout after structural changes

Inserting, moving or removing a view (`_insertSubview`, `_removeSubview`)
schedules layout exactly like a layout-affecting property write. AppKit lays
out dirty owners in its own layout pass, which its update cycle runs before
drawing each frame (the nearest stack is marked `needsLayout`), and again
before the run loop sleeps; UIKit marks the owner `setNeedsLayout`. A view added by an
update is therefore placed before it is first drawn, and never appears at its
container's origin. A Lua geometry read (`frame`, `size`, `fittingSize`, …)
flushes pending layout first. Apps never call `layout()`.

### Keeping live updates steady

Progress updates (a scan, a download) usually arrive outside any transaction,
many times a second. They should change values, not structure:

- Give rows that can re-rank a `key` so they move instead of rewriting each
  other's text.
- Give changing values a fixed width (`width` with `alignment="trailing"`)
  so “Calculating…” and “≥ 998.9 MB” occupy the same space.
- Prefer one view with changing attributes over an `if` that swaps between
  different tags; every swap rebuilds that node.
- Put charts' changing data in their records (`SectorMark` values) and let
  `updateRecords` apply it.
- Apply progress immediately. Never wrap frequent updates in an animated
  transaction (there is none).

Diskmap's overview is the reference case: during a 30-second scan the donut
is never rebuilt and legend rows never overlap
(`apps/diskmap/views/sections/Hero.etlua`, `LegendRow.etlua`).

## Testing

| Hook | Use |
|---|---|
| `arc.animating` | Whether an Arc's own path animation is running. |
| `bridge._pendingLayoutCount()` | Views waiting for the next layout pass. |
| `bridge._flushLayout()` | Run the pending layout pass. |

Useful assertions for a retained screen: after an update, the refs you care
about are the same userdata as before (the node was patched, not rebuilt),
`_pendingLayoutCount()` is non-zero after a structural change, and frames read
after the update are final. See `tests/sector_chart.test.lua` and
`tests/auto_layout.test.lua`.

To check a running app, sample its retained refs from an `ns.async` loop and
count identity changes while real data streams in; that is how the Diskmap
overview's rebuild count was measured.
