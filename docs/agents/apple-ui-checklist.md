---
layout: default
title: Apple UI checklist
---

# Apple UI checklist

Use this checklist while generating or reviewing an app. The goal is native,
quietly polished UI that behaves correctly on macOS now and can map to UIKit on
iPhone/iPad later.

## Structure

- Establish one clear primary task and a readable hierarchy.
- Use a semantic `Window` sidebar for navigation and reserve the content column
  for the primary task.
- Keep window-wide actions in the native toolbar; keep row actions local.
- Let native split views, tables, and windows own their geometry.
- Make the primary content consume flexible space.

## Controls

- Use real controls: `List`, `TextField`, `SearchField`, `Button`, `Toggle`,
  `TextEditor`, `ToolbarItem`, and `SystemImage`.
- Use concise verb labels for actions and noun phrases for headings.
- Use SF Symbols with meaningful labels and tooltips for toolbar actions.
- Never imitate separators, checkboxes, progress indicators, or icons with text,
  emoji, or decorative drawing.
- Provide an accessibility label for search fields and icon-only controls.

## Layout

- Stacks add sibling spacing, not implicit outer margins.
- Use named layout constants in a controller table.
- Keep tables edge-to-edge for primary data (`plain`/`fullWidth`).
- Use `sourceList` only for navigation and `inset` only for grouped settings.
- Design for the smallest supported window before adding decorative content.
- Test long labels, empty data, narrow columns, and dynamic content.

## Visual language

- Prefer system fonts, semantic dynamic colors, and native control metrics.
- Do not rely on color alone to communicate gain/loss, status, or errors.
- Check light, dark, and increased-contrast appearances.
- Avoid hard-coded colors and platform-specific visual hacks in shared templates.
- Keep the interface dense enough for useful desktop work without making it
  cramped.

## Behavior and validation

- Show table loading with `showLoading()` and stop it with `hideLoading()`.
- Provide empty and error states near the content they describe.
- Preserve keyboard navigation, native selection, focus, and resizing.
- Add a headless regression test for state and data behavior.
- Inspect a screenshot and a layout dump for visual changes.

Read Apple’s [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
for platform details, then use the project’s [Project Reference](../PROJECT_REFERENCE.md)
for the implementation contract.
