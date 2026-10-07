# Performance

Routine review only. Deeper retained-description work stays in `gaps.md` unless the user asked for a performance investigation.

- Unbounded rows use `<List>` or `<LazyVStack>` / `<LazyVGrid>` with a fixed `rowHeight`. An eager `VStack` that creates every child is for a small, fixed group.
- Do not prebuild native views in the controller and drop them through a passthrough tag unless the view cannot be described in XML, as `<Chart data="chart">` does.
- Keep template work to iteration, conditionals, and value injection.
- Update a retained ref when one property changes. Rerender when structure changes. Do not rebuild the window on each keystroke.
- Headless tests must not spawn `./lua-objc`. Require the controller and call it in-process. Subprocess launches race the run loop.
