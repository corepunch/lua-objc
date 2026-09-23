# Performance

Create only the views the user needs. XML loops and eager stacks create every
child; they do not virtualize or recycle rows. Use the native `<List>` for
data-driven content where its current row API fits. Do not claim `LazyVStack` or
`LazyVGrid` support until the renderer and platform bridge expose them.

## Choose containers by data size

- Use `VStack` / `HStack` for small, bounded groups such as a form or toolbar.
- Use `<List>` for native table-style collections. Check
  `docs/tableview_swiftui.md` for row and sizing behavior.
- Avoid emitting thousands of eager XML children. Large-list virtualization,
  dequeue measurements, and benchmark results are tracked in
  [issue #9](https://github.com/corepunch/lua-objc/issues/9).

Never publish FPS or memory comparisons without measuring the same row content,
device, OS version, and test conditions. The repository does not currently
publish a reproducible SwiftUI comparison.

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
