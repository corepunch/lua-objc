# Native reorder on ordinary containers

`Content.etlua` marks `VStack`, `Grid`, and `FlowStack` as reorderable and
routes each native drag to a controller action. The action receives a
`ui.reorder.Difference`, applies it to the model, and updates a retained etlua
template. AppKit starts a native dragging session; UIKit uses drag and drop
interactions. Each platform supplies its native drag preview.

These containers construct their child views eagerly. Use the lazy collection
example for large data sets.

```sh
make
./lua-objc --screenshot=/tmp/container-reorder.png demo/container-reorder/init.lua
```
