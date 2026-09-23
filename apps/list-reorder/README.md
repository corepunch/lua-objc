# Native List row reordering

This example uses the public native table/list reordering behavior through
`<List>`. The template declares `reorderable="true"` and names a controller
action with `reorderContainer`. The bridge sends the controller a
`ui.reorder.Difference`; the model applies that operation to its ordered rows.

The current bridge supports native `List` rows. Reordering arbitrary stack and
grid children requires a lazy/reconciled container API and is not advertised as
available.
