# Native List row reordering

`<List>` supports native row dragging on AppKit and native row movement on
UIKit. The controller receives a `ui.reorder.Difference` from its
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

Lazy stacks, grids, arbitrary layout containers, cross-container drags, and
custom drag previews are not supported. Keep large collections in a native
table; see [issue #5](https://github.com/corepunch/lua-objc/issues/5) for the
remaining container work.
