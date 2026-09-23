# Performance

Create only the views the user needs. Eager stacks create every native child.
Do not use `VStack` + `ForEach` for unbounded or 1,000-plus row data. Use
native `<List>` for table-style data; its table implementation owns cell reuse.
Use `<LazyVStack>` or `<LazyVGrid>` for custom etlua item views; their native
collection hosts create views on demand. Etlua still expands and parses the
item descriptions up front, so large data sets still have template cost.

## Choose containers by data size

- Use `VStack` / `HStack` for small, bounded groups such as a form or toolbar.
- Use `<List>` for native table-style collections. Check
  `docs/tableview_swiftui.md` for row and sizing behavior.
- Use `<LazyVStack rowHeight="44">` or `<LazyVGrid columns="3"
  rowHeight="64">` when each visible item needs a composed native view.
  Item heights are fixed; choose a size that fits text at supported Dynamic
  Type sizes.
- Avoid emitting thousands of eager stack children. Run
  `./lua-objc benchmarks/list.lua` to measure local eager-stack and List
  construction time and Lua heap deltas. It does not measure frame rate or
whole-process peak memory.

For runtime traces in Instruments, filter the `org.luaobjc` / `Performance`
signpost category. Layout intervals use `appkit.layout` or `uikit.layout`; cell
creation intervals use `appkit.cell.dequeue` or `uikit.cell.dequeue`.

Never publish FPS or process-memory comparisons without measuring the same row
content, device, OS version, and test conditions. Headless construction numbers
are not evidence of scrolling performance or a SwiftUI comparison.

## Keep work off interaction hot paths

- Do not rerender the whole window for each keystroke. Update the focused native
  ref when only a control value changes; rerender the affected template when
  structure changes.
- Keep model queries and formatting proportional to the visible interaction.
- Do not decode large images on the main thread. Use the native image path and
  downsample before display when the source is larger than its rendered size.
- Do not drive animation with Lua timers or per-frame assignments. Native
  transitions and the system own motion.

For the retained-view invalidation contract, see
[`state-and-observation.md`](state-and-observation.md) and
`ARCHITECTURE.md`. Use `--dump-layout` when container measurement or clipping is
the suspected bottleneck.
