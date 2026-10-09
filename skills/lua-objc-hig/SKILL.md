---
name: lua-objc-hig
description: >
  Apple Human Interface Guidelines adapted for lua-objc.
  Distills key HIG rules, measurements, and patterns for building native-feeling
  macOS and iOS UIs with declarative etlua templates and Lua over AppKit/UIKit.
  Use when designing, reviewing, or implementing interfaces in lua-objc so agents
  produce polished, accessible, system-consistent UIs without inventing controls.
---

# lua-objc HIG Skill

lua-objc maps SwiftUI-like declarative APIs to real AppKit and UIKit controls.
Follow Apple's Human Interface Guidelines for all visual, layout, interaction,
and accessibility decisions. This skill provides the distilled rules and the
lua-objc mapping so agents do not approximate.

Source inspiration: https://github.com/justinwetch/HIGAgentSkills (2026-09-27 release,
Apple snapshot 2026-09-12). Prefer the official HIG for edge cases; this skill
captures the rules most relevant to lua-objc's component set.

## When to use

- Designing a new screen, window, sheet, or component in an `apps/` or `demo/` project.
- Reviewing etlua templates or controllers for visual hierarchy, spacing, controls, and accessibility.
- Choosing between system controls vs custom drawing.
- Adapting an existing layout for iPhone, iPad, or macOS conventions.

## Core non-negotiables (from HIG + lua-objc rules)

- Use real native controls. Never imitate buttons, lists, separators, progress, or icons with text, emoji, or custom drawing.
- Prefer system fonts, semantic colors (`systemBlue`, etc.), SF Symbols, and platform metrics. No hard-coded colors or sizes unless the HIG specifies an exact value.
- Touch targets and hit areas: minimum 44×44 pt on iOS; respect macOS click targets and keyboard focus.
- Primary content consumes flexible space. Stacks provide sibling spacing only; do not add implicit outer margins.
- Accessibility: every icon-only control and search field needs a label. Support Dynamic Type, VoiceOver, and increased contrast.
- Dark mode and appearances are automatic with semantic colors and materials. Test light, dark, and high contrast.
- Alignment is exact: symbols and labels share columns; do not approximate with padding.
- Idle UI uses 0% CPU. No custom scroll or animation loops; use system facilities.

## Mapping HIG concepts to lua-objc

| HIG / SwiftUI concept | lua-objc / etlua |
|-----------------------|------------------|
| VStack / HStack / ZStack | `<VStack>`, `<HStack>`, `<ZStack>` (or `ns.VStack` only at framework level) |
| List / Table | `<List>` with columns; `plain`/`fullWidth` for data, `sourceList` for nav, `inset` for settings |
| Button | `<Button>` (system styles: filled, tinted, plain) |
| Toggle / Switch | `<Toggle>` |
| TextField / SearchField | `<TextField>`, `<SearchField>` |
| SF Symbol | `<SystemImage>` with meaningful name and accessibility label |
| Toolbar | `<ToolbarItem>` in window toolbar |
| Sheet / Dialog | native sheet or panel via controller; etlua for content |
| Materials / Glass | `<GlassEffect>`, system backgrounds |
| Navigation | sidebar via split view; tab bars where appropriate |

Views are **etlua only**. Controllers prepare data and call `xml.renderFile`; they do not build view trees with `ns.*` constructors (except the root window).

## Loading guidance

For a typical design or review task, consult:

1. This file for mappings and non-negotiables.
2. `docs/agents/apple-ui-checklist.md` for the project checklist.
3. `docs/agents/layout.md` and `docs/agents/xml-syntax.md` for concrete syntax.
4. Official HIG pages for the component in question (buttons, lists, layout, accessibility, etc.).

When measurements matter (margins, icon sizes, type scale), quote the HIG value and express it with named constants or system metrics rather than magic numbers in templates.

## Platform notes

- **macOS**: source lists, toolbars, menu bar, keyboard navigation, window tabbing. Target macOS 26+.
- **iOS / iPadOS**: tab bars, navigation bars, sheets, safe areas, Dynamic Type. Use the iPhone Simulator host described in `docs/ios.md`.
- **iPhone Duo**: when adapting an existing app, follow Apple's Duo guidance for folding layouts; keep the same etlua templates and let the platform handle the form factor where possible.

## Enforcement

If the user asks for a strict review or "enforce HIG", walk the generated or proposed etlua against the checklist above and the apple-ui-checklist. Flag any imitation of system controls, missing accessibility labels, hard-coded colors, or alignment that does not share columns. Suggest the native equivalent.

## Related project docs

- [AGENTS.md](../../AGENTS.md)
- [docs/agents/apple-ui-checklist.md](../../docs/agents/apple-ui-checklist.md)
- [docs/PROJECT_REFERENCE.md](../../docs/PROJECT_REFERENCE.md)
