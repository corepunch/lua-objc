# Virtualized reorderable stack and grid

`<LazyVStack>` and `<LazyVGrid>` compile one item description per etlua loop
iteration, then create native item views only when the collection host asks for
visible cells. AppKit uses `NSCollectionView`; UIKit uses `UICollectionView`.
`rowHeight` fixes each item height, and `columns` sets the grid column count.
The native collection view supplies drag previews and move animation. The
controller receives a `ui.reorder.Difference`, updates the model, and refreshes
the retained template.

The default example shows a 1,000-item stack. Set `LUA_OBJC_LAZY_KIND=grid`
to show a three-column grid with the same items.

```sh
make
./lua-objc --screenshot=/tmp/lazy-stack.png demo/lazy-reorder/init.lua
LUA_OBJC_LAZY_KIND=grid ./lua-objc --screenshot=/tmp/lazy-grid.png \
  demo/lazy-reorder/init.lua
```
