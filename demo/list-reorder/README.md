# Native List row reordering

This example uses the public native table/list reordering behavior through
`<List>`. The template declares `reorderable="true"` and names a controller
action with `reorderContainer`. The bridge sends the controller a
`ui.reorder.Difference`; the model applies that operation to its ordered rows.

Stacks, grids, flow layouts, and lazy collection views use the same
`reorderable` and `reorderContainer` attributes. See
[`demo/container-reorder/`](../container-reorder/README.md) and
[`demo/lazy-reorder/`](../lazy-reorder/README.md) for those examples.
