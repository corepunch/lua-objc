---
name: swiftui-parity
description: Reviews lua-objc apps against the SwiftUI Pro checklist, translated to APIs this bridge actually implements. Use when writing, reviewing, or checking SwiftUI-shaped Lua or etlua for modern native UI, accessibility, navigation, layout, or performance.
license: MIT
metadata:
  author: corepunch
  version: "1.0.0"
  benchmark: https://github.com/twostraws/SwiftUI-Agent-Skill
---

Review lua-objc app code for native SwiftUI-shaped UI that this repository actually implements. Report only genuine problems. Do not nitpick, and do not invent a SwiftUI modifier the bridge does not have.

During feature work, finish the requested change. Suggest unrelated modernization separately. Do not apply it unless asked.

This is the SwiftUI Pro v2 review shape (https://github.com/twostraws/SwiftUI-Agent-Skill) mapped onto lua-objc. SwiftUI is the behavioral reference. It is not an implementation path. Never copy SwiftUI source, React Native, or a second state framework into an app.

Review process:

1. Check API mapping and soft gaps using `references/api.md`.
2. Check view structure, controls, and motion using `references/views.md`.
3. Check data flow using `references/data.md`.
4. Check navigation and presentation using `references/navigation.md`.
5. Check HIG-shaped design using `references/design.md`.
6. Check resize and safe area using `references/resizability.md`.
7. Check accessibility using `references/accessibility.md`.
8. Check list and template performance using `references/performance.md`.
9. Finish with hygiene using `references/hygiene.md`.

For a partial review, load only the relevant reference. Keep `references/gaps.md` out of routine reviews. Load it when a requested SwiftUI API is missing, or when the review would otherwise invent a substitute.

The tag contract is `tests/swiftui_parity_contract.test.lua`. A tag named in `references/api.md` must be a key of `xml.schema`. Do not document a tag the contract does not list.

## Core instructions

- Apps stay in Lua and etlua. Native work belongs in the bridge, under `skills/maintain-lua-objc-framework`.
- Check `xml.schema` in `lua/ui/xml.lua` before using a tag or attribute. Registry presence is not proof of both platforms; say which platform a sample uses.
- `<Label>` is SwiftUI `Text`. A symbol-plus-title is `<Label systemImage="...">` or `<Button systemImage="...">`, not a second control named Label.
- `<List>` is a native table (`NSTableView` / `UITableView`) with `<Column>` children. It is not a SwiftUI `List` of arbitrary row views. Custom row views use `<LazyVStack>` or `<LazyVGrid>`.
- There is no implicit `withAnimation`, no `Binding(get:set:)`, no `@Observable`, and no iPhone Duo hinge API. Do not fake them.
- Append with `table.insert(items, value)`. Parenthesize multi-return calls: `table.insert(items, (fn()))`.

## Output format

Organize findings by file. For each issue, name the file and line, name the rule, and show a short before/after. Skip clean files. End with a prioritized summary.

### apps/stocks/views/Detail.etlua

**Line 18: Icon-only buttons need a title or accessibilityLabel.**

```xml
<!-- Before -->
<Button systemImage="plus" action="add" />

<!-- After -->
<Button title="Add symbol" systemImage="plus" action="add" />
```

### Summary

1. **Accessibility (high):** the add button has no name VoiceOver can speak.
2. **Collections (medium):** an unbounded `VStack` should be `List` or `LazyVStack`.
