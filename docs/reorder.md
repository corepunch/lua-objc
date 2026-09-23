# Native List row reordering

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

Lazy stacks, grids, arbitrary layout containers, cross-container drags, and
custom drag previews are not supported. Keep large collections in a native
table; see [issue #5](https://github.com/corepunch/lua-objc/issues/5) for the
remaining container work.
