# Native container reordering

`<List>` supports native row dragging on AppKit and UIKit. UIKit uses table
drag and drop with the system row preview and move animation. The controller receives a
`ui.reorder.Difference` from its
`reorderContainer` action and applies it to the same row array used to render
the list.

```etlua
<List data="tasks" reorderable="true" reorderContainer="reorderTasks" header="false">
  <Column id="title" title="Task" />
</List>
```

```lua
actions = {
	reorderTasks = function(difference)
		difference:apply(model.tasks)
	end,
}
```

Indices passed to `Difference:move(from, to)` are one-based. `move` mutates the
array passed to `apply`; `applyTo` returns a reordered copy. The platform updates
its visible native table before invoking the action, so the model update should
be synchronous.

`ui.reorder.fromArrayDiff(oldItems, newItems, idKey)` builds an ordered edit
script containing moves, inserts, and removes from stable unique IDs. It
rejects missing or duplicate IDs, since those make a reorder ambiguous.

The same attributes work on `VStack`, `Grid`, `FlowStack`, `LazyVStack`, and
`LazyVGrid`. Stack-style containers use native platform drag interactions;
lazy collections use `NSCollectionView` or `UICollectionView` with native move
animation and cell reuse. For these structural views, apply the difference in
the model and update a retained `ui.template` mount so etlua reflects the new
order. See `apps/container-reorder/` and `apps/lazy-reorder/`.

Cross-container moves are not part of this single-container API. The built-in
system drag preview is used; there is no custom preview styling option.
