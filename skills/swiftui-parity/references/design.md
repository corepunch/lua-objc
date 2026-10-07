# Design

- Put shared spacing, padding, type size, and color names in one controller `LAYOUT` table. Do not scatter magic numbers through templates.
- Prefer semantic colors (`accent`, `secondary`, `label`) over hex and over UIKit color objects in templates.
- Prefer flexible frames. Fixed width is for content that has a known size, such as a toolbar search field.
- A feature available at the default size must remain available at the minimum size. Extra width may show list and detail together. It must not be the only place an action exists.
- iOS hit targets stay at least 44 by 44 points. Do not shrink an icon button below that.
- Empty data uses `<ContentUnavailable>` with one next action. Search misses should include the term in the title the controller already has. There is no `ContentUnavailableView.search` helper.
- Settings controls sit in `<LabeledContent>` inside `<Form>`.
- Use `weight="bold"` when bold is the meaning. Do not sprinkle `semibold` without a reason.
- Do not use emoji, a drawn checkbox, or a text glyph as a system control.
- Cross-pane peers that share a baseline, such as a sidebar search field and a detail header, must share a top edge. Compare `y + height` in a layout dump. AppKit's origin is bottom-left.
