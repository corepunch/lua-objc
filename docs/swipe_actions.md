# Native swipe actions

`List` rows and `SwipeRow` elements inside a `VStack` use native AppKit/UIKit
table swipe actions. The controller receives a one-based row index and a plain
row record for `List`, or the declared `rowId` and row record for `SwipeRow`.

```etlua
<List id="tasks" data="tasks" swipeLeading="archive" swipeTrailing="delete"
      swipeLeadingTitle="Archive" swipeTrailingTitle="Delete"
      swipeTrailingRole="destructive" fullSwipe="true">
  <Column id="title" title="Task" />
</List>

<VStack maxWidth="infinity">
  <% for _, task in ipairs(smallTaskGroup) do %>
    <SwipeRow id="row_<%= task.id %>" rowId="<%= task.id %>"
              title="<%= task.title %>" status="<%= task.status %>"
              swipeLeading="archiveSmallTask" swipeTrailing="completeSmallTask"
              fullSwipe="true" maxWidth="infinity" />
  <% end %>
</VStack>
```

Resolve each action name through `actions` in the template render data. The
controller calls a model mutation and updates only the affected native row.
For a `List` removal, remove the model item and call `list:removeRow(index - 1)`;
the native removal method currently uses a zero-based index. For a `SwipeRow`
status change, update its one-row table with `clearRows()` and `addRow()`.
Neither operation reconstructs unrelated rows or the window.

UIKit uses `UISwipeActionsConfiguration`; `fullSwipe="true"` performs the first
action on that edge. AppKit uses `NSTableViewRowAction` and owns the swipe
behavior. Set `swipeLeadingRole` or `swipeTrailingRole` to `destructive` only
for an action that removes data.
