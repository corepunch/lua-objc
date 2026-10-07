# Accessibility

- Every icon-only `Button`, `Image`, and `SearchField` needs `accessibilityLabel` or a visible `title`. `accessibilityLabel` is copied onto the native view for any tag that returns userdata.
- `id` is the accessibility identifier. Use it for tests and dumps. It is not a substitute for a spoken label.
- Do not emit `accessibilityHint` or `accessibilityRole`. Those attributes are not in the schema.
- Do not use a `Label` as a button. The control must be a `Button` so the platform trait is button.
- Decorative images get an empty `accessibilityLabel` so VoiceOver can skip them.
- Do not encode state by color alone. Pair a semantic color with text or a symbol.
- Dynamic Type is the platform font, not a `size="24"` that must fit one phone. A fixed `size` is a finding when the text is body copy. Check the layout dump for `cropped` and `ellipsis` after a narrow-window pass.
- Reduce Motion: do not add a custom opacity animation. Platform transitions already follow the system setting. There is no `bridge._reduceMotionEnabled()` to call from an app.
- macOS keyboard: Tab must reach each control, Return activates the default button, Escape dismisses a sheet. Do not invent `setEscapeKeyAction` unless `src/` already exports it.
