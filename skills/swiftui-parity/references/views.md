# Views

- Keep screens in `.etlua`. Controllers prepare data, render, retain refs, and bind `data.actions`. They do not build widget trees.
- Do not call `ns.Text`, `ns.Button`, or other constructors inside `<% %>`. Those run before XML parsing and emit unparseable text.
- Repeat siblings with `<% for _, item in ipairs(items) do %>`. There is no `<ForEach>` tag.
- Prefer `<Label systemImage="...">` over an `HStack` of `SystemImage` plus `Label` when the icon and title are one control.
- Button styles that exist: `plain`, `bordered`, `filled`, `glass`, `tinted`. Roles that exist: `destructive`, `cancel`. An icon-only button still needs `title` or `accessibilityLabel`.
- Use `<ContentUnavailable>` for empty, missing, and no-search-results states. Give it one next action as a `Button` child, not only a caption.
- Use `<Form>` and `<LabeledContent label="Email">` for settings. Do not invent a custom form style.
- Use `<GlassEffect>` or `<MaterialView>` for system materials. Do not draw a fake blur.
- `<List>` takes columns and a record array (`data="items"`). It dequeues native cells. Custom visible-only rows are `<LazyVStack rowHeight="...">` or `<LazyVGrid columns="2" rowHeight="...">`. Etlua still expands item descriptions up front; the native host creates views as cells appear.
- Reorder with `reorderable="true"` and `reorderContainer` set to a controller action. The action receives `ui.reorder.Difference`. A reorderable lazy tag errors without that action.
- Swipe with `<SwipeRow>` or list `swipeLeading` / `swipeTrailing`. `fullSwipe` is UIKit.
- Motion is platform default plus `onTap` / `onDrag` and `ui.haptics`. Do not add `withAnimation`, a transition library, or Reanimated. Read `docs/animation.md` before changing motion.
